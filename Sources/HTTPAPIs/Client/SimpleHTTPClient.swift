//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
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
@_exported public import HTTPTypes

/// A protocol that defines the interface for a simple HTTP client.
///
/// ``HTTPClient`` provides asynchronous request execution with buffered request
/// and response bodies.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol SimpleHTTPClient<RequestOptions>: ~Copyable {
    associatedtype RequestOptions: HTTPClientCapability.RequestOptions

    /// Performs an HTTP request and processes the response.
    ///
    /// This method executes the HTTP request with the specified options, then invokes
    /// the response handler when the full response is received.
    ///
    /// - Parameters:
    ///   - request: The HTTP request header to send.
    ///   - body: The optional request body to send. When `nil`, no body is sent.
    ///   - options: The options for this request.
    ///   - responseHandler: The closure to process the response. This closure is invoked
    ///     when the full response is received and can read the response body.
    ///
    /// - Returns: The value returned by the response handler closure.
    ///
    /// - Throws: An error if the request fails or if the response handler throws.
    func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: Span<UInt8>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, Span<UInt8>) async throws -> Return
    ) async throws -> Return
}
