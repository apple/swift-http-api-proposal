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

public import AsyncStreaming
public import HTTPTypes

/// A closure-based implementation of ``HTTPServerRequestHandler``.
///
/// ``HTTPServerClosureRequestHandler`` provides a convenient way to create an HTTP request handler
/// using a closure instead of conforming a custom type to the ``HTTPServerRequestHandler`` protocol.
/// This is useful for simple handlers or when you need to create handlers dynamically.
///
/// - Example:
/// ```swift
/// let echoHandler = HTTPServerClosureRequestHandler { request, context, bodyReader, responseSender in
///     // Read the entire request body
///     let (bodyData, _) = try await bodyReader.consumeAndConclude { reader in
///         // ... body reading code ...
///     }
///
///     // Create and send response
///     var response = HTTPResponse(status: .ok)
///     let responseWriter = try await responseSender.send(response)
///     try await responseWriter.produceAndConclude { writer in
///         try await writer.write(bodyData.span)
///         return ((), nil)
///     }
/// }
/// ```
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerClosureRequestHandler<
    ConcludingRequestReader: ConcludingAsyncReader<RequestReader, HTTPFields?> & ~Copyable & SendableMetatype,
    RequestReader: AsyncReader<UInt8, any Error> & ~Copyable & ~Escapable,
    ConcludingResponseWriter: ConcludingAsyncWriter<RequestWriter, HTTPFields?> & ~Copyable & SendableMetatype,
    RequestWriter: AsyncWriter<UInt8, any Error> & ~Copyable & ~Escapable
>: HTTPServerRequestHandler {
    /// The underlying closure that handles HTTP requests.
    private let _handler:
        nonisolated(nonsending) @Sendable (
            HTTPRequest,
            HTTPRequestContext,
            consuming sending ConcludingRequestReader,
            consuming sending HTTPResponseSender<ConcludingResponseWriter>
        ) async throws -> Void

    /// Creates a new closure-based HTTP request handler.
    ///
    /// - Parameter handler: A closure that will be called to handle each incoming HTTP request.
    ///   The closure takes the same parameters as the ``HTTPServerRequestHandler/handle(request:requestBodyAndTrailers:responseSender:)`` method.
    public init(
        handler:
            nonisolated(nonsending) @Sendable @escaping (
                HTTPRequest,
                HTTPRequestContext,
                consuming sending ConcludingRequestReader,
                consuming sending HTTPResponseSender<ConcludingResponseWriter>
            ) async throws -> Void
    ) {
        self._handler = handler
    }

    /// Handles an incoming HTTP request by delegating to the closure provided at initialization.
    ///
    /// This method simply forwards all parameters to the handler closure.
    ///
    /// - Parameters:
    ///   - request: The HTTP request headers and metadata.
    ///   - requestContext: A ``HTTPRequestContext``.
    ///   - requestBodyAndTrailers: A reader for accessing the request body data and trailing headers.
    ///   - responseSender: An ``HTTPResponseSender`` to send the HTTP response.
    public func handle(
        request: HTTPRequest,
        requestContext: HTTPRequestContext,
        requestBodyAndTrailers: consuming sending ConcludingRequestReader,
        responseSender: consuming sending HTTPResponseSender<ConcludingResponseWriter>
    ) async throws {
        try await self._handler(request, requestContext, requestBodyAndTrailers, responseSender)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPServer {
    /// Starts an HTTP server with a closure-based request handler.
    ///
    /// This method provides a convenient way to start an HTTP server using a closure to handle incoming requests.
    ///
    /// - Parameters:
    ///   - handler: An async closure that processes HTTP requests. The closure receives:
    ///     - `HTTPRequest`: The incoming HTTP request with headers and metadata.
    ///     - ``HTTPRequestContext``: The request's context.
    ///     - ``HTTPRequestConcludingAsyncReader``: An async reader for consuming the request body and trailers.
    ///     - ``HTTPResponseSender``: A non-copyable wrapper for a function that accepts an `HTTPResponse` and provides access to an ``HTTPResponseConcludingAsyncWriter``.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await server.serve { request, bodyReader, responseSender in
    ///     // Process the request
    ///     let response = HTTPResponse(status: .ok)
    ///     let writer = try await responseSender.send(response)
    ///     try await writer.produceAndConclude { writer in
    ///         try await writer.write("Hello, World!".utf8)
    ///         return ((), nil)
    ///     }
    /// }
    /// ```
    public func serve(
        handler:
            nonisolated(nonsending) @Sendable @escaping (
                _ request: HTTPRequest,
                _ requestContext: HTTPRequestContext,
                _ requestBodyAndTrailers: consuming sending RequestReader,
                _ responseSender: consuming sending HTTPResponseSender<ResponseWriter>
            ) async throws -> Void
    ) async throws {
        try await self.serve(handler: HTTPServerClosureRequestHandler(handler: handler))
    }
}
