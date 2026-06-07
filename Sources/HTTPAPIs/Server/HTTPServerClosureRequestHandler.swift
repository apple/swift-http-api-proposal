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

public import AsyncStreaming

/// A closure-based implementation of ``HTTPServerRequestHandler``.
///
/// ``HTTPServerClosureRequestHandler`` provides a convenient way to create an HTTP request handler
/// using a closure instead of conforming a custom type to the ``HTTPServerRequestHandler`` protocol.
/// This is useful for simple handlers or when you need to create handlers dynamically.
///
/// - Example:
/// ```swift
/// let echoHandler = HTTPServerClosureRequestHandler { request, context, reader, responseSender in
///     let writer = try await responseSender.send(.init(status: .ok))
///     try await reader.pipe(into: writer)
/// }
/// ```
@available(anyAppleOS 26.0, *)
public struct HTTPServerClosureRequestHandler<
    RequestContext: HTTPServerCapability.RequestContext & ~Copyable,
    Reader: AsyncReader & ~Copyable,
    ResponseSender: HTTPResponseSender & ~Copyable,
>: HTTPServerRequestHandler
where
    Reader.ReadElement == UInt8,
    Reader.FinalElement == HTTPFields?,
    ResponseSender.Writer: ~Copyable
{
    /// The underlying closure that handles HTTP requests.
    private let _handler:
        @Sendable (
            HTTPRequest,
            consuming RequestContext,
            consuming sending Reader,
            consuming sending ResponseSender
        ) async throws -> Void

    /// Creates a new closure-based HTTP request handler.
    public init(
        handler:
            @Sendable @escaping (
                HTTPRequest,
                consuming RequestContext,
                consuming sending Reader,
                consuming sending ResponseSender
            ) async throws -> Void
    ) {
        self._handler = handler
    }

    /// Handles an incoming HTTP request by delegating to the closure provided at initialization.
    public func handle(
        request: HTTPRequest,
        requestContext: consuming RequestContext,
        reader: consuming sending Reader,
        responseSender: consuming sending ResponseSender
    ) async throws {
        try await self._handler(request, requestContext, reader, responseSender)
    }
}

@available(anyAppleOS 26.0, *)
extension HTTPServer
where
    Self: ~Copyable,
    Self: ~Escapable,
    RequestContext: ~Copyable,
    Reader: ~Copyable,
    ResponseSender: ~Copyable,
    ResponseSender.Writer: ~Copyable
{
    /// Starts an HTTP server with a closure-based request handler.
    ///
    /// This method provides a convenient way to start an HTTP server using a closure to handle incoming requests.
    ///
    /// - Parameters:
    ///   - handler: An async closure that processes HTTP requests. The closure receives:
    ///     - `HTTPRequest`: The incoming HTTP request with headers and metadata.
    ///     - `RequestContext`: The request context provided by the server.
    ///     - ``AsyncStreaming/AsyncReader``: A reader for the request body and trailing fields.
    ///     - ``HTTPResponseSender``: A wrapper that accepts an `HTTPResponse` and returns a
    ///       ``AsyncStreaming/CallerAsyncWriter`` for streaming the response body and trailing fields.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await server.serve { request, requestContext, reader, responseSender in
    ///     let writer = try await responseSender.send(.init(status: .ok))
    ///     var buffer = UniqueArray<UInt8>(copying: "Hello, World!".utf8)
    ///     try await writer.finish(buffer: &buffer, finalElement: nil)
    /// }
    /// ```
    public func serve(
        handler:
            @Sendable @escaping (
                _ request: HTTPRequest,
                _ requestContext: consuming RequestContext,
                _ reader: consuming sending Reader,
                _ responseSender: consuming sending ResponseSender
            ) async throws -> Void
    ) async throws {
        try await self.serve(
            handler: HTTPServerClosureRequestHandler(handler: handler)
        )
    }
}
