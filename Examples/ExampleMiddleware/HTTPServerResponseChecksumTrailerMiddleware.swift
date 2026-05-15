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

/// A middleware that observes all response body bytes and appends a checksum
/// (XOR of all bytes) as the `X-Body-Checksum` trailer.
///
/// This demonstrates a wrapping writer middleware that intercepts every write
/// to update internal state, then injects work into the body's `finish` step
/// so the trailer is fused with the final body chunk and the FIN signal.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerResponseChecksumTrailerMiddleware<
    Reader: HTTPBodyReader & ~Copyable,
    ResponseSender: HTTPResponseSender & ~Copyable
>: Middleware
where
    Reader: ~Copyable & Escapable,
    ResponseSender: ~Copyable & Escapable,
    ResponseSender.Writer: ~Copyable & Escapable
{
    public typealias Input = HTTPServerMiddlewareInput<Reader, ResponseSender>
    public typealias NextInput = HTTPServerMiddlewareInput<
        Reader,
        HTTPServerResponseChecksumTrailerSender<ResponseSender>
    >

    public init(
        readerType: Reader.Type = Reader.self,
        responseSenderType: ResponseSender.Type = ResponseSender.self
    ) {}

    public func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await input.withContents { request, context, reader, responseSender in
            let wrappedSender = HTTPServerResponseChecksumTrailerSender(base: responseSender)
            return try await next(
                HTTPServerMiddlewareInput(
                    request: request,
                    requestContext: context,
                    reader: reader,
                    responseSender: wrappedSender
                )
            )
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension Middleware where Input: ~Copyable & ~Escapable, NextInput: ~Copyable & ~Escapable {
    /// Adds a middleware that emits an `X-Body-Checksum` trailer covering the response body.
    public func checksumTrailer<Reader, ResponseSender>()
        -> HTTPServerResponseChecksumTrailerMiddleware<Reader, ResponseSender>
    where
        Input == HTTPServerMiddlewareInput<Reader, ResponseSender>,
        Reader: HTTPBodyReader & ~Copyable & Escapable,
        ResponseSender: HTTPResponseSender & ~Copyable & Escapable,
        ResponseSender.Writer: ~Copyable & Escapable
    {
        HTTPServerResponseChecksumTrailerMiddleware()
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerResponseChecksumTrailerSender<
    Base: HTTPResponseSender & ~Copyable
>: HTTPResponseSender, ~Copyable
where Base.Writer: ~Copyable {
    public typealias Writer = ChecksumWriter

    public struct ChecksumWriter: HTTPBodyWriter, ~Copyable {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = Base.Writer.WriteFailure
        public typealias Buffer = Base.Writer.Buffer

        @usableFromInline
        var underlying: Base.Writer
        @usableFromInline
        var checksum: UInt8

        init(wrapping writer: consuming Base.Writer) {
            self.underlying = writer
            self.checksum = 0
        }

        public mutating func write<Return: ~Copyable, Failure: Error>(
            _ body: (inout Buffer) async throws(Failure) -> Return
        ) async throws(EitherError<Base.Writer.WriteFailure, Failure>) -> Return {
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
        ) async throws(EitherError<Base.Writer.WriteFailure, Failure>) {
            // Move state out of self before the consuming call. Capturing
            // `self.checksum` directly while consuming `self.underlying`
            // triggers a use-after-consume on `self`.
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

    private var base: Base

    init(base: consuming Base) {
        self.base = base
    }

    public func sendInformational(_ response: HTTPResponse) async throws {
        try await self.base.sendInformational(response)
    }

    public consuming func send(_ response: HTTPResponse) async throws -> ChecksumWriter {
        let underlying = try await self.base.send(response)
        return ChecksumWriter(wrapping: underlying)
    }
}
