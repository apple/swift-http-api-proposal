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
/// ``HTTPServerClosureRequestHandler`` provides a convenient way to create an HTTP request handler
/// using a closure instead of conforming a custom type to the ``HTTPServerRequestHandler`` protocol.
/// This is useful for simple handlers or when you need to create handlers dynamically.
///
/// - Example:
/// ```swift
/// let echoHandler = HTTPServerClosureRequestHandler { request, _, requestReceiver, responseSender in
///     try await responseSender.send(.init(status: .ok)) { writer in
///         var writer = writer
///         let (_, trailers) = try await requestReceiver.receive { reader in
///             try await writer.write(reader)
///         }
///         return ((), trailers)
///     }
/// }
/// ```
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerClosureRequestHandler<
    RequestReceiver: HTTPRequestReceiver & ~Copyable,
    ResponseSender: HTTPResponseSender & ~Copyable,
>: HTTPServerRequestHandler
where
    RequestReceiver.Reader: ~Copyable,
    ResponseSender.Writer: ~Copyable
{
    /// The underlying closure that handles HTTP requests.
    private let _handler:
        @Sendable (
            HTTPRequest,
            HTTPRequestContext,
            consuming sending RequestReceiver,
            consuming sending ResponseSender
        ) async throws -> Void

    /// Creates a new closure-based HTTP request handler.
    ///
    /// - Parameter handler: A closure that will be called to handle each incoming HTTP request.
    ///   The closure takes the same parameters as the
    ///   ``HTTPServerRequestHandler/handle(request:requestContext:requestReceiver:responseSender:)`` method.
    public init(
        handler:
            @Sendable @escaping (
                HTTPRequest,
                HTTPRequestContext,
                consuming sending RequestReceiver,
                consuming sending ResponseSender
            ) async throws -> Void
    ) {
        self._handler = handler
    }

    /// Handles an incoming HTTP request by delegating to the closure provided at initialization.
    public func handle(
        request: HTTPRequest,
        requestContext: HTTPRequestContext,
        requestReceiver: consuming sending RequestReceiver,
        responseSender: consuming sending ResponseSender
    ) async throws {
        try await self._handler(request, requestContext, requestReceiver, responseSender)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPServer
where
    Self: ~Copyable,
    Self: ~Escapable,
    RequestReceiver: ~Copyable,
    RequestReceiver.Reader: ~Copyable,
    ResponseSender: ~Copyable,
    ResponseSender.Writer: ~Copyable
{
    /// Starts an HTTP server with a closure-based request handler.
    ///
    /// This method provides a convenient way to start an HTTP server using a closure to handle incoming requests.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await server.serve { request, _, requestReceiver, responseSender in
    ///     try await responseSender.send(.init(status: .ok), body: "Hello, World!".utf8.uniqueArray)
    /// }
    /// ```
    public func serve(
        handler:
            @Sendable @escaping (
                _ request: HTTPRequest,
                _ requestContext: HTTPRequestContext,
                _ requestReceiver: consuming sending RequestReceiver,
                _ responseSender: consuming sending ResponseSender
            ) async throws -> Void
    ) async throws {
        try await self.serve(
            handler: HTTPServerClosureRequestHandler(handler: handler)
        )
    }
}
