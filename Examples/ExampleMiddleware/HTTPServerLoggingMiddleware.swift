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
///
/// ``HTTPServerLoggingMiddleware`` wraps the request reader and response writer with logging
/// decorators that output information about the HTTP request path, method, response status,
/// and the number of bytes read from the request body and written to the response body.
/// This middleware is useful for debugging and monitoring HTTP traffic.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPServerLoggingMiddleware<
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
    public typealias NextInput = HTTPServerMiddlewareInput<
        HTTPRequestLoggingConcludingAsyncReader<RequestConcludingAsyncReader>,
        HTTPResponseLoggingConcludingAsyncWriter<ResponseConcludingAsyncWriter>
    >

    let logger: Logger

    /// Creates a new logging middleware.
    ///
    /// - Parameters:
    ///   - requestConcludingAsyncReaderType: The type of the request reader. Defaults to the inferred type.
    ///   - responseConcludingAsyncWriterType: The type of the response writer. Defaults to the inferred type.
    ///   - logger: The logger instance to use for logging HTTP events.
    public init(
        requestConcludingAsyncReaderType: RequestConcludingAsyncReader.Type = RequestConcludingAsyncReader.self,
        responseConcludingAsyncWriterType: ResponseConcludingAsyncWriter.Type = ResponseConcludingAsyncWriter.self,
        logger: Logger
    ) {
        self.logger = logger
    }

    public func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await input.withContents { request, context, requestReader, responseSender in
            self.logger.info("Received request \(request.path ?? "unknown" ) \(request.method.rawValue)")
            defer {
                self.logger.info("Finished request \(request.path ?? "unknown" ) \(request.method.rawValue)")
            }
            let wrappedReader = HTTPRequestLoggingConcludingAsyncReader(
                base: requestReader,
                logger: self.logger
            )

            var maybeSender = Optional(responseSender)
            let requestResponseBox = HTTPServerMiddlewareInput(
                request: request,
                requestContext: context,
                requestReader: wrappedReader,
                responseSender: HTTPResponseSender { [logger] response in
                    if let sender = maybeSender.take() {
                        logger.info("Sending response \(response)")
                        let writer = try await sender.send(response)
                        return HTTPResponseLoggingConcludingAsyncWriter(
                            base: writer,
                            logger: logger
                        )
                    } else {
                        fatalError("Called closure more than once")
                    }
                } sendInformational: { response in
                    self.logger.info("Sending informational response \(response)")
                    try await maybeSender?.sendInformational(response)
                }
            )
            return try await next(requestResponseBox)
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension Middleware where Input: ~Copyable, NextInput: ~Copyable {
    /// Creates logging middleware for HTTP servers.
    ///
    /// This middleware logs all incoming requests and outgoing responses, including the request
    /// path, method, response status, and the number of bytes read and written in the body.
    ///
    /// - Parameter logger: The logger to use for logging requests and responses.
    /// - Returns: A middleware that logs HTTP request and response details.
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
    public func logging<RequestReader, ResponseWriter>(
        logger: Logger
    ) -> HTTPServerLoggingMiddleware<RequestReader, ResponseWriter>
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
        HTTPServerLoggingMiddleware(logger: logger)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPRequestLoggingConcludingAsyncReader<
    Base: ConcludingAsyncReader & ~Copyable
>: ConcludingAsyncReader, ~Copyable
where
    Base.Underlying: ~Copyable,
    Base.Underlying: Escapable,
    Base.Underlying.ReadElement == UInt8,
    Base.FinalElement == HTTPFields?
{
    public typealias Underlying = RequestBodyAsyncReader
    public typealias FinalElement = HTTPFields?

    public struct RequestBodyAsyncReader: AsyncReader, ~Copyable {
        public typealias ReadElement = UInt8
        public typealias ReadFailure = Base.Underlying.ReadFailure
        public typealias Buffer = Base.Underlying.Buffer

        private var underlying: Base.Underlying
        private let logger: Logger

        init(underlying: consuming Base.Underlying, logger: Logger) {
            self.underlying = underlying
            self.logger = logger
        }

        public mutating func read<Return: ~Copyable, Failure>(
            body: (inout Buffer) async throws(Failure) -> Return
        ) async throws(EitherError<Base.Underlying.ReadFailure, Failure>) -> Return {
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

    public consuming func consumeAndConclude<Return, Failure>(
        body: (consuming sending RequestBodyAsyncReader) async throws(Failure) -> Return
    ) async throws(Failure) -> (Return, HTTPTypes.HTTPFields?) {
        let (result, trailers) = try await self.base.consumeAndConclude { [logger] reader async throws(Failure) -> Return in
            let wrappedReader = RequestBodyAsyncReader(
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
public struct HTTPResponseLoggingConcludingAsyncWriter<
    Base: ConcludingAsyncWriter & ~Copyable
>: ConcludingAsyncWriter, ~Copyable
where
    Base.Underlying: ~Copyable,
    Base.Underlying: Escapable,
    Base.Underlying.WriteElement == UInt8,
    Base.FinalElement == HTTPFields?
{
    public typealias Underlying = ResponseBodyAsyncWriter
    public typealias FinalElement = HTTPFields?

    public struct ResponseBodyAsyncWriter: AsyncWriter, ~Copyable {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = Base.Underlying.WriteFailure
        public typealias Buffer = Base.Underlying.Buffer

        private var underlying: Base.Underlying
        private let logger: Logger

        init(underlying: consuming Base.Underlying, logger: Logger) {
            self.underlying = underlying
            self.logger = logger
        }

        public mutating func write<Result: ~Copyable, Failure>(
            _ body: (inout Buffer) async throws(Failure) -> Result
        ) async throws(EitherError<Base.Underlying.WriteFailure, Failure>) -> Result {
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

    public consuming func produceAndConclude<Return>(
        body: (consuming sending ResponseBodyAsyncWriter) async throws -> (Return, HTTPFields?)
    ) async throws -> Return {
        let logger = self.logger
        return try await self.base.produceAndConclude { writer in
            let wrappedAsyncWriter = ResponseBodyAsyncWriter(underlying: writer, logger: logger)
            let (result, trailers) = try await body(wrappedAsyncWriter)

            if let trailers {
                logger.info("Wrote response trailers \(trailers)")
            } else {
                logger.info("Wrote no response trailers")
            }
            return (result, trailers)
        }
    }
}
