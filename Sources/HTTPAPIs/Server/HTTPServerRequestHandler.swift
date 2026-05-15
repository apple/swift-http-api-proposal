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
/// ``HTTPServerRequestHandler`` provides a structured way to process incoming HTTP requests
/// and generate appropriate responses. Conforming types implement the
/// ``handle(request:requestContext:requestReceiver:responseSender:)`` method, which is
/// called by the HTTP server for each incoming request. The handler is responsible for reading
/// the request body, processing the request, and sending a response.
///
/// This protocol fully supports bidirectional streaming HTTP request handling, including
/// optional request and response trailers.
///
/// # Example
///
/// ```swift
/// struct EchoHandler<
///     RequestReceiver: HTTPRequestReceiver & ~Copyable,
///     ResponseSender: HTTPResponseSender & ~Copyable
/// >: HTTPServerRequestHandler
/// where RequestReceiver.Reader: ~Copyable, ResponseSender.Writer: ~Copyable {
///     func handle(
///         request: HTTPRequest,
///         requestContext: HTTPRequestContext,
///         requestReceiver: consuming sending RequestReceiver,
///         responseSender: consuming sending ResponseSender
///     ) async throws {
///         try await responseSender.send(.init(status: .ok)) { writer in
///             var writer = writer
///             let (_, trailers) = try await requestReceiver.receive { reader in
///                 try await writer.write(reader)
///             }
///             return ((), trailers)
///         }
///     }
/// }
/// ```
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPServerRequestHandler<RequestReceiver, ResponseSender>: Sendable {
    /// The type used to read request body data and trailers.
    associatedtype RequestReceiver: HTTPRequestReceiver, ~Copyable
    where RequestReceiver.Reader: ~Copyable

    /// The type used to write response body data and trailers.
    associatedtype ResponseSender: HTTPResponseSender, ~Copyable
    where ResponseSender.Writer: ~Copyable

    /// Handles an incoming HTTP request and generates a response.
    ///
    /// The HTTP server calls this method for each incoming client request. Implementations should:
    /// 1. Examine the request headers in the `request` parameter.
    /// 2. Read the request body data from `requestReceiver` as needed.
    /// 3. Process the request and prepare a response.
    /// 4. Optionally call ``HTTPResponseSender/sendInformational(_:)`` for informational responses.
    /// 5. Call ``HTTPResponseSender/send(_:body:)`` (or one of its convenience overloads) to
    ///    send the response head, body, and trailing fields.
    ///
    /// - Parameters:
    ///   - request: The HTTP request headers and metadata.
    ///   - requestContext: A ``HTTPRequestContext`` carrying additional request information.
    ///   - requestReceiver: A receiver for accessing the request body data and trailing fields.
    ///   - responseSender: An ``HTTPResponseSender`` for sending the response head, body, and trailing fields.
    ///
    /// - Throws: Any error encountered during request processing or response generation.
    func handle(
        request: HTTPRequest,
        requestContext: HTTPRequestContext,
        requestReceiver: consuming sending RequestReceiver,
        responseSender: consuming sending ResponseSender
    ) async throws
}
