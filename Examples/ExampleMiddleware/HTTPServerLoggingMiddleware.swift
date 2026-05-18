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
    RequestReceiver: HTTPRequestReceiver & ~Copyable,
    ResponseSender: HTTPResponseSender & ~Copyable
>: Middleware
where
    RequestReceiver: ~Copyable & Escapable,
    RequestReceiver.Reader: ~Copyable & Escapable,
    ResponseSender: ~Copyable & Escapable,
    ResponseSender.Writer: ~Copyable & Escapable
{
    public typealias Input = HTTPServerMiddlewareInput<RequestReceiver, ResponseSender>
    public typealias NextInput = HTTPServerMiddlewareInput<
        HTTPRequestLoggingReceiver<RequestReceiver>,
        HTTPResponseLoggingSender<ResponseSender>
    >

    let logger: Logger

    public init(
        requestReceiverType: RequestReceiver.Type = RequestReceiver.self,
        responseSenderType: ResponseSender.Type = ResponseSender.self,
        logger: Logger
    ) {
        self.logger = logger
    }

    public func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await input.withContents { request, context, requestReceiver, responseSender in
            self.logger.info("Received request \(request.path ?? "unknown" ) \(request.method.rawValue)")
            defer {
                self.logger.info("Finished request \(request.path ?? "unknown" ) \(request.method.rawValue)")
            }
            let wrappedReceiver = HTTPRequestLoggingReceiver(
                base: requestReceiver,
                logger: self.logger
            )
            let wrappedSender = HTTPResponseLoggingSender(
                base: responseSender,
                logger: self.logger
            )
            let requestResponseBox = HTTPServerMiddlewareInput(
                request: request,
                requestContext: context,
                requestReceiver: wrappedReceiver,
                responseSender: wrappedSender
            )
            return try await next(requestResponseBox)
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension Middleware where Input: ~Copyable, NextInput: ~Copyable {
    /// Creates logging middleware for HTTP servers.
    public func logging<RequestReceiver, ResponseSender>(
        logger: Logger
    ) -> HTTPServerLoggingMiddleware<RequestReceiver, ResponseSender>
    where
        Input == HTTPServerMiddlewareInput<RequestReceiver, ResponseSender>,
        RequestReceiver: HTTPRequestReceiver & ~Copyable & Escapable,
        RequestReceiver.Reader: ~Copyable & Escapable,
        ResponseSender: HTTPResponseSender & ~Copyable & Escapable,
        ResponseSender.Writer: ~Copyable & Escapable
    {
        HTTPServerLoggingMiddleware(logger: logger)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPRequestLoggingReceiver<
    Base: HTTPRequestReceiver & ~Copyable
>: HTTPRequestReceiver, ~Copyable
where Base.Reader: ~Copyable & Escapable {
    public typealias Reader = LoggingReader

    public struct LoggingReader: AsyncReader, ~Copyable {
        public typealias ReadElement = UInt8
        public typealias ReadFailure = Base.Reader.ReadFailure
        public typealias Buffer = Base.Reader.Buffer

        private var underlying: Base.Reader
        private let logger: Logger

        init(underlying: consuming Base.Reader, logger: Logger) {
            self.underlying = underlying
            self.logger = logger
        }

        public mutating func read<Return: ~Copyable, Failure>(
            body: (inout Buffer) async throws(Failure) -> Return
        ) async throws(EitherError<Base.Reader.ReadFailure, Failure>) -> Return {
            let logger = self.logger
            return try await self.underlying.read { (buffer: inout Buffer) async throws(Failure) -> Return in
                logger.info("Received next chunk \(buffer.count)")
                return try await body(&buffer)
            }
        }
    }

    private var base: Base
    private let logger: Logger

    init(base: consuming Base, logger: Logger) {
        self.base = base
        self.logger = logger
    }

    public consuming func receive<Return, Failure: Error>(
        body: (consuming sending LoggingReader) async throws(Failure) -> Return
    ) async throws(Failure) -> (Return, HTTPFields?) {
        let (result, trailers) = try await self.base.receive { [logger] reader async throws(Failure) -> Return in
            let wrappedReader = LoggingReader(
                underlying: reader,
                logger: logger
            )
            return try await body(wrappedReader)
        }

        if let trailers {
            self.logger.info("Received request trailers \(trailers)")
        } else {
            self.logger.info("Received no request trailers")
        }

        return (result, trailers)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPResponseLoggingSender<
    Base: HTTPResponseSender & ~Copyable
>: HTTPResponseSender, ~Copyable
where Base.Writer: ~Copyable & Escapable {
    public typealias Writer = LoggingWriter

    public struct LoggingWriter: AsyncWriter, ~Copyable {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = Base.Writer.WriteFailure
        public typealias Buffer = Base.Writer.Buffer

        private var underlying: Base.Writer
        private let logger: Logger

        init(underlying: consuming Base.Writer, logger: Logger) {
            self.underlying = underlying
            self.logger = logger
        }

        public mutating func write<Result: ~Copyable, Failure>(
            _ body: (inout Buffer) async throws(Failure) -> Result
        ) async throws(EitherError<Base.Writer.WriteFailure, Failure>) -> Result {
            return try await self.underlying.write { (buffer: inout Buffer) async throws(Failure) -> Result in
                let result = try await body(&buffer)
                self.logger.info("Wrote response bytes \(buffer.count)")
                return result
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

    public consuming func send<Return>(
        _ response: HTTPResponse,
        body: (consuming sending LoggingWriter) async throws -> (Return, HTTPFields?)
    ) async throws -> Return {
        self.logger.info("Sending response \(response)")
        let logger = self.logger
        return try await self.base.send(response) { writer in
            let wrappedWriter = LoggingWriter(underlying: writer, logger: logger)
            let (result, trailers) = try await body(wrappedWriter)

            if let trailers {
                logger.info("Wrote response trailers \(trailers)")
            } else {
                logger.info("Wrote no response trailers")
            }
            return (result, trailers)
        }
    }
}
