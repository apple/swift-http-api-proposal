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
///     Context: HTTPServerCapability.RequestContext & ~Copyable,
///     Reader: AsyncReader & ~Copyable,
///     ResponseSender: HTTPResponseSender & ~Copyable
/// >: HTTPServerRequestHandler
/// where
///     Reader.ReadElement == UInt8,
///     Reader.FinalElement == HTTPFields?,
///     ResponseSender.Writer: ~Copyable
/// {
///     func handle(
///         request: HTTPRequest,
///         requestContext: consuming Context,
///         reader: consuming sending Reader,
///         responseSender: consuming sending ResponseSender
///     ) async throws {
///         let writer = try await responseSender.send(.init(status: .ok))
///         try await reader.pipe(into: writer)
///     }
/// }
/// ```
@available(anyAppleOS 26.0, *)
public protocol HTTPServerRequestHandler<RequestContext, Reader, ResponseSender>: Sendable {
    /// The type of the request context provided by the server.
    associatedtype RequestContext: HTTPServerCapability.RequestContext, ~Copyable

    /// The body reader type used to stream request body bytes and trailers.
    // TODO: Check if we should allow ~Escapable readers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype Reader: AsyncReader, ~Copyable
    where Reader.ReadElement == UInt8, Reader.FinalElement == HTTPFields?

    /// The type used to write response head, body, and trailing fields.
    // TODO: Check if we should allow ~Escapable readers https://github.com/apple/swift-http-api-proposal/issues/13
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
    ///   - requestContext: A context carrying additional request information provided by the server.
    ///   - reader: A body reader for the request body and trailing fields.
    ///   - responseSender: An ``HTTPResponseSender`` for sending the response head, body, and trailing fields.
    ///
    /// - Throws: Any error encountered during request processing or response generation.
    func handle(
        request: HTTPRequest,
        requestContext: consuming RequestContext,
        reader: consuming sending Reader,
        responseSender: consuming sending ResponseSender
    ) async throws
}
