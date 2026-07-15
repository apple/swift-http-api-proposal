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

import NetworkTypes
import Testing

@Suite
struct VariableLengthIntegerTests {
    /// Encodes `value` into a fresh byte array via the OutputSpan initializer.
    @available(anyAppleOS 26.0, *)
    static func encoded(_ value: UInt64) throws -> [UInt8] {
        try [UInt8](capacity: 8) { output in
            try VariableLengthInteger.encode(value, into: &output)
        }
    }

    /// Encodes `value` into a fresh byte array of `capacity` bytes via the OutputSpan initializer.
    @available(anyAppleOS 26.0, *)
    static func encoded(_ value: UInt64, intoBufferWithCapacity capacity: Int) throws -> [UInt8] {
        try [UInt8](capacity: capacity) { output in
            try VariableLengthInteger.encode(value, into: &output)
        }
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func encodedByteCount() throws {
        #expect(try VariableLengthInteger.encodedByteCount(0) == 1)
        #expect(try VariableLengthInteger.encodedByteCount(0x3F) == 1)

        #expect(try VariableLengthInteger.encodedByteCount(0x3F + 1) == 2)
        #expect(try VariableLengthInteger.encodedByteCount(0x3FFF) == 2)

        #expect(try VariableLengthInteger.encodedByteCount(0x3FFF + 1) == 4)
        #expect(try VariableLengthInteger.encodedByteCount(0x3FFF_FFFF) == 4)

        #expect(try VariableLengthInteger.encodedByteCount(0x3FFF_FFFF + 1) == 8)
        #expect(try VariableLengthInteger.encodedByteCount(VariableLengthInteger.max) == 8)

        #expect(throws: NetworkTypeError.exceedsMaximumValue.self) {
            try VariableLengthInteger.encodedByteCount(VariableLengthInteger.max + 1)
        }
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func decodesRFC9000Vectors() {
        let eightByte: [UInt8] = [0xc2, 0x19, 0x7c, 0x5e, 0xff, 0x14, 0xe8, 0x8c]
        #expect(VariableLengthInteger.decode(from: eightByte.span)?.value == 151_288_809_941_952_652)
        let fourByte: [UInt8] = [0x9d, 0x7f, 0x3e, 0x7d]
        #expect(VariableLengthInteger.decode(from: fourByte.span)?.value == 494_878_333)
        let twoByte: [UInt8] = [0x7b, 0xbd]
        #expect(VariableLengthInteger.decode(from: twoByte.span)?.value == 15_293)
        let oneByte: [UInt8] = [0x25]
        #expect(VariableLengthInteger.decode(from: oneByte.span)?.value == 37)
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func decodesNonMinimalEncoding() {
        // 37 encoded in two bytes instead of one; legal to receive (RFC 9297 §1.1).
        let bytes: [UInt8] = [0x40, 0x25]
        let result = VariableLengthInteger.decode(from: bytes.span)
        #expect(result?.value == 37)
        #expect(result?.byteCount == 2)
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func decodeReturnsNilWhenTruncated() {
        // First byte announces a 4-byte integer, only 2 bytes present.
        let truncated: [UInt8] = [0x9d, 0x7f]
        #expect(VariableLengthInteger.decode(from: truncated.span) == nil)
        let empty: [UInt8] = []
        #expect(VariableLengthInteger.decode(from: empty.span) == nil)
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func encodesToMinimalForm() throws {
        #expect(try Self.encoded(63) == [0x3f])
        #expect(try Self.encoded(64) == [0x40, 0x40])
        #expect(try Self.encoded(15_293) == [0x7b, 0xbd])
    }

    @Test(arguments: [
        (UInt64(15_293), 1),
        (UInt64(494_878_333), 1),
        (UInt64(494_878_333), 2),
        (UInt64(151_288_809_941_952_652), 1),
        (UInt64(151_288_809_941_952_652), 2),
        (UInt64(151_288_809_941_952_652), 3),
    ])
    @available(anyAppleOS 26.0, *)
    func encodesThrowsWhenNotEnoughCapacity(number: UInt64, capacity: Int) throws {
        #expect(throws: NetworkTypeError.self) { try Self.encoded(number, intoBufferWithCapacity: capacity) }
    }

    @Test(arguments: [UInt64]([0, 63, 64, 16_383, 16_384, 1_073_741_823, 1_073_741_824, 0x3FFF_FFFF_FFFF_FFFF]))
    @available(anyAppleOS 26.0, *)
    func roundTripsAllBoundaries(value: UInt64) throws {
        let bytes = try Self.encoded(value)
        let decoded = VariableLengthInteger.decode(from: bytes.span)
        #expect(decoded?.value == value)
        #expect(decoded?.byteCount == bytes.count)
    }
}
