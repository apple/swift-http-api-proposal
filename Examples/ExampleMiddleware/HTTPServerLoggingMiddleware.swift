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
public import Logging
public import Middleware

/// A middleware that logs HTTP server requests and responses.
@available(anyAppleOS 26.0, *)
public struct HTTPServerLoggingMiddleware<
    RequestContext: HTTPServerCapability.RequestContext & ~Copyable,
    Reader: AsyncReader & ~Copyable,
    ResponseSender: HTTPResponseSender & ~Copyable
>: Middleware
where
    Reader.ReadElement == UInt8,
    Reader.FinalElement == HTTPFields?,
    ResponseSender.Writer: ~Copyable
{
    public typealias Input = HTTPServerMiddlewareInput<RequestContext, Reader, ResponseSender>
    public typealias NextInput = HTTPServerMiddlewareInput<
        RequestContext,
        LoggingReader<Reader>,
        HTTPResponseLoggingSender<ResponseSender>
    >

    let logger: Logger

    public init(
        readerType: Reader.Type = Reader.self,
        responseSenderType: ResponseSender.Type = ResponseSender.self,
        logger: Logger
    ) {
        self.logger = logger
    }

    public func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await input.withContents { request, context, reader, responseSender in
            self.logger.info("Received request \(request.path ?? "unknown" ) \(request.method.rawValue)")
            defer {
                self.logger.info("Finished request \(request.path ?? "unknown" ) \(request.method.rawValue)")
            }
            let wrappedReader = LoggingReader(wrapping: reader, logger: self.logger)
            let wrappedSender = HTTPResponseLoggingSender(
                base: responseSender,
                logger: self.logger
            )
            let requestResponseBox = HTTPServerMiddlewareInput(
                request: request,
                requestContext: context,
                reader: wrappedReader,
                responseSender: wrappedSender
            )
            return try await next(requestResponseBox)
        }
    }
}

@available(anyAppleOS 26.0, *)
extension Middleware where Input: ~Copyable & ~Escapable, NextInput: ~Copyable & ~Escapable {
    /// Creates logging middleware for HTTP servers.
    public func logging<RequestContext, Reader, ResponseSender>(
        logger: Logger
    ) -> HTTPServerLoggingMiddleware<RequestContext, Reader, ResponseSender>
    where
        Input == HTTPServerMiddlewareInput<RequestContext, Reader, ResponseSender>,
        RequestContext: HTTPServerCapability.RequestContext & ~Copyable,
        Reader: AsyncReader & ~Copyable,
        Reader.ReadElement == UInt8,
        Reader.FinalElement == HTTPFields?,
        ResponseSender: HTTPResponseSender & ~Copyable,
        ResponseSender.Writer: ~Copyable
    {
        HTTPServerLoggingMiddleware(logger: logger)
    }
}

@available(anyAppleOS 26.0, *)
public struct LoggingReader<Base: AsyncReader & ~Copyable>: AsyncReader, ~Copyable
where Base.ReadElement == UInt8, Base.FinalElement == HTTPFields? {
    public typealias ReadElement = UInt8
    public typealias ReadFailure = Base.ReadFailure
    public typealias Buffer = Base.Buffer
    public typealias FinalElement = HTTPFields?

    @usableFromInline
    var underlying: Base
    @usableFromInline
    let logger: Logger

    init(wrapping reader: consuming Base, logger: Logger) {
        self.underlying = reader
        self.logger = logger
    }

    public mutating func read<Return: ~Copyable, Failure>(
        body: (inout Buffer, consuming HTTPFields??) async throws(Failure) -> Return
    ) async throws(EitherError<Base.ReadFailure, Failure>) -> Return {
        let logger = self.logger
        return try await self.underlying.read {
            (buffer: inout Buffer, finalElement: consuming HTTPFields??) async throws(Failure) -> Return in
            logger.info("Received next chunk \(buffer.count)")
            if let trailers = finalElement, let actual = trailers {
                logger.info("Received request trailers \(actual)")
            }
            return try await body(&buffer, finalElement)
        }
    }
}

@available(anyAppleOS 26.0, *)
public struct HTTPResponseLoggingSender<
    Base: HTTPResponseSender & ~Copyable
>: HTTPResponseSender, ~Copyable
where Base.Writer: ~Copyable {

    public struct LoggingWriter: CallerAsyncWriter, ~Copyable {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = Base.Writer.WriteFailure
        public typealias FinalElement = HTTPFields?

        @usableFromInline
        var underlying: Base.Writer
        @usableFromInline
        let logger: Logger

        init(wrapping writer: consuming Base.Writer, logger: Logger) {
            self.underlying = writer
            self.logger = logger
        }

        public mutating func write<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
            buffer: inout Buffer
        ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
            self.logger.info("Wrote response bytes \(buffer.count)")
            try await self.underlying.write(buffer: &buffer)
        }

        public consuming func finish<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
            buffer: inout Buffer,
            finalElement: consuming HTTPFields?
        ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
            // Copy out captures before the consuming call. Capturing `self.logger`
            // directly while consuming `self.underlying` triggers a use-after-
            // consume on `self`.
            let logger = self.logger
            if let finalElement {
                logger.info("Wrote response trailers \(finalElement)")
            } else {
                logger.info("Wrote no response trailers")
            }
            try await self.underlying.finish(buffer: &buffer, finalElement: finalElement)
        }
    }

    public typealias Writer = LoggingWriter

    private var base: Base
    private let logger: Logger

    init(base: consuming Base, logger: Logger) {
        self.base = base
        self.logger = logger
    }

    public mutating func sendInformational(_ response: HTTPResponse) async throws {
        self.logger.info("Sending informational response \(response)")
        try await self.base.sendInformational(response)
    }

    public consuming func send(_ response: HTTPResponse) async throws -> LoggingWriter {
        self.logger.info("Sending response \(response)")
        let underlying = try await self.base.send(response)
        return LoggingWriter(wrapping: underlying, logger: self.logger)
    }
}
