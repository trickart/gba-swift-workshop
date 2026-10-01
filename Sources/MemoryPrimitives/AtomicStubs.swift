// __atomic_* ライブラリコールのスタブ。
//
// ARM7TDMI (armv4t) にはアトミック命令がないため、LLVMはアトミック操作を
// libatomic 形式のライブラリコールに変換する (Swiftランタイムの swift_once や
// _Volatile モジュールのアクセスなどが該当)。
// GBA はシングルコアで、このプロジェクトは割り込みハンドラ内から
// これらを呼ばないため、通常のload/storeで十分。
//
// memorder引数はABI上必要なだけで無視する。

// MARK: - load

@c(__atomic_load_1)
@inline(never)
public func atomicLoad1(_ ptr: UnsafeRawPointer, _ memorder: Int32) -> UInt8 {
    ptr.assumingMemoryBound(to: UInt8.self).pointee
}

@c(__atomic_load_2)
@inline(never)
public func atomicLoad2(_ ptr: UnsafeRawPointer, _ memorder: Int32) -> UInt16 {
    ptr.assumingMemoryBound(to: UInt16.self).pointee
}

@c(__atomic_load_4)
@inline(never)
public func atomicLoad4(_ ptr: UnsafeRawPointer, _ memorder: Int32) -> UInt32 {
    ptr.assumingMemoryBound(to: UInt32.self).pointee
}

// MARK: - store

@c(__atomic_store_1)
@inline(never)
public func atomicStore1(_ ptr: UnsafeMutableRawPointer, _ value: UInt8, _ memorder: Int32) {
    ptr.assumingMemoryBound(to: UInt8.self).pointee = value
}

@c(__atomic_store_2)
@inline(never)
public func atomicStore2(_ ptr: UnsafeMutableRawPointer, _ value: UInt16, _ memorder: Int32) {
    ptr.assumingMemoryBound(to: UInt16.self).pointee = value
}

@c(__atomic_store_4)
@inline(never)
public func atomicStore4(_ ptr: UnsafeMutableRawPointer, _ value: UInt32, _ memorder: Int32) {
    ptr.assumingMemoryBound(to: UInt32.self).pointee = value
}

// MARK: - exchange

@c(__atomic_exchange_1)
@inline(never)
public func atomicExchange1(_ ptr: UnsafeMutableRawPointer, _ value: UInt8, _ memorder: Int32) -> UInt8 {
    let p = ptr.assumingMemoryBound(to: UInt8.self)
    let old = p.pointee
    p.pointee = value
    return old
}

@c(__atomic_exchange_2)
@inline(never)
public func atomicExchange2(_ ptr: UnsafeMutableRawPointer, _ value: UInt16, _ memorder: Int32) -> UInt16 {
    let p = ptr.assumingMemoryBound(to: UInt16.self)
    let old = p.pointee
    p.pointee = value
    return old
}

@c(__atomic_exchange_4)
@inline(never)
public func atomicExchange4(_ ptr: UnsafeMutableRawPointer, _ value: UInt32, _ memorder: Int32) -> UInt32 {
    let p = ptr.assumingMemoryBound(to: UInt32.self)
    let old = p.pointee
    p.pointee = value
    return old
}

// MARK: - compare_exchange

@c(__atomic_compare_exchange_1)
@inline(never)
public func atomicCompareExchange1(
    _ ptr: UnsafeMutableRawPointer,
    _ expected: UnsafeMutableRawPointer,
    _ desired: UInt8,
    _ successOrder: Int32,
    _ failureOrder: Int32
) -> Bool {
    let p = ptr.assumingMemoryBound(to: UInt8.self)
    let e = expected.assumingMemoryBound(to: UInt8.self)
    if p.pointee == e.pointee {
        p.pointee = desired
        return true
    }
    e.pointee = p.pointee
    return false
}

@c(__atomic_compare_exchange_2)
@inline(never)
public func atomicCompareExchange2(
    _ ptr: UnsafeMutableRawPointer,
    _ expected: UnsafeMutableRawPointer,
    _ desired: UInt16,
    _ successOrder: Int32,
    _ failureOrder: Int32
) -> Bool {
    let p = ptr.assumingMemoryBound(to: UInt16.self)
    let e = expected.assumingMemoryBound(to: UInt16.self)
    if p.pointee == e.pointee {
        p.pointee = desired
        return true
    }
    e.pointee = p.pointee
    return false
}

@c(__atomic_compare_exchange_4)
@inline(never)
public func atomicCompareExchange4(
    _ ptr: UnsafeMutableRawPointer,
    _ expected: UnsafeMutableRawPointer,
    _ desired: UInt32,
    _ successOrder: Int32,
    _ failureOrder: Int32
) -> Bool {
    let p = ptr.assumingMemoryBound(to: UInt32.self)
    let e = expected.assumingMemoryBound(to: UInt32.self)
    if p.pointee == e.pointee {
        p.pointee = desired
        return true
    }
    e.pointee = p.pointee
    return false
}

// MARK: - fetch_add / fetch_sub / fetch_and / fetch_or / fetch_xor (4バイトのみ)

@c(__atomic_fetch_add_4)
@inline(never)
public func atomicFetchAdd4(_ ptr: UnsafeMutableRawPointer, _ value: UInt32, _ memorder: Int32) -> UInt32 {
    let p = ptr.assumingMemoryBound(to: UInt32.self)
    let old = p.pointee
    p.pointee = old &+ value
    return old
}

@c(__atomic_fetch_sub_4)
@inline(never)
public func atomicFetchSub4(_ ptr: UnsafeMutableRawPointer, _ value: UInt32, _ memorder: Int32) -> UInt32 {
    let p = ptr.assumingMemoryBound(to: UInt32.self)
    let old = p.pointee
    p.pointee = old &- value
    return old
}

@c(__atomic_fetch_and_4)
@inline(never)
public func atomicFetchAnd4(_ ptr: UnsafeMutableRawPointer, _ value: UInt32, _ memorder: Int32) -> UInt32 {
    let p = ptr.assumingMemoryBound(to: UInt32.self)
    let old = p.pointee
    p.pointee = old & value
    return old
}

@c(__atomic_fetch_or_4)
@inline(never)
public func atomicFetchOr4(_ ptr: UnsafeMutableRawPointer, _ value: UInt32, _ memorder: Int32) -> UInt32 {
    let p = ptr.assumingMemoryBound(to: UInt32.self)
    let old = p.pointee
    p.pointee = old | value
    return old
}

@c(__atomic_fetch_xor_4)
@inline(never)
public func atomicFetchXor4(_ ptr: UnsafeMutableRawPointer, _ value: UInt32, _ memorder: Int32) -> UInt32 {
    let p = ptr.assumingMemoryBound(to: UInt32.self)
    let old = p.pointee
    p.pointee = old ^ value
    return old
}
