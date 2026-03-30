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

/// A protocol that defines the interface for an HTTP client.
///
/// ``HTTPClient`` provides asynchronous request execution with streaming request
/// and response bodies.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPClient<RequestOptions>: Sendable, ~Copyable {
    associatedtype RequestOptions: HTTPClientCapability.RequestOptions

    /// The type used to write request body data and trailers.
    // TODO: Check if we should allow ~Escapable readers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype RequestWriter: AsyncWriter, ~Copyable, SendableMetatype
    where RequestWriter.WriteElement == UInt8

    /// The type used to read response body data and trailers.
    // TODO: Check if we should allow ~Escapable writers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype ResponseConcludingReader: ConcludingAsyncReader, ~Copyable, SendableMetatype
    where ResponseConcludingReader.Underlying.ReadElement == UInt8, ResponseConcludingReader.FinalElement == HTTPFields?

    /// The default request options for `perform`.
    var defaultRequestOptions: RequestOptions { get }

    /// Performs an HTTP request and processes the response.
    ///
    /// This method executes the HTTP request with the specified options, then invokes
    /// the response handler when it receives the response header. The client streams
    /// request and response bodies using its writer and reader types.
    ///
    /// - Parameters:
    ///   - request: The HTTP request header to send.
    ///   - body: The optional request body to send. When `nil`, sends no body.
    ///   - options: The options for this request.
    ///   - responseHandler: A closure that processes the response. The method invokes this
    ///     closure when it receives the response header, providing access to the response body.
    ///
    /// - Returns: The value returned by the response handler closure.
    ///
    /// - Throws: An error if the request fails or if the response handler throws.
    func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return
    ) async throws -> Return
}
