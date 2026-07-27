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
    func initialization() {
        let capsule = Capsule(type: .datagram, value: [0x01, 0x02])
        #expect(capsule.type == .datagram)
        #expect(capsule.value == [0x01, 0x02])
        #expect(capsule.value.count == 2)
    }
}
