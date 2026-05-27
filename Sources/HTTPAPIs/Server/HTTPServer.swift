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

@available(anyAppleOS 26.0, *)
/// A protocol that defines the interface for an HTTP server.
///
/// ``HTTPServer`` provides the contract for server implementations that accept
/// incoming HTTP connections and process requests using a ``HTTPServerRequestHandler``.
public protocol HTTPServer<RequestContext, RequestConcludingReader, ResponseConcludingWriter>: Sendable, ~Copyable, ~Escapable {
    /// The type of context provided to request handlers for each incoming request.
    ///
    /// Server implementations define this type to carry per-request metadata that isn't part
    /// of the HTTP message itself, such as connection information or routing state.
    associatedtype RequestContext: HTTPServerCapability.RequestContext, ~Copyable

    /// The type used to read request body data and trailers.
    // TODO: Check if we should allow ~Escapable readers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype RequestConcludingReader: ConcludingAsyncReader, ~Copyable, SendableMetatype
    where
        RequestConcludingReader.Underlying: ~Copyable,
        RequestConcludingReader.Underlying.ReadElement == UInt8,
        RequestConcludingReader.FinalElement == HTTPFields?

    /// The type used to write response body data and trailers.
    // TODO: Check if we should allow ~Escapable writers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype ResponseConcludingWriter: ConcludingAsyncWriter, ~Copyable, SendableMetatype
    where
        ResponseConcludingWriter.Underlying: ~Copyable,
        ResponseConcludingWriter.Underlying.WriteElement == UInt8,
        ResponseConcludingWriter.FinalElement == HTTPFields?

    /// Starts an HTTP server with the specified request handler.
    ///
    /// This method creates and runs an HTTP server that processes incoming requests using the provided
    /// ``HTTPServerRequestHandler`` implementation.
    ///
    /// Implementations of this method should handle each connection concurrently using Swift's structured concurrency.
    ///
    /// - Parameters:
    ///   - handler: A ``HTTPServerRequestHandler`` implementation that processes incoming HTTP requests. The handler
    ///     receives each request along with a body reader and ``HTTPResponseSender``.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let server = // create an instance of a type conforming to the `ServerProtocol`
    /// try await server.serve(handler: YourRequestHandler())
    /// ```
    func serve<Handler: HTTPServerRequestHandler>(handler: Handler) async throws
    where
        Handler.RequestContext: ~Copyable,
        Handler.RequestContext == RequestContext,
        Handler.RequestReader == RequestConcludingReader,
        Handler.RequestReader: ~Copyable,
        Handler.ResponseWriter == ResponseConcludingWriter,
        Handler.ResponseWriter: ~Copyable
}
