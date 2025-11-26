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

public import HTTPTypes

/// A protocol that defines the contract for handling HTTP server requests.
///
/// ``HTTPServerRequestHandler`` provides a structured way to process incoming HTTP requests
/// and generate appropriate responses. Conforming types implement the
/// ``handle(request:requestContext:requestBodyAndTrailers:responseSender:)`` method, which is
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
///     ConcludingRequestReader: ConcludingAsyncReader<RequestReader, HTTPFields?> & ~Copyable,
///     RequestReader: AsyncReader<UInt8, any Error> & ~Copyable,
///     ConcludingResponseWriter: ConcludingAsyncWriter<RequestWriter, HTTPFields?> & ~Copyable,
///     RequestWriter: AsyncWriter<UInt8, any Error> & ~Copyable
/// >: HTTPServerRequestHandler {
///     func handle(
///         request: HTTPRequest,
///         requestContext: HTTPRequestContext,
///         requestBodyAndTrailers: consuming sending ConcludingRequestReader,
///         responseSender: consuming sending HTTPResponseSender<ConcludingResponseWriter>
///     ) async throws {
///         var responseSender: HTTPResponseSender<ConcludingResponseWriter>? = responseSender
///         _ = try await requestBodyAndTrailers.consumeAndConclude { reader in
///             var reader: RequestReader? = reader
///             let responseBodyAndTrailers = try await responseSender.take()!.send(
///                 .init(status: .ok)
///             )
///             try await responseBodyAndTrailers.produceAndConclude { writer in
///                 var writer = writer
///                 try await reader.take()!.forEach { span in
///                     try await writer.write(span)
///                 }
///                 return ((), nil)
///             }
///         }
///     }
/// }
/// ```
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol HTTPServerRequestHandler<RequestReader, ResponseWriter>: Sendable {
    /// The type used to read request body data and trailers.
    associatedtype RequestReader: ConcludingAsyncReader, ~Copyable
    where RequestReader.Underlying.ReadElement == UInt8, RequestReader.FinalElement == HTTPFields?

    /// The type used to write response body data and trailers.
    associatedtype ResponseWriter: ConcludingAsyncWriter, ~Copyable
    where ResponseWriter.Underlying.WriteElement == UInt8, ResponseWriter.FinalElement == HTTPFields?

    /// Handles an incoming HTTP request and generates a response.
    ///
    /// This method is called by the HTTP server for each incoming client request. Implementations should:
    /// 1. Examine the request headers in the `request` parameter.
    /// 2. Read the request body data from the `requestBodyAndTrailers` reader as needed.
    /// 3. Process the request and prepare a response.
    /// 4. Optionally call ``HTTPResponseSender/sendInformational(_:)`` for informational responses.
    /// 5. Call ``HTTPResponseSender/send(_:)`` with the final HTTP response.
    /// 6. Write the response body data to the returned writer.
    ///
    /// - Parameters:
    ///   - request: The HTTP request headers and metadata.
    ///   - requestContext: A ``HTTPRequestContext`` carrying additional request information.
    ///   - requestBodyAndTrailers: A reader for accessing the request body data and trailing headers.
    ///   - responseSender: An ``HTTPResponseSender`` that accepts an HTTP response and returns a writer for the
    ///     response body. The returned writer allows for incremental writing of the response body and supports trailers.
    ///
    /// - Throws: Any error encountered during request processing or response generation.
    func handle(
        request: HTTPRequest,
        requestContext: HTTPRequestContext,
        requestBodyAndTrailers: consuming sending RequestReader,
        responseSender: consuming sending HTTPResponseSender<ResponseWriter>
    ) async throws
}
