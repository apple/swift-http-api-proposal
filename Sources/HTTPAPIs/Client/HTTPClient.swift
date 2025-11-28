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

// We are using exported imports so that developers don't have to
// import multiple modules just to execute an HTTP request
@_exported public import AsyncStreaming
@_exported public import HTTPTypes

/// A protocol that defines the interface for an HTTP client.
///
/// ``HTTPClient`` provides asynchronous request execution with streaming request
/// and response bodies.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol HTTPClient<RequestConcludingWriter, ResponseConcludingReader>: ~Copyable {
    /// The type used to write request body data and trailers.
    // TODO: Check if we should allow ~Escapable readers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype RequestConcludingWriter: ConcludingAsyncWriter, ~Copyable, SendableMetatype
    where RequestConcludingWriter.Underlying.WriteElement == UInt8, RequestConcludingWriter.FinalElement == HTTPFields?

    /// The type used to read response body data and trailers.
    // TODO: Check if we should allow ~Escapable writers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype ResponseConcludingReader: ConcludingAsyncReader, ~Copyable, SendableMetatype
    where ResponseConcludingReader.Underlying.ReadElement == UInt8, ResponseConcludingReader.FinalElement == HTTPFields?

    /// Performs an HTTP request and processes the response.
    ///
    /// This method executes the HTTP request with the specified configuration and event
    /// handler, then invokes the response handler when the response headers are received.
    /// The request and response bodies are streamed using the client's writer and reader types.
    ///
    /// - Parameters:
    ///   - request: The HTTP request headers to send.
    ///   - body: The optional request body to send. When `nil`, no body is sent.
    ///   - configuration: The configuration settings for this request.
    ///   - eventHandler: The handler for processing events during request execution.
    ///   - responseHandler: The closure to process the response. This closure is invoked
    ///     when the response headers are received and can read the response body.
    ///
    /// - Returns: The value returned by the response handler closure.
    ///
    /// - Throws: An error if the request fails or if the response handler throws.
    func perform<Return>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestConcludingWriter>?,
        configuration: HTTPClientConfiguration,
        eventHandler: borrowing some HTTPClientEventHandler & ~Escapable & ~Copyable,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return
    ) async throws -> Return
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension HTTPClient where Self: ~Copyable {
    /// Performs an HTTP request and processes the response.
    ///
    /// This method executes the HTTP request with the specified configuration and event
    /// handler, then invokes the response handler when the response headers are received.
    /// The request and response bodies are streamed using the client's writer and reader types.
    ///
    /// - Parameters:
    ///   - request: The HTTP request headers to send.
    ///   - body: The optional request body to send. When `nil`, no body is sent.
    ///   - configuration: The configuration settings for this request.
    ///   - eventHandler: The handler for processing events during request execution.
    ///   - responseHandler: The closure to process the response. This closure is invoked
    ///     when the response headers are received and can read the response body.
    ///
    /// - Returns: The value returned by the response handler closure.
    ///
    /// - Throws: An error if the request fails or if the response handler throws.
    public func perform<Return>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestConcludingWriter>? = nil,
        configuration: HTTPClientConfiguration = .init(),
        eventHandler: consuming some HTTPClientEventHandler & ~Escapable & ~Copyable =
            DefaultHTTPClientEventHandler(),
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return,
    ) async throws -> Return {
        try await self.perform(
            request: request,
            body: body,
            configuration: configuration,
            eventHandler: eventHandler,
            responseHandler: responseHandler
        )
    }
}
