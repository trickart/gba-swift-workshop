// ソフトフロートの中核: 形式の定義、ビット列と「分解形」の相互変換、128bit 整数。
//
// GBA の CPU (ARM7TDMI) には浮動小数点ユニットがないため、Float / Double の
// 演算はコンパイラが ARM EABI のヘルパ関数 (__aeabi_fadd など) の呼び出しに
// 置き換える。このモジュールはそのヘルパ関数を Swift で実装する。
//
// 重要: このモジュール内では Float / Double の演算子や変換を一切使わない。
// 使うと、その演算がこのモジュール自身のヘルパ関数の呼び出しになって無限再帰する。
// 値はすべて UInt32 / UInt64 のビット列として扱い、Float(bitPattern:) と
// .bitPattern (どちらもビットの読み替えだけで演算を伴わない) で出入りする。
//
// 丸めは IEEE 754 の「最近接・偶数丸め」のみ対応する (Swift の既定と同じ)。
// 非正規化数、無限大、NaN、符号付きゼロも規格どおりに扱う。
// NaN は中身 (ペイロード) を伝搬せず、常に quiet NaN の標準形を返す。

// MARK: - 形式

/// IEEE 754 二進形式のパラメータ (半精度 / 単精度 / 倍精度)
struct Format {
    /// 全体のビット数
    let totalBits: Int
    /// 仮数部フィールドのビット数 (隠れビットを除く)
    let mantissaBits: Int
    /// 指数部フィールドのビット数
    let exponentBits: Int

    // static let にすると遅延初期化のグローバル変数 (swift_once) になるので、
    // 計算プロパティにして定数畳み込みされるようにする
    static var half: Format { Format(totalBits: 16, mantissaBits: 10, exponentBits: 5) }
    static var single: Format { Format(totalBits: 32, mantissaBits: 23, exponentBits: 8) }
    static var double: Format { Format(totalBits: 64, mantissaBits: 52, exponentBits: 11) }

    /// 有効桁数 (隠れビットを含む仮数のビット数)
    var precision: Int { mantissaBits + 1 }
    var bias: Int { (1 << (exponentBits - 1)) - 1 }
    /// 正規化数の最小指数 (これより小さい値は非正規化数になる)
    var minExponent: Int { 1 - bias }
    var maxExponent: Int { bias }
    var exponentFieldMax: Int { (1 << exponentBits) - 1 }

    var signMask: UInt64 { 1 << UInt64(totalBits - 1) }
    var mantissaMask: UInt64 { (1 << UInt64(mantissaBits)) - 1 }
    var hiddenBit: UInt64 { 1 << UInt64(mantissaBits) }
    var exponentFieldMask: UInt64 { UInt64(exponentFieldMax) << UInt64(mantissaBits) }

    /// 標準形の quiet NaN (符号は正)
    var quietNaN: UInt64 { exponentFieldMask | (1 << UInt64(mantissaBits - 1)) }

    func infinity(negative: Bool) -> UInt64 {
        (negative ? signMask : 0) | exponentFieldMask
    }

    func zero(negative: Bool) -> UInt64 {
        negative ? signMask : 0
    }

    /// 1.0 のビット列
    var one: UInt64 { UInt64(bias) << UInt64(mantissaBits) }
}

// MARK: - 分解形

/// 有限かつ非ゼロの値の分解形。
/// 値 = (-1)^negative × significand × 2^(exponent - 63)
/// significand は常に bit 63 が立つよう正規化してある (非正規化数も正規化して持つ)。
/// つまり値は [2^exponent, 2^(exponent+1)) の範囲にある。
struct Unpacked {
    var negative: Bool
    var exponent: Int
    var significand: UInt64

    /// 絶対値の比較 (a < b なら負、等しければ 0、a > b なら正)
    static func compareMagnitude(_ a: Unpacked, _ b: Unpacked) -> Int {
        if a.exponent != b.exponent { return a.exponent < b.exponent ? -1 : 1 }
        if a.significand != b.significand { return a.significand < b.significand ? -1 : 1 }
        return 0
    }
}

/// ビット列を分類した結果
enum Value {
    case nan
    case infinity(negative: Bool)
    case zero(negative: Bool)
    case finite(Unpacked)
}

/// ビット列を分解する
func unpack(_ format: Format, _ bits: UInt64) -> Value {
    let negative = bits & format.signMask != 0
    let exponentField = Int((bits >> UInt64(format.mantissaBits)) & UInt64(format.exponentFieldMax))
    let mantissa = bits & format.mantissaMask

    if exponentField == format.exponentFieldMax {
        return mantissa == 0 ? .infinity(negative: negative) : .nan
    }
    if exponentField == 0 && mantissa == 0 {
        return .zero(negative: negative)
    }

    // 仮数を bit 63 に寄せる。非正規化数は隠れビットがなく最上位が下にあるので、
    // 指数を minExponent にした上で先頭の 1 が bit 63 に来るまで左に詰める。
    let shift = UInt64(64 - format.precision)
    var significand: UInt64
    var exponent: Int
    if exponentField == 0 {
        significand = mantissa << shift
        exponent = format.minExponent
        let leadingZeros = significand.leadingZeroBitCount
        significand <<= UInt64(leadingZeros)
        exponent -= leadingZeros
    } else {
        significand = (mantissa | format.hiddenBit) << shift
        exponent = exponentField - format.bias
    }
    return .finite(Unpacked(negative: negative, exponent: exponent, significand: significand))
}

/// 分解形をビット列に戻す。ここで丸め (最近接・偶数丸め) を行う。
///
/// significand は bit 63 が立っている (または全体が 0 の) 64bit 値で、
/// 有効桁より下のビットが丸めの判断に使われる。
/// sticky は「significand の下にさらに非ゼロのビットが続いている」ことを示す。
/// 指数が範囲を超えれば無限大、下回れば非正規化数またはゼロになる。
func pack(_ format: Format, negative: Bool, exponent: Int, significand: UInt64, sticky: Bool) -> UInt64 {
    var exponent = exponent
    var significand = significand
    var sticky = sticky
    let dropBits = UInt64(64 - format.precision)

    // 非正規化数: 指数を minExponent に固定し、その分だけ仮数を右にずらす
    if exponent < format.minExponent {
        let extra = format.minExponent - exponent
        if extra >= 64 {
            sticky = sticky || significand != 0
            significand = 0
        } else {
            sticky = sticky || significand & ((1 << UInt64(extra)) - 1) != 0
            significand >>= UInt64(extra)
        }
        exponent = format.minExponent
    }

    // 丸め: 落とすビット列 (rest) と 1/2 (half) を比べる
    var mantissa = significand >> dropBits
    let rest = significand & ((1 << dropBits) - 1)
    let half: UInt64 = 1 << (dropBits - 1)
    let roundUp = rest > half || (rest == half && (sticky || mantissa & 1 != 0))
    if roundUp {
        mantissa += 1
        // 繰り上がりで桁が増えたら指数を 1 つ上げる (仮数は 2^precision ちょうど)
        if mantissa >> UInt64(format.precision) != 0 {
            mantissa >>= 1
            exponent += 1
        }
    }

    if exponent > format.maxExponent {
        return format.infinity(negative: negative)
    }
    let signBits = negative ? format.signMask : 0
    if mantissa & format.hiddenBit == 0 {
        // 隠れビットが立っていない = ゼロまたは非正規化数 (指数フィールド 0)
        return signBits | mantissa
    }
    return signBits
        | UInt64(exponent + format.bias) << UInt64(format.mantissaBits)
        | (mantissa & format.mantissaMask)
}

/// 符号なし整数から分解形を作ってビット列にする (magnitude == 0 なら符号付きゼロ)
func packInteger(_ format: Format, negative: Bool, magnitude: UInt64) -> UInt64 {
    if magnitude == 0 { return format.zero(negative: negative) }
    let leadingZeros = magnitude.leadingZeroBitCount
    return pack(
        format,
        negative: negative,
        exponent: 63 - leadingZeros,
        significand: magnitude << UInt64(leadingZeros),
        sticky: false
    )
}

// MARK: - 128bit 整数 (乗算、fma、平方根で使う)

struct UInt128Bits {
    var hi: UInt64
    var lo: UInt64

    var isZero: Bool { hi == 0 && lo == 0 }

    var leadingZeroBitCount: Int {
        hi != 0 ? hi.leadingZeroBitCount : 64 + lo.leadingZeroBitCount
    }

    static func >= (a: UInt128Bits, b: UInt128Bits) -> Bool {
        a.hi != b.hi ? a.hi > b.hi : a.lo >= b.lo
    }

    static func == (a: UInt128Bits, b: UInt128Bits) -> Bool {
        a.hi == b.hi && a.lo == b.lo
    }

    static func > (a: UInt128Bits, b: UInt128Bits) -> Bool {
        a.hi != b.hi ? a.hi > b.hi : a.lo > b.lo
    }

    /// 加算。繰り上がり (129bit 目) を返す
    func adding(_ other: UInt128Bits) -> (result: UInt128Bits, carry: Bool) {
        let (lo, carryLo) = self.lo.addingReportingOverflow(other.lo)
        let (hi1, carryHi1) = self.hi.addingReportingOverflow(other.hi)
        let (hi, carryHi2) = hi1.addingReportingOverflow(carryLo ? 1 : 0)
        return (UInt128Bits(hi: hi, lo: lo), carryHi1 || carryHi2)
    }

    /// 減算 (self >= other であること)
    func subtracting(_ other: UInt128Bits) -> UInt128Bits {
        let (lo, borrow) = self.lo.subtractingReportingOverflow(other.lo)
        let hi = self.hi &- other.hi &- (borrow ? 1 : 0)
        return UInt128Bits(hi: hi, lo: lo)
    }

    /// 左シフト (0 <= count < 128)
    func shiftedLeft(by count: Int) -> UInt128Bits {
        if count == 0 { return self }
        if count >= 64 { return UInt128Bits(hi: lo << UInt64(count - 64), lo: 0) }
        return UInt128Bits(hi: (hi << UInt64(count)) | (lo >> UInt64(64 - count)), lo: lo << UInt64(count))
    }

    /// 右シフト。こぼれたビットに非ゼロがあれば sticky を立てる
    func shiftedRight(by count: Int, sticky: inout Bool) -> UInt128Bits {
        if count == 0 { return self }
        if count >= 128 {
            sticky = sticky || !isZero
            return UInt128Bits(hi: 0, lo: 0)
        }
        if count >= 64 {
            let dropped = count - 64
            sticky = sticky || lo != 0 || (dropped > 0 && hi & ((1 << UInt64(dropped)) - 1) != 0)
            return UInt128Bits(hi: 0, lo: hi >> UInt64(dropped))
        }
        sticky = sticky || lo & ((1 << UInt64(count)) - 1) != 0
        return UInt128Bits(hi: hi >> UInt64(count), lo: (lo >> UInt64(count)) | (hi << UInt64(64 - count)))
    }
}

/// 64bit × 64bit → 128bit の乗算 (32bit の部分積 4 つで組み立てる)
func multiplyFull(_ a: UInt64, _ b: UInt64) -> UInt128Bits {
    let mask: UInt64 = 0xFFFF_FFFF
    let a0 = a & mask, a1 = a >> 32
    let b0 = b & mask, b1 = b >> 32
    let p00 = a0 &* b0
    let p01 = a0 &* b1
    let p10 = a1 &* b0
    let p11 = a1 &* b1
    // 中段: p00 の上位 + p01 の下位 + p10 の下位 (最大でも 3 × 2^32 程度で 64bit に収まる)
    let mid = (p00 >> 32) &+ (p01 & mask) &+ (p10 & mask)
    let lo = (mid << 32) | (p00 & mask)
    let hi = p11 &+ (p01 >> 32) &+ (p10 >> 32) &+ (mid >> 32)
    return UInt128Bits(hi: hi, lo: lo)
}
