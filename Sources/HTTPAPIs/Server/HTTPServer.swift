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

/// A protocol that defines the interface for an HTTP server.
///
/// ``HTTPServer`` provides the contract for server implementations that accept
/// incoming HTTP connections and process requests using a
/// ``HTTPServerRequestHandler``. The body reader and response sender types are
/// surfaced directly; there are no separate "request receiver" wrapper types.
// TODO: We should revisit if this should be Sendable
@available(anyAppleOS 26.0, *)
public protocol HTTPServer<RequestContext, Reader, ResponseSender>: Sendable, ~Copyable, ~Escapable {
    /// The type of context provided to request handlers for each incoming request.
    ///
    /// Server implementations define this type to carry per-request metadata that isn't part
    /// of the HTTP message itself, such as connection information or routing state.
    associatedtype RequestContext: HTTPServerCapability.RequestContext, ~Copyable

    /// The body reader type used to stream request body bytes and trailers.
    // TODO: Check if we should allow ~Escapable readers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype Reader: AsyncReader, ~Copyable, SendableMetatype
    where Reader.ReadElement == UInt8, Reader.FinalElement == HTTPFields?

    /// The type used to write response head, body, and trailing fields.
    // TODO: Check if we should allow ~Escapable readers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype ResponseSender: HTTPResponseSender, ~Copyable, SendableMetatype
    where ResponseSender.Writer: ~Copyable

    /// Starts an HTTP server with the specified request handler.
    ///
    /// This method creates and runs an HTTP server that processes incoming requests using the provided
    /// ``HTTPServerRequestHandler`` implementation.
    ///
    /// Implementations of this method should handle each connection concurrently using Swift's structured concurrency.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let server = // create an instance of a type conforming to the `ServerProtocol`
    /// try await server.serve(handler: YourRequestHandler())
    /// ```
    ///
    /// - Parameters:
    ///   - handler: A ``HTTPServerRequestHandler`` implementation that
    ///     processes incoming HTTP requests. The handler receives each
    ///     request along with a request body reader and an
    ///     ``HTTPResponseSender``.
    func serve<Handler: HTTPServerRequestHandler>(handler: Handler) async throws
    where
        Handler.RequestContext: ~Copyable,
        Handler.RequestContext == RequestContext,
        Handler.Reader == Reader,
        Handler.Reader: ~Copyable,
        Handler.ResponseSender == ResponseSender,
        Handler.ResponseSender: ~Copyable
}
