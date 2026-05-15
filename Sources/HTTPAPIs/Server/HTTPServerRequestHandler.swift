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

/// A protocol that defines the contract for handling HTTP server requests.
///
/// ``HTTPServerRequestHandler`` provides a structured way to process incoming
/// HTTP requests and generate appropriate responses. Conforming types
/// implement ``handle(request:requestContext:reader:responseSender:)``, which
/// is called by the HTTP server for each incoming request. The handler is
/// responsible for reading the request body, processing the request, and
/// sending a response.
///
/// This protocol fully supports bidirectional streaming HTTP request
/// handling, including optional request and response trailers.
///
/// # Example
///
/// ```swift
/// struct EchoHandler<
///     Reader: HTTPBodyReader & ~Copyable,
///     ResponseSender: HTTPResponseSender & ~Copyable
/// >: HTTPServerRequestHandler
/// where ResponseSender.Writer: ~Copyable, Reader.Buffer == ResponseSender.Writer.Buffer {
///     func handle(
///         request: HTTPRequest,
///         requestContext: HTTPRequestContext,
///         reader: consuming sending Reader,
///         responseSender: consuming sending ResponseSender
///     ) async throws {
///         let writer = try await responseSender.send(.init(status: .ok))
///         try await reader.pipe(to: writer)
///     }
/// }
/// ```
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPServerRequestHandler<Reader, ResponseSender>: Sendable {
    /// The body reader type used to stream request body bytes and trailers.
    associatedtype Reader: HTTPBodyReader, ~Copyable

    /// The type used to write response head, body, and trailing fields.
    associatedtype ResponseSender: HTTPResponseSender, ~Copyable
    where ResponseSender.Writer: ~Copyable

    /// Handles an incoming HTTP request and generates a response.
    ///
    /// The HTTP server calls this method for each incoming client request.
    /// Implementations should:
    /// 1. Examine the request headers in the `request` parameter.
    /// 2. Read the request body data from `reader` as needed.
    /// 3. Process the request and prepare a response.
    /// 4. Optionally call ``HTTPResponseSender/sendInformational(_:)`` for informational responses.
    /// 5. Call ``HTTPResponseSender/send(_:)`` (or one of its convenience overloads) to
    ///    send the response head, body, and trailing fields.
    ///
    /// - Parameters:
    ///   - request: The HTTP request headers and metadata.
    ///   - requestContext: A ``HTTPRequestContext`` carrying additional request information.
    ///   - reader: A body reader for the request body and trailing fields.
    ///   - responseSender: An ``HTTPResponseSender`` for sending the response head, body, and trailing fields.
    ///
    /// - Throws: Any error encountered during request processing or response generation.
    func handle(
        request: HTTPRequest,
        requestContext: HTTPRequestContext,
        reader: consuming sending Reader,
        responseSender: consuming sending ResponseSender
    ) async throws
}
