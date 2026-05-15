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

/// A protocol that defines the interface for an HTTP server.
///
/// ``HTTPServer`` provides the contract for server implementations that accept
/// incoming HTTP connections and process requests using a
/// ``HTTPServerRequestHandler``. The body reader and response sender types are
/// surfaced directly; there are no separate "request receiver" wrapper types.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPServer<Reader, ResponseSender>: Sendable, ~Copyable, ~Escapable {
    /// The body reader type used to stream request body bytes and trailers.
    associatedtype Reader: HTTPBodyReader, ~Copyable, SendableMetatype

    /// The type used to write response head, body, and trailing fields.
    associatedtype ResponseSender: HTTPResponseSender, ~Copyable, SendableMetatype
    where ResponseSender.Writer: ~Copyable

    /// Starts an HTTP server with the specified request handler.
    ///
    /// - Parameters:
    ///   - handler: A ``HTTPServerRequestHandler`` implementation that
    ///     processes incoming HTTP requests. The handler receives each
    ///     request along with a request body reader and an
    ///     ``HTTPResponseSender``.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await server.serve { request, _, reader, responseSender in
    ///     let writer = try await responseSender.send(.init(status: .ok))
    ///     try await reader.pipe(to: writer)
    /// }
    /// ```
    func serve<Handler: HTTPServerRequestHandler>(handler: Handler) async throws
    where
        Handler.Reader == Reader,
        Handler.Reader: ~Copyable,
        Handler.ResponseSender == ResponseSender,
        Handler.ResponseSender: ~Copyable
}
