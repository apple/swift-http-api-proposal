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
/// ``HTTPServerMiddlewareInput`` serves as a container for the request, request
/// context, request body reader, and response sender. This boxing is necessary
/// because some of these parameters are `~Copyable` types that cannot be
/// stored in tuples.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerMiddlewareInput<
    Reader: HTTPBodyReader & ~Copyable & ~Escapable,
    ResponseSender: HTTPResponseSender & ~Copyable & ~Escapable
>: ~Copyable, ~Escapable where ResponseSender.Writer: ~Copyable & ~Escapable {
    private let request: HTTPRequest
    private let requestContext: HTTPRequestContext
    private let reader: Reader
    private let responseSender: ResponseSender

    @_lifetime(copy reader, copy responseSender)
    public init(
        request: HTTPRequest,
        requestContext: HTTPRequestContext,
        reader: consuming Reader,
        responseSender: consuming ResponseSender
    ) {
        self.request = request
        self.requestContext = requestContext
        self.reader = reader
        self.responseSender = responseSender
    }

    public consuming func withContents<Return: ~Copyable>(
        _ handler:
            (
                HTTPRequest,
                HTTPRequestContext,
                consuming Reader,
                consuming ResponseSender
            ) async throws -> Return
    ) async throws -> Return {
        try await handler(
            self.request,
            self.requestContext,
            self.reader,
            self.responseSender
        )
    }
}

@available(*, unavailable)
extension HTTPServerMiddlewareInput: Sendable {}
