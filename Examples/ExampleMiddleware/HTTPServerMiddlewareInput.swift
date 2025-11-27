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

public import HTTPAPIs

/// A struct that encapsulates all parameters passed to HTTP server request handlers.
///
/// ``HTTPServerMiddlewareInput`` serves as a container for the request, request context,
/// request body reader, and response sender. This boxing is necessary because some of these
/// parameters are `~Copyable` types that cannot be stored in tuples, and it provides a
/// convenient way to pass all request-handling components through the middleware chain.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct HTTPServerMiddlewareInput<
    RequestReader: ConcludingAsyncReader & ~Copyable,
    ResponseWriter: ConcludingAsyncWriter & ~Copyable
>: ~Copyable {
    private let request: HTTPRequest
    private let requestContext: HTTPRequestContext
    private let requestReader: RequestReader
    private let responseSender: HTTPResponseSender<ResponseWriter>

    /// Creates a new HTTP server middleware input container.
    ///
    /// - Parameters:
    ///   - request: The HTTP request headers and metadata.
    ///   - requestContext: Additional context information for the request.
    ///   - requestReader: A reader for accessing the request body data and trailing headers.
    ///   - responseSender: A sender for transmitting the HTTP response and response body.
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

    /// Provides scoped access to the contents of this input container.
    ///
    /// This method exposes all the encapsulated request components to a closure, allowing
    /// middleware to access and process them. The closure receives the request, request context,
    /// request reader, and response sender as separate parameters.
    ///
    /// - Parameter handler: A closure that processes the request components.
    ///
    /// - Returns: The value returned by the handler closure.
    ///
    /// - Throws: Any error thrown by the handler closure.
    public consuming func withContents<Return: ~Copyable>(
        _ handler:
            (
                HTTPRequest,
                HTTPRequestContext,
                consuming RequestReader,
                consuming HTTPResponseSender<ResponseWriter>
            ) async throws -> Return
    ) async throws -> Return {
        try await handler(
            self.request,
            self.requestContext,
            self.requestReader,
            self.responseSender
        )
    }
}

@available(*, unavailable)
extension HTTPServerMiddlewareInput: Sendable {}
