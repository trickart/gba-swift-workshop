// ARM EABI (Run-time ABI for the ARM Architecture) の浮動小数点ヘルパ関数。
// コンパイラが Float / Double の演算をこれらの呼び出しに置き換える。
// 本体は Operations.swift にあり、ここでは引数と返り値のビット列を受け渡すだけ。
//
// 呼び出し規約はソフトフロート ABI: Float は r0、Double は r0:r1 の整数レジスタで
// 渡される。Swift の @c 関数に Float / Double 型の引数を書けばそのまま一致する。

@inline(__always) private func bits(_ x: Float) -> UInt64 { UInt64(x.bitPattern) }
@inline(__always) private func bits(_ x: Double) -> UInt64 { x.bitPattern }
@inline(__always) private func single(_ bits: UInt64) -> Float { Float(bitPattern: UInt32(truncatingIfNeeded: bits)) }
@inline(__always) private func double(_ bits: UInt64) -> Double { Double(bitPattern: bits) }
@inline(__always) private func flag(_ value: Bool) -> Int32 { value ? 1 : 0 }

// MARK: - 単精度: 四則演算

@c(__aeabi_fadd)
public func aeabiFadd(_ a: Float, _ b: Float) -> Float { single(add(.single, bits(a), bits(b))) }

@c(__aeabi_fsub)
public func aeabiFsub(_ a: Float, _ b: Float) -> Float { single(subtract(.single, bits(a), bits(b))) }

/// b - a (引数が逆順の減算)
@c(__aeabi_frsub)
public func aeabiFrsub(_ a: Float, _ b: Float) -> Float { single(subtract(.single, bits(b), bits(a))) }

@c(__aeabi_fmul)
public func aeabiFmul(_ a: Float, _ b: Float) -> Float { single(multiply(.single, bits(a), bits(b))) }

@c(__aeabi_fdiv)
public func aeabiFdiv(_ a: Float, _ b: Float) -> Float { single(divide(.single, bits(a), bits(b))) }

// MARK: - 単精度: 比較 (真なら 1、偽または NaN を含むなら 0)

@c(__aeabi_fcmpeq)
public func aeabiFcmpeq(_ a: Float, _ b: Float) -> Int32 { flag(compare(.single, bits(a), bits(b)) == .equal) }

@c(__aeabi_fcmplt)
public func aeabiFcmplt(_ a: Float, _ b: Float) -> Int32 { flag(compare(.single, bits(a), bits(b)) == .less) }

@c(__aeabi_fcmple)
public func aeabiFcmple(_ a: Float, _ b: Float) -> Int32 {
    let order = compare(.single, bits(a), bits(b))
    return flag(order == .less || order == .equal)
}

@c(__aeabi_fcmpgt)
public func aeabiFcmpgt(_ a: Float, _ b: Float) -> Int32 { flag(compare(.single, bits(a), bits(b)) == .greater) }

@c(__aeabi_fcmpge)
public func aeabiFcmpge(_ a: Float, _ b: Float) -> Int32 {
    let order = compare(.single, bits(a), bits(b))
    return flag(order == .greater || order == .equal)
}

/// どちらかが NaN なら 1
@c(__aeabi_fcmpun)
public func aeabiFcmpun(_ a: Float, _ b: Float) -> Int32 { flag(compare(.single, bits(a), bits(b)) == .unordered) }

// MARK: - 単精度: 整数との変換 (z = 0 方向への切り捨て)

@c(__aeabi_f2iz)
public func aeabiF2iz(_ a: Float) -> Int32 {
    Int32(truncatingIfNeeded: toInteger(.single, bits(a), signed: true, width: 32))
}

@c(__aeabi_f2uiz)
public func aeabiF2uiz(_ a: Float) -> UInt32 {
    UInt32(truncatingIfNeeded: toInteger(.single, bits(a), signed: false, width: 32))
}

@c(__aeabi_f2lz)
public func aeabiF2lz(_ a: Float) -> Int64 {
    Int64(bitPattern: toInteger(.single, bits(a), signed: true, width: 64))
}

@c(__aeabi_f2ulz)
public func aeabiF2ulz(_ a: Float) -> UInt64 {
    toInteger(.single, bits(a), signed: false, width: 64)
}

@c(__aeabi_i2f)
public func aeabiI2f(_ a: Int32) -> Float { single(fromSigned(.single, Int64(a))) }

@c(__aeabi_ui2f)
public func aeabiUi2f(_ a: UInt32) -> Float { single(fromUnsigned(.single, UInt64(a))) }

@c(__aeabi_l2f)
public func aeabiL2f(_ a: Int64) -> Float { single(fromSigned(.single, a)) }

@c(__aeabi_ul2f)
public func aeabiUl2f(_ a: UInt64) -> Float { single(fromUnsigned(.single, a)) }

// MARK: - 倍精度: 四則演算

@c(__aeabi_dadd)
public func aeabiDadd(_ a: Double, _ b: Double) -> Double { double(add(.double, bits(a), bits(b))) }

@c(__aeabi_dsub)
public func aeabiDsub(_ a: Double, _ b: Double) -> Double { double(subtract(.double, bits(a), bits(b))) }

@c(__aeabi_drsub)
public func aeabiDrsub(_ a: Double, _ b: Double) -> Double { double(subtract(.double, bits(b), bits(a))) }

@c(__aeabi_dmul)
public func aeabiDmul(_ a: Double, _ b: Double) -> Double { double(multiply(.double, bits(a), bits(b))) }

@c(__aeabi_ddiv)
public func aeabiDdiv(_ a: Double, _ b: Double) -> Double { double(divide(.double, bits(a), bits(b))) }

// MARK: - 倍精度: 比較

@c(__aeabi_dcmpeq)
public func aeabiDcmpeq(_ a: Double, _ b: Double) -> Int32 { flag(compare(.double, bits(a), bits(b)) == .equal) }

@c(__aeabi_dcmplt)
public func aeabiDcmplt(_ a: Double, _ b: Double) -> Int32 { flag(compare(.double, bits(a), bits(b)) == .less) }

@c(__aeabi_dcmple)
public func aeabiDcmple(_ a: Double, _ b: Double) -> Int32 {
    let order = compare(.double, bits(a), bits(b))
    return flag(order == .less || order == .equal)
}

@c(__aeabi_dcmpgt)
public func aeabiDcmpgt(_ a: Double, _ b: Double) -> Int32 { flag(compare(.double, bits(a), bits(b)) == .greater) }

@c(__aeabi_dcmpge)
public func aeabiDcmpge(_ a: Double, _ b: Double) -> Int32 {
    let order = compare(.double, bits(a), bits(b))
    return flag(order == .greater || order == .equal)
}

@c(__aeabi_dcmpun)
public func aeabiDcmpun(_ a: Double, _ b: Double) -> Int32 { flag(compare(.double, bits(a), bits(b)) == .unordered) }

// MARK: - 倍精度: 整数との変換

@c(__aeabi_d2iz)
public func aeabiD2iz(_ a: Double) -> Int32 {
    Int32(truncatingIfNeeded: toInteger(.double, bits(a), signed: true, width: 32))
}

@c(__aeabi_d2uiz)
public func aeabiD2uiz(_ a: Double) -> UInt32 {
    UInt32(truncatingIfNeeded: toInteger(.double, bits(a), signed: false, width: 32))
}

@c(__aeabi_d2lz)
public func aeabiD2lz(_ a: Double) -> Int64 {
    Int64(bitPattern: toInteger(.double, bits(a), signed: true, width: 64))
}

@c(__aeabi_d2ulz)
public func aeabiD2ulz(_ a: Double) -> UInt64 {
    toInteger(.double, bits(a), signed: false, width: 64)
}

@c(__aeabi_i2d)
public func aeabiI2d(_ a: Int32) -> Double { double(fromSigned(.double, Int64(a))) }

@c(__aeabi_ui2d)
public func aeabiUi2d(_ a: UInt32) -> Double { double(fromUnsigned(.double, UInt64(a))) }

@c(__aeabi_l2d)
public func aeabiL2d(_ a: Int64) -> Double { double(fromSigned(.double, a)) }

@c(__aeabi_ul2d)
public func aeabiUl2d(_ a: UInt64) -> Double { double(fromUnsigned(.double, a)) }

// MARK: - 形式間の変換 (半精度は UInt16 のビット列で受け渡す)

@c(__aeabi_f2d)
public func aeabiF2d(_ a: Float) -> Double { double(convert(bits(a), from: .single, to: .double)) }

@c(__aeabi_d2f)
public func aeabiD2f(_ a: Double) -> Float { single(convert(bits(a), from: .double, to: .single)) }

@c(__aeabi_h2f)
public func aeabiH2f(_ a: UInt16) -> Float { single(convert(UInt64(a), from: .half, to: .single)) }

@c(__aeabi_f2h)
public func aeabiF2h(_ a: Float) -> UInt16 { UInt16(truncatingIfNeeded: convert(bits(a), from: .single, to: .half)) }

@c(__aeabi_d2h)
public func aeabiD2h(_ a: Double) -> UInt16 { UInt16(truncatingIfNeeded: convert(bits(a), from: .double, to: .half)) }
