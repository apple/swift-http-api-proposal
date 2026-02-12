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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
/// A protocol that defines the interface for an HTTP server.
///
/// ``HTTPServer`` provides the contract for server implementations that accept incoming HTTP connections and process requests
/// using an ``HTTPServerRequestHandler``.
public protocol HTTPServer: Sendable, ~Copyable, ~Escapable {
    /// The ``ConcludingAsyncReader`` to use when reading requests. ``ConcludingAsyncReader/FinalElement``
    /// must be an optional `HTTPFields`, and ``ConcludingAsyncReader/Underlying`` must use `UInt8` as its
    /// `ReadElement`.
    associatedtype RequestReader: ConcludingAsyncReader & ~Copyable & SendableMetatype
    where
        RequestReader.Underlying.ReadElement == UInt8,
        RequestReader.Underlying.ReadFailure == any Error,
        RequestReader.FinalElement == HTTPFields?

    /// The ``ConcludingAsyncWriter`` to use when writing responses. ``ConcludingAsyncWriter/FinalElement``
    /// must be an optional `HTTPFields`, and ``ConcludingAsyncWriter/Underlying`` must use `UInt8` as its
    /// `WriteElement`.
    associatedtype ResponseWriter: ConcludingAsyncWriter & ~Copyable & SendableMetatype
    where
        ResponseWriter.Underlying.WriteElement == UInt8,
        ResponseWriter.Underlying.WriteFailure == any Error,
        ResponseWriter.FinalElement == HTTPFields?

    /// Starts an HTTP server with the specified request handler.
    ///
    /// This method creates and runs an HTTP server that processes incoming requests using the provided
    /// ``HTTPServerRequestHandler`` implementation.
    ///
    /// Implementations of this method should handle each connection concurrently using Swift's structured concurrency.
    ///
    /// - Parameters:
    ///   - handler: A ``HTTPServerRequestHandler`` implementation that processes incoming HTTP requests. The handler
    ///     receives each request along with its context, a body and trailers reader, and an ``HTTPResponseSender``.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let server = // create an instance of a type conforming to the `HTTPServer` protocol
    /// try await server.serve(handler: YourRequestHandler())
    /// ```
    func serve(handler: some HTTPServerRequestHandler<RequestReader, ResponseWriter>) async throws
}
