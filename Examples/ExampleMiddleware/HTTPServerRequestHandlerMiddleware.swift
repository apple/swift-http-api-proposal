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
public import Middleware

/// A terminal middleware that echoes HTTP request bodies back as responses.
@available(anyAppleOS 26.0, *)
public struct HTTPServerRequestHandlerMiddleware<
    RequestContext: HTTPServerCapability.RequestContext & ~Copyable,
    Reader: AsyncReader & ~Copyable,
    ResponseSender: HTTPResponseSender & ~Copyable,
>: Middleware, Sendable
where
    Reader.ReadElement == UInt8,
    Reader.FinalElement == HTTPFields?,
    ResponseSender.Writer: ~Copyable
{
    public typealias Input = HTTPServerMiddlewareInput<RequestContext, Reader, ResponseSender>
    public typealias NextInput = Void

    /// Creates a new request handler middleware.
    public init() {}

    public func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await input.withContents { request, _, reader, responseSender in
            let writer = try await responseSender.send(.init(status: .ok))
            try await reader.pipe(into: writer)
        }

        return try await next(())
    }
}

@available(anyAppleOS 26.0, *)
extension Middleware where Input: ~Copyable & ~Escapable, NextInput: ~Copyable & ~Escapable {
    /// Creates a request handler middleware that echoes the request body back as the response.
    public func requestHandler<RequestContext, Reader, ResponseSender>() -> HTTPServerRequestHandlerMiddleware<RequestContext, Reader, ResponseSender>
    where
        Input == HTTPServerMiddlewareInput<RequestContext, Reader, ResponseSender>,
        RequestContext: HTTPServerCapability.RequestContext & ~Copyable,
        Reader: AsyncReader & ~Copyable,
        Reader.ReadElement == UInt8,
        Reader.FinalElement == HTTPFields?,
        ResponseSender: HTTPResponseSender & ~Copyable,
        ResponseSender.Writer: ~Copyable
    {
        HTTPServerRequestHandlerMiddleware()
    }
}
