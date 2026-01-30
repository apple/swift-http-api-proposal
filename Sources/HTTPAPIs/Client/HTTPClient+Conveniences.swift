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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClient {
    /// Performs an HTTP request and processes the response.
    ///
    /// This convenience method provides default values for `body` and `options` arguments,
    /// making it easier to execute HTTP requests without specifying optional parameters.
    ///
    /// - Parameters:
    ///   - request: The HTTP request header to send.
    ///   - body: The optional request body to send. Defaults to no body.
    ///   - options: The options for this request. Defaults to an empty initialized `RequestOptions`.
    ///   - responseHandler: The closure to process the response. This closure is invoked
    ///     when the response header is received and can read the response body.
    ///
    /// - Returns: The value returned by the response handler closure.
    ///
    /// - Throws: An error if the request fails or if the response handler throws.
    public func perform<Return>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>? = nil,
        options: RequestOptions = .init(),
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return,
    ) async throws -> Return {
        return try await self.perform(request: request, body: body, options: options, responseHandler: responseHandler)
    }
}
