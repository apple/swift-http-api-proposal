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

/// A protocol that defines the contract for handling HTTP server requests.
///
/// ``HTTPServerRequestHandler`` provides a structured way to process incoming HTTP requests and generate appropriate responses.
/// Conforming types implement the ``handle(request:requestContext:requestBodyAndTrailers:responseSender:)`` method,
/// which is called by the HTTP server for each incoming request. The handler is responsible for:
///
/// - Processing the request headers.
/// - Reading the request body data using the provided `RequestReader`
/// - Generating and sending an appropriate response using the response callback
///
/// This protocol fully supports bi-directional streaming HTTP request handling including the optional request and response trailers.
///
/// # Example
///
/// ```swift
/// struct EchoHandler: HTTPServerRequestHandler {
///   func handle(
///     request: HTTPRequest,
///     requestContext: HTTPRequestContext,
///     requestConcludingAsyncReader: consuming sending HTTPRequestConcludingAsyncReader,
///     responseSender: consuming sending HTTPResponseSender<HTTPResponseConcludingAsyncWriter>
///   ) async throws {
///     // Read the entire request body
///     let (bodyData, trailers) = try await requestConcludingAsyncReader.consumeAndConclude { reader in
///         var reader = reader
///         var data = [UInt8]()
///         var shouldContinue = true
///         while shouldContinue {
///             try await reader.read { span in
///                 guard let span else {
///                     shouldContinue = false
///                     return
///                 }
///                 data.reserveCapacity(data.count + span.count)
///                 for index in span.indices {
///                     data.append(span[index])
///                 }
///             }
///         }
///         return data
///     }
///
///     // Create a response
///     var response = HTTPResponse(status: .ok)
///     response.headerFields[.contentType] = "text/plain"
///
///     // Send the response and write the echo data back
///     let responseWriter = try await responseSender.send(response)
///     try await responseWriter.produceAndConclude { writer in
///         var writer = writer
///         try await writer.write(bodyData.span)
///         return ((), nil) // No trailers
///     }
///  }
/// }
/// ```
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPServerRequestHandler<RequestReader, ResponseWriter>: Sendable {
    /// The ``ConcludingAsyncReader`` to use when reading requests. ``ConcludingAsyncReader/FinalElement``
    /// must be an optional `HTTPFields`, and ``ConcludingAsyncReader/Underlying`` must use `Span<UInt8>` as its
    /// `ReadElement`.
    associatedtype RequestReader: ConcludingAsyncReader & ~Copyable & SendableMetatype
    where
        RequestReader.Underlying.ReadElement == UInt8,
        RequestReader.FinalElement == HTTPFields?

    /// The ``ConcludingAsyncWriter`` to use when writing responses. ``ConcludingAsyncWriter/FinalElement``
    /// must be an optional `HTTPFields`, and ``ConcludingAsyncWriter/Underlying`` must use `Span<UInt8>` as its
    /// `WriteElement`.
    associatedtype ResponseWriter: ConcludingAsyncWriter & ~Copyable & SendableMetatype
    where
        ResponseWriter.Underlying.WriteElement == UInt8,
        ResponseWriter.FinalElement == HTTPFields?

    /// Handles an incoming HTTP request and generates a response.
    ///
    /// This method is called by the HTTP server for each incoming client request. Implementations should:
    /// 1. Examine the request headers in the `request` parameter
    /// 2. Read the request body data from the `RequestReader` as needed
    /// 3. Process the request and prepare a response
    /// 4. Optionally call ``HTTPResponseSender/sendInformational(_:)`` as needed
    /// 4. Call the ``HTTPResponseSender/send(_:)`` with an appropriate HTTP response
    /// 5. Write the response body data to the returned `ResponseWriter`
    ///
    /// - Parameters:
    ///   - request: The HTTP request headers and metadata.
    ///   - requestContext: A ``HTTPRequestContext``.
    ///   - requestBodyAndTrailers: A reader for accessing the request body data and trailing headers.
    ///     This follows the `ConcludingAsyncReader` pattern, allowing for incremental reading of request body data
    ///     and concluding with any trailer fields sent at the end of the request.
    ///   - responseSender: An ``HTTPResponseSender`` that takes an HTTP response and returns a writer for the
    ///     response body. The returned writer allows for the incremental writing of the response body, and supports trailers.
    ///
    /// - Throws: Any error encountered during request processing or response generation.
    func handle(
        request: HTTPRequest,
        requestContext: HTTPRequestContext,
        requestBodyAndTrailers: consuming sending RequestReader,
        responseSender: consuming sending HTTPResponseSender<ResponseWriter>
    ) async throws
}
