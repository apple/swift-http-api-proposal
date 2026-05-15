//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import BasicContainers

#if canImport(FoundationEssentials)
public import struct FoundationEssentials.URL
public import struct FoundationEssentials.Data
#else
public import struct Foundation.URL
public import struct Foundation.Data
#endif

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClient
where
    Self: ~Copyable & ~Escapable,
    Reader: ~Copyable,
    Writer: ~Copyable
{
    /// Performs an HTTP request and processes the response.
    public mutating func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<Writer>? = nil,
        options: RequestOptions? = nil,
        responseHandler: (HTTPResponse, consuming Reader) async throws -> Return,
    ) async throws -> Return {
        let options = options ?? self.defaultRequestOptions
        return try await self.perform(request: request, body: body, options: options, responseHandler: responseHandler)
    }

    /// Performs an HTTP GET request and collects the response body.
    public mutating func get(
        url: URL,
        headerFields: HTTPFields = [:],
        options: RequestOptions? = nil,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        let request = HTTPRequest(url: url, headerFields: headerFields)
        let options = options ?? self.defaultRequestOptions
        return try await self.perform(request: request, body: nil, options: options) { response, reader in
            (
                response,
                try await Self.collectBody(reader, upTo: limit)
            )
        }
    }

    /// Performs an HTTP POST request with a body and collects the response body.
    public mutating func post(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: RequestOptions? = nil,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        let request = HTTPRequest(method: .post, url: url, headerFields: headerFields)
        let options = options ?? self.defaultRequestOptions
        return try await self.perform(request: request, body: .data(bodyData), options: options) { response, reader in
            (
                response,
                try await Self.collectBody(reader, upTo: limit)
            )
        }
    }

    /// Performs an HTTP PUT request with a body and collects the response body.
    public mutating func put(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: RequestOptions? = nil,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        let request = HTTPRequest(method: .put, url: url, headerFields: headerFields)
        let options = options ?? self.defaultRequestOptions
        return try await self.perform(request: request, body: .data(bodyData), options: options) { response, reader in
            (
                response,
                try await Self.collectBody(reader, upTo: limit)
            )
        }
    }

    /// Performs an HTTP DELETE request and collects the response body.
    public mutating func delete(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data? = nil,
        options: RequestOptions? = nil,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        let request = HTTPRequest(method: .delete, url: url, headerFields: headerFields)
        let options = options ?? self.defaultRequestOptions
        return try await self.perform(request: request, body: bodyData.map { .data($0) }, options: options) { response, reader in
            (
                response,
                try await Self.collectBody(reader, upTo: limit)
            )
        }
    }

    /// Performs an HTTP PATCH request with a body and collects the response body.
    public mutating func patch(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: RequestOptions? = nil,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data) {
        let request = HTTPRequest(method: .patch, url: url, headerFields: headerFields)
        let options = options ?? self.defaultRequestOptions
        return try await self.perform(request: request, body: .data(bodyData), options: options) { response, reader in
            (
                response,
                try await Self.collectBody(reader, upTo: limit)
            )
        }
    }

    private static func collectBody<R: HTTPBodyReader & ~Copyable>(
        _ reader: consuming R,
        upTo limit: Int
    ) async throws -> Data {
        // Read iteratively into a growable buffer rather than pre-allocating
        // `limit` bytes (which can be Int.max). Check the cap after each chunk.
        var buffer = UniqueArray<UInt8>()
        var reader = reader
        var done = false
        while !done {
            try await reader.read { (chunk: inout R.Buffer, trailers: HTTPFields?) in
                if trailers != nil {
                    done = true
                }
                if chunk.count == 0 {
                    if trailers == nil {
                        done = true
                    }
                    return
                }
                buffer.append(
                    moving: chunk.startIndex..<chunk.endIndex,
                    from: &chunk
                )
            }
            if buffer.count > limit {
                throw LengthLimitExceededError()
            }
        }
        return buffer.span.withUnsafeBytes { unsafe Data($0) }
    }
}

struct LengthLimitExceededError: Error {}
