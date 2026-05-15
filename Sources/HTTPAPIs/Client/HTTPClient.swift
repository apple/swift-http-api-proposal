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

/// A protocol that defines the interface for an HTTP client.
///
/// ``HTTPClient`` provides asynchronous request execution with streaming request
/// and response bodies. Implementations expose the body reader and writer types
/// directly; there are no separate "receiver" or "request sender" wrapper types.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPClient<RequestOptions>: Sendable, ~Copyable, ~Escapable {
    associatedtype RequestOptions: HTTPClientCapability.RequestOptions

    /// The body writer type used to stream request body bytes and signal end-of-body.
    associatedtype Writer: HTTPBodyWriter, ~Copyable, SendableMetatype

    /// The body reader type used to stream response body bytes and trailers.
    associatedtype Reader: HTTPBodyReader, ~Copyable, SendableMetatype

    /// The default request options for `perform`.
    var defaultRequestOptions: RequestOptions { get }

    /// Performs an HTTP request and processes the response.
    ///
    /// - Parameters:
    ///   - request: The HTTP request header to send.
    ///   - body: The optional request body to send. When `nil`, sends no body.
    ///   - options: The options for this request.
    ///   - responseHandler: A closure that runs once the response head has
    ///     arrived. Receives the response head and a body reader. The reader
    ///     is owned by the closure and must be drained or its scope must end
    ///     before the closure returns; the surrounding `perform` performs
    ///     per-request cleanup based on the reader's terminal state.
    ///
    /// - Returns: The value returned by the response handler closure.
    ///
    /// - Throws: An error if the request fails or if the response handler throws.
    mutating func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<Writer>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming Reader) async throws -> Return
    ) async throws -> Return
}
