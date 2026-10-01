// 64bit 整数のシフトヘルパ (ARM EABI)。
//
// ARM7TDMI は 32bit CPU なので、コンパイラは UInt64 / Int64 の可変量シフトを
//   <<  → __aeabi_llsl,  >> (符号なし) → __aeabi_llsr,  >> (符号付き) → __aeabi_lasr
// の呼び出しに置き換えることがある (定数シフトはインライン展開される)。
//
// 64bit値は r0(下位):r1(上位)、シフト量は r2 で渡される。
// Swiftの (UInt64, Int32) -> UInt64 の @c ABI と一致する。
// 実装内で64bitシフトを使うと再帰呼び出しになるため、
// ポインタ経由で32bit半分ずつに分解して計算する。

/// UInt64 を64bitシフトを使わずに (lo, hi) に分解する。
@inline(__always)
private func split64(_ value: UInt64) -> (lo: UInt32, hi: UInt32) {
    var v = value
    return withUnsafePointer(to: &v) { ptr in
        let p = UnsafeRawPointer(ptr).assumingMemoryBound(to: UInt32.self)
        return (p[0], p[1])  // リトルエンディアン
    }
}

/// (lo, hi) から64bitシフトを使わずに UInt64 を組み立てる。
@inline(__always)
private func make64(lo: UInt32, hi: UInt32) -> UInt64 {
    var result: UInt64 = 0
    withUnsafeMutablePointer(to: &result) { ptr in
        let p = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: UInt32.self)
        p[0] = lo
        p[1] = hi
    }
    return result
}

@c(__aeabi_llsl)
@inline(never)
public func aeabiLlsl(_ a: UInt64, _ b: Int32) -> UInt64 {
    let (lo, hi) = split64(a)
    if b >= 32 {
        return make64(lo: 0, hi: lo &<< (b &- 32))
    } else if b == 0 {
        return a
    } else {
        return make64(lo: lo &<< b, hi: (hi &<< b) | (lo &>> (32 &- b)))
    }
}

@c(__aeabi_llsr)
@inline(never)
public func aeabiLlsr(_ a: UInt64, _ b: Int32) -> UInt64 {
    let (lo, hi) = split64(a)
    if b >= 32 {
        return make64(lo: hi &>> (b &- 32), hi: 0)
    } else if b == 0 {
        return a
    } else {
        return make64(lo: (lo &>> b) | (hi &<< (32 &- b)), hi: hi &>> b)
    }
}

@c(__aeabi_lasr)
@inline(never)
public func aeabiLasr(_ a: UInt64, _ b: Int32) -> UInt64 {
    let (lo, hi) = split64(a)
    let signedHi = Int32(bitPattern: hi)
    if b >= 32 {
        let shifted = signedHi &>> (b &- 32)
        return make64(lo: UInt32(bitPattern: shifted), hi: UInt32(bitPattern: signedHi &>> 31))
    } else if b == 0 {
        return a
    } else {
        return make64(
            lo: (lo &>> b) | (hi &<< (32 &- b)),
            hi: UInt32(bitPattern: signedHi &>> b)
        )
    }
}
