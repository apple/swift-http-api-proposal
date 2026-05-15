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
public import HTTPTypes

/// This type holds the values passed to the ``HTTPServerRequestHandler`` when handling a request.
///
/// It is necessary to box them together so that they can be used with `Middlewares`, as this will be the `Middleware.Input`.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct RequestResponseMiddlewareBox<
    RequestReceiver: HTTPRequestReceiver & ~Copyable,
    ResponseSender: HTTPResponseSender & ~Copyable
>: ~Copyable
where RequestReceiver.Reader: ~Copyable, ResponseSender.Writer: ~Copyable {
    private let request: HTTPRequest
    private let requestContext: HTTPRequestContext
    private let requestReceiver: RequestReceiver
    private let responseSender: ResponseSender

    /// Create a new ``RequestResponseMiddlewareBox``.
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

    /// Provides a closure exposing the request, request receiver, and response sender contained in this box.
    /// - Parameter handler: The handler for this box's contents.
    /// - Returns: The value returned from `handler`.
    public consuming func withContents<T>(
        _ handler:
            nonisolated(nonsending) (
                HTTPRequest,
                HTTPRequestContext,
                consuming RequestReceiver,
                consuming ResponseSender
            ) async throws -> T
    ) async throws -> T {
        try await handler(
            self.request,
            self.requestContext,
            self.requestReceiver,
            self.responseSender
        )
    }
}

@available(*, unavailable)
extension RequestResponseMiddlewareBox: Sendable {}
