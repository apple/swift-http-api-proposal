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

/// A middleware that frames the response body with a fixed prefix and suffix.
///
/// The prefix is written before the user's handler runs, and the suffix is
/// fused with the user's last body chunk and the FIN signal via the wrapping
/// writer's `finish`. Useful as a minimal demonstration of a middleware that
/// needs work both *before* the user's handler writes anything and *after* it
/// declares the body finished.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerResponsePrefixSuffixMiddleware<
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
        HTTPServerResponsePrefixSuffixSender<ResponseSender>
    >

    let prefix: [UInt8]
    let suffix: [UInt8]

    public init(
        prefix: [UInt8],
        suffix: [UInt8],
        readerType: Reader.Type = Reader.self,
        responseSenderType: ResponseSender.Type = ResponseSender.self
    ) {
        self.prefix = prefix
        self.suffix = suffix
    }

    public func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await input.withContents { request, context, reader, responseSender in
            let wrappedSender = HTTPServerResponsePrefixSuffixSender(
                base: responseSender,
                prefix: self.prefix,
                suffix: self.suffix
            )
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
    /// Adds a middleware that frames the response body with a fixed prefix and suffix.
    public func prefixSuffix<Reader, ResponseSender>(
        prefix: [UInt8],
        suffix: [UInt8]
    ) -> HTTPServerResponsePrefixSuffixMiddleware<Reader, ResponseSender>
    where
        Input == HTTPServerMiddlewareInput<Reader, ResponseSender>,
        Reader: HTTPBodyReader & ~Copyable & Escapable,
        ResponseSender: HTTPResponseSender & ~Copyable & Escapable,
        ResponseSender.Writer: ~Copyable & Escapable
    {
        HTTPServerResponsePrefixSuffixMiddleware(prefix: prefix, suffix: suffix)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerResponsePrefixSuffixSender<
    Base: HTTPResponseSender & ~Copyable
>: HTTPResponseSender, ~Copyable
where Base.Writer: ~Copyable & Escapable {
    public typealias Writer = PrefixSuffixWriter

    public struct PrefixSuffixWriter: HTTPBodyWriter, ~Copyable {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = Base.Writer.WriteFailure
        public typealias Buffer = Base.Writer.Buffer

        @usableFromInline
        var underlying: Base.Writer
        @usableFromInline
        let suffix: [UInt8]

        init(wrapping writer: consuming Base.Writer, suffix: [UInt8]) {
            self.underlying = writer
            self.suffix = suffix
        }

        public mutating func write<Return: ~Copyable, Failure: Error>(
            _ body: (inout Buffer) async throws(Failure) -> Return
        ) async throws(EitherError<Base.Writer.WriteFailure, Failure>) -> Return {
            try await self.underlying.write(body)
        }

        public consuming func finish<Failure: Error>(
            body: (inout Buffer) async throws(Failure) -> HTTPFields?
        ) async throws(EitherError<Base.Writer.WriteFailure, Failure>) {
            // Copy `suffix` out before the consuming call. Capturing `self.suffix`
            // directly while consuming `self.underlying` triggers a use-after-
            // consume on `self`.
            let suffix = self.suffix
            // Fuse user body + suffix + trailers into a single underlying
            // `finish` call: the user's body writes its final bytes into the
            // transport buffer, we append the suffix, and return the user's
            // trailers — all in one transport frame.
            // TODO: #11 — `buffer.append(b)` here assumes the underlying
            // buffer grows on demand. If a future writer ships a fixed-capacity
            // buffer, this silently truncates the suffix. Either guard with
            // `freeCapacity` and split across multiple writes, or document the
            // capacity contract on AsyncWriter so we can rely on it.
            try await self.underlying.finish { buffer throws(Failure) -> HTTPFields? in
                let trailers = try await body(&buffer)
                for b in suffix {
                    buffer.append(b)
                }
                return trailers
            }
        }
    }

    private var base: Base
    private let prefix: [UInt8]
    private let suffix: [UInt8]

    init(base: consuming Base, prefix: [UInt8], suffix: [UInt8]) {
        self.base = base
        self.prefix = prefix
        self.suffix = suffix
    }

    public func sendInformational(_ response: HTTPResponse) async throws {
        try await self.base.sendInformational(response)
    }

    public consuming func send(_ response: HTTPResponse) async throws -> PrefixSuffixWriter {
        let prefix = self.prefix
        let suffix = self.suffix
        var writer = try await self.base.send(response)
        // Write the prefix up front, before the user handler sees the writer.
        try await writer.write { buffer in
            buffer.append(copying: prefix)
        }
        return PrefixSuffixWriter(wrapping: writer, suffix: suffix)
    }
}
