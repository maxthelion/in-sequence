import Foundation

final class AtomicInt64 {
    private let storage: UnsafeMutablePointer<Int64>

    init(_ value: Int64) {
        storage = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        storage.initialize(to: value)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    func load() -> Int64 {
        OSAtomicAdd64Barrier(0, storage)
    }

    func store(_ value: Int64) {
        while true {
            let oldValue = load()
            if OSAtomicCompareAndSwap64Barrier(oldValue, value, storage) {
                return
            }
        }
    }

    func storeMaximum(_ value: Int64, shouldReplace: (Int64, Int64) -> Bool) {
        while true {
            let oldValue = load()
            guard shouldReplace(oldValue, value) else { return }
            if OSAtomicCompareAndSwap64Barrier(oldValue, value, storage) {
                return
            }
        }
    }

    func exchange(_ value: Int64) -> Int64 {
        while true {
            let oldValue = load()
            if OSAtomicCompareAndSwap64Barrier(oldValue, value, storage) {
                return oldValue
            }
        }
    }
}

final class AtomicInt32 {
    private let storage: UnsafeMutablePointer<Int32>

    init(_ value: Int32) {
        storage = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        storage.initialize(to: value)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    func load() -> Int32 {
        OSAtomicAdd32Barrier(0, storage)
    }

    func store(_ value: Int32) {
        while true {
            let oldValue = load()
            if OSAtomicCompareAndSwap32Barrier(oldValue, value, storage) {
                return
            }
        }
    }

    @discardableResult
    func increment() -> Int32 {
        OSAtomicIncrement32Barrier(storage)
    }
}
