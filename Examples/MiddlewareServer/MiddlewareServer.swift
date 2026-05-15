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
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
@main
struct MiddlewareServer {
    static func main() async throws {
    }

    static func serve<Server: HTTPServer>(server: Server) async throws
    where
        Server.Reader: ~Copyable & Escapable,
        Server.ResponseSender: ~Copyable,
        Server.ResponseSender.Writer: ~Copyable & Escapable,
        Server.Reader.Buffer == Server.ResponseSender.Writer.Buffer
    {
        try await ExampleMiddlewareServer(
            server: server
        ) { server in
            server
                .logging(logger: Logger(label: "Logger"))
                .checksumTrailer()
                .prefixSuffix(prefix: Array("<<".utf8), suffix: Array(">>".utf8))
                .requestHandler()
        }.serve()
    }
}
