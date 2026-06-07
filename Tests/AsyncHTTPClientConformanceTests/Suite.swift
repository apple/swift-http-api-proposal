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

import AHCHTTPClient
import AsyncHTTPClient
import HTTPClientConformance
import Testing

@Suite struct AsyncHTTPClientTests {
    @available(anyAppleOS 26.0, *)
    @Test func conformance() async throws {
        var config = HTTPClient.Configuration()
        config.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = 1
        config.httpVersion = .automatic
        config.decompression = .enabled(limit: .none)
        let httpClient = HTTPClient(eventLoopGroup: .singletonMultiThreadedEventLoopGroup, configuration: config)
        defer { try! await httpClient.shutdown() }

        try await runConformanceTests(excluding: [
            // TODO: AHC does not support cookies
            .testBasicCookieSetAndUse,
            // TODO: AHC does not support caching
            .testETag,
        ]) {
            httpClient
        }
    }
}
