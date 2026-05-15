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
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct ExampleMiddlewareServer<
    Server: HTTPServer,
    ServerMiddleware: Middleware & Sendable
>: ~Copyable
where
    Server.Reader: ~Copyable,
    Server.ResponseSender: ~Copyable,
    Server.ResponseSender.Writer: ~Copyable,
    ServerMiddleware.Input: ~Copyable,
    ServerMiddleware.NextInput: ~Copyable,
    ServerMiddleware.Input == HTTPServerMiddlewareInput<Server.Reader, Server.ResponseSender>
{
    typealias Reader = Server.Reader
    typealias ResponseSender = Server.ResponseSender

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
        try await self.server.serve { request, requestContext, reader, responseSender in
            let input: ServerMiddleware.Input = ServerMiddleware.Input(
                request: request,
                requestContext: requestContext,
                reader: reader,
                responseSender: responseSender
            )
            return try await middleware.intercept(
                input: input
            ) { _ in }
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct RequestMiddleware<Server: HTTPServer>: Middleware
where
    Server.Reader: ~Copyable,
    Server.ResponseSender: ~Copyable,
    Server.ResponseSender.Writer: ~Copyable
{
    typealias Input = HTTPServerMiddlewareInput<Server.Reader, Server.ResponseSender>
    typealias NextInput = Input

    func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await next(input)
    }
}
