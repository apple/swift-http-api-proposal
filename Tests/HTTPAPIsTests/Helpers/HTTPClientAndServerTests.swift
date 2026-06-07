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

import AsyncStreaming
import BasicContainers
import ContainersPreview
import DequeModule
import HTTPAPIs
import HTTPTypes
import Synchronization
import Testing

/// A test client and server.
///
/// This type hooks up a client to a server in-process using
/// ``DuplexAsyncChannel`` for both directions: the client side writes the
/// request body and reads the response body; the server side mirrors that.
@available(anyAppleOS 26.0, *)
final class TestClientAndServer: HTTPClient, HTTPServer {
    struct HTTPRequestContext: HTTPServerCapability.RequestContext {
        var remoteAddress: String?
        var localAddress: String?

        init(remoteAddress: String? = nil, localAddress: String? = nil) {
            self.remoteAddress = remoteAddress
            self.localAddress = localAddress
        }
    }

    struct RequestOptions: HTTPClientCapability.RequestOptions {
        init() {}
    }

    typealias UnderlyingDuplex = DuplexAsyncChannel<UInt8, HTTPFields?, any Error>

    /// A body writer for the test client/server.
    ///
    /// Wraps one side of a ``DuplexAsyncChannel`` and adapts its `EitherError`
    /// write/finish failures to plain `any Error`.
    struct AsyncChannelBodyWriter: CallerAsyncWriter, ~Copyable, SendableMetatype {
        typealias WriteElement = UInt8
        typealias WriteFailure = any Error
        typealias FinalElement = HTTPFields?

        var underlying: UnderlyingDuplex.Writer

        init(underlying: consuming sending UnderlyingDuplex.Writer) {
            self.underlying = underlying
        }

        mutating func write<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
            buffer: inout Buffer
        ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
            try await self.underlying.write(buffer: &buffer)
        }

        consuming func finish<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
            buffer: inout Buffer,
            finalElement: consuming HTTPFields?
        ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
            try await self.underlying.finish(buffer: &buffer, finalElement: finalElement)
        }
    }

    /// A body reader for the test client/server.
    ///
    /// Wraps one side of a ``DuplexAsyncChannel`` and flattens its nested
    /// `EitherError` read failures into the shape this test type publishes.
    struct AsyncChannelBodyReader: AsyncReader, ~Copyable, SendableMetatype {
        typealias ReadElement = UInt8
        typealias ReadFailure = any Error
        typealias Buffer = UniqueDeque<UInt8>
        typealias FinalElement = HTTPFields?

        var underlying: UnderlyingDuplex.Reader

        init(underlying: consuming sending UnderlyingDuplex.Reader) {
            self.underlying = underlying
        }

        mutating func read<Return: ~Copyable, Failure: Error>(
            body: (inout UniqueDeque<UInt8>, consuming HTTPFields??) async throws(Failure) -> Return
        ) async throws(EitherError<any Error, Failure>) -> Return {
            do {
                return try await self.underlying.read(body: body)
            } catch {
                // Flatten the underlying `EitherError<EitherError<any Error, CancellationError>, Failure>`
                // into the `EitherError<any Error, Failure>` shape consumers expect.
                switch error {
                case .first(let readSide):
                    switch readSide {
                    case .first(let inner): throw .first(inner)
                    case .second(let cancel): throw .first(cancel)
                    }
                case .second(let bodyError):
                    throw .second(bodyError)
                }
            }
        }
    }

    /// A response sender backed by a ``DuplexAsyncChannel`` writer.
    struct AsyncChannelResponseSender: HTTPResponseSender, ~Copyable, SendableMetatype {
        typealias Writer = AsyncChannelBodyWriter

        let resumeWith: @Sendable (HTTPResponse, consuming sending AsyncChannelBodyReader) -> Void
        var responseWriter: Disconnected<UnderlyingDuplex.Writer?>
        let responseReader: Disconnected<AsyncChannelBodyReader?>

        init(
            resumeWith: @escaping @Sendable (HTTPResponse, consuming sending AsyncChannelBodyReader) -> Void,
            responseWriter: consuming sending UnderlyingDuplex.Writer,
            responseReader: consuming sending AsyncChannelBodyReader
        ) {
            self.resumeWith = resumeWith
            self.responseWriter = Disconnected(value: consume responseWriter)
            self.responseReader = Disconnected(value: consume responseReader)
        }

        func sendInformational(_ response: HTTPResponse) async throws {
            // No-op
        }

        consuming func send(_ response: HTTPResponse) async throws -> AsyncChannelBodyWriter {
            self.resumeWith(response, self.responseReader.take()!)
            let writer = self.responseWriter.swap(newValue: nil)!
            return AsyncChannelBodyWriter(underlying: writer)
        }
    }

    // A helper struct to buffer everything belonging to the incoming request.
    private struct BufferedRequest: ~Copyable {
        final class Response {
            var response: HTTPResponse
            private var responseReader: AsyncChannelBodyReader?
            /// Signaled by the client when it's finished using the response reader.
            ///
            /// The server awaits this before letting the ``withDuplex`` scope
            /// tear the underlying channel down.
            let clientDone: AsyncStream<Void>.Continuation

            init(
                response: HTTPResponse,
                responseReader: consuming AsyncChannelBodyReader,
                clientDone: AsyncStream<Void>.Continuation
            ) {
                self.response = response
                self.responseReader = consume responseReader
                self.clientDone = clientDone
            }

            func takeResponseReader() -> AsyncChannelBodyReader {
                self.responseReader.take()!
            }
        }
        var request: HTTPRequest
        var body: Disconnected<HTTPClientRequestBody<AsyncChannelBodyWriter>??>
        var responseContinuation: CheckedContinuation<Response, any Error>

        init(
            request: HTTPRequest,
            body: consuming sending HTTPClientRequestBody<AsyncChannelBodyWriter>?,
            responseContinuation: CheckedContinuation<Response, any Error>
        ) {
            self.request = request
            self.body = Disconnected(value: consume body)
            self.responseContinuation = responseContinuation
        }

        mutating func takeBody() -> sending HTTPClientRequestBody<AsyncChannelBodyWriter>? {
            self.body.swap(newValue: nil)!
        }
    }

    typealias RequestContext = HTTPRequestContext
    typealias Writer = AsyncChannelBodyWriter
    typealias Reader = AsyncChannelBodyReader
    typealias ResponseSender = AsyncChannelResponseSender

    private let requests = Mutex<UniqueArray<BufferedRequest>>(.init())
    private let (stream, continuation): (AsyncStream<Void>, AsyncStream<Void>.Continuation)

    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    var defaultRequestOptions: RequestOptions {
        .init()
    }

    func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<AsyncChannelBodyWriter>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming AsyncChannelBodyReader) async throws -> Return
    ) async throws -> Return {
        let response = try await withCheckedThrowingContinuation { continuation in
            self.requests.withLock { requests in
                requests.append(
                    BufferedRequest(
                        request: request,
                        // Needed since we are lacking call-once closures
                        body: body.take(),
                        responseContinuation: continuation
                    )
                )
            }
            self.continuation.yield()
        }

        // Unconditionally signal that we're done with the reader so the
        // server can exit its ``withDuplex`` scope, even if the response
        // handler throws.
        let clientDone = response.clientDone
        defer {
            clientDone.yield()
            clientDone.finish()
        }

        return try await responseHandler(
            response.response,
            // Needed since we are lacking call-once closures
            response.takeResponseReader()
        )
    }

    func serve(
        handler: some HTTPServerRequestHandler<HTTPRequestContext, AsyncChannelBodyReader, AsyncChannelResponseSender>
    ) async throws {
        try await withThrowingDiscardingTaskGroup { group in
            for await _ in self.stream {
                var request: BufferedRequest? = self.requests.withLock { requests in
                    return requests.popLast()!
                }
                group.addTask {
                    try await Self.handleRequest(
                        // Needed since we are lacking call-once closures
                        request: request.take()!,
                        handler: handler
                    )
                }
            }
        }
    }

    private static func handleRequest(
        request: consuming BufferedRequest,
        handler: some HTTPServerRequestHandler<HTTPRequestContext, AsyncChannelBodyReader, AsyncChannelResponseSender>
    ) async throws {
        // Consume the request up front so the duplex body closure doesn't
        // need to capture and re-consume it across scopes.
        let httpRequest = request.request
        let body = request.takeBody()
        let responseContinuation = request.responseContinuation
        let bodySlot = Mutex(
            Disconnected<HTTPClientRequestBody<AsyncChannelBodyWriter>??>(value: body)
        )

        // The signal the server awaits to know the client is finished with
        // the response reader. Until then, the duplex scope must stay open
        // so the reader's underlying storage is still valid.
        let (clientDoneStream, clientDoneCont) = AsyncStream<Void>.makeStream()

        try await UnderlyingDuplex.withDuplex(
            withFinalElement: HTTPFields?.self,
            throwing: (any Error).self,
            backpressureStrategy: .watermark(low: 10, high: 20)
        ) { writerA, readerA, writerB, readerB in
            // Side A is the client: writes the request body, reads the response.
            // Side B is the server: reads the request body, writes the response.
            // Consume each handle into a Sendable slot here so the inner
            // task-group closure can take ownership across the boundary.
            let requestWriterSlot = Mutex(
                Disconnected<AsyncChannelBodyWriter?>(
                    value: Optional(AsyncChannelBodyWriter(underlying: writerA))
                )
            )
            let requestReaderSlot = Mutex(
                Disconnected<AsyncChannelBodyReader?>(
                    value: Optional(AsyncChannelBodyReader(underlying: readerB))
                )
            )
            let responseWriterSlot = Mutex(
                Disconnected<UnderlyingDuplex.Writer?>(value: Optional(writerB))
            )
            let responseReaderSlot = Mutex(
                Disconnected<AsyncChannelBodyReader?>(
                    value: Optional(AsyncChannelBodyReader(underlying: readerA))
                )
            )

            try await withThrowingTaskGroup(of: Void.self) { group in
                let body = bodySlot.withLock { $0.swap(newValue: nil) }!
                group.addTask {
                    let writer = requestWriterSlot.withLock { $0.swap(newValue: nil) }!
                    if let body {
                        try await body.produce(into: writer)
                    } else {
                        // No body: just signal end-of-stream with no trailer.
                        try await writer.finish(trailer: nil)
                    }
                }

                let responseSender = AsyncChannelResponseSender(
                    resumeWith: { response, reader in
                        responseContinuation.resume(
                            returning: .init(
                                response: response,
                                responseReader: reader,
                                clientDone: clientDoneCont
                            )
                        )
                    },
                    responseWriter: responseWriterSlot.withLock { $0.swap(newValue: nil) }!,
                    responseReader: responseReaderSlot.withLock { $0.swap(newValue: nil) }!
                )

                let requestReader = requestReaderSlot.withLock { $0.swap(newValue: nil) }!
                try await handler
                    .handle(
                        request: httpRequest,
                        requestContext: HTTPRequestContext(
                            remoteAddress: "127.0.0.1:54321",
                            localAddress: "0.0.0.0:8080"
                        ),
                        reader: requestReader,
                        responseSender: responseSender
                    )
            }

            // Wait for the client to release the response reader before
            // letting ``withDuplex`` tear down the underlying storage.
            for await _ in clientDoneStream { break }
        }
    }
}
