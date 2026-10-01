// 起動時初期化。crt0.S の _startup からスタック設定直後に飛んでくる。
//
// この時点では .data / .bss が未初期化なので、main を呼ぶまでの間は
// グローバル変数に依存してはならない。
//
// リンカシンボルの参照方法に注意:
// @_extern の「変数」として参照すると、コンパイラがアドレス定数を .data 内の
// アンカーとして実体化するため、「.data をコピーする前に .data を読む」
// 鶏と卵の問題になる (ELFローダが .data を配置してくれるESP32等と違い、
// GBAは自前コピーのため)。
// 一方 @_extern の「関数」として宣言すれば、参照はリンク時定数として
// コード側 (ROM内のリテラルプール) に埋め込まれるので、この問題を回避できる。
// シンボルは呼び出さずアドレスとしてのみ使う。

/// crt0.S から呼ばれるエントリ。.data コピー → .bss クリア → main。戻らない。
///
/// `table` は crt0.S がイメージ内に持つリンカシンボルのアドレステーブル:
///   [0] _sidata  (.data の初期値があるアドレス。Multibootイメージ末尾 = EWRAM)
///   [1] _sdata   (.data の先頭)
///   [2] _edata   (.data の終端)
///   [3] _sbss    (.bss の先頭)
///   [4] _ebss    (.bss の終端)
/// Swift側で @_extern を使ってシンボルを参照すると、変数・関数いずれの形でも
/// アドレス定数が .data 内のアンカーとして実体化され、「.data をコピーする前に
/// .data を読む」鶏と卵の問題になる (ELFローダが .data を配置してくれる
/// ESP32等と違い、GBAは自前コピーのため)。実行時に渡される不透明なポインタ
/// なら、オプティマイザに定数畳み込みされる余地もない。
@c(startupMain)
func startupMain(_ table: UnsafePointer<UInt>) -> Never {
    copyDataSection(table[0], table[1], table[2])
    clearBSS(table[3], table[4])

    Application.main()

    // main は戻らない想定だが、万一戻ってきた場合はここで停止する。
    // volatile 読み出しを含めてループが最適化で消えないようにする。
    while true {
        _ = mmioRead16(Reg.vcount)
    }
}

/// 初期値付きグローバル変数 (.data) をロードアドレス (イメージ末尾、EWRAM) から
/// 実行アドレス (IWRAM) へコピーする。
/// 各セクションはリンカスクリプトで4バイト境界に揃えてあるためワード単位で行う。
private func copyDataSection(_ source: UInt, _ start: UInt, _ end: UInt) {
    guard let src = UnsafePointer<UInt32>(bitPattern: source),
          let dst = UnsafeMutablePointer<UInt32>(bitPattern: start) else { return }
    var i = 0
    while start &+ UInt(i) &* 4 < end {
        dst[i] = src[i]
        i &+= 1
    }
}

/// .bss セクションをゼロクリアする。
private func clearBSS(_ start: UInt, _ end: UInt) {
    guard let ptr = UnsafeMutablePointer<UInt32>(bitPattern: start) else { return }
    var i = 0
    while start &+ UInt(i) &* 4 < end {
        ptr[i] = 0
        i &+= 1
    }
}
