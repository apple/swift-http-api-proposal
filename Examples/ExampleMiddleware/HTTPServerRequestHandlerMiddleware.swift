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
///
/// ``HTTPServerRequestHandlerMiddleware`` serves as an example terminal middleware that reads
/// the entire request body and writes it back as the response body with a 200 OK status.
/// This middleware has `Never` as its `NextInput` type, indicating it's the end of the chain.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerRequestHandlerMiddleware<
    RequestReceiver: HTTPRequestReceiver & ~Copyable,
    ResponseSender: HTTPResponseSender & ~Copyable,
>: Middleware, Sendable
where
    RequestReceiver.Reader: ~Copyable,
    ResponseSender.Writer: ~Copyable
{
    public typealias Input = HTTPServerMiddlewareInput<RequestReceiver, ResponseSender>
    public typealias NextInput = Void

    /// Creates a new request handler middleware.
    public init() {}

    public func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await input.withContents { request, _, requestReceiver, responseSender in
            // Needed since we are lacking call-once closures
            var requestReceiver = Optional(consume requestReceiver)

            try await responseSender.send(.init(status: .ok)) { writer in
                var writer = writer
                let (_, trailers) = try await requestReceiver.take()!.receive { reader in
                    try await writer.write(reader)
                }
                return ((), trailers)
            }
        }

        return try await next(())
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension Middleware where Input: ~Copyable, NextInput: ~Copyable {
    /// Creates a request handler middleware that echoes the request body back as the response.
    public func requestHandler<RequestReceiver, ResponseSender>() -> HTTPServerRequestHandlerMiddleware<RequestReceiver, ResponseSender>
    where
        Input == HTTPServerMiddlewareInput<RequestReceiver, ResponseSender>,
        RequestReceiver: HTTPRequestReceiver & ~Copyable,
        RequestReceiver.Reader: ~Copyable,
        ResponseSender: HTTPResponseSender & ~Copyable,
        ResponseSender.Writer: ~Copyable
    {
        HTTPServerRequestHandlerMiddleware()
    }
}
