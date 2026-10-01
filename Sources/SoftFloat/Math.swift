// C の数学ライブラリ (libm) のうち、Swift 標準ライブラリの基本的な浮動小数点 API が
// 内部で呼ぶもの。-nostdlib では libm がないのでここで提供する。
//
//   squareRoot()                      → sqrtf / sqrt
//   rounded(.down / .up / .towardZero) → floorf / ceilf / truncf (と double 版)
//   rounded() / rounded(.toNearestOrEven) → roundf / rintf
//   truncatingRemainder(dividingBy:)   → fmodf / fmod
//   remainder(dividingBy:)             → remainderf / remainder
//   addingProduct(_:_:)                → fmaf / fma
//
// sin / cos / exp / log / pow などの超越関数は提供していない。

@inline(__always) private func bits(_ x: Float) -> UInt64 { UInt64(x.bitPattern) }
@inline(__always) private func bits(_ x: Double) -> UInt64 { x.bitPattern }
@inline(__always) private func single(_ bits: UInt64) -> Float { Float(bitPattern: UInt32(truncatingIfNeeded: bits)) }
@inline(__always) private func double(_ bits: UInt64) -> Double { Double(bitPattern: bits) }

// MARK: - 平方根

@c(sqrtf)
public func softSqrtf(_ x: Float) -> Float { single(squareRoot(.single, bits(x))) }

@c(sqrt)
public func softSqrt(_ x: Double) -> Double { double(squareRoot(.double, bits(x))) }

// MARK: - 整数への丸め

@c(floorf)
public func softFloorf(_ x: Float) -> Float { single(roundToIntegral(.single, bits(x), .down)) }

@c(floor)
public func softFloor(_ x: Double) -> Double { double(roundToIntegral(.double, bits(x), .down)) }

@c(ceilf)
public func softCeilf(_ x: Float) -> Float { single(roundToIntegral(.single, bits(x), .up)) }

@c(ceil)
public func softCeil(_ x: Double) -> Double { double(roundToIntegral(.double, bits(x), .up)) }

@c(truncf)
public func softTruncf(_ x: Float) -> Float { single(roundToIntegral(.single, bits(x), .towardZero)) }

@c(trunc)
public func softTrunc(_ x: Double) -> Double { double(roundToIntegral(.double, bits(x), .towardZero)) }

@c(roundf)
public func softRoundf(_ x: Float) -> Float { single(roundToIntegral(.single, bits(x), .nearestAway)) }

@c(round)
public func softRound(_ x: Double) -> Double { double(roundToIntegral(.double, bits(x), .nearestAway)) }

@c(rintf)
public func softRintf(_ x: Float) -> Float { single(roundToIntegral(.single, bits(x), .nearestEven)) }

@c(rint)
public func softRint(_ x: Double) -> Double { double(roundToIntegral(.double, bits(x), .nearestEven)) }

// MARK: - 剰余

@c(fmodf)
public func softFmodf(_ x: Float, _ y: Float) -> Float { single(truncatingRemainder(.single, bits(x), bits(y))) }

@c(fmod)
public func softFmod(_ x: Double, _ y: Double) -> Double { double(truncatingRemainder(.double, bits(x), bits(y))) }

@c(remainderf)
public func softRemainderf(_ x: Float, _ y: Float) -> Float { single(ieeeRemainder(.single, bits(x), bits(y))) }

@c(remainder)
public func softRemainder(_ x: Double, _ y: Double) -> Double { double(ieeeRemainder(.double, bits(x), bits(y))) }

// MARK: - 積和

@c(fmaf)
public func softFmaf(_ x: Float, _ y: Float, _ z: Float) -> Float {
    single(fusedMultiplyAdd(.single, bits(x), bits(y), bits(z)))
}

@c(fma)
public func softFma(_ x: Double, _ y: Double, _ z: Double) -> Double {
    double(fusedMultiplyAdd(.double, bits(x), bits(y), bits(z)))
}
