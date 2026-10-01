// 64bit 整数の除算と、先頭ゼロの数え上げ (ARM EABI のヘルパ関数)。
// 64bit シフトは Shifts.swift にある。
//
// ARM7TDMI には除算命令も CLZ 命令もないため、コンパイラは
//   Int64 / Int64, Int64 % Int64     → __aeabi_ldivmod
//   UInt64 / UInt64, UInt64 % UInt64 → __aeabi_uldivmod
//   leadingZeroBitCount              → __clzsi2
// の呼び出しを生成する。32bit の除算ヘルパ (__aeabi_uidiv / __aeabi_idiv /
// __aeabi_uidivmod / __aeabi_idivmod) は GBA BIOS の SWI 0x06 (Div) を使うため
// Sources/Startup/crt0.S でアセンブリ実装している。
//
// __aeabi_[u]ldivmod は「商を r0:r1、余りを r2:r3 で同時に返す」規約で、
// これは Swift の関数では表現できない。そこで本体をここに Swift で書き、
// Sources/Startup/crt0.S の薄いシムが余りをレジスタに積み替える:
//   __aeabi_uldivmod → __udivmoddi4(n, d, &余り)  (この名前は libgcc / compiler-rt と同じ)
//   __aeabi_ldivmod  → __divmoddi4(n, d, &余り)
//
// 注意: この中で UInt64 / Int64 の / や % を使うと、それ自体が __aeabi_uldivmod の
// 呼び出しになって無限再帰する。使うのは UInt32 の除算 (crt0.S 経由で GBA BIOS の
// SWI 0x06 Div が実行される) だけにする。

// MARK: - 先頭ゼロの数え上げ

/// 32bit 値の先頭ゼロの数 (0 なら 32)。16, 8, 4, 2, 1 ビットずつの二分探索。
/// leadingZeroBitCount はこの関数の呼び出しになるので、ここでは使えない。
@c(__clzsi2)
public func clzsi2(_ value: UInt32) -> Int32 {
    if value == 0 { return 32 }
    var x = value
    var count: Int32 = 0
    if x >> 16 == 0 { count += 16; x <<= 16 }
    if x >> 24 == 0 { count += 8; x <<= 8 }
    if x >> 28 == 0 { count += 4; x <<= 4 }
    if x >> 30 == 0 { count += 2; x <<= 2 }
    if x >> 31 == 0 { count += 1 }
    return count
}

// MARK: - 64bit 除算

/// 符号なし 64bit 除算。商を返し、余りを remainder に書く。
@c(__udivmoddi4)
public func udivmoddi4(_ n: UInt64, _ d: UInt64, _ remainder: UnsafeMutablePointer<UInt64>?) -> UInt64 {
    // 両方が 32bit に収まるなら UInt32 の除算 = BIOS の Div (crt0.S の __aeabi_uidivmod)
    if n >> 32 == 0 && d >> 32 == 0 {
        let n32 = UInt32(truncatingIfNeeded: n)
        let d32 = UInt32(truncatingIfNeeded: d)
        let q = n32 / d32
        remainder?.pointee = UInt64(n32 &- q &* d32)
        return UInt64(q)
    }
    if n < d {
        remainder?.pointee = n
        return 0
    }
    // 筆算 (引き戻し法)。除数の先頭ビットを被除数の先頭に揃えてから、
    // 1 桁ずつ下げながら引けるかどうかを調べる。
    // 除数の方を右にずらしていくので、余りが 64bit からあふれることはない。
    let shift = d.leadingZeroBitCount - n.leadingZeroBitCount
    var divisor = d << UInt64(shift)
    var rest = n
    var quotient: UInt64 = 0
    for _ in 0...shift {
        quotient <<= 1
        if rest >= divisor {
            rest &-= divisor
            quotient |= 1
        }
        divisor >>= 1
    }
    remainder?.pointee = rest
    return quotient
}

/// 符号付き 64bit 除算 (0 方向への切り捨て。余りの符号は被除数と同じ)。
/// 絶対値で udivmoddi4 を呼び、符号を後から付け直す。
@c(__divmoddi4)
public func divmoddi4(_ n: Int64, _ d: Int64, _ remainder: UnsafeMutablePointer<Int64>?) -> Int64 {
    let nNegative = n < 0
    let dNegative = d < 0
    let nMagnitude = nNegative ? 0 &- UInt64(bitPattern: n) : UInt64(bitPattern: n)
    let dMagnitude = dNegative ? 0 &- UInt64(bitPattern: d) : UInt64(bitPattern: d)
    var rest: UInt64 = 0
    let quotient = udivmoddi4(nMagnitude, dMagnitude, &rest)
    remainder?.pointee = Int64(bitPattern: nNegative ? 0 &- rest : rest)
    return Int64(bitPattern: nNegative != dNegative ? 0 &- quotient : quotient)
}
