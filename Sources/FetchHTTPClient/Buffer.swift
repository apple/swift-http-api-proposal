public class Buffer {
    var storage: UnsafeMutableBufferPointer<UInt8>
    var numElements: Int

    public init() {
        self.storage = .allocate(capacity: 4 * 1024)
        self.numElements = 0
    }

    public func hasSpace() -> Bool {
        return self.numElements < self.storage.count
    }
}

public class BufferArray {
    var buffers = [Buffer]()

    func toBytes() -> [UInt8] {
        var totalCapacity = 0
        for buffer in buffers {
            totalCapacity += buffer.numElements
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(totalCapacity)
        for buffer in buffers {
            let ptr: UnsafeMutableBufferPointer<UInt8>
            if (buffer.hasSpace()) {
                ptr = buffer.storage.extracting(0..<buffer.numElements)
            } else {
                ptr = buffer.storage
            }
            bytes.append(contentsOf: ptr)
        }
        return bytes
    }
}
