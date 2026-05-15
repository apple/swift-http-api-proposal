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

/// A closure-based implementation of ``HTTPServerRequestHandler``.
///
/// - Example:
/// ```swift
/// let echoHandler = HTTPServerClosureRequestHandler { request, _, reader, responseSender in
///     let writer = try await responseSender.send(.init(status: .ok))
///     try await reader.pipe(to: writer)
/// }
/// ```
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerClosureRequestHandler<
    Reader: HTTPBodyReader & ~Copyable,
    ResponseSender: HTTPResponseSender & ~Copyable,
>: HTTPServerRequestHandler
where ResponseSender.Writer: ~Copyable {
    /// The underlying closure that handles HTTP requests.
    private let _handler:
        @Sendable (
            HTTPRequest,
            HTTPRequestContext,
            consuming sending Reader,
            consuming sending ResponseSender
        ) async throws -> Void

    /// Creates a new closure-based HTTP request handler.
    public init(
        handler:
            @Sendable @escaping (
                HTTPRequest,
                HTTPRequestContext,
                consuming sending Reader,
                consuming sending ResponseSender
            ) async throws -> Void
    ) {
        self._handler = handler
    }

    /// Handles an incoming HTTP request by delegating to the closure provided at initialization.
    public func handle(
        request: HTTPRequest,
        requestContext: HTTPRequestContext,
        reader: consuming sending Reader,
        responseSender: consuming sending ResponseSender
    ) async throws {
        try await self._handler(request, requestContext, reader, responseSender)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPServer
where
    Self: ~Copyable,
    Self: ~Escapable,
    Reader: ~Copyable,
    ResponseSender: ~Copyable,
    ResponseSender.Writer: ~Copyable
{
    /// Starts an HTTP server with a closure-based request handler.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await server.serve { request, _, reader, responseSender in
    ///     try await responseSender.send(.init(status: .ok), body: "Hello, World!".utf8.span)
    /// }
    /// ```
    public func serve(
        handler:
            @Sendable @escaping (
                _ request: HTTPRequest,
                _ requestContext: HTTPRequestContext,
                _ reader: consuming sending Reader,
                _ responseSender: consuming sending ResponseSender
            ) async throws -> Void
    ) async throws {
        try await self.serve(
            handler: HTTPServerClosureRequestHandler(handler: handler)
        )
    }
}
