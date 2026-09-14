import Foundation

/// A small locked ring of Float samples for playback. Drops the oldest samples when full.
final class FloatRing {
    private var storage: [Float]
    private var readIndex = 0
    private var writeIndex = 0
    private(set) var count = 0
    private let lock = NSLock()

    init(capacity: Int) { storage = [Float](repeating: 0, count: max(1, capacity)) }

    func write(_ samples: UnsafeBufferPointer<Float>) {
        lock.lock(); defer { lock.unlock() }
        let cap = storage.count
        for s in samples {
            storage[writeIndex] = s
            writeIndex = (writeIndex + 1) % cap
            if count == cap { readIndex = (readIndex + 1) % cap } else { count += 1 }
        }
    }

    /// Fills `out` with up to its length; the rest is silence. Returns how many real samples were read.
    func read(into out: UnsafeMutablePointer<Float>, frames: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        let n = min(frames, count)
        let cap = storage.count
        for i in 0..<n {
            out[i] = storage[readIndex]
            readIndex = (readIndex + 1) % cap
        }
        count -= n
        if n < frames { for i in n..<frames { out[i] = 0 } }
        return n
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        readIndex = 0; writeIndex = 0; count = 0
    }
}
