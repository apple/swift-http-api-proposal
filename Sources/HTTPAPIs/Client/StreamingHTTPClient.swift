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
#if canImport(FoundationEssentials)
internal import FoundationEssentials
#else
internal import Foundation
#endif

/// A protocol that defines the interface for a streaming HTTP client.
///
/// ``HTTPClient`` provides asynchronous request execution with streaming request
/// and response bodies.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol StreamingHTTPClient<RequestOptions>: ~Copyable, SimpleHTTPClient {

    /// The type used to write request body data and trailers.
    // TODO: Check if we should allow ~Escapable readers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype RequestWriter: AsyncWriter, ~Copyable, SendableMetatype
    where RequestWriter.WriteElement == UInt8

    /// The type used to read response body data and trailers.
    // TODO: Check if we should allow ~Escapable writers https://github.com/apple/swift-http-api-proposal/issues/13
    associatedtype ResponseConcludingReader: ConcludingAsyncReader, ~Copyable, SendableMetatype
    where ResponseConcludingReader.Underlying.ReadElement == UInt8, ResponseConcludingReader.FinalElement == HTTPFields?

    /// Performs an HTTP request and processes the response.
    ///
    /// This method executes the HTTP request with the specified options, then invokes
    /// the response handler when the response header is received. The request and
    /// response bodies are streamed using the client's writer and reader types.
    ///
    /// - Parameters:
    ///   - request: The HTTP request header to send.
    ///   - body: The optional request body to send. When `nil`, no body is sent.
    ///   - options: The options for this request.
    ///   - responseHandler: The closure to process the response. This closure is invoked
    ///     when the response header is received and can read the response body.
    ///
    /// - Returns: The value returned by the response handler closure.
    ///
    /// - Throws: An error if the request fails or if the response handler throws.
    func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming StreamingHTTPClientRequestBody<RequestWriter>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return
    ) async throws -> Return
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension StreamingHTTPClient {
    public func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: Span<UInt8>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, Span<UInt8>) async throws -> Return
    ) async throws -> Return {
        let _body: StreamingHTTPClientRequestBody<RequestWriter>?
        if let body {
            _body = .span(body)
        } else {
            _body = nil
        }
        // TODO: Should be configured somewhere, possibly on the options.
        let limit: Int = 10 * 1024 * 1024
        return try await self.perform(
            request: request,
            body: _body,
            options: options,
            responseHandler: { response, reader in
                let responseBody = try await collectBody(reader, upTo: limit)
                return try await responseHandler(response, responseBody.span)
            }
        )
    }

    private func collectBody<Reader: ConcludingAsyncReader>(
        _ body: consuming Reader,
        upTo limit: Int
    ) async throws -> Data
    where Reader: ~Copyable, Reader.Underlying.ReadElement == UInt8 {
        try await body.collect(upTo: limit == .max ? .max : limit + 1) {
            if $0.count > limit {
                throw LengthLimitExceededError()
            }
            return unsafe $0.withUnsafeBytes { unsafe Data($0) }
        }.0
    }
}

private struct LengthLimitExceededError: Error {}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension StreamingHTTPClientRequestBody where Writer: ~Copyable {
    /// Creates a seekable request body from a span.
    ///
    /// - Parameter data: The bytes to send as the request body.
    internal static func span(_ span: Span<UInt8>) -> Self {
        var data = Data()
        data.reserveCapacity(span.count)
        for index in span.indices {
            data.append(span[index])
        }
        let _data = data
        return .seekable(knownLength: Int64(span.count)) { offset, writer in
            var writer = writer
            try await writer.write(_data.span.extracting(droppingFirst: Int(offset)))
            return nil
        }
    }
}
