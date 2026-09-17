//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public import HTTPAPIs
public import Middleware

/// An error thrown when a request fails authentication.
///
/// This error is thrown after the middleware has already sent a `401 Unauthorized` response
/// with the appropriate `WWW-Authenticate` header. Callers can catch this error to perform
/// additional logging or cleanup, but the response has already been sent to the client.
public struct AuthenticationError: Error {
    public init() {}
}

/// A middleware that checks for a valid `Authorization` header and responds with
/// `401 Unauthorized` and a `WWW-Authenticate` header when authentication fails.
///
/// ``HTTPServerAuthenticationMiddleware`` validates incoming requests by checking
/// the `Authorization` header against a user-provided validation closure. If the
/// header is missing or the validator returns `false`, the middleware short-circuits
/// the chain and responds immediately with a `401 Unauthorized` status.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerAuthenticationMiddleware<
    RequestConcludingAsyncReader: ConcludingAsyncReader & ~Copyable,
    ResponseConcludingAsyncWriter: ConcludingAsyncWriter & ~Copyable
>: Middleware
where
    RequestConcludingAsyncReader: ~Copyable & Escapable,
    RequestConcludingAsyncReader.Underlying: ~Copyable & Escapable,
    RequestConcludingAsyncReader.Underlying.ReadElement == UInt8,
    RequestConcludingAsyncReader.FinalElement == HTTPFields?,
    ResponseConcludingAsyncWriter: ~Copyable & Escapable,
    ResponseConcludingAsyncWriter.Underlying: ~Copyable & Escapable,
    ResponseConcludingAsyncWriter.Underlying.WriteElement == UInt8,
    ResponseConcludingAsyncWriter.FinalElement == HTTPFields?
{
    public typealias Input = HTTPServerMiddlewareInput<RequestConcludingAsyncReader, ResponseConcludingAsyncWriter>
    public typealias NextInput = Input

    let scheme: String
    let validate: @Sendable (String) -> Bool

    /// Creates a new authentication middleware.
    ///
    /// - Parameters:
    ///   - requestConcludingAsyncReaderType: The type of the request reader. Defaults to the inferred type.
    ///   - responseConcludingAsyncWriterType: The type of the response writer. Defaults to the inferred type.
    ///   - scheme: The authentication scheme advertised in the `WWW-Authenticate` response header (e.g. `"Bearer"`).
    ///   - validate: A closure that receives the `Authorization` header value and returns `true` if the request is authorized.
    public init(
        requestConcludingAsyncReaderType: RequestConcludingAsyncReader.Type = RequestConcludingAsyncReader.self,
        responseConcludingAsyncWriterType: ResponseConcludingAsyncWriter.Type = ResponseConcludingAsyncWriter.self,
        scheme: String,
        validate: @escaping @Sendable (String) -> Bool
    ) {
        self.scheme = scheme
        self.validate = validate
    }

    public func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await input.withContents { request, context, requestReader, responseSender in
            let isAuthorized: Bool
            if let authorization = request.headerFields[.authorization] {
                isAuthorized = self.validate(authorization)
            } else {
                isAuthorized = false
            }

            guard isAuthorized else {
                let writer = try await responseSender.send(
                    HTTPResponse(
                        status: .unauthorized,
                        headerFields: [.wwwAuthenticate: self.scheme]
                    )
                )
                try await writer.produceAndConclude { _ in
                    return ((), nil)
                }
                // TODO: what should it mean when a middleware throws?
                throw AuthenticationError()
            }

            let nextInput = HTTPServerMiddlewareInput(
                request: request,
                requestContext: context,
                requestReader: requestReader,
                responseSender: responseSender
            )
            return try await next(nextInput)
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension Middleware where Input: ~Copyable, NextInput: ~Copyable {
    /// Creates authentication middleware that validates the `Authorization` header.
    ///
    /// Requests without a valid `Authorization` header receive a `401 Unauthorized`
    /// response with a `WWW-Authenticate` header advertising the expected scheme.
    ///
    /// - Parameters:
    ///   - scheme: The authentication scheme (e.g. `"Bearer"`).
    ///   - validate: A closure that returns `true` if the `Authorization` header value is valid.
    /// - Returns: A middleware that enforces authentication.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @MiddlewareBuilder
    /// func buildMiddleware() -> some Middleware<...> {
    ///     .authenticate(scheme: "Bearer") { $0.hasPrefix("Bearer ") }
    ///     .logging(logger: Logger(label: "HTTPServer"))
    ///     .requestHandler()
    /// }
    /// ```
    public func authenticate<RequestReader, ResponseWriter>(
        scheme: String,
        validate: @escaping @Sendable (String) -> Bool
    ) -> HTTPServerAuthenticationMiddleware<RequestReader, ResponseWriter>
    where
        Input == HTTPServerMiddlewareInput<RequestReader, ResponseWriter>,
        RequestReader: ConcludingAsyncReader & ~Copyable & Escapable,
        RequestReader.Underlying: ~Copyable & Escapable,
        RequestReader.Underlying.ReadElement == UInt8,
        RequestReader.FinalElement == HTTPFields?,
        ResponseWriter: ConcludingAsyncWriter & ~Copyable & Escapable,
        ResponseWriter.Underlying: ~Copyable & Escapable,
        ResponseWriter.Underlying.WriteElement == UInt8,
        ResponseWriter.FinalElement == HTTPFields?
    {
        HTTPServerAuthenticationMiddleware(scheme: scheme, validate: validate)
    }
}
