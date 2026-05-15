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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
/// A protocol that defines the interface for an HTTP server.
///
/// ``HTTPServer`` provides the contract for server implementations that accept
/// incoming HTTP connections and process requests using a ``HTTPServerRequestHandler``.
public protocol HTTPServer<RequestReceiver, ResponseSender>: Sendable, ~Copyable, ~Escapable {
    /// The type used to read request body data and trailers.
    // TODO: Check if we should allow ~Escapable receivers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype RequestReceiver: HTTPRequestReceiver, ~Copyable, SendableMetatype
    where RequestReceiver.Reader: ~Copyable

    /// The type used to write response body data and trailers.
    // TODO: Check if we should allow ~Escapable senders https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype ResponseSender: HTTPResponseSender, ~Copyable, SendableMetatype
    where ResponseSender.Writer: ~Copyable

    /// Starts an HTTP server with the specified request handler.
    ///
    /// This method creates and runs an HTTP server that processes incoming requests using the provided
    /// ``HTTPServerRequestHandler`` implementation.
    ///
    /// Implementations of this method should handle each connection concurrently using Swift's structured concurrency.
    ///
    /// - Parameters:
    ///   - handler: A ``HTTPServerRequestHandler`` implementation that processes incoming HTTP requests. The handler
    ///     receives each request along with a request receiver and ``HTTPResponseSender``.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let server = // create an instance of a type conforming to the `ServerProtocol`
    /// try await server.serve(handler: YourRequestHandler())
    /// ```
    func serve<Handler: HTTPServerRequestHandler>(handler: Handler) async throws
    where
        Handler.RequestReceiver == RequestReceiver,
        Handler.RequestReceiver: ~Copyable,
        Handler.ResponseSender == ResponseSender,
        Handler.ResponseSender: ~Copyable
}
