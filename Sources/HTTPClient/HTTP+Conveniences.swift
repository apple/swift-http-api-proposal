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

extension HTTP {
    /// Performs an HTTP request and processes the response.
    ///
    /// This convenience method provides default values for `body`, `options`, and `client` arguments,
    /// making it easier to execute HTTP requests without specifying optional parameters.
    ///
    /// - Parameters:
    ///   - request: The HTTP request header to send.
    ///   - body: The optional request body to send. Defaults to no body.
    ///   - options: The options for this request. Defaults to an empty initialized options.
    ///   - client: The HTTP client to use for the request. Defaults to `HTTPConnectionPool.shared`.
    ///   - responseHandler: The closure to process the response. This closure is invoked
    ///     when the response header is received and can read the response body.
    ///
    /// - Returns: The value returned by the response handler closure.
    ///
    /// - Throws: An error if the request fails or if the response handler throws.
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    public static func perform<Client: HTTPClient & ~Copyable, Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<Client.RequestWriter>? = nil,
        options: Client.RequestOptions = .init(),
        on client: borrowing Client = HTTPConnectionPool.shared,
        responseHandler: (HTTPResponse, consuming Client.ResponseConcludingReader) async throws -> Return,
    ) async throws -> Return {
        return try await client.perform(request: request, body: body, options: options, responseHandler: responseHandler)
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
    ///   - client: The HTTP client to use for the request. Defaults to `HTTPConnectionPool.shared`.
    ///   - limit: The maximum number of bytes to collect from the response body.
    ///
    /// - Returns: A tuple containing the HTTP response header and the collected response body data.
    ///
    /// - Throws: An error if the request fails, if the response body exceeds the limit, or if collection fails.
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    public static func get<Client: HTTPClient & ~Copyable>(
        url: URL,
        headerFields: HTTPFields = [:],
        options: Client.RequestOptions = .init(),
        on client: borrowing Client = HTTPConnectionPool.shared,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        try await client.get(url: url, headerFields: headerFields, options: options, collectUpTo: limit)
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
    ///   - client: The HTTP client to use for the request. Defaults to `HTTPConnectionPool.shared`.
    ///   - limit: The maximum number of bytes to collect from the response body.
    ///
    /// - Returns: A tuple containing the HTTP response header and the collected response body data.
    ///
    /// - Throws: An error if the request fails, if the response body exceeds the limit, or if collection fails.
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    public static func post<Client: HTTPClient & ~Copyable>(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: Client.RequestOptions = .init(),
        on client: borrowing Client = HTTPConnectionPool.shared,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        try await client.post(url: url, headerFields: headerFields, bodyData: bodyData, options: options, collectUpTo: limit)
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
    ///   - client: The HTTP client to use for the request. Defaults to `HTTPConnectionPool.shared`.
    ///   - limit: The maximum number of bytes to collect from the response body.
    ///
    /// - Returns: A tuple containing the HTTP response header and the collected response body data.
    ///
    /// - Throws: An error if the request fails, if the response body exceeds the limit, or if collection fails.
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    public static func put<Client: HTTPClient & ~Copyable>(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: Client.RequestOptions = .init(),
        on client: borrowing Client = HTTPConnectionPool.shared,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        try await client.put(url: url, headerFields: headerFields, bodyData: bodyData, options: options, collectUpTo: limit)
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
    ///   - client: The HTTP client to use for the request. Defaults to `HTTPConnectionPool.shared`.
    ///   - limit: The maximum number of bytes to collect from the response body.
    ///
    /// - Returns: A tuple containing the HTTP response header and the collected response body data.
    ///
    /// - Throws: An error if the request fails, if the response body exceeds the limit, or if collection fails.
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    public static func delete<Client: HTTPClient & ~Copyable>(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data? = nil,
        options: Client.RequestOptions = .init(),
        on client: borrowing Client = HTTPConnectionPool.shared,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        try await client.delete(url: url, headerFields: headerFields, bodyData: bodyData, options: options, collectUpTo: limit)
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
    ///   - client: The HTTP client to use for the request. Defaults to `HTTPConnectionPool.shared`.
    ///   - limit: The maximum number of bytes to collect from the response body.
    ///
    /// - Returns: A tuple containing the HTTP response header and the collected response body data.
    ///
    /// - Throws: An error if the request fails, if the response body exceeds the limit, or if collection fails.
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    public static func patch<Client: HTTPClient & ~Copyable>(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: Client.RequestOptions = .init(),
        on client: borrowing Client = HTTPConnectionPool.shared,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        try await client.patch(url: url, headerFields: headerFields, bodyData: bodyData, options: options, collectUpTo: limit)
    }
}
