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

import HTTPAPIs
import Middleware

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct ExampleMiddlewareClient<Client: HTTPClient & ~Copyable, ClientMiddleware: Middleware<HTTPRequest, HTTPRequest>>: HTTPClient, ~Copyable {
    typealias RequestOptions = Client.RequestOptions
    typealias RequestSender = Client.RequestSender
    typealias ResponseReceiver = Client.ResponseReceiver

    var defaultRequestOptions: Client.RequestOptions {
        self.client.defaultRequestOptions
    }

    private var client: Client
    private let middleware: ClientMiddleware

    init(
        client: consuming Client,
        @MiddlewareBuilder
        middlewareBuilder: (RequestMiddleware<Client>) -> ClientMiddleware
    ) {
        self.client = client
        self.middleware = middlewareBuilder(RequestMiddleware<Client>())
    }

    mutating func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestSender>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseReceiver) async throws -> Return
    ) async throws -> Return {
        var body = Optional(body)
        return try await self.middleware.intercept(
            input: request
        ) { request in
            try await self.client.perform(
                request: request,
                body: body.take()!,
                options: options,
                responseHandler: responseHandler
            )
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct RequestMiddleware<Client: HTTPClient & ~Copyable>: Middleware {
    typealias Input = HTTPRequest
    typealias NextInput = Input

    func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await next(input)
    }
}
