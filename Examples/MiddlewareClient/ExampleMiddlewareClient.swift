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

import ExampleMiddleware
import HTTPAPIs
import Middleware

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct ExampleMiddlewareClient<
    Client: HTTPClient & ~Copyable,
    OutWriter: HTTPBodyWriter & ~Copyable & SendableMetatype,
    ClientMiddleware: Middleware & Sendable
>: HTTPClient, ~Copyable
where
    Client.Writer: SendableMetatype,
    ClientMiddleware.Input: ~Copyable,
    ClientMiddleware.NextInput: ~Copyable,
    ClientMiddleware.Input == HTTPClientMiddlewareInput<OutWriter>,
    ClientMiddleware.NextInput == HTTPClientMiddlewareInput<Client.Writer>
{
    typealias RequestOptions = Client.RequestOptions
    typealias Writer = OutWriter
    typealias Reader = Client.Reader

    var defaultRequestOptions: Client.RequestOptions {
        self.client.defaultRequestOptions
    }

    private var client: Client
    private let middleware: ClientMiddleware

    init(
        client: consuming Client,
        @MiddlewareBuilder
        middlewareBuilder: (BaseRequestMiddleware<Client>) -> ClientMiddleware
    ) {
        self.client = client
        self.middleware = middlewareBuilder(BaseRequestMiddleware<Client>())
    }

    mutating func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<OutWriter>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming Reader) async throws -> Return
    ) async throws -> Return {
        return try await self.middleware.intercept(
            input: HTTPClientMiddlewareInput(request: request, body: body)
        ) { middlewareOutput in
            try await self.client.perform(
                request: middlewareOutput.request,
                body: middlewareOutput.body,
                options: options,
                responseHandler: responseHandler
            )
        }
    }
}

/// The starting middleware (seed) for the client-side chain. Pass-through; its
/// purpose is to anchor the chain's Input type so the user-facing extensions
/// like `.forwarding()` and `.checksumTrailer()` infer the right generics.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct BaseRequestMiddleware<Client: HTTPClient & ~Copyable>: Middleware, Sendable
where Client.Writer: SendableMetatype {
    typealias Input = HTTPClientMiddlewareInput<Client.Writer>
    typealias NextInput = HTTPClientMiddlewareInput<Client.Writer>

    func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await next(input)
    }
}
