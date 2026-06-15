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

public import AsyncStreaming
public import HTTPAPIs

/// A struct that encapsulates all parameters passed to HTTP server request handlers.
///
/// ``HTTPServerMiddlewareInput`` serves as a container for the request, request
/// context, request body reader, and response sender. This boxing is necessary
/// because some of these parameters are `~Copyable` types that cannot be
/// stored in tuples.
@available(anyAppleOS 26.0, *)
public struct HTTPServerMiddlewareInput<
    RequestContext: HTTPServerCapability.RequestContext & ~Copyable,
    Reader: AsyncReader & ~Copyable,
    ResponseSender: HTTPResponseSender & ~Copyable
>: ~Copyable
where
    Reader.ReadElement == UInt8,
    Reader.FinalElement == HTTPFields?,
    ResponseSender.Writer: ~Copyable
{
    private let request: HTTPRequest
    private let requestContext: RequestContext
    private let reader: Reader
    private let responseSender: ResponseSender

    public init(
        request: HTTPRequest,
        requestContext: consuming RequestContext,
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
                consuming RequestContext,
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
