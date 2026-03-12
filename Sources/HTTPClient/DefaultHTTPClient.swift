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

// We are using an exported import here since we don't want developers
// to have to import both this module and the HTTPAPIs module.
@_exported public import HTTPAPIs

#if canImport(Darwin) || os(Linux)

#if canImport(Darwin)
import URLSessionHTTPClient

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
typealias ActualHTTPClient = URLSessionHTTPClient
#else
import AsyncHTTPClient
import AHCHTTPClient

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
typealias ActualHTTPClient = AsyncHTTPClient.HTTPClient
#endif

/// The default HTTP client that manages persistent connections to HTTP servers.
///
/// `DefaultHTTPClient` provides an efficient HTTP client implementation that reuses
/// connections across multiple requests. It supports HTTP/1.1, HTTP/2, and HTTP/3 protocols,
/// automatically handling connection management, protocol negotiation, and resource cleanup.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct DefaultHTTPClient: HTTPAPIs.HTTPClient, ~Copyable {
    public struct RequestWriter: AsyncWriter, ~Copyable {
        public mutating func write<Result, Failure>(
            _ body: (inout OutputSpan<UInt8>) async throws(Failure) -> Result
        ) async throws(AsyncStreaming.EitherError<any Error, Failure>) -> Result where Failure: Error {
            try await self.actual.write(body)
        }

        public mutating func write(
            _ span: Span<UInt8>
        ) async throws(EitherError<any Error, AsyncWriterWroteShortError>) {
            try await self.actual.write(span)
        }

        var actual: ActualHTTPClient.RequestWriter
    }

    public struct ResponseConcludingReader: ConcludingAsyncReader, ~Copyable {
        public struct Underlying: AsyncReader, ~Copyable {
            public mutating func read<Return, Failure>(
                maximumCount: Int?,
                body: (consuming Span<UInt8>) async throws(Failure) -> Return
            ) async throws(AsyncStreaming.EitherError<any Error, Failure>) -> Return where Failure: Error {
                try await self.actual.read(maximumCount: maximumCount, body: body)
            }

            var actual: ActualHTTPClient.ResponseConcludingReader.Underlying
        }

        public func consumeAndConclude<Return, Failure>(
            body: (consuming sending Underlying) async throws(Failure) -> Return
        ) async throws(Failure) -> (Return, HTTPFields?) where Failure: Error {
            try await self.actual.consumeAndConclude { actual throws(Failure) in
                try await body(Underlying(actual: actual))
            }
        }

        let actual: ActualHTTPClient.ResponseConcludingReader
    }

    /// A shared connection pool instance with default configuration.
    public static var shared: DefaultHTTPClient {
        DefaultHTTPClient(client: ActualHTTPClient.shared)
    }

    /// Creates a client with custom pool configuration and executes a closure with it.
    ///
    /// This method provides a scoped way to use a custom-configured connection pool.
    /// The pool is automatically cleaned up after the closure completes.
    ///
    /// - Parameters:
    ///   - poolConfiguration: The configuration to use for the connection pool.
    ///   - body: A closure that receives the configured connection pool and performs
    ///     HTTP operations with it.
    /// - Returns: The value returned by the `body` closure.
    /// - Throws: Any error thrown by the `body` closure.
    public static func withClient<Return: ~Copyable, Failure: Error>(
        poolConfiguration: HTTPConnectionPoolConfiguration,
        body: (borrowing DefaultHTTPClient) async throws(Failure) -> Return
    ) async throws(Failure) -> Return {
        #if canImport(Darwin)
        var configuration = URLSessionConnectionPoolConfiguration()
        configuration.maximumConcurrentHTTP1ConnectionsPerHost = poolConfiguration.maximumConcurrentHTTP1ConnectionsPerHost
        return try await URLSessionHTTPClient.withClient(poolConfiguration: configuration) { client throws(Failure) in
            try await body(DefaultHTTPClient(client: client))
        }
        #else
        var result: Result<Return, Failure>? = nil
        do {
            var configuration = AsyncHTTPClient.HTTPClient.Configuration()
            configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = poolConfiguration.maximumConcurrentHTTP1ConnectionsPerHost
            try await AsyncHTTPClient.HTTPClient.withHTTPClient(configuration: configuration) { client in
                do throws(Failure) {
                    result = .success(try await body(DefaultHTTPClient(client: client)))
                } catch {
                    result = .failure(error)
                }
            }
        } catch {
            // Ignore error
        }
        return try result!.get()
        #endif
    }

    private let client: ActualHTTPClient

    private init(client: ActualHTTPClient) {
        self.client = client
    }

    public var defaultRequestOptions: HTTPRequestOptions {
        .init()
    }

    public func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>?,
        options: HTTPRequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return
    ) async throws -> Return {
        // TODO: translate request options
        let options = self.client.defaultRequestOptions
        let body = body.map {
            HTTPClientRequestBody<ActualHTTPClient.RequestWriter>(other: $0) { RequestWriter(actual: $0) }
        }
        return try await self.client.perform(request: request, body: body, options: options) { response, body in
            try await responseHandler(response, ResponseConcludingReader(actual: body))
        }
    }
}

#endif
