// Multiboot イメージ転送ツール
//
// 使い方: swift tools/multiboot.swift <イメージファイル> [--port デバイス] [--timeout 秒] [--clock Hz] [--gap µs]
//         (Makefile からは xcrun swift で実行)
//
// https://github.com/trickart/gba-multiboot-web のファームウェアを書き込んだアダプタ
// (USB シリアル) へイメージを流し込む。GBA との Multiboot 通信 (ハンドシェイク、暗号化、CRC) は
// アダプタ側のファームウェアが行うので、ここでやるのは次のフレームのやり取りだけ:
//
//   [type: 1バイト][length: 2バイト LE][payload: length バイト]
//
//   RESET → GET_INFO → SET_CONFIG → MB_START(全長) → MB_DATA を流す → MB_DONE / MB_ERROR を待つ
//
// アダプタは受け取ったデータをリングバッファに溜めて GBA へ送るので、
// 「送った量 - GBA へ送り終えた量 (MB_PROGRESS で通知される)」がバッファ容量を超えないように送る。

#if canImport(Darwin)
import Darwin
let portPatterns = ["/dev/cu.usbmodem*"]
let TIOCMBIS_: UInt = 0x8004_746C
#elseif canImport(Glibc)
import Glibc
let portPatterns = ["/dev/ttyACM*"]
let TIOCMBIS_: UInt = 0x5416
#endif
let TIOCM_DTR_: CInt = 0x002
let TIOCM_RTS_: CInt = 0x004

// MARK: - プロトコル定義 (gba-multiboot-web の Sources/LinkCore/Protocol.swift と同じ値)

let protocolVersion: UInt8 = 1

enum Command {
    static let getInfo: UInt8 = 0x01
    static let setConfig: UInt8 = 0x02
    static let mbStart: UInt8 = 0x10
    static let mbData: UInt8 = 0x11
    static let mbAbort: UInt8 = 0x12
    static let reset: UInt8 = 0x30
}

enum Event {
    static let info: UInt8 = 0x80
    static let log: UInt8 = 0x81
    static let mbStatus: UInt8 = 0x90
    static let mbProgress: UInt8 = 0x91
    static let mbDone: UInt8 = 0x92
    static let mbError: UInt8 = 0x93
    static let nak: UInt8 = 0xFE
}

let phaseNames = ["待機", "GBA 待ち", "ヘッダ", "パレット", "長さ", "本体", "CRC", "完了", "失敗"]

let errorNames = [
    "エラーなし",
    "イメージのサイズが不正",
    "GBA が見つからない (接続タイムアウト)",
    "GBA の応答が想定外 (スレーブ番号)",
    "master/slave 情報交換の応答不一致",
    "ヘッダ転送中の応答不一致",
    "ヘッダ完了通知の応答不一致",
    "パレット応答が得られない",
    "ハンドシェイクの応答不一致",
    "長さ情報の応答不一致",
    "本体転送中の応答不一致",
    "本体転送完了通知の応答不一致",
    "CRC 準備待ちで想定外の応答",
    "CRC 転送予告の応答不一致",
    "CRC 不一致",
    "中止された",
]

// イメージのサイズ制約 (GBATEK "Multiboot Transfer Protocol")
let headerSize = 0xC0
let minBodySize = 0x100
let bodyAlignment = 0x10
let maxTotalSize = 0x40000

let chunkSize = 1024

// MARK: - 小物

func fail(_ message: String) -> Never {
    fflush(stdout)
    var line = "multiboot: \(message)\n"
    line.withUTF8 { _ = write(2, $0.baseAddress, $0.count) }
    exit(1)
}

func hex(_ value: UInt32, digits: Int = 4) -> String {
    let text = String(value, radix: 16, uppercase: true)
    return "0x" + String(repeating: "0", count: max(0, digits - text.count)) + text
}

func le16(_ value: UInt16) -> [UInt8] {
    [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
}

func le32(_ value: UInt32) -> [UInt8] {
    (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
}

func readLE16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
}

func readLE32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
}

/// 起動からの経過ミリ秒
func nowMs() -> Int {
    var time = timespec()
    clock_gettime(CLOCK_MONOTONIC, &time)
    return Int(time.tv_sec) * 1000 + Int(time.tv_nsec) / 1_000_000
}

/// ミリ秒を "12.3" の形の秒にする
func seconds(_ ms: Int) -> String {
    "\(ms / 1000).\(ms % 1000 / 100)"
}

func readFile(_ path: String) -> [UInt8] {
    guard let file = fopen(path, "rb") else { fail("\(path) を開けません") }
    defer { fclose(file) }
    fseek(file, 0, SEEK_END)
    let size = ftell(file)
    guard size >= 0 else { fail("\(path) のサイズを取得できません") }
    rewind(file)
    var bytes = [UInt8](repeating: 0, count: size)
    guard fread(&bytes, 1, size, file) == size else { fail("\(path) を読めません") }
    return bytes
}

// MARK: - 引数

var imagePath: String? = nil
var portPath: String? = nil
var timeoutSeconds: UInt32 = 60
var clockHz: UInt32 = 256_000
var gapUs: UInt16 = 40

let usage = "使い方: multiboot.swift <イメージファイル> [--port デバイス] [--timeout 秒] [--clock Hz] [--gap µs]"

do {
    var arguments = CommandLine.arguments.dropFirst().makeIterator()
    func value(of option: String) -> String {
        guard let value = arguments.next() else { fail("\(option) に値がありません\n\(usage)") }
        return value
    }
    func number<T: FixedWidthInteger>(of option: String) -> T {
        guard let number = T(value(of: option)) else { fail("\(option) の値が数値ではありません") }
        return number
    }
    while let argument = arguments.next() {
        switch argument {
        case "--port": portPath = value(of: argument)
        case "--timeout": timeoutSeconds = number(of: argument)
        case "--clock": clockHz = number(of: argument)
        case "--gap": gapUs = number(of: argument)
        default:
            guard !argument.hasPrefix("-"), imagePath == nil else { fail(usage) }
            imagePath = argument
        }
    }
}
guard let imagePath else { fail(usage) }

// MARK: - イメージの読み込みとパディング

// 本体 (0xC0 以降) は 16 バイト境界で、最低 0x100 バイト必要
var image = readFile(imagePath)
guard image.count > headerSize else { fail("\(imagePath) は小さすぎます (\(image.count) バイト)") }
do {
    let body = max(minBodySize, (image.count - headerSize + bodyAlignment - 1) / bodyAlignment * bodyAlignment)
    image += [UInt8](repeating: 0, count: headerSize + body - image.count)
}
guard image.count <= maxTotalSize else { fail("イメージが 256KiB を超えています (\(image.count) バイト)") }

// MARK: - シリアルポート

/// アダプタらしいデバイスを探す (1つだけ見つかったときに限り自動で選ぶ)
func findPort() -> String {
    var found: [String] = []
    for pattern in portPatterns {
        var result = glob_t()
        defer { globfree(&result) }
        guard glob(pattern, 0, nil, &result) == 0 else { continue }
        for index in 0..<Int(result.gl_pathc) {
            if let path = result.gl_pathv[index] { found.append(String(cString: path)) }
        }
    }
    if found.isEmpty { fail("アダプタが見つかりません。--port でデバイスを指定してください") }
    if found.count > 1 {
        fail("デバイスが複数あります。--port で指定してください:\n  " + found.joined(separator: "\n  "))
    }
    return found[0]
}

func openPort(_ path: String) -> CInt {
    // 相手の準備 (DCD) を待たずに開くため O_NONBLOCK を付け、開いたあとで外す
    let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
    guard fd >= 0 else { fail("\(path) を開けません: \(String(cString: strerror(errno)))") }
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)

    // 改行変換やエコーなどを全部切って、バイト列をそのまま通す
    var settings = termios()
    guard tcgetattr(fd, &settings) == 0 else { fail("\(path) はシリアルデバイスではありません") }
    cfmakeraw(&settings)
    settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
    cfsetspeed(&settings, speed_t(B115200))   // USB なので速度に意味はない
    guard tcsetattr(fd, TCSANOW, &settings) == 0 else { fail("\(path) を設定できません") }

    // ファームウェアは DTR を「ホスト接続中」の印に使う
    var lines = TIOCM_DTR_ | TIOCM_RTS_
    _ = ioctl(fd, TIOCMBIS_, &lines)
    tcflush(fd, TCIOFLUSH)
    return fd
}

let port = portPath ?? findPort()
let fd = openPort(port)
print("ポート: \(port)")

// Ctrl-C で中断されたら、アダプタにも転送の中止を伝える
var interrupted: sig_atomic_t = 0
signal(SIGINT) { _ in interrupted = 1 }

// MARK: - フレームの送受信

struct Frame {
    var type: UInt8
    var payload: [UInt8]
}

var received: [UInt8] = []

func send(_ type: UInt8, _ payload: [UInt8] = []) {
    let bytes = [type] + le16(UInt16(payload.count)) + payload
    var offset = 0
    while offset < bytes.count {
        let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if written < 0 {
            if errno == EINTR || errno == EAGAIN { continue }
            fail("書き込みに失敗しました: \(String(cString: strerror(errno)))")
        }
        offset += written
    }
}

/// 最大 timeoutMs ミリ秒だけ受信を待ち、そろったフレームを返す
func receive(timeoutMs: Int) -> [Frame] {
    var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    if poll(&descriptor, 1, CInt(timeoutMs)) > 0 {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = read(fd, &chunk, chunk.count)
        if count > 0 {
            received += chunk[..<count]
        } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
            fail("アダプタとの接続が切れました")
        }
    }
    var frames: [Frame] = []
    while received.count >= 3 {
        let length = Int(readLE16(received, 1))
        guard received.count >= 3 + length else { break }
        frames.append(Frame(type: received[0], payload: Array(received[3..<3 + length])))
        received.removeFirst(3 + length)
    }
    return frames
}

func printLog(_ frame: Frame) {
    print("[アダプタ] \(String(decoding: frame.payload, as: UTF8.self))")
}

/// 指定した種類のフレームが届くまで待つ。時間切れなら nil
func waitFor(_ type: UInt8, minimumLength: Int, timeoutMs: Int) -> Frame? {
    let deadline = nowMs() + timeoutMs
    while true {
        let remaining = deadline - nowMs()
        guard remaining > 0, interrupted == 0 else { return nil }
        for frame in receive(timeoutMs: remaining) {
            if frame.type == type && frame.payload.count >= minimumLength { return frame }
            if frame.type == Event.log { printLog(frame) }
        }
    }
}

// MARK: - 接続

// RESET で同期を取り直す。前回の残りや他のプロセスが送った文字列でフレームの区切りが
// ずれていることがあるので、受信済みのデータを捨てながら数回試す
do {
    usleep(200_000)
    var synced = false
    for _ in 0..<3 where !synced {
        tcflush(fd, TCIFLUSH)
        received.removeAll()
        send(Command.reset)
        synced = waitFor(Event.mbStatus, minimumLength: 5, timeoutMs: 1000) != nil
    }
    if !synced {
        fail("アダプタが応答しません (ブラウザなど、他のアプリがポートを開いていないか確認してください)")
    }
}

send(Command.getInfo)
guard let info = waitFor(Event.info, minimumLength: 8, timeoutMs: 2000)?.payload else {
    fail("GET_INFO の応答がありません")
}
guard info[0] == protocolVersion else {
    fail("プロトコルのバージョンが合いません (アダプタ: \(info[0])、このツール: \(protocolVersion))")
}
let ringCapacity = max(chunkSize, Int(readLE32(info, 4)))
print("ファームウェア: v\(info[1]).\(info[2]).\(info[3])")

let palette: UInt8 = 0xD1   // 転送中に GBA のロゴ画面が光る色
send(Command.setConfig, le32(clockHz) + le16(gapUs) + [palette] + le32(timeoutSeconds &* 1000))
guard waitFor(Event.info, minimumLength: 8, timeoutMs: 2000) != nil else {
    fail("SET_CONFIG の応答がありません")
}

// MARK: - 転送

print("イメージ: \(imagePath) (\(image.count) バイト)")
print("GBA をカートリッジなしで起動してください (\(timeoutSeconds) 秒待ちます)")

send(Command.mbStart, le32(UInt32(image.count)))

let startedAt = nowMs()
var sent = 0
var consumed = 0
var lastPhase: UInt8 = 0
var progressShown = false

func endProgressLine() {
    if progressShown { print() }
    progressShown = false
}

while true {
    if interrupted != 0 {
        send(Command.mbAbort)
        endProgressLine()
        fail("中断しました")
    }

    // リングバッファに空きがあれば次の塊を送る
    var waitMs = 100
    if sent < image.count && sent - consumed + chunkSize <= ringCapacity {
        let end = min(image.count, sent + chunkSize)
        send(Command.mbData, Array(image[sent..<end]))
        sent = end
        waitMs = 0
    }

    for frame in receive(timeoutMs: waitMs) {
        let payload = frame.payload
        switch frame.type {
        case Event.mbStatus where payload.count >= 1:
            guard payload[0] != lastPhase else { break }
            lastPhase = payload[0]
            endProgressLine()
            let name = Int(lastPhase) < phaseNames.count ? phaseNames[Int(lastPhase)] : "\(lastPhase)"
            print("[\(seconds(nowMs() - startedAt))s] \(name)")

        case Event.mbProgress where payload.count >= 4:
            consumed = Int(readLE32(payload, 0))
            print("\r  \(consumed) / \(image.count) バイト (\(consumed * 100 / image.count)%)", terminator: "")
            fflush(stdout)
            progressShown = true

        case Event.mbDone where payload.count >= 6:
            endProgressLine()
            print("転送完了: \(seconds(Int(readLE32(payload, 2)))) 秒、CRC \(hex(UInt32(readLE16(payload, 0))))")
            close(fd)
            exit(0)

        case Event.mbError where payload.count >= 10:
            endProgressLine()
            let code = Int(payload[0])
            let phase = Int(payload[1])
            fail("""
                転送に失敗しました: \(code < errorNames.count ? errorNames[code] : "コード \(code)")
                  段階: \(phase < phaseNames.count ? phaseNames[phase] : "\(phase)")、\
                期待した応答: \(hex(readLE32(payload, 2)))、実際の応答: \(hex(readLE32(payload, 6)))
                """)

        case Event.nak where payload.count >= 1:
            endProgressLine()
            fail("アダプタがコマンド \(hex(UInt32(payload[0]), digits: 2)) を拒否しました")

        case Event.log:
            endProgressLine()
            printLog(frame)

        default:
            break
        }
    }
}
