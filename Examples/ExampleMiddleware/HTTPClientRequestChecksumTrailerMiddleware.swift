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

import BasicContainers
public import HTTPAPIs
public import Middleware

/// A client-side middleware that observes all request body bytes and appends
/// a checksum (XOR of all bytes) as the `X-Body-Checksum` trailer.
///
/// Client-side mirror of ``HTTPServerResponseChecksumTrailerMiddleware``. The
/// `body` field of the input is wrapped with a ``ChecksumRequestWriter`` so
/// the inner stage (eventually the underlying client) receives a body whose
/// writes are intercepted to update the checksum, and whose `finish` appends
/// the `X-Body-Checksum` trailer.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPClientRequestChecksumTrailerMiddleware<
    Writer: HTTPBodyWriter & ~Copyable & SendableMetatype
>: Middleware, Sendable {
    public typealias Input = HTTPClientMiddlewareInput<ChecksumRequestWriter<Writer>>
    public typealias NextInput = HTTPClientMiddlewareInput<Writer>

    public init(writerType: Writer.Type = Writer.self) {}

    public func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        let translatedBody: HTTPClientRequestBody<Writer>? = input.body.map { userBody in
            HTTPClientRequestBody<Writer>(other: userBody) { baseWriter in
                ChecksumRequestWriter(wrapping: baseWriter)
            }
        }
        return try await next(
            HTTPClientMiddlewareInput(request: input.request, body: translatedBody)
        )
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension Middleware where Input: ~Copyable & ~Escapable, NextInput: ~Copyable & ~Escapable {
    /// Adds a middleware that emits an `X-Body-Checksum` trailer covering the request body.
    public func checksumTrailer<Writer>()
        -> HTTPClientRequestChecksumTrailerMiddleware<Writer>
    where
        Input == HTTPClientMiddlewareInput<Writer>,
        Writer: HTTPBodyWriter & ~Copyable & SendableMetatype
    {
        HTTPClientRequestChecksumTrailerMiddleware()
    }
}

/// A wrapping ``HTTPBodyWriter`` that XORs every written byte into a running
/// checksum and emits an `X-Body-Checksum` trailer at conclude time.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct ChecksumRequestWriter<Base: HTTPBodyWriter & ~Copyable>: HTTPBodyWriter, ~Copyable, SendableMetatype
where Base: SendableMetatype {
    public typealias WriteElement = UInt8
    public typealias WriteFailure = Base.WriteFailure
    public typealias Buffer = Base.Buffer

    @usableFromInline
    var underlying: Base
    @usableFromInline
    var checksum: UInt8

    init(wrapping writer: consuming Base) {
        self.underlying = writer
        self.checksum = 0
    }

    public mutating func write<Return: ~Copyable, Failure: Error>(
        _ body: (inout Buffer) async throws(Failure) -> Return
    ) async throws(EitherError<Base.WriteFailure, Failure>) -> Return {
        try await self.underlying.write { buffer throws(Failure) in
            let result = try await body(&buffer)
            buffer._borrowingForEach {
                self.checksum ^= $0
            }
            return result
        }
    }

    public consuming func finish<Failure: Error>(
        body: (inout Buffer) async throws(Failure) -> HTTPFields?
    ) async throws(EitherError<Base.WriteFailure, Failure>) {
        // Move state out of self before the consuming call. Capturing
        // `self.checksum` directly while consuming `self.underlying` triggers
        // a use-after-consume on `self`.
        var checksum = self.checksum
        try await self.underlying.finish { buffer throws(Failure) in
            var trailers = try await body(&buffer) ?? .init()
            buffer._borrowingForEach {
                checksum ^= $0
            }
            trailers.append(.init(name: .init("X-Body-Checksum")!, value: String(checksum, radix: 16)))
            return trailers
        }
    }
}
