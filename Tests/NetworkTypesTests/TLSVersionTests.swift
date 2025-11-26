//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP API Proposal project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NetworkTypes
import Testing

@Suite
struct TLSVersionTests {
    @Test
    func versionsAreDistinct() {
        let v1_2 = TLSVersion.v1_2
        let v1_3 = TLSVersion.v1_3

        #expect(v1_2 != v1_3)
    }

    @Test
    func equalityWorks() {
        let v1_2_first = TLSVersion.v1_2
        let v1_2_second = TLSVersion.v1_2

        #expect(v1_2_first == v1_2_second)
    }

    @Test
    func hashableConformance() {
        let v1_2 = TLSVersion.v1_2
        let v1_3 = TLSVersion.v1_3

        // Test that different versions have different hash values
        // Note: This is not guaranteed by Hashable but is expected in practice
        #expect(v1_2.hashValue != v1_3.hashValue)

        // Test that same version has same hash value
        #expect(v1_2.hashValue == TLSVersion.v1_2.hashValue)
        #expect(v1_3.hashValue == TLSVersion.v1_3.hashValue)
    }
}
