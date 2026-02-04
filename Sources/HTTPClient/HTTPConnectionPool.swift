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

/// Configuration options for an HTTP connection pool.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPConnectionPoolConfiguration: Hashable, Sendable {
    /// The maximum number of concurrent HTTP/1.1 connections allowed per host.
    ///
    /// This limit helps prevent overwhelming a single host with too many simultaneous
    /// connections. HTTP/2 and HTTP/3 connections typically use multiplexing and are
    /// not subject to this limit.
    ///
    /// The default value is `6`.
    public var maximumConcurrentHTTP1ConnectionsPerHost: Int = 6

    public init() {}
}

/// A connection pool-based HTTP client that manages persistent connections to HTTP servers.
///
/// `HTTPConnectionPool` provides an efficient HTTP client implementation that reuses
/// connections across multiple requests. It supports HTTP/1.1, HTTP/2, and HTTP/3 protocols,
/// automatically handling connection management, protocol negotiation, and resource cleanup.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPConnectionPool: HTTPClient, Sendable, ~Copyable {
    public struct RequestWriter: AsyncWriter, ~Copyable {
        public mutating func write<Result, Failure>(
            _ body: (inout OutputSpan<UInt8>) async throws(Failure) -> Result
        ) async throws(AsyncStreaming.EitherError<any Error, Failure>) -> Result where Failure: Error {
            #if canImport(Darwin)
            try await self.actual.write(body)
            #else
            fatalError()
            #endif
        }

        #if canImport(Darwin)
        let actual: URLSessionHTTPClient.RequestWriter
        #endif
    }

    public struct ResponseConcludingReader: ConcludingAsyncReader, ~Copyable {
        public struct Underlying: AsyncReader, ~Copyable {
            public mutating func read<Return, Failure>(
                maximumCount: Int?,
                body: (consuming Span<UInt8>) async throws(Failure) -> Return
            ) async throws(AsyncStreaming.EitherError<any Error, Failure>) -> Return where Failure: Error {
                #if canImport(Darwin)
                try await self.actual.read(maximumCount: maximumCount, body: body)
                #else
                fatalError()
                #endif
            }

            #if canImport(Darwin)
            let actual: URLSessionHTTPClient.ResponseConcludingReader.Underlying
            #endif
        }

        public func consumeAndConclude<Return, Failure>(
            body: (consuming sending Underlying) async throws(Failure) -> Return
        ) async throws(Failure) -> (Return, HTTPFields?) where Failure: Error {
            #if canImport(Darwin)
            try await self.actual.consumeAndConclude { actual throws(Failure) in
                try await body(Underlying(actual: actual))
            }
            #else
            fatalError()
            #endif
        }

        #if canImport(Darwin)
        let actual: URLSessionHTTPClient.ResponseConcludingReader
        #endif
    }

    /// A shared connection pool instance with default configuration.
    public static var shared: HTTPConnectionPool {
        #if canImport(Darwin)
        HTTPConnectionPool(client: URLSessionHTTPClient.shared)
        #else
        fatalError()
        #endif
    }

    /// Creates a connection pool with custom configuration and executes a closure with it.
    ///
    /// This method provides a scoped way to use a custom-configured connection pool.
    /// The pool is automatically cleaned up after the closure completes.
    ///
    /// - Parameters:
    ///   - configuration: The configuration to use for the connection pool.
    ///   - body: A closure that receives the configured connection pool and performs
    ///     HTTP operations with it.
    /// - Returns: The value returned by the `body` closure.
    /// - Throws: Any error thrown by the `body` closure.
    public static func withHTTPConnectionPool<Return: ~Copyable, Failure: Error>(
        configuration: HTTPConnectionPoolConfiguration,
        body: (borrowing HTTPConnectionPool) async throws(Failure) -> Return
    ) async throws(Failure) -> Return {
        #if canImport(Darwin)
        try await URLSessionHTTPClient.withClient(poolConfiguration: configuration) { client throws(Failure) in
            try await body(HTTPConnectionPool(client: client))
        }
        #else
        fatalError()
        #endif
    }

    #if canImport(Darwin)
    private let client: URLSessionHTTPClient

    private init(client: URLSessionHTTPClient) {
        self.client = client
    }
    #endif

    public func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>?,
        options: HTTPRequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return
    ) async throws -> Return {
        #if canImport(Darwin)
        let body = body.map {
            HTTPClientRequestBody<URLSessionHTTPClient.RequestWriter>(other: $0, transform: RequestWriter.init)
        }
        return try await self.client.perform(request: request, body: body, options: options) { response, body in
            try await responseHandler(response, ResponseConcludingReader(actual: body))
        }
        #else
        fatalError()
        #endif
    }
}

#endif
