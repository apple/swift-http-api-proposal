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
struct CapsuleTypeTests {
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
    func hashableConformance() {
        let capsuleA = CapsuleType.addressAssign
        let capsuleD = CapsuleType.datagram

        // Test that different types have different hash values
        // Note: This is not guaranteed by Hashable but is expected in practice
        #expect(capsuleA.hashValue != capsuleD.hashValue)

        // Test that same version has same hash value
        #expect(capsuleA.hashValue == CapsuleType.addressAssign.hashValue)
        #expect(capsuleD.hashValue == CapsuleType.datagram.hashValue)
    }
}
