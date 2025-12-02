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

import Synchronization

#if canImport(Darwin)
public import Security
#endif

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
@usableFromInline
struct ScopedHTTPClientEventHandler<NextHandler: HTTPClientEventHandler & ~Escapable & ~Copyable>:
    HTTPClientEventHandler, ~Escapable, ~Copyable
{
    private let nextHandler: NextHandler

    private var redirectionHandler:
        (
            (_ response: HTTPResponse, _ newRequest: HTTPRequest) async throws ->
                HTTPClientRedirectionAction
        )? = nil
    #if canImport(Darwin)
    private var serverTrustHandler: ((_ trust: SecTrust) async throws -> HTTPClientTrustResult)? = nil
    #endif

    @_lifetime(copy nextHandler)
    private init(nextHandler: consuming NextHandler) {
        self.nextHandler = nextHandler
    }

    @usableFromInline
    func handleRedirection(
        response: HTTPResponse,
        newRequest: HTTPRequest
    ) async throws -> HTTPClientRedirectionAction {
        if let handler = self.redirectionHandler {
            try await handler(response, newRequest)
        } else {
            try await self.nextHandler.handleRedirection(response: response, newRequest: newRequest)
        }
    }

    #if canImport(Darwin)
    @usableFromInline
    func handleServerTrust(_ trust: SecTrust) async throws -> HTTPClientTrustResult {
        if let handler = self.serverTrustHandler {
            try await handler(trust)
        } else {
            try await self.nextHandler.handleServerTrust(trust)
        }
    }
    #endif

    #if canImport(Darwin)
    @usableFromInline
    static func withEventHandler<Return>(
        nextHandler: consuming NextHandler,
        operation: (inout ScopedHTTPClientEventHandler<NextHandler>) async throws -> Return,
        onRedirection: (
            (_ response: HTTPResponse, _ newRequest: HTTPRequest) async throws ->
                HTTPClientRedirectionAction
        )?,
        onServerTrust: ((_ trust: SecTrust) async throws -> HTTPClientTrustResult)?,
    ) async rethrows -> Return {
        var eventHandler = ScopedHTTPClientEventHandler(nextHandler: nextHandler)
        eventHandler.redirectionHandler = onRedirection
        eventHandler.serverTrustHandler = onServerTrust
        return try await operation(&eventHandler)
    }
    #else
    @usableFromInline
    static func withEventHandler<Return>(
        nextHandler: consuming NextHandler,
        operation: (inout ScopedHTTPClientEventHandler<NextHandler>) async throws -> Return,
        onRedirection: (
            (_ response: HTTPResponse, _ newRequest: HTTPRequest) async throws ->
                HTTPClientRedirectionAction
        )?,
    ) async rethrows -> Return {
        var eventHandler = ScopedHTTPClientEventHandler(nextHandler: nextHandler)
        eventHandler.redirectionHandler = onRedirection
        return try await operation(&eventHandler)
    }
    #endif
}
