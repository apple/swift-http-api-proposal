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
public import Middleware

/// A terminal middleware that echoes HTTP request bodies back as responses.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerRequestHandlerMiddleware<
    Reader: HTTPBodyReader & ~Copyable,
    ResponseSender: HTTPResponseSender & ~Copyable,
>: Middleware, Sendable
where
    ResponseSender.Writer: ~Copyable,
    Reader.Buffer == ResponseSender.Writer.Buffer
{
    public typealias Input = HTTPServerMiddlewareInput<Reader, ResponseSender>
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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension Middleware where Input: ~Copyable & ~Escapable, NextInput: ~Copyable & ~Escapable {
    /// Creates a request handler middleware that echoes the request body back as the response.
    public func requestHandler<Reader, ResponseSender>() -> HTTPServerRequestHandlerMiddleware<Reader, ResponseSender>
    where
        Input == HTTPServerMiddlewareInput<Reader, ResponseSender>,
        Reader: HTTPBodyReader & ~Copyable,
        ResponseSender: HTTPResponseSender & ~Copyable,
        ResponseSender.Writer: ~Copyable,
        Reader.Buffer == ResponseSender.Writer.Buffer
    {
        HTTPServerRequestHandlerMiddleware()
    }
}
