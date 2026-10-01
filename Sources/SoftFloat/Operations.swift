// ソフトフロートの演算本体。すべて形式 (Format) をパラメータに取り、
// ビット列 (UInt64 に右詰め) を受け取ってビット列を返す。
// 単精度と倍精度 (と半精度) で同じコードを共有する。

// MARK: - 加減算

/// a + b
func add(_ format: Format, _ aBits: UInt64, _ bBits: UInt64) -> UInt64 {
    switch (unpack(format, aBits), unpack(format, bBits)) {
    case (.nan, _), (_, .nan):
        return format.quietNaN
    case (.infinity(let aNegative), .infinity(let bNegative)):
        // ∞ + ∞ = ∞、∞ + (-∞) = NaN
        return aNegative == bNegative ? aBits : format.quietNaN
    case (.infinity, _):
        return aBits
    case (_, .infinity):
        return bBits
    case (.zero(let aNegative), .zero(let bNegative)):
        // (-0) + (-0) だけが -0、それ以外は +0
        return format.zero(negative: aNegative && bNegative)
    case (.zero, _):
        return bBits
    case (_, .zero):
        return aBits
    case (.finite(let a), .finite(let b)):
        return addFinite(format, a, b)
    }
}

/// a - b (b の符号を反転して加算)
func subtract(_ format: Format, _ aBits: UInt64, _ bBits: UInt64) -> UInt64 {
    add(format, aBits, bBits ^ format.signMask)
}

/// 有限かつ非ゼロ同士の加算
private func addFinite(_ format: Format, _ a: Unpacked, _ b: Unpacked) -> UInt64 {
    // 絶対値の大きい方を big にする (減算の結果が負にならないように)
    var big = a
    var small = b
    if Unpacked.compareMagnitude(b, a) > 0 {
        big = b
        small = a
    }

    // 指数を揃える: small の仮数を右にずらし、こぼれたビットは sticky にまとめる
    let shift = big.exponent - small.exponent
    var smallSignificand = small.significand
    var sticky = false
    if shift >= 64 {
        sticky = true
        smallSignificand = 0
    } else if shift > 0 {
        sticky = smallSignificand & ((1 << UInt64(shift)) - 1) != 0
        smallSignificand >>= UInt64(shift)
    }

    if big.negative == small.negative {
        // 同符号: 加算。繰り上がったら 1 ビット右にずらす
        let (sum, carry) = big.significand.addingReportingOverflow(smallSignificand)
        var significand = sum
        var exponent = big.exponent
        if carry {
            sticky = sticky || significand & 1 != 0
            significand = (significand >> 1) | (1 << 63)
            exponent += 1
        }
        return pack(format, negative: big.negative, exponent: exponent, significand: significand, sticky: sticky)
    }

    // 異符号: 減算。
    // sticky が立っている (small の下に非ゼロのビットがある) ときの真の差は
    // big - small_shifted より少し小さいので、1 引いた値を sticky 付きで扱う。
    // sticky が立つのは shift が (64 - precision) より大きいときだけで、そのとき
    // small_shifted は big に比べて十分小さく、差の先頭ゼロは高々 1 ビットなので、
    // 不確かなビットが丸めの判定位置まで上がってくることはない。
    var significand = big.significand &- smallSignificand
    if sticky {
        significand &-= 1
    }
    if significand == 0 {
        // x - x は +0 (最近接丸めでは常に正のゼロ)
        return format.zero(negative: false)
    }
    let leadingZeros = significand.leadingZeroBitCount
    significand <<= UInt64(leadingZeros)
    return pack(
        format,
        negative: big.negative,
        exponent: big.exponent - leadingZeros,
        significand: significand,
        sticky: sticky
    )
}

// MARK: - 乗除算

/// a × b
func multiply(_ format: Format, _ aBits: UInt64, _ bBits: UInt64) -> UInt64 {
    let negative = (aBits ^ bBits) & format.signMask != 0
    switch (unpack(format, aBits), unpack(format, bBits)) {
    case (.nan, _), (_, .nan):
        return format.quietNaN
    case (.infinity, .zero), (.zero, .infinity):
        return format.quietNaN
    case (.infinity, _), (_, .infinity):
        return format.infinity(negative: negative)
    case (.zero, _), (_, .zero):
        return format.zero(negative: negative)
    case (.finite(let a), .finite(let b)):
        let product = multiplyFull(a.significand, b.significand)
        return packProduct(format, negative: negative, exponent: a.exponent + b.exponent, product: product)
    }
}

/// 仮数同士の 128bit 積 (2^126 以上 2^128 未満) を 64bit に詰めてビット列にする。
/// exponent は両者の指数の和。積の値は product × 2^(exponent - 126)。
private func packProduct(_ format: Format, negative: Bool, exponent: Int, product: UInt128Bits) -> UInt64 {
    if product.hi >> 63 != 0 {
        return pack(format, negative: negative, exponent: exponent + 1, significand: product.hi, sticky: product.lo != 0)
    }
    let significand = (product.hi << 1) | (product.lo >> 63)
    return pack(format, negative: negative, exponent: exponent, significand: significand, sticky: product.lo << 1 != 0)
}

/// a ÷ b
func divide(_ format: Format, _ aBits: UInt64, _ bBits: UInt64) -> UInt64 {
    let negative = (aBits ^ bBits) & format.signMask != 0
    switch (unpack(format, aBits), unpack(format, bBits)) {
    case (.nan, _), (_, .nan):
        return format.quietNaN
    case (.infinity, .infinity), (.zero, .zero):
        return format.quietNaN
    case (.infinity, _), (_, .zero):
        return format.infinity(negative: negative)
    case (.zero, _), (_, .infinity):
        return format.zero(negative: negative)
    case (.finite(let a), .finite(let b)):
        return divideFinite(format, negative: negative, a, b)
    }
}

private func divideFinite(_ format: Format, negative: Bool, _ a: Unpacked, _ b: Unpacked) -> UInt64 {
    // 筆算 (引き戻し法) で商を 64 ビット求める。
    // 余り (remainder) は 65 ビットになりうるので、あふれた最上位ビットを
    // overflow として別に持つ。
    var remainder = a.significand
    let divisor = b.significand
    var exponent = a.exponent - b.exponent
    var overflow = false

    // 商の最上位ビットが必ず 1 になるよう、a < b なら a を 2 倍しておく
    if remainder < divisor {
        overflow = true  // bit 63 は立っているので 2 倍すると必ずあふれる
        remainder <<= 1
        exponent -= 1
    }

    var quotient: UInt64 = 0
    for _ in 0..<64 {
        quotient <<= 1
        if overflow || remainder >= divisor {
            remainder = remainder &- divisor
            quotient |= 1
        }
        overflow = remainder >> 63 != 0
        remainder <<= 1
    }
    let sticky = overflow || remainder != 0
    return pack(format, negative: negative, exponent: exponent, significand: quotient, sticky: sticky)
}

// MARK: - 積和 (fma)

/// a × b + c を 1 回だけ丸める
func fusedMultiplyAdd(_ format: Format, _ aBits: UInt64, _ bBits: UInt64, _ cBits: UInt64) -> UInt64 {
    let productNegative = (aBits ^ bBits) & format.signMask != 0
    let a = unpack(format, aBits)
    let b = unpack(format, bBits)
    let c = unpack(format, cBits)

    // 特殊値の処理
    switch (a, b, c) {
    case (.nan, _, _), (_, .nan, _), (_, _, .nan):
        return format.quietNaN
    case (.infinity, .zero, _), (.zero, .infinity, _):
        return format.quietNaN
    case (.infinity, _, _), (_, .infinity, _):
        // 積は無限大。c が逆符号の無限大なら NaN
        if case .infinity(let cNegative) = c, cNegative != productNegative {
            return format.quietNaN
        }
        return format.infinity(negative: productNegative)
    case (_, _, .infinity):
        return cBits
    case (.zero, _, _), (_, .zero, _):
        // 積は (符号付き) ゼロ。ゼロ + c の規則に従う
        return add(format, format.zero(negative: productNegative), cBits)
    case (.finite, .finite, .zero):
        return multiply(format, aBits, bBits)
    default:
        break
    }
    guard case .finite(let x) = a, case .finite(let y) = b, case .finite(let z) = c else {
        return format.quietNaN  // ここには来ない
    }

    // 積を 128bit で正確に求め、bit 127 に揃える
    var product = multiplyFull(x.significand, y.significand)
    var productExponent = x.exponent + y.exponent + 1
    if product.hi >> 63 == 0 {
        product = product.shiftedLeft(by: 1)
        productExponent -= 1
    }
    // c も 128bit に広げる (上位 64bit に置く)
    let addend = UInt128Bits(hi: z.significand, lo: 0)

    // 以降は addFinite と同じ手順を 128bit で行う
    var bigNegative = productNegative
    var bigExponent = productExponent
    var big = product
    var smallNegative = z.negative
    var smallExponent = z.exponent
    var small = addend
    if z.exponent > productExponent || (z.exponent == productExponent && addend > product) {
        swap(&big, &small)
        swap(&bigExponent, &smallExponent)
        swap(&bigNegative, &smallNegative)
    }

    var sticky = false
    small = small.shiftedRight(by: bigExponent - smallExponent, sticky: &sticky)

    var exponent = bigExponent
    var sum: UInt128Bits
    if bigNegative == smallNegative {
        let (result, carry) = big.adding(small)
        sum = result
        if carry {
            sum = sum.shiftedRight(by: 1, sticky: &sticky)
            sum.hi |= 1 << 63
            exponent += 1
        }
    } else {
        sum = big.subtracting(small)
        if sticky {
            sum = sum.subtracting(UInt128Bits(hi: 0, lo: 1))
        }
        if sum.isZero {
            return format.zero(negative: false)
        }
        let leadingZeros = sum.leadingZeroBitCount
        sum = sum.shiftedLeft(by: leadingZeros)
        exponent -= leadingZeros
    }
    // 128bit → 64bit: 下位 64bit はすべて sticky にまとめる
    sticky = sticky || sum.lo != 0
    return pack(format, negative: bigNegative, exponent: exponent, significand: sum.hi, sticky: sticky)
}

// MARK: - 平方根

func squareRoot(_ format: Format, _ aBits: UInt64) -> UInt64 {
    switch unpack(format, aBits) {
    case .nan:
        return format.quietNaN
    case .infinity(let negative):
        return negative ? format.quietNaN : aBits
    case .zero:
        return aBits  // sqrt(±0) = ±0
    case .finite(let a):
        if a.negative { return format.quietNaN }
        // 指数を偶数にして 128bit の整数 X を作り、floor(sqrt(X)) を求める。
        //   偶数: X = sig × 2^63  → sqrt(X) = sqrt(sig / 2^63) × 2^63 ∈ [2^63, 2^63.5)
        //   奇数: X = sig × 2^64  → sqrt(X) = sqrt(sig / 2^62) × 2^63 ∈ [2^63.5, 2^64)
        // どちらも結果の bit 63 が立つ。
        var radicand: UInt128Bits
        let exponent: Int
        if a.exponent & 1 == 0 {
            radicand = UInt128Bits(hi: a.significand >> 1, lo: a.significand << 63)
            exponent = a.exponent >> 1
        } else {
            radicand = UInt128Bits(hi: a.significand, lo: 0)
            exponent = (a.exponent - 1) >> 1
        }
        // 1 桁ずつ (2 ビットずつ) 求める筆算の開平法
        var remainder = UInt128Bits(hi: 0, lo: 0)
        var root: UInt64 = 0
        for _ in 0..<64 {
            let top2 = radicand.hi >> 62
            radicand = radicand.shiftedLeft(by: 2)
            remainder = remainder.shiftedLeft(by: 2)
            remainder.lo |= top2
            // root を r、新しい桁を 1 にしたときの増分は (2r+1)^2 - (2r)^2 = 4r + 1
            let trial = UInt128Bits(hi: root >> 62, lo: (root << 2) | 1)
            root <<= 1
            if remainder >= trial {
                remainder = remainder.subtracting(trial)
                root |= 1
            }
        }
        // 余りが残れば真の値は root より大きい (ちょうど中間になることはない)
        return pack(format, negative: false, exponent: exponent, significand: root, sticky: !remainder.isZero)
    }
}

// MARK: - 比較

enum Ordering {
    case less
    case equal
    case greater
    case unordered
}

func compare(_ format: Format, _ aBits: UInt64, _ bBits: UInt64) -> Ordering {
    if isNaN(format, aBits) || isNaN(format, bBits) { return .unordered }
    let a = orderKey(format, aBits)
    let b = orderKey(format, bBits)
    if a < b { return .less }
    if a > b { return .greater }
    return .equal
}

func isNaN(_ format: Format, _ bits: UInt64) -> Bool {
    bits & format.exponentFieldMask == format.exponentFieldMask && bits & format.mantissaMask != 0
}

/// 大小関係が整数の比較と一致するような値に変換する (+0 と -0 はどちらも 0)
private func orderKey(_ format: Format, _ bits: UInt64) -> Int64 {
    let magnitude = Int64(bitPattern: bits & (format.signMask - 1))
    return bits & format.signMask != 0 ? -magnitude : magnitude
}

// MARK: - 整数との変換

/// 0 方向への切り捨てで整数に変換する。
/// 範囲外は飽和し NaN は 0 になる (ARM の浮動小数点ユニットと同じ)。
/// 返り値は width ビットの整数のビットパターン (符号付きは 2 の補数)。
func toInteger(_ format: Format, _ bits: UInt64, signed: Bool, width: Int) -> UInt64 {
    let unsignedMax: UInt64 = width == 64 ? .max : (1 << UInt64(width)) - 1
    let signedLimit: UInt64 = 1 << UInt64(width - 1)  // 2^(width-1)
    func saturate(negative: Bool) -> UInt64 {
        if signed { return negative ? 0 &- signedLimit : signedLimit - 1 }
        return negative ? 0 : unsignedMax
    }

    switch unpack(format, bits) {
    case .nan, .zero:
        return 0
    case .infinity(let negative):
        return saturate(negative: negative)
    case .finite(let a):
        if a.exponent < 0 { return 0 }  // |a| < 1
        if a.exponent >= 64 { return saturate(negative: a.negative) }
        let magnitude = a.significand >> UInt64(63 - a.exponent)
        if signed {
            if a.negative {
                return magnitude >= signedLimit ? 0 &- signedLimit : 0 &- magnitude
            }
            return magnitude >= signedLimit ? signedLimit - 1 : magnitude
        }
        if a.negative { return 0 }
        return magnitude > unsignedMax ? unsignedMax : magnitude
    }
}

/// 符号付き整数から変換する
func fromSigned(_ format: Format, _ value: Int64) -> UInt64 {
    let negative = value < 0
    let magnitude = negative ? 0 &- UInt64(bitPattern: value) : UInt64(bitPattern: value)
    return packInteger(format, negative: negative, magnitude: magnitude)
}

/// 符号なし整数から変換する
func fromUnsigned(_ format: Format, _ value: UInt64) -> UInt64 {
    packInteger(format, negative: false, magnitude: value)
}

// MARK: - 形式間の変換

/// 別の形式に変換する (精度が下がる場合は丸める)
func convert(_ bits: UInt64, from source: Format, to target: Format) -> UInt64 {
    switch unpack(source, bits) {
    case .nan:
        return target.quietNaN
    case .infinity(let negative):
        return target.infinity(negative: negative)
    case .zero(let negative):
        return target.zero(negative: negative)
    case .finite(let a):
        return pack(target, negative: a.negative, exponent: a.exponent, significand: a.significand, sticky: false)
    }
}

// MARK: - 整数への丸め (floor / ceil / trunc / round / rint)

enum RoundingMode {
    case towardZero       // trunc
    case down             // floor
    case up               // ceil
    case nearestAway      // round (0.5 は 0 から遠い方へ)
    case nearestEven      // rint (0.5 は偶数へ)
}

func roundToIntegral(_ format: Format, _ bits: UInt64, _ mode: RoundingMode) -> UInt64 {
    let negative = bits & format.signMask != 0
    let signBits = bits & format.signMask
    let exponentField = Int((bits >> UInt64(format.mantissaBits)) & UInt64(format.exponentFieldMax))
    if exponentField == format.exponentFieldMax {
        return isNaN(format, bits) ? format.quietNaN : bits  // NaN / ∞
    }
    let exponent = exponentField - format.bias
    let one = signBits | format.one

    if exponentField == 0 || exponent < 0 {
        // |x| < 1: 結果は ±0 か ±1。符号は x のものを保つ
        let isZero = exponentField == 0 && bits & format.mantissaMask == 0
        let isHalf = exponent == -1 && bits & format.mantissaMask == 0
        let atLeastHalf = exponent == -1
        switch mode {
        case .towardZero:
            return signBits
        case .down:
            return negative && !isZero ? one : signBits
        case .up:
            return !negative && !isZero ? one : signBits
        case .nearestAway:
            return atLeastHalf ? one : signBits
        case .nearestEven:
            return atLeastHalf && !isHalf ? one : signBits
        }
    }

    if exponent >= format.mantissaBits {
        return bits  // すでに整数
    }
    // 小数部のビット数と、その中での 1/2 の位置
    let fractionBits = UInt64(format.mantissaBits - exponent)
    let fractionMask: UInt64 = (1 << fractionBits) - 1
    let fraction = bits & fractionMask
    if fraction == 0 {
        return bits
    }
    let truncated = bits & ~fractionMask
    // 整数部の最下位に 1 を足す (指数への繰り上がりもビット列上で自然に起きる)
    let roundedAway = truncated + (1 << fractionBits)
    let half: UInt64 = 1 << (fractionBits - 1)
    switch mode {
    case .towardZero:
        return truncated
    case .down:
        return negative ? roundedAway : truncated
    case .up:
        return negative ? truncated : roundedAway
    case .nearestAway:
        return fraction >= half ? roundedAway : truncated
    case .nearestEven:
        let integerIsOdd = bits & (1 << fractionBits) != 0
        return fraction > half || (fraction == half && integerIsOdd) ? roundedAway : truncated
    }
}

// MARK: - 剰余 (fmod / remainder)

/// fmod(a, b): a - trunc(a / b) × b。結果の符号は a と同じで、誤差なく求まる。
func truncatingRemainder(_ format: Format, _ aBits: UInt64, _ bBits: UInt64) -> UInt64 {
    remainderCore(format, aBits, bBits).result
}

/// IEEE 754 の remainder(a, b): a - n × b、n は a / b に最も近い整数 (中間は偶数)。
func ieeeRemainder(_ format: Format, _ aBits: UInt64, _ bBits: UInt64) -> UInt64 {
    let core = remainderCore(format, aBits, bBits)
    guard case .finite(let r) = unpack(format, core.result),
          case .finite(let b) = unpack(format, bBits) else {
        return core.result  // 特殊値、またはちょうど割り切れた (±0)
    }
    // |r| < |b| のはず。2|r| と |b| を比べて、|r| が |b|/2 を超える (中間なら商が奇数) なら
    // 商を 1 つ寄せて r から ±|b| を引く
    let doubled = Unpacked(negative: false, exponent: r.exponent + 1, significand: r.significand)
    let order = Unpacked.compareMagnitude(doubled, Unpacked(negative: false, exponent: b.exponent, significand: b.significand))
    if order > 0 || (order == 0 && core.quotientIsOdd) {
        // r - sign(a) × |b| = r + (|b| に a と逆の符号を付けたもの)
        let signedB = (bBits & ~format.signMask) | ((aBits & format.signMask) ^ format.signMask)
        return add(format, core.result, signedB)
    }
    return core.result
}

/// fmod 本体。商 (切り捨て) の最下位ビットも返す
private func remainderCore(_ format: Format, _ aBits: UInt64, _ bBits: UInt64) -> (result: UInt64, quotientIsOdd: Bool) {
    let a: Unpacked
    let b: Unpacked
    switch (unpack(format, aBits), unpack(format, bBits)) {
    case (.nan, _), (_, .nan), (.infinity, _), (_, .zero):
        return (format.quietNaN, false)
    case (_, .infinity), (.zero, _):
        return (aBits, false)
    case (.finite(let x), .finite(let y)):
        a = x
        b = y
    }
    if Unpacked.compareMagnitude(a, b) < 0 {
        return (aBits, false)
    }

    // 筆算: 指数差 + 1 桁ぶんの商を上から順に求め、余りだけを残す。
    // 余りは 65 ビットになりうるので overflow を別に持つ (divideFinite と同じ)。
    var remainder = a.significand
    let divisor = b.significand
    var overflow = false
    for _ in 0..<(a.exponent - b.exponent) {
        if overflow || remainder >= divisor {
            remainder = remainder &- divisor
        }
        overflow = remainder >> 63 != 0
        remainder <<= 1
    }
    let quotientIsOdd = overflow || remainder >= divisor
    if quotientIsOdd {
        remainder = remainder &- divisor
    }
    if remainder == 0 {
        return (format.zero(negative: a.negative), quotientIsOdd)
    }
    // 余りは b と同じ桁 (2^(b.exponent - 63)) の単位。正規化して詰め直す (誤差なし)
    let leadingZeros = remainder.leadingZeroBitCount
    let result = pack(
        format,
        negative: a.negative,
        exponent: b.exponent - leadingZeros,
        significand: remainder << UInt64(leadingZeros),
        sticky: false
    )
    return (result, quotientIsOdd)
}
