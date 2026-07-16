//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// A QUIC variable-length integer, as defined in RFC 9000, Section 16.
///
/// The two most significant bits of the first byte select the encoded length
/// (1, 2, 4, or 8 bytes); the remaining bits hold the value in network byte
/// order.
public enum VariableLengthInteger {
    /// The largest representable value, `2^62 - 1`.
    public static var max: UInt64 { 0x3FFF_FFFF_FFFF_FFFF }

    /// The number of bytes the minimal encoding of `value` occupies (1, 2, 4, or 8).
    ///
    /// - throws: ``NetworkTypeError.exceedsMaximumValue`` if `value` is greater than ``max``.
    public static func encodedByteCount(_ value: UInt64) throws(NetworkTypeError) -> Int {
        // 2 bits are reserved to encode the number of bytes.
        // N bytes can encode N * 8 - 2 bits.
        switch 64 - value.leadingZeroBitCount {
        case 0...6: return 1  // fits in 6 bits
        case 7...14: return 2  // fits in 14 bits
        case 15...30: return 4  // fits in 30 bits
        case 31...62: return 8  // fits in 62 bits
        default: throw .exceedsMaximumValue
        }
    }

    /// Write`value` into `output` in network byte order.
    ///
    /// - Precondition: `output` has enough capcity to write `value`.
    private static func write<T: BinaryInteger & FixedWidthInteger>(_ value: T, into output: inout OutputSpan<UInt8>) {
        let numBytes = MemoryLayout<T>.size
        assert(output.capacity >= numBytes)
        let valueBigEndian = value.bigEndian

        withUnsafeBytes(of: valueBigEndian) { bufferPointer in
            for unsafe value in unsafe bufferPointer {
                output.append(value)
            }
        }
    }

    /// Encodes `value` into `output` using the minimal number of bytes.
    ///
    /// - throws: ``NetworkTypeError.exceedsMaximumValue`` if `value` is greater than ``max``.
    /// - throws: ``NetworkTypeError.insufficientCapacity`` if `output` does not have enough capacity to encode `value`.
    public static func encode(_ value: UInt64, into output: inout OutputSpan<UInt8>) throws(NetworkTypeError) {
        let byteCount = try Self.encodedByteCount(value)
        guard output.capacity >= byteCount else {
            throw NetworkTypeError.insufficientCapacity
        }

        switch byteCount {
        case 1:
            let value = UInt8(truncatingIfNeeded: value)
            Self.write(value, into: &output)
        case 2:
            let value = UInt16(truncatingIfNeeded: value | 0x4000)
            Self.write(value, into: &output)
        case 4:
            let value = UInt32(truncatingIfNeeded: value | 0x8000_0000)
            Self.write(value, into: &output)
        case 8:
            let value = UInt64(truncatingIfNeeded: value | 0xC000_0000_0000_0000)
            Self.write(value, into: &output)
        default:
            throw .exceedsMaximumValue
        }
    }

    /// A decoded value and the bytes read to decode it.
    public struct DecodeResult {
        /// The decoded value.
        public let value: UInt64

        /// Number of bytes used for the encoding.
        ///
        /// This might differ from `encodedByteCount(value)` since it is not
        /// required that values are encoded using the minimum number of bytes.
        public let byteCount: Int
    }

    /// Decodes the variable-length integer at the front of `input`.
    ///
    /// - Returns: The decoded value and the number of bytes it occupied, or
    ///   `nil` if `input` holds fewer bytes than its length prefix requires.
    public static func decode(from input: Span<UInt8>) -> DecodeResult? {
        guard input.count > 0 else {
            return nil
        }

        let first = input[0]
        // Extract bits that signifiy the number bytes used for encoding.
        let byteCount = 1 << Int(first >> 6)
        guard input.count >= byteCount else {
            return nil
        }

        var value = UInt64(first & 0x3F)
        for index in 1..<byteCount {
            value = (value << 8) | UInt64(input[index])
        }
        return .init(value: value, byteCount: byteCount)
    }
}
