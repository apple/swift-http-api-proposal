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

public import AsyncStreaming
public import HTTPTypes

/// This type holds the values passed to the ``HTTPServerRequestHandler`` when handling a request.
///
/// It is necessary to box them together so that they can be used with `Middlewares`, as this will be the `Middleware.Input`.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct RequestResponseMiddlewareBox<
    RequestReader: ConcludingAsyncReader & ~Copyable,
    ResponseWriter: ConcludingAsyncWriter & ~Copyable
>: ~Copyable {
    private let request: HTTPRequest
    private let requestContext: HTTPRequestContext
    private let requestReader: RequestReader
    private let responseSender: HTTPResponseSender<ResponseWriter>

    /// Create a new ``RequestResponseMiddlewareBox``.
    /// - Parameters:
    ///   - request: The `HTTPRequest`.
    ///   - requestReader: The `RequestReader`.
    ///   - responseSender: The ``HTTPResponseSender``.
    public init(
        request: HTTPRequest,
        requestContext: HTTPRequestContext,
        requestReader: consuming RequestReader,
        responseSender: consuming HTTPResponseSender<ResponseWriter>
    ) {
        self.request = request
        self.requestContext = requestContext
        self.requestReader = requestReader
        self.responseSender = responseSender
    }

    /// Provides a closure exposing the request, request reader and response sender contained in this box.
    /// - Parameter handler: The handler for this box's contents.
    /// - Returns: The value returned from `handler`.
    public consuming func withContents<T>(
        _ handler:
            nonisolated(nonsending) (
                HTTPRequest,
                HTTPRequestContext,
                consuming RequestReader,
                consuming HTTPResponseSender<ResponseWriter>
            ) async throws -> T
    ) async throws -> T {
        try await handler(
            self.request,
            self.requestContext,
            self.requestReader,
            self.responseSender
        )
    }
}

@available(*, unavailable)
extension RequestResponseMiddlewareBox: Sendable {}
