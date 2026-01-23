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
public import FoundationEssentials
#else
public import Foundation
#endif

extension HTTP {
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    public static func perform<Client: HTTPClient, Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<Client.RequestWriter>? = nil,
        options: Client.RequestOptions = .init(),
        on client: Client = HTTPConnectionPool.shared,
        responseHandler: (HTTPResponse, consuming Client.ResponseConcludingReader) async throws -> Return,
    ) async throws -> Return {
        return try await client.perform(request: request, body: body, options: options, responseHandler: responseHandler)
    }

    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    public static func get<Client: HTTPClient>(
        url: URL,
        headerFields: HTTPFields = [:],
        options: Client.RequestOptions = .init(),
        on client: Client = HTTPConnectionPool.shared,
        collectUpTo limit: Int,
    ) async throws -> (HTTPResponse, Data) {
        let request = HTTPRequest(url: url, headerFields: headerFields)
        return try await client.perform(request: request, body: nil, options: options) { response, body in
            (
                response,
                try await body.collect(upTo: limit) {
                    unsafe $0.withUnsafeBytes { unsafe Data($0) }
                }.0
            )
        }
    }

    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    public static func post<Client: HTTPClient>(
        url: URL,
        headerFields: HTTPFields = [:],
        body: Data,
        options: Client.RequestOptions = .init(),
        on client: Client = HTTPConnectionPool.shared,
        collectUpTo limit: Int,
    ) async throws -> (HTTPResponse, Data) {
        let request = HTTPRequest(method: .post, url: url, headerFields: headerFields)
        return try await client.perform(request: request, body: .init(body), options: options) { response, body in
            (
                response,
                try await body.collect(upTo: limit) {
                    unsafe $0.withUnsafeBytes { unsafe Data($0) }
                }.0
            )
        }
    }

    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    public static func put<Client: HTTPClient>(
        url: URL,
        headerFields: HTTPFields = [:],
        body: Data,
        options: Client.RequestOptions = .init(),
        on client: Client = HTTPConnectionPool.shared,
        collectUpTo limit: Int,
    ) async throws -> (HTTPResponse, Data) {
        let request = HTTPRequest(method: .put, url: url, headerFields: headerFields)
        return try await client.perform(request: request, body: .init(body), options: options) { response, body in
            (
                response,
                try await body.collect(upTo: limit) {
                    unsafe $0.withUnsafeBytes { unsafe Data($0) }
                }.0
            )
        }
    }

    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    public static func delete<Client: HTTPClient>(
        url: URL,
        headerFields: HTTPFields = [:],
        body: Data? = nil,
        options: Client.RequestOptions = .init(),
        on client: Client = HTTPConnectionPool.shared,
        collectUpTo limit: Int,
    ) async throws -> (HTTPResponse, Data) {
        let request = HTTPRequest(method: .delete, url: url, headerFields: headerFields)
        return try await client.perform(request: request, body: body.map { .init($0) }, options: options) { response, body in
            (
                response,
                try await body.collect(upTo: limit) {
                    unsafe $0.withUnsafeBytes { unsafe Data($0) }
                }.0
            )
        }
    }

    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    public static func patch<Client: HTTPClient>(
        url: URL,
        headerFields: HTTPFields = [:],
        body: Data,
        options: Client.RequestOptions = .init(),
        on client: Client = HTTPConnectionPool.shared,
        collectUpTo limit: Int,
    ) async throws -> (HTTPResponse, Data) {
        let request = HTTPRequest(method: .patch, url: url, headerFields: headerFields)
        return try await client.perform(request: request, body: .init(body), options: options) { response, body in
            (
                response,
                try await body.collect(upTo: limit) {
                    unsafe $0.withUnsafeBytes { unsafe Data($0) }
                }.0
            )
        }
    }
}
