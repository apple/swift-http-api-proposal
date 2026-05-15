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
import BasicContainers

#if canImport(Darwin)
public import URLSessionHTTPClient

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public typealias ActualHTTPClient = URLSessionHTTPClient
#else
public import AsyncHTTPClient
public import AHCHTTPClient

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public typealias ActualHTTPClient = AsyncHTTPClient.HTTPClient
#endif

/// The default HTTP client that manages persistent connections to HTTP servers.
///
/// `DefaultHTTPClient` provides an efficient HTTP client implementation that reuses
/// connections across multiple requests. It supports HTTP/1.1, HTTP/2, and HTTP/3 protocols,
/// automatically handling connection management, protocol negotiation, and resource cleanup.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public final class DefaultHTTPClient: HTTPAPIs.HTTPClient {
    public typealias Writer = ActualHTTPClient.Writer
    public typealias Reader = ActualHTTPClient.Reader

    /// A shared connection pool instance with default configuration.
    public static var shared: DefaultHTTPClient {
        DefaultHTTPClient(client: ActualHTTPClient.shared)
    }

    /// Creates a client with custom pool configuration and executes a closure with it.
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
        responseHandler: (HTTPResponse, consuming Reader) async throws -> Return
    ) async throws -> Return {
        // TODO: translate request options
        let options = self.client.defaultRequestOptions
        return try await self.client.perform(request: request, body: body, options: options, responseHandler: responseHandler)
    }
}

#endif
