//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public import HTTPAPIs

/// A struct that encapsulates all parameters passed to HTTP server request handlers.
///
/// ``HTTPServerMiddlewareInput`` serves as a container for the request, request context,
/// request receiver, and response sender. This boxing is necessary because some of these
/// parameters are `~Copyable` types that cannot be stored in tuples, and it provides a
/// convenient way to pass all request-handling components through the middleware chain.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerMiddlewareInput<
    RequestReceiver: HTTPRequestReceiver & ~Copyable,
    ResponseSender: HTTPResponseSender & ~Copyable
>: ~Copyable where RequestReceiver.Reader: ~Copyable, ResponseSender.Writer: ~Copyable {
    private let request: HTTPRequest
    private let requestContext: HTTPRequestContext
    private let requestReceiver: RequestReceiver
    private let responseSender: ResponseSender

    public init(
        request: HTTPRequest,
        requestContext: HTTPRequestContext,
        requestReceiver: consuming RequestReceiver,
        responseSender: consuming ResponseSender
    ) {
        self.request = request
        self.requestContext = requestContext
        self.requestReceiver = requestReceiver
        self.responseSender = responseSender
    }

    public consuming func withContents<Return: ~Copyable>(
        _ handler:
            (
                HTTPRequest,
                HTTPRequestContext,
                consuming RequestReceiver,
                consuming ResponseSender
            ) async throws -> Return
    ) async throws -> Return {
        try await handler(
            self.request,
            self.requestContext,
            self.requestReceiver,
            self.responseSender
        )
    }
}

@available(*, unavailable)
extension HTTPServerMiddlewareInput: Sendable {}
