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
public import Logging
public import Middleware

/// A middleware that logs HTTP server requests and responses.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerLoggingMiddleware<
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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension Middleware where Input: ~Copyable & ~Escapable, NextInput: ~Copyable & ~Escapable {
    /// Creates logging middleware for HTTP servers.
    public func logging<Reader, ResponseSender>(
        logger: Logger
    ) -> HTTPServerLoggingMiddleware<Reader, ResponseSender>
    where
        Input == HTTPServerMiddlewareInput<Reader, ResponseSender>,
        Reader: HTTPBodyReader & ~Copyable & Escapable,
        ResponseSender: HTTPResponseSender & ~Copyable & Escapable,
        ResponseSender.Writer: ~Copyable & Escapable
    {
        HTTPServerLoggingMiddleware(logger: logger)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct LoggingReader<Base: HTTPBodyReader & ~Copyable>: HTTPBodyReader, ~Copyable {
    public typealias ReadElement = UInt8
    public typealias ReadFailure = Base.ReadFailure
    public typealias Buffer = Base.Buffer

    @usableFromInline
    var underlying: Base
    @usableFromInline
    let logger: Logger

    init(wrapping reader: consuming Base, logger: Logger) {
        self.underlying = reader
        self.logger = logger
    }

    public mutating func read<Return: ~Copyable, Failure>(
        body: (inout Buffer, HTTPFields?) async throws(Failure) -> Return
    ) async throws(EitherError<Base.ReadFailure, Failure>) -> Return {
        let logger = self.logger
        return try await self.underlying.read { (buffer: inout Buffer, trailers: HTTPFields?) async throws(Failure) -> Return in
            logger.info("Received next chunk \(buffer.count)")
            if let trailers {
                logger.info("Received request trailers \(trailers)")
            }
            return try await body(&buffer, trailers)
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPResponseLoggingSender<
    Base: HTTPResponseSender & ~Copyable
>: HTTPResponseSender, ~Copyable
where Base.Writer: ~Copyable & Escapable {
    public typealias Writer = LoggingWriter

    public struct LoggingWriter: HTTPBodyWriter, ~Copyable {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = Base.Writer.WriteFailure
        public typealias Buffer = Base.Writer.Buffer

        @usableFromInline
        var underlying: Base.Writer
        @usableFromInline
        let logger: Logger

        init(wrapping writer: consuming Base.Writer, logger: Logger) {
            self.underlying = writer
            self.logger = logger
        }

        public mutating func write<Result: ~Copyable, Failure>(
            _ body: (inout Buffer) async throws(Failure) -> Result
        ) async throws(EitherError<Base.Writer.WriteFailure, Failure>) -> Result {
            let logger = self.logger
            return try await self.underlying.write { (buffer: inout Buffer) async throws(Failure) -> Result in
                let result = try await body(&buffer)
                logger.info("Wrote response bytes \(buffer.count)")
                return result
            }
        }

        public consuming func finish<Failure: Error>(
            body: (inout Buffer) async throws(Failure) -> HTTPFields?
        ) async throws(EitherError<Base.Writer.WriteFailure, Failure>) {
            // Copy out captures before the consuming call. Capturing `self.logger`
            // directly while consuming `self.underlying` triggers a use-after-
            // consume on `self`.
            let logger = self.logger
            try await self.underlying.finish { buffer throws(Failure) in
                let trailers: HTTPFields?
                do throws(Failure) {
                    trailers = try await body(&buffer)
                } catch {
                    logger.info("Failed to write response bytes")
                    throw error
                }

                if let trailers {
                    logger.info("Wrote response trailers \(trailers)")
                } else {
                    logger.info("Wrote no response trailers")
                }

                return trailers
            }
        }
    }

    private var base: Base
    private let logger: Logger

    init(base: consuming Base, logger: Logger) {
        self.base = base
        self.logger = logger
    }

    public func sendInformational(_ response: HTTPResponse) async throws {
        self.logger.info("Sending informational response \(response)")
        try await self.base.sendInformational(response)
    }

    public consuming func send(_ response: HTTPResponse) async throws -> LoggingWriter {
        self.logger.info("Sending response \(response)")
        let underlying = try await self.base.send(response)
        return LoggingWriter(wrapping: underlying, logger: self.logger)
    }
}
