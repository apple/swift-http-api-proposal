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
import HTTPServer
import Logging
import Middleware

/// This is an example server that wraps an HTTP server inside a middleware.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct ExampleMiddlewareServer<
    Server: HTTPServer,
    ServerMiddleware: Middleware & Sendable
> {
//    typealias RequestConcludingReader = Server.RequestConcludingReader
//    typealias ResponseConcludingWriter = Server.ResponseConcludingWriter
//
//    private let server: Server
//    private let middleware: ServerMiddleware
    
//    init(
//        server: Server,
//        @MiddlewareBuilder
//        middlewareBuilder: (RequestMiddleware<Server>) -> ServerMiddleware
//    ) {
//        self.server = server
//        self.middleware = middlewareBuilder(RequestMiddleware<Server>())
//    }
    
//    func serve() async throws {
//        try await self.server.serve { request, requestContext, requestBodyAndTrailers, responseSender in
//            try await self.middleware.intercept(
//                input: HTTPServerMiddlewareInput(
//                    request: request,
//                    requestContext: requestContext,
//                    requestReader: requestBodyAndTrailers,
//                    responseSender: responseSender
//                )
//            ) { _ in }
//        }
//    }
}

//@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
//struct RequestMiddleware<Server: HTTPServer>: Middleware {
//    typealias Input = HTTPServerMiddlewareInput<Server.RequestConcludingReader, Server.ResponseConcludingWriter>
//    typealias NextInput = Input
//
//    func intercept<Return: ~Copyable>(
//        input: consuming Input,
//        next: (consuming NextInput) async throws -> Return
//    ) async throws -> Return {
//        try await next(input)
//    }
//}
