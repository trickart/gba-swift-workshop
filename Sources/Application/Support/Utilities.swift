// ゲームでよく使う小さな部品: 乱数と、四角形どうしの当たり判定。

/// 乱数 (xorshift)。GBAにはシステムの乱数がないので自前で持つ。
struct Random {
    private var state: UInt32

    /// 同じ seed からは同じ並びの乱数が出る
    init(seed: UInt32) {
        state = seed == 0 ? 0x2545_F491 : seed
    }

    mutating func next() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }

    /// range の中から1つ選ぶ
    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt32(range.count))
    }
}

/// 四角形 (ピクセル単位)。x, y は左上。
struct Rect {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    /// 2つの四角形が重なっているか
    func intersects(_ other: Rect) -> Bool {
        x < other.x + other.width && other.x < x + width
            && y < other.y + other.height && other.y < y + height
    }
}

/// 角度 (度) の三角関数。GBAには小数がないので、結果は 1/256 単位の整数 (256 で 1.0)。
enum Angle {
    static func sin(_ degrees: Int) -> Int {
        let d = ((degrees % 360) + 360) % 360
        switch d {
        case 0..<90: return quarterSine[d]
        case 90..<180: return quarterSine[180 - d]
        case 180..<270: return -quarterSine[d - 180]
        default: return -quarterSine[360 - d]
        }
    }

    static func cos(_ degrees: Int) -> Int {
        sin(degrees + 90)
    }

    /// 0〜90度の sin を 1/256 単位にした表
    private static let quarterSine = [
        0, 4, 9, 13, 18, 22, 27, 31, 36, 40, 44, 49, 53,
        58, 62, 66, 71, 75, 79, 83, 88, 92, 96, 100, 104, 108,
        112, 116, 120, 124, 128, 132, 136, 139, 143, 147, 150, 154, 158,
        161, 165, 168, 171, 175, 178, 181, 184, 187, 190, 193, 196, 199,
        202, 204, 207, 210, 212, 215, 217, 219, 222, 224, 226, 228, 230,
        232, 234, 236, 237, 239, 241, 242, 243, 245, 246, 247, 248, 249,
        250, 251, 252, 253, 254, 254, 255, 255, 255, 256, 256, 256, 256,
    ]
}
