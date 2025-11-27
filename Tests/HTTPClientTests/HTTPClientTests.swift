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
import Testing

let testsEnabled: Bool = {
    #if canImport(Darwin)
    true
    #else
    false
    #endif
}()

@Suite
struct HTTPClientTests {
    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testHTTPBin() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "https",
            authority: "httpbin.org",
            path: "/get"
        )
        try await httpClient.perform(
            request: request,
            body: nil
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            let (_, trailers) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let isEmpty = span.isEmpty
                #expect(!isEmpty)
            }
            #expect(trailers == nil)
        }
    }
}
