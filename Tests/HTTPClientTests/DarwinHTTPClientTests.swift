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

import HTTPClient
import HTTPClientConformance
import Testing

let testsEnabled: Bool = {
    #if canImport(Darwin)
    true
    #else
    false
    #endif
}()

@Suite
struct DarwinHTTPClientTests {
    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func conformance() async throws {
        try await runAllConformanceTests {
            return HTTPConnectionPool.shared
        }
    }
}
