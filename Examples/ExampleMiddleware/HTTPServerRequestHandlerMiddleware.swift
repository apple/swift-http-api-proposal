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
@available(anyAppleOS 26.0, *)
public struct HTTPServerRequestHandlerMiddleware<
    RequestContext: HTTPServerCapability.RequestContext & ~Copyable,
    RequestConcludingAsyncReader: ConcludingAsyncReader & ~Copyable,
    ResponseConcludingAsyncWriter: ConcludingAsyncWriter & ~Copyable,
>: Middleware, Sendable
where
    RequestConcludingAsyncReader.Underlying: ~Copyable,
    RequestConcludingAsyncReader.Underlying.ReadElement == UInt8,
    RequestConcludingAsyncReader.FinalElement == HTTPFields?,
    ResponseConcludingAsyncWriter.Underlying: ~Copyable,
    ResponseConcludingAsyncWriter.Underlying.WriteElement == UInt8,
    ResponseConcludingAsyncWriter.FinalElement == HTTPFields?
{
    public typealias Input = HTTPServerMiddlewareInput<RequestContext, RequestConcludingAsyncReader, ResponseConcludingAsyncWriter>
    public typealias NextInput = Void

    /// Creates a new request handler middleware.
    public init() {}

    public func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await input.withContents { request, _, requestBodyAndTrailers, responseSender in
            // Needed since we are lacking call-once closures
            var responseSender: HTTPResponseSender<ResponseConcludingAsyncWriter>? = consume responseSender

            _ = try await requestBodyAndTrailers.consumeAndConclude { reader in
                // Needed since we are lacking call-once closures
                var reader: RequestConcludingAsyncReader.Underlying? = consume reader

                let responseBodyAndTrailers = try await responseSender.take()!.send(.init(status: .ok))
                try await responseBodyAndTrailers.produceAndConclude { responseBody in
                    var responseBody = responseBody
                    try await responseBody.write(reader.take()!)
                    return nil
                }
            }
        }

        return try await next(())
    }
}

@available(anyAppleOS 26.0, *)
extension Middleware where Input: ~Copyable, NextInput: ~Copyable {
    /// Creates a request handler middleware that echoes the request body back as the response.
    ///
    /// This is a simple example middleware that reads the entire request body and writes it
    /// back as the response with a 200 OK status. This middleware is the terminal middleware
    /// in the chain and has `Never` as its `NextInput` type.
    ///
    /// - Returns: A middleware that handles HTTP requests by echoing the body.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @MiddlewareBuilder
    /// func buildMiddleware() -> some Middleware<...> {
    ///     .logging(logger: Logger(label: "HTTPServer"))
    ///     .requestHandler()
    /// }
    /// ```
    public func requestHandler<RequestContext, RequestReader, ResponseWriter>() -> HTTPServerRequestHandlerMiddleware<
        RequestContext, RequestReader, ResponseWriter
    >
    where
        Input == HTTPServerMiddlewareInput<RequestContext, RequestReader, ResponseWriter>,
        RequestContext: HTTPServerCapability.RequestContext & ~Copyable,
        RequestReader: ConcludingAsyncReader & ~Copyable,
        RequestReader.Underlying: ~Copyable,
        RequestReader.Underlying.ReadElement == UInt8,
        RequestReader.FinalElement == HTTPFields?,
        ResponseWriter: ConcludingAsyncWriter & ~Copyable,
        ResponseWriter.Underlying: ~Copyable,
        ResponseWriter.Underlying.WriteElement == UInt8,
        ResponseWriter.FinalElement == HTTPFields?
    {
        HTTPServerRequestHandlerMiddleware()
    }
}
