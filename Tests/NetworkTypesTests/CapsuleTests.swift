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
struct CapsuleTests {
    @Test
    func datagramTypeIsZero() {
        #expect(CapsuleType.datagram.rawValue == 0)
        #expect(CapsuleType.datagram == 0)
    }

    @Test
    func capsuleTypeEqualityIsByCode() {
        #expect(CapsuleType(5) == CapsuleType(5))
        #expect(CapsuleType(5) != CapsuleType(6))
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func decodesDatagramCapsule() {
        let bytes: [UInt8] = [0x00, 0x04, 0xde, 0xad, 0xbe, 0xef]
        var rest = bytes.span
        if let capsule = Capsule.decode(from: &rest) {
            #expect(capsule.type == .datagram)
            #expect(capsule.value.count == 4)
            #expect(capsule.value[0] == 0xde)
        } else {
            Issue.record("expected to decode a capsule")
        }
        #expect(rest.count == 0)
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func decodesEmptyValue() {
        let bytes: [UInt8] = [0x00, 0x00]
        var rest = bytes.span
        if let capsule = Capsule.decode(from: &rest) {
            #expect(capsule.type == .datagram)
            #expect(capsule.value.count == 0)
        } else {
            Issue.record("expected to decode an empty-value capsule")
        }
        #expect(rest.count == 0)
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func decodesUnknownType() {
        // Type 0x21 (unassigned), length 2, value [0xaa, 0xbb].
        let bytes: [UInt8] = [0x21, 0x02, 0xaa, 0xbb]
        var rest = bytes.span
        if let capsule = Capsule.decode(from: &rest) {
            #expect(capsule.type == CapsuleType(0x21))
            #expect(capsule.value.count == 2)
        } else {
            Issue.record("expected to decode an unknown-type capsule")
        }
        #expect(rest.count == 0)
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func decodesMultipleCapsulesAndLeavesTruncatedRemainder() {
        // Two complete capsules, then a truncated third (type 0x00, length 2, one value byte).
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x01, 0xaa, 0x00, 0x02, 0xbb]
        var rest = bytes.span
        var count = 0
        while let capsule = Capsule.decode(from: &rest) {
            count += 1
            _ = capsule.type
        }
        #expect(count == 2)
        #expect(rest.count == 3)
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func peekHeaderReadsHeaderWithoutMutation() {
        // Type 0x00, length 16384 (a 4-byte varint: 80 00 40 00); no value bytes present.
        let bytes: [UInt8] = [0x00, 0x80, 0x00, 0x40, 0x00]
        let header = Capsule.peekHeader(from: bytes.span)
        #expect(header?.type == .datagram)
        #expect(header?.valueByteCount == 16_384)
        #expect(header?.headerByteCount == 5)
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func decodeHeaderReadsHeaderChangingSpan() {
        // Type 0x00, length 16384 (a 4-byte varint: 80 00 40 00); no value bytes present.
        let bytes: [UInt8] = [0x00, 0x80, 0x00, 0x40, 0x00]
        var bytesSpan = bytes.span
        let header = Capsule.decodeHeader(from: &bytesSpan)
        #expect(header?.type == .datagram)
        #expect(header?.valueByteCount == 16_384)
        #expect(header?.headerByteCount == 5)
        #expect(bytesSpan.count == 0)
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func peekAllFCapsuleTypeHeader() {
        let bytes: [UInt8] = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00]
        let header = Capsule.peekHeader(from: bytes.span)
        #expect(header?.type == CapsuleType(QUICVariableLengthInteger.max))
        #expect(header?.valueByteCount == 0)
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func encodedByteCountMatchesLayout() throws {
        let payload: [UInt8] = [0xde, 0xad, 0xbe, 0xef]
        let capsule = Capsule(type: .datagram, value: payload)
        #expect(try capsule.encodedByteCount == 6)  // 1 (type) + 1 (length) + 4 (value)
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func encodesDatagramToWireBytes() throws {
        let payload: [UInt8] = [0xde, 0xad, 0xbe, 0xef]
        let count = try Capsule(type: .datagram, value: payload).encodedByteCount
        let encoded = try [UInt8](capacity: count) { output in
            try Capsule(type: .datagram, value: payload).encode(into: &output)
        }
        #expect(encoded == [0x00, 0x04, 0xde, 0xad, 0xbe, 0xef])
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func encodeHeaderWritesOnlyFraming() throws {
        let encoded = try [UInt8](capacity: 16) { output in
            try Capsule.encodeHeader(type: .datagram, valueByteCount: 4, into: &output)
        }
        #expect(encoded == [0x00, 0x04])
    }

    @Test
    @available(anyAppleOS 26.0, *)
    func roundTripsThroughEncodeAndDecode() throws {
        let payload: [UInt8] = [0x01, 0x02, 0x03]
        let count = try Capsule(type: CapsuleType(0x1234), value: payload).encodedByteCount
        let encoded = try [UInt8](capacity: count) { output in
            try Capsule(type: CapsuleType(0x1234), value: payload).encode(into: &output)
        }
        var rest = encoded.span
        if let decoded = Capsule.decode(from: &rest) {
            #expect(decoded.type == CapsuleType(0x1234))
            #expect(decoded.value.count == 3)
            #expect(decoded.value[0] == 0x01)
            #expect(decoded.value[1] == 0x02)
            #expect(decoded.value[2] == 0x03)
        } else {
            Issue.record("expected to decode the round-tripped capsule")
        }
        #expect(rest.count == 0)
    }
}
