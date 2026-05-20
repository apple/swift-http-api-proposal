//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import ExampleMiddleware
import Foundation
import HTTPClient
import Logging
import Middleware

/// This example shows how to use middleware together with an HTTP client.
@available(anyAppleOS 26.0, *)
@main
struct MiddlewareClient {
    static func main() async throws {
        var client = ExampleMiddlewareClient(
            client: DefaultHTTPClient.shared
        ) { request in
            request
                .forwarding()
        }
        let (_, responseBody) = try await client.get(url: URL(string: "https://httpbin.org/get")!, collectUpTo: 1024)
        print("Received \(String(data: responseBody, encoding: .utf8)!)")
    }
}
