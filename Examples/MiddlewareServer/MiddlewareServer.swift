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
import HTTPAPIs
import Logging
import Middleware

/// This example shows how to use middleware together with an HTTP server.
@available(anyAppleOS 26.0, *)
@main
struct MiddlewareServer {
    static func main() async throws {
    }

    static func serve<Server: HTTPServer>(server: Server) async throws
    where
        Server.Reader: ~Copyable,
        Server.ResponseSender: ~Copyable,
        Server.ResponseSender.Writer: ~Copyable
    {
        try await ExampleMiddlewareServer(
            server: server
        ) { server in
            server
                .logging(logger: Logger(label: "Logger"))
                .requestHandler()
        }.serve()
    }
}
