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

#if canImport(FoundationEssentials)
public import struct FoundationEssentials.URL
public import struct FoundationEssentials.Data
#else
public import struct Foundation.URL
public import struct Foundation.Data
#endif

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClient where Self: ~Copyable {
    /// Performs an HTTP request and processes the response.
    ///
    /// This convenience method provides default values for `body` and `options` arguments,
    /// making it easier to execute HTTP requests without specifying optional parameters.
    ///
    /// - Parameters:
    ///   - request: The HTTP request header to send.
    ///   - body: The optional request body to send. Defaults to no body.
    ///   - options: The options for this request. Defaults to an empty initialized options.
    ///   - responseHandler: The closure to process the response. This closure is invoked
    ///     when the response header is received and can read the response body.
    ///
    /// - Returns: The value returned by the response handler closure.
    ///
    /// - Throws: An error if the request fails or if the response handler throws.
    public func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>? = nil,
        options: RequestOptions = .init(),
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return,
    ) async throws -> Return {
        return try await self.perform(request: request, body: body, options: options, responseHandler: responseHandler)
    }

    /// Performs an HTTP GET request and collects the response body.
    ///
    /// This convenience method executes a GET request to the specified URL and collects
    /// the response body data up to the specified limit.
    ///
    /// - Parameters:
    ///   - url: The URL to send the GET request to.
    ///   - headerFields: The HTTP header fields to include in the request. Defaults to an empty collection.
    ///   - options: The options for this request. Defaults to an empty initialized options.
    ///   - limit: The maximum number of bytes to collect from the response body.
    ///
    /// - Returns: A tuple containing the HTTP response header and the collected response body data.
    ///
    /// - Throws: An error if the request fails, if the response body exceeds the limit, or if collection fails.
    public func get(
        url: URL,
        headerFields: HTTPFields = [:],
        options: RequestOptions = .init(),
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        let request = HTTPRequest(url: url, headerFields: headerFields)
        return try await self.perform(request: request, body: nil, options: options) { response, body in
            (
                response,
                try await self.collectBody(body, upTo: limit)
            )
        }
    }

    /// Performs an HTTP POST request with a body and collects the response body.
    ///
    /// This convenience method executes a POST request to the specified URL with the provided
    /// request body data and collects the response body data up to the specified limit.
    ///
    /// - Parameters:
    ///   - url: The URL to send the POST request to.
    ///   - headerFields: The HTTP header fields to include in the request. Defaults to an empty collection.
    ///   - bodyData: The request body data to send.
    ///   - options: The options for this request. Defaults to an empty initialized options.
    ///   - limit: The maximum number of bytes to collect from the response body.
    ///
    /// - Returns: A tuple containing the HTTP response header and the collected response body data.
    ///
    /// - Throws: An error if the request fails, if the response body exceeds the limit, or if collection fails.
    public func post(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: RequestOptions = .init(),
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        let request = HTTPRequest(method: .post, url: url, headerFields: headerFields)
        return try await self.perform(request: request, body: .data(bodyData), options: options) { response, body in
            (
                response,
                try await self.collectBody(body, upTo: limit)
            )
        }
    }

    /// Performs an HTTP PUT request with a body and collects the response body.
    ///
    /// This convenience method executes a PUT request to the specified URL with the provided
    /// request body data and collects the response body data up to the specified limit.
    ///
    /// - Parameters:
    ///   - url: The URL to send the PUT request to.
    ///   - headerFields: The HTTP header fields to include in the request. Defaults to an empty collection.
    ///   - bodyData: The request body data to send.
    ///   - options: The options for this request. Defaults to an empty initialized options.
    ///   - limit: The maximum number of bytes to collect from the response body.
    ///
    /// - Returns: A tuple containing the HTTP response header and the collected response body data.
    ///
    /// - Throws: An error if the request fails, if the response body exceeds the limit, or if collection fails.
    public func put(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: RequestOptions = .init(),
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        let request = HTTPRequest(method: .put, url: url, headerFields: headerFields)
        return try await self.perform(request: request, body: .data(bodyData), options: options) { response, body in
            (
                response,
                try await self.collectBody(body, upTo: limit)
            )
        }
    }

    /// Performs an HTTP DELETE request and collects the response body.
    ///
    /// This convenience method executes a DELETE request to the specified URL with an optional
    /// request body and collects the response body data up to the specified limit.
    ///
    /// - Parameters:
    ///   - url: The URL to send the DELETE request to.
    ///   - headerFields: The HTTP header fields to include in the request. Defaults to an empty collection.
    ///   - bodyData: The optional request body data to send. Defaults to no body.
    ///   - options: The options for this request. Defaults to an empty initialized options.
    ///   - limit: The maximum number of bytes to collect from the response body.
    ///
    /// - Returns: A tuple containing the HTTP response header and the collected response body data.
    ///
    /// - Throws: An error if the request fails, if the response body exceeds the limit, or if collection fails.
    public func delete(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data? = nil,
        options: RequestOptions = .init(),
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        let request = HTTPRequest(method: .delete, url: url, headerFields: headerFields)
        return try await self.perform(request: request, body: bodyData.map { .data($0) }, options: options) { response, body in
            (
                response,
                try await self.collectBody(body, upTo: limit)
            )
        }
    }

    /// Performs an HTTP PATCH request with a body and collects the response body.
    ///
    /// This convenience method executes a PATCH request to the specified URL with the provided
    /// request body data and collects the response body data up to the specified limit.
    ///
    /// - Parameters:
    ///   - url: The URL to send the PATCH request to.
    ///   - headerFields: The HTTP header fields to include in the request. Defaults to an empty collection.
    ///   - bodyData: The request body data to send.
    ///   - options: The options for this request. Defaults to an empty initialized options.
    ///   - limit: The maximum number of bytes to collect from the response body.
    ///
    /// - Returns: A tuple containing the HTTP response header and the collected response body data.
    ///
    /// - Throws: An error if the request fails, if the response body exceeds the limit, or if collection fails.
    public func patch(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: RequestOptions = .init(),
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        let request = HTTPRequest(method: .patch, url: url, headerFields: headerFields)
        return try await self.perform(request: request, body: .data(bodyData), options: options) { response, body in
            (
                response,
                try await self.collectBody(body, upTo: limit)
            )
        }
    }

    private func collectBody<Reader: ConcludingAsyncReader>(_ body: consuming Reader, upTo limit: Int) async throws -> Data
    where Reader: ~Copyable, Reader.Underlying.ReadElement == UInt8 {
        try await body.collect(upTo: limit == .max ? .max : limit + 1) {
            if $0.count > limit {
                throw LengthLimitExceededError()
            }
            return unsafe $0.withUnsafeBytes { unsafe Data($0) }
        }.0
    }
}

struct LengthLimitExceededError: Error {}
