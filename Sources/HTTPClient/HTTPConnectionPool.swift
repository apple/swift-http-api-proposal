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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPConnectionPoolConfiguration: Hashable, Sendable {
    public var maximumConcurrentHTTP1ConnectionsPerHost: Int = 6
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public final class HTTPConnectionPool: HTTPClient, Sendable {
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

    public static let shared = HTTPConnectionPool(configuration: .init())

    public static func withHTTPConnectionPool<Return: ~Copyable, Failure: Error>(
        connectionPoolConfiguration: HTTPConnectionPoolConfiguration,
        body: (HTTPConnectionPool) async throws(Failure) -> Return
    ) async throws(Failure) -> Return {
        try await body(HTTPConnectionPool(configuration: connectionPoolConfiguration))
    }

    #if canImport(Darwin)
    private let client: URLSessionHTTPClient
    #endif

    private init(configuration: HTTPConnectionPoolConfiguration) {
        #if canImport(Darwin)
        self.client = URLSessionHTTPClient(poolConfiguration: configuration)
        #endif
    }

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
