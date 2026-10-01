// ベアメタルARM (GBA / ARM7TDMI) 上の Embedded Swift に必要なメモリ操作関数。
//
// -nostdlib でリンクするため、Cライブラリの memset/memcpy/memmove/memcmp と
// ARM EABI のメモリ操作ヘルパ (__aeabi_memcpy / __aeabi_memclr など) をここで提供する。
// アトミック操作のスタブ (__atomic_*) は AtomicStubs.swift にある。
// 整数演算のヘルパ (64bit シフト・除算) は Sources/IntegerArithmetic、
// 浮動小数点は Sources/SoftFloat にある。
//
// このターゲットは -Xllvm -disable-loop-idiom-memcpy/-memset 付きでコンパイル
// される。LLVMがバイトコピー/クリアのループを認識して、まさにここで定義して
// いる関数への呼び出しに置き換えてしまう(無限再帰になる)のを防ぐため。

// MARK: - 実装本体
//
// 公開する関数 (memset や __aeabi_memclr など) は、すべてここの関数を
// インライン展開して作る。公開関数どうしで呼び合ってはいけない:
// LLVMは memset/memcpy/memmove という名前の関数への呼び出しを標準ライブラリ
// 関数とみなし、ARM EABI では __aeabi_memclr などの呼び出しに置き換える。
// そのため、たとえば __aeabi_memclr の中から memset を呼ぶと、自分自身を
// 呼び続ける無限再帰になる。

@inline(__always)
private func fill(_ dest: UnsafeMutableRawPointer, _ value: Int32, _ count: Int) {
    let byte = UInt8(truncatingIfNeeded: value)
    let ptr = dest.assumingMemoryBound(to: UInt8.self)
    for i in 0..<count {
        ptr[i] = byte
    }
}

@inline(__always)
private func copy(_ dest: UnsafeMutableRawPointer, _ src: UnsafeRawPointer, _ count: Int) {
    let d = dest.assumingMemoryBound(to: UInt8.self)
    let s = src.assumingMemoryBound(to: UInt8.self)
    for i in 0..<count {
        d[i] = s[i]
    }
}

/// 領域が重なっていても正しくコピーする
@inline(__always)
private func move(_ dest: UnsafeMutableRawPointer, _ src: UnsafeRawPointer, _ count: Int) {
    let d = dest.assumingMemoryBound(to: UInt8.self)
    let s = src.assumingMemoryBound(to: UInt8.self)
    if UInt(bitPattern: d) < UInt(bitPattern: s) {
        for i in 0..<count {
            d[i] = s[i]
        }
    } else if UInt(bitPattern: d) > UInt(bitPattern: s) {
        var i = count
        while i > 0 {
            i &-= 1
            d[i] = s[i]
        }
    }
}

// MARK: - libc メモリ関数

@c
@inline(never)
public func memset(
    _ dest: UnsafeMutableRawPointer,
    _ value: Int32,
    _ count: Int
) -> UnsafeMutableRawPointer {
    fill(dest, value, count)
    return dest
}

@c
@inline(never)
public func memcpy(
    _ dest: UnsafeMutableRawPointer,
    _ src: UnsafeRawPointer,
    _ count: Int
) -> UnsafeMutableRawPointer {
    copy(dest, src, count)
    return dest
}

@c
@inline(never)
public func memmove(
    _ dest: UnsafeMutableRawPointer,
    _ src: UnsafeRawPointer,
    _ count: Int
) -> UnsafeMutableRawPointer {
    move(dest, src, count)
    return dest
}

@c
@inline(never)
public func memcmp(
    _ a: UnsafeRawPointer,
    _ b: UnsafeRawPointer,
    _ count: Int
) -> Int32 {
    let pa = a.assumingMemoryBound(to: UInt8.self)
    let pb = b.assumingMemoryBound(to: UInt8.self)
    for i in 0..<count {
        if pa[i] != pb[i] {
            return pa[i] < pb[i] ? -1 : 1
        }
    }
    return 0
}

// MARK: - __aeabi_mem* (LLVMがAEABIターゲットで生成することがある)
// 注意: __aeabi_memset は memset と引数順が異なる (dest, n, value)。

@c(__aeabi_memcpy)
public func aeabiMemcpy(_ dest: UnsafeMutableRawPointer, _ src: UnsafeRawPointer, _ n: Int) {
    copy(dest, src, n)
}

@c(__aeabi_memcpy4)
public func aeabiMemcpy4(_ dest: UnsafeMutableRawPointer, _ src: UnsafeRawPointer, _ n: Int) {
    copy(dest, src, n)
}

@c(__aeabi_memcpy8)
public func aeabiMemcpy8(_ dest: UnsafeMutableRawPointer, _ src: UnsafeRawPointer, _ n: Int) {
    copy(dest, src, n)
}

@c(__aeabi_memmove)
public func aeabiMemmove(_ dest: UnsafeMutableRawPointer, _ src: UnsafeRawPointer, _ n: Int) {
    move(dest, src, n)
}

@c(__aeabi_memmove4)
public func aeabiMemmove4(_ dest: UnsafeMutableRawPointer, _ src: UnsafeRawPointer, _ n: Int) {
    move(dest, src, n)
}

@c(__aeabi_memmove8)
public func aeabiMemmove8(_ dest: UnsafeMutableRawPointer, _ src: UnsafeRawPointer, _ n: Int) {
    move(dest, src, n)
}

@c(__aeabi_memset)
public func aeabiMemset(_ dest: UnsafeMutableRawPointer, _ n: Int, _ value: Int32) {
    fill(dest, value, n)
}

@c(__aeabi_memset4)
public func aeabiMemset4(_ dest: UnsafeMutableRawPointer, _ n: Int, _ value: Int32) {
    fill(dest, value, n)
}

@c(__aeabi_memset8)
public func aeabiMemset8(_ dest: UnsafeMutableRawPointer, _ n: Int, _ value: Int32) {
    fill(dest, value, n)
}

@c(__aeabi_memclr)
public func aeabiMemclr(_ dest: UnsafeMutableRawPointer, _ n: Int) {
    fill(dest, 0, n)
}

@c(__aeabi_memclr4)
public func aeabiMemclr4(_ dest: UnsafeMutableRawPointer, _ n: Int) {
    fill(dest, 0, n)
}

@c(__aeabi_memclr8)
public func aeabiMemclr8(_ dest: UnsafeMutableRawPointer, _ n: Int) {
    fill(dest, 0, n)
}
