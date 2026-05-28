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

/// This is an example server that wraps an HTTP server inside a middleware.
@available(anyAppleOS 26.0, *)
struct ExampleMiddlewareServer<
    Server: HTTPServer,
    ServerMiddleware: Middleware & Sendable
>: ~Copyable
where
    Server.RequestConcludingReader: ~Copyable,
    Server.RequestConcludingReader.Underlying: ~Copyable,
    Server.ResponseConcludingWriter: ~Copyable,
    Server.ResponseConcludingWriter.Underlying: ~Copyable,
    ServerMiddleware.Input: ~Copyable,
    ServerMiddleware.NextInput: ~Copyable,
    ServerMiddleware.Input == HTTPServerMiddlewareInput<Server.RequestContext, Server.RequestConcludingReader, Server.ResponseConcludingWriter>
{
    typealias RequestConcludingReader = Server.RequestConcludingReader
    typealias ResponseConcludingWriter = Server.ResponseConcludingWriter

    private let server: Server
    private let middleware: ServerMiddleware

    init(
        server: Server,
        @MiddlewareBuilder
        middlewareBuilder: (RequestMiddleware<Server>) -> ServerMiddleware
    ) {
        self.server = server
        self.middleware = middlewareBuilder(RequestMiddleware<Server>())
    }

    consuming func serve() async throws {
        let middleware = self.middleware
        try await self.server.serve { request, requestContext, requestBodyAndTrailers, responseSender in
            let input: ServerMiddleware.Input = ServerMiddleware.Input(
                request: request,
                requestContext: requestContext,
                requestReader: requestBodyAndTrailers,
                responseSender: responseSender
            )
            return try await middleware.intercept(
                input: input
            ) { _ in }
        }
    }
}

@available(anyAppleOS 26.0, *)
struct RequestMiddleware<Server: HTTPServer>: Middleware
where
    Server.RequestConcludingReader: ~Copyable,
    Server.RequestConcludingReader.Underlying: ~Copyable,
    Server.ResponseConcludingWriter: ~Copyable,
    Server.ResponseConcludingWriter.Underlying: ~Copyable
{
    typealias Input = HTTPServerMiddlewareInput<Server.RequestContext, Server.RequestConcludingReader, Server.ResponseConcludingWriter>
    typealias NextInput = Input

    func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await next(input)
    }
}
