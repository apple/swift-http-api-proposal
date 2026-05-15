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

public import AsyncAlgorithms  // TODO: This public import is only needed to work around a compiler assertion which is fixed by https://github.com/swiftlang/swift/pull/88829
import AsyncStreaming
import BasicContainers
import HTTPAPIs
import HTTPTypes
import Synchronization
import Testing

/// A test client and server.
///
/// This type hooks up a client to a server in-process.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
final class TestClientAndServer: HTTPClient, HTTPServer {
    struct RequestOptions: HTTPClientCapability.RequestOptions {
        init() {}
    }

    typealias UnderlyingChannel = MultiProducerSingleConsumerAsyncChannel<UInt8, any Error>
    typealias UnderlyingSource = UnderlyingChannel.Source

    /// A body writer for the test client/server. Wraps an MPSC source and a
    /// trailers side-channel so trailers and end-of-body flow together.
    struct AsyncChannelBodyWriter: HTTPBodyWriter, ~Copyable, SendableMetatype {
        typealias WriteElement = UInt8
        typealias WriteFailure = any Error
        typealias Buffer = UniqueArray<UInt8>

        var source: UnderlyingSource
        var trailersChannel: AsyncChannel<HTTPFields?>

        init(source: consuming UnderlyingSource, trailersChannel: AsyncChannel<HTTPFields?>) {
            self.source = source
            self.trailersChannel = trailersChannel
        }

        mutating func write<Return: ~Copyable, F: Error>(
            _ body: (inout UniqueArray<UInt8>) async throws(F) -> Return
        ) async throws(EitherError<any Error, F>) -> Return {
            try await self.source.write(body)
        }

        consuming func finish<Failure: Error>(
            body: (inout UniqueArray<UInt8>) async throws(Failure) -> HTTPFields?
        ) async throws(EitherError<any Error, Failure>) {
            var buffer = UniqueArray<UInt8>()
            let trailers: HTTPFields?
            do {
                trailers = try await body(&buffer)
            } catch {
                throw .second(error)
            }
            var consumer = buffer.consumeAll()
            while let element = consumer.next() {
                do {
                    try await self.source.send(element)
                } catch {
                    throw .first(error)
                }
            }
            self.source.finish()
            await self.trailersChannel.send(trailers)
        }
    }

    /// A body reader for the test client/server. Wraps an MPSC channel and a
    /// trailers side-channel so trailers ride on the read that emits the last
    /// chunk.
    struct AsyncChannelBodyReader: HTTPBodyReader, ~Copyable, SendableMetatype {
        typealias ReadElement = UInt8
        typealias ReadFailure = any Error
        typealias Buffer = UniqueArray<UInt8>

        var channel: UnderlyingChannel
        var trailersChannel: AsyncChannel<HTTPFields?>
        var trailersDelivered: Bool = false

        init(channel: consuming UnderlyingChannel, trailersChannel: AsyncChannel<HTTPFields?>) {
            self.channel = channel
            self.trailersChannel = trailersChannel
        }

        mutating func read<Return: ~Copyable, Failure: Error>(
            body: (inout UniqueArray<UInt8>, HTTPFields?) async throws(Failure) -> Return
        ) async throws(EitherError<any Error, Failure>) -> Return {
            var buffer = UniqueArray<UInt8>()
            var trailers: HTTPFields? = nil

            if !self.trailersDelivered {
                let element: UInt8?
                do {
                    element = try await self.channel.next()
                } catch {
                    throw .first(error)
                }

                if let element {
                    buffer.append(element)
                } else {
                    self.trailersDelivered = true
                    let received = await self.trailersChannel.first { _ in true } ?? nil
                    trailers = received ?? HTTPFields()
                }
            }

            do {
                return try await body(&buffer, trailers)
            } catch {
                throw .second(error)
            }
        }
    }

    /// A response sender backed by an MPSCAsyncChannel.Source.
    struct AsyncChannelResponseSender: HTTPResponseSender, ~Copyable, SendableMetatype {
        typealias Writer = AsyncChannelBodyWriter

        let resumeWith: @Sendable (HTTPResponse, consuming sending AsyncChannelBodyReader) -> Void
        var source: Disconnected<UnderlyingSource?>
        let responseReader: Disconnected<AsyncChannelBodyReader?>
        var trailersChannel: AsyncChannel<HTTPFields?>

        init(
            resumeWith: @escaping @Sendable (HTTPResponse, consuming sending AsyncChannelBodyReader) -> Void,
            source: consuming sending UnderlyingSource,
            responseReader: consuming sending AsyncChannelBodyReader,
            trailersChannel: AsyncChannel<HTTPFields?>
        ) {
            self.resumeWith = resumeWith
            self.source = Disconnected(value: consume source)
            self.responseReader = Disconnected(value: consume responseReader)
            self.trailersChannel = trailersChannel
        }

        func sendInformational(_ response: HTTPResponse) async throws {
            // No-op
        }

        consuming func send(_ response: HTTPResponse) async throws -> AsyncChannelBodyWriter {
            self.resumeWith(response, self.responseReader.take()!)
            let source = self.source.swap(newValue: nil)!
            return AsyncChannelBodyWriter(source: source, trailersChannel: self.trailersChannel)
        }
    }

    // A helper struct to buffer everything belonging to the incoming request
    private struct BufferedRequest: ~Copyable {
        final class Response {
            var response: HTTPResponse
            private var responseReader: AsyncChannelBodyReader?

            init(response: HTTPResponse, responseReader: consuming AsyncChannelBodyReader) {
                self.response = response
                self.responseReader = consume responseReader
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

        return try await responseHandler(
            response.response,
            // Needed since we are lacking call-once closures
            response.takeResponseReader()
        )
    }

    func serve(
        handler: some HTTPServerRequestHandler<AsyncChannelBodyReader, AsyncChannelResponseSender>
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
        handler: some HTTPServerRequestHandler<AsyncChannelBodyReader, AsyncChannelResponseSender>
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            let trailersChannel = AsyncChannel<HTTPFields?>()
            var requestChannelAndSource = UnderlyingChannel.makeChannel(
                throwing: (any Error).self,
                backpressureStrategy: .watermark(low: 10, high: 20)
            )
            let requestChannel = requestChannelAndSource.takeChannel()
            let requestSource = requestChannelAndSource.source
            // Needed since we are lacking call-once closures
            let requestWriterSlot = Mutex(
                Disconnected<AsyncChannelBodyWriter?>(
                    value: Optional(
                        AsyncChannelBodyWriter(
                            source: requestSource,
                            trailersChannel: trailersChannel
                        )
                    )
                )
            )
            let requestReader = AsyncChannelBodyReader(
                channel: requestChannel,
                trailersChannel: trailersChannel
            )
            var responseChannelAndSource = UnderlyingChannel.makeChannel(
                throwing: (any Error).self,
                backpressureStrategy: .watermark(low: 10, high: 20)
            )
            let responseChannel = responseChannelAndSource.takeChannel()
            let responseSource = responseChannelAndSource.source
            let responseReader = AsyncChannelBodyReader(
                channel: responseChannel,
                trailersChannel: trailersChannel
            )

            // Needed since we are lacking call-once closures
            let body = request.takeBody()
            group.addTask {
                let writer = requestWriterSlot.withLock { $0.swap(newValue: nil) }!
                if let body {
                    try await body.produce(into: writer)
                } else {
                    // No body: just signal end-of-stream with no trailers.
                    try await writer.finish(trailers: nil)
                }
            }

            let responseContinuation = request.responseContinuation
            let responseSender = AsyncChannelResponseSender(
                resumeWith: { response, reader in
                    responseContinuation.resume(
                        returning: .init(response: response, responseReader: reader)
                    )
                },
                source: responseSource,
                responseReader: responseReader,
                trailersChannel: trailersChannel
            )

            try await handler
                .handle(
                    request: request.request,
                    requestContext: .init(),
                    reader: requestReader,
                    responseSender: responseSender
                )
        }
    }
}
