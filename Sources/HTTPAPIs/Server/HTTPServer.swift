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

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
/// A protocol that defines the interface for an HTTP server.
///
/// ``HTTPServerProtocol`` provides the contract for server implementations that accept
/// incoming HTTP connections and process requests using a ``HTTPServerRequestHandler``.
public protocol HTTPServer<RequestConcludingReader, ResponseConcludingWriter>: Sendable, ~Copyable, ~Escapable {
    /// The type used to read request body data and trailers.
    // TODO: Check if we should allow ~Escapable readers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype RequestConcludingReader: ConcludingAsyncReader, ~Copyable, SendableMetatype
    where RequestConcludingReader.Underlying.ReadElement == UInt8, RequestConcludingReader.FinalElement == HTTPFields?

    /// The type used to write response body data and trailers.
    // TODO: Check if we should allow ~Escapable writers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype ResponseConcludingWriter: ConcludingAsyncWriter, ~Copyable, SendableMetatype
    where ResponseConcludingWriter.Underlying.WriteElement == UInt8, ResponseConcludingWriter.FinalElement == HTTPFields?

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
    func serve(handler: some HTTPServerRequestHandler<RequestConcludingReader, ResponseConcludingWriter>) async throws
}
