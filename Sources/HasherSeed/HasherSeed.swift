// arc4random_buf のスタブ。
//
// Swift標準ライブラリの Hasher は、ハッシュの種を arc4random_buf で初期化する。
// Dictionary や Set だけでなく、`enum State { case a, b }` のような単純な enum に
// 自動生成される hashValue からも参照されるため、これがないと enum を1つ
// 定義しただけでリンクエラー (undefined symbol: arc4random_buf) になる。
//
// GBAには乱数源がないので、固定の種から始まる xorshift で埋める。
// ハッシュの種が毎回同じになるだけで、ゲーム用途では問題ない
// (暗号や、外部入力に対するハッシュ衝突攻撃への耐性が必要な用途には使えない)。

nonisolated(unsafe) private var randomState: UInt32 = 0x9E37_79B9

@c(arc4random_buf)
@inline(never)
public func arc4randomBuf(_ buffer: UnsafeMutableRawPointer, _ count: Int) {
    let bytes = buffer.assumingMemoryBound(to: UInt8.self)
    for i in 0..<count {
        randomState ^= randomState << 13
        randomState ^= randomState >> 17
        randomState ^= randomState << 5
        bytes[i] = UInt8(truncatingIfNeeded: randomState >> 8)
    }
}
