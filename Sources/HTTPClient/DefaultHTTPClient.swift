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

// We are using an exported import here since we don't want developers
// to have to import both this module and the HTTPAPIs module.
@_exported public import HTTPAPIs

#if canImport(Darwin) || os(Linux)
public import BasicContainers

#if canImport(Darwin)
import URLSessionHTTPClient

@available(anyAppleOS 26.0, *)
typealias ActualHTTPClient = URLSessionHTTPClient
#else
import AsyncHTTPClient
import AHCHTTPClient

@available(anyAppleOS 26.0, *)
typealias ActualHTTPClient = AsyncHTTPClient.HTTPClient
#endif

/// The default HTTP client that manages persistent connections to HTTP servers.
///
/// `DefaultHTTPClient` provides an efficient HTTP client implementation that reuses
/// connections across multiple requests. It supports HTTP/1.1, HTTP/2, and HTTP/3 protocols,
/// automatically handling connection management, protocol negotiation, and resource cleanup.
@available(anyAppleOS 26.0, *)
public final class DefaultHTTPClient: HTTPAPIs.HTTPClient {
    /// The request body writer surfaced by ``DefaultHTTPClient``.
    public struct Writer: CallerAsyncWriter, ~Copyable, SendableMetatype {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = any Error
        public typealias FinalElement = HTTPFields?

        fileprivate var actual: ActualHTTPClient.Writer

        init(actual: consuming ActualHTTPClient.Writer) {
            self.actual = actual
        }

        public mutating func write<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
            buffer: inout Buffer
        ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
            try await self.actual.write(buffer: &buffer)
        }

        public consuming func finish<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
            buffer: inout Buffer,
            finalElement: consuming HTTPFields?
        ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
            try await self.actual.finish(buffer: &buffer, finalElement: finalElement)
        }
    }

    /// The response body reader surfaced by ``DefaultHTTPClient``.
    public struct Reader: AsyncReader, ~Copyable, SendableMetatype {
        public typealias ReadElement = UInt8
        public typealias ReadFailure = any Error
        public typealias Buffer = UniqueArray<UInt8>
        public typealias FinalElement = HTTPFields?

        private var actual: ActualHTTPClient.Reader

        init(actual: consuming ActualHTTPClient.Reader) {
            self.actual = actual
        }

        public mutating func read<Return: ~Copyable, Failure: Error>(
            body: (inout UniqueArray<UInt8>, consuming HTTPFields??) async throws(Failure) -> Return
        ) async throws(EitherError<any Error, Failure>) -> Return {
            try await self.actual.read(body: body)
        }
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
        body: consuming HTTPClientRequestBody<Writer>?,
        options: HTTPRequestOptions,
        responseHandler: (HTTPResponse, consuming Reader, consuming Future<Writer?>) async throws -> Return
    ) async throws -> Return {
        // TODO: translate request options
        let options = self.client.defaultRequestOptions
        let body = body.map {
            HTTPClientRequestBody<ActualHTTPClient.Writer>(
                other: $0,
                transform: { Writer(actual: $0) },
                reverseTransform: { $0.actual }
            )
        }
        return try await self.client.perform(request: request, body: body, options: options) { response, actualReader, writer in
            let writer: Future<Writer?> = writer.map {
                if let writer = $0 { Writer(actual: writer) } else { nil }
            }
            return try await responseHandler(response, Reader(actual: actualReader), writer)
        }
    }
}

#endif
