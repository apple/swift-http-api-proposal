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

import ExampleMiddleware
import HTTPClient
import Logging
import Middleware

/// This example shows how to use middleware together with an HTTP server.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
@main
struct MiddlewareClient {
    static func main() async throws {
        let client = ExampleMiddlewareClient(
            client: httpClient
        ) { request in
            request
                .forwarding()
        }
        
        let request = HTTPRequest(
            method: .get,
            scheme: "https",
            authority: "httpbin.org",
            path: "/get"
        )
        try await client.perform(
            request: request,
            body: nil
        ) { response, responseBodyAndTrailers in
            let (_, trailers) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let isEmpty = span.isEmpty
            }
        }
    }
}
