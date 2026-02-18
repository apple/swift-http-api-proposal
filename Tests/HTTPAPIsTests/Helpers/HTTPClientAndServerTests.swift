//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP API Proposal project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncAlgorithms
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
    /// A concluding async reader backed by an underlying MPSCAsyncChannel.
    struct AsyncChannelConcludingAsyncReader: ConcludingAsyncReader, ~Copyable, SendableMetatype {
        typealias Underlying = MultiProducerSingleConsumerAsyncChannel<UInt8, any Error>
        typealias FinalElement = HTTPFields?

        var channel: Disconnected<MultiProducerSingleConsumerAsyncChannel<UInt8, any Error>?>
        var trailersChannel: AsyncChannel<HTTPFields?>

        init(
            channel: consuming sending MultiProducerSingleConsumerAsyncChannel<UInt8, any Error>,
            trailersChannel: AsyncChannel<HTTPFields?>
        ) {
            self.channel = Disconnected(value: channel)
            self.trailersChannel = trailersChannel
        }

        consuming func consumeAndConclude<Return, Failure: Error>(
            body: (consuming sending MultiProducerSingleConsumerAsyncChannel<UInt8, any Error>) async throws(Failure) -> Return
        ) async throws(Failure) -> (Return, HTTPFields?) {
            let channel = self.channel.swap(newValue: nil)!
            let result = try await body(channel)
            let trailers = await self.trailersChannel.first { _ in true } ?? nil
            return (result, trailers)
        }
    }

    /// A concluding async writer backed by an underlying MPSCAsyncChannel.Source.
    struct AsyncChannelConcludingAsyncWriter: ConcludingAsyncWriter, ~Copyable, SendableMetatype {
        typealias Underlying = MultiProducerSingleConsumerAsyncChannel<UInt8, any Error>.Source
        typealias FinalElement = HTTPFields?

        var source: Disconnected<MultiProducerSingleConsumerAsyncChannel<UInt8, any Error>.Source?>
        var trailersChannel: AsyncChannel<HTTPFields?>

        init(
            source: consuming sending MultiProducerSingleConsumerAsyncChannel<UInt8, any Error>.Source,
            trailersChannel: AsyncChannel<HTTPFields?>
        ) {
            self.source = Disconnected(value: consume source)
            self.trailersChannel = trailersChannel
        }

        consuming func produceAndConclude<Return>(
            body: (consuming sending MultiProducerSingleConsumerAsyncChannel<UInt8, any Error>.Source) async throws -> (Return, HTTPFields?)
        ) async throws -> Return {
            do {
                let source = self.source.swap(newValue: nil)!
                let (result, trailers) = try await body(source)
                await self.trailersChannel.send(trailers)
                return result
            } catch {
                self.trailersChannel.finish()
                throw error
            }
        }
    }

    // A helper struct to buffer everything belonging to the incoming request
    private struct BufferedRequest: ~Copyable {
        final class Response {
            var response: HTTPResponse
            private var responseReader: AsyncChannelConcludingAsyncReader?

            init(response: HTTPResponse, responseReader: consuming AsyncChannelConcludingAsyncReader) {
                self.response = response
                self.responseReader = consume responseReader
            }

            func takeResponseReader() -> AsyncChannelConcludingAsyncReader {
                self.responseReader.take()!
            }
        }
        var request: HTTPRequest
        var body: Disconnected<HTTPClientRequestBody<AsyncChannelConcludingAsyncWriter.Underlying>??>
        var responseContinuation: CheckedContinuation<Response, any Error>

        init(
            request: HTTPRequest,
            body: consuming sending HTTPClientRequestBody<AsyncChannelConcludingAsyncWriter.Underlying>?,
            responseContinuation: CheckedContinuation<Response, any Error>
        ) {
            self.request = request
            self.body = Disconnected(value: consume body)
            self.responseContinuation = responseContinuation
        }

        mutating func takeBody() -> sending HTTPClientRequestBody<AsyncChannelConcludingAsyncWriter.Underlying>? {
            self.body.swap(newValue: nil)!
        }
    }

    typealias RequestWriter = AsyncChannelConcludingAsyncWriter.Underlying
    typealias ResponseConcludingReader = AsyncChannelConcludingAsyncReader
    typealias RequestConcludingReader = AsyncChannelConcludingAsyncReader
    typealias ResponseConcludingWriter = AsyncChannelConcludingAsyncWriter

    private let requests = Mutex<UniqueArray<BufferedRequest>>(.init())
    private let (stream, continuation): (AsyncStream<Void>, AsyncStream<Void>.Continuation)

    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<AsyncChannelConcludingAsyncWriter.Underlying>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming AsyncChannelConcludingAsyncReader) async throws -> Return
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
        handler: some HTTPServerRequestHandler<AsyncChannelConcludingAsyncReader, AsyncChannelConcludingAsyncWriter>
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
        handler: some HTTPServerRequestHandler<AsyncChannelConcludingAsyncReader, AsyncChannelConcludingAsyncWriter>
    ) async throws {
        try await withThrowingTaskGroup { group in
            let trailersChannel = AsyncChannel<HTTPFields?>()
            var requestChannelAndSource = MultiProducerSingleConsumerAsyncChannel<UInt8, any Error>.makeChannel(
                throwing: (any Error).self,
                backpressureStrategy: .watermark(low: 10, high: 20)
            )
            let requestChannel = requestChannelAndSource.takeChannel()
            let requestSource = requestChannelAndSource.source
            // Needed since we are lacking call-once closures
            var requestWriter: AsyncChannelConcludingAsyncWriter? = AsyncChannelConcludingAsyncWriter(
                source: requestSource,
                trailersChannel: trailersChannel
            )
            let requestReader = AsyncChannelConcludingAsyncReader(
                channel: requestChannel,
                trailersChannel: trailersChannel
            )
            var responseChannelAndSource = MultiProducerSingleConsumerAsyncChannel<UInt8, any Error>.makeChannel(
                throwing: (any Error).self,
                backpressureStrategy: .watermark(low: 10, high: 20)
            )
            let responseChannel = responseChannelAndSource.takeChannel()
            let responseSource = responseChannelAndSource.source
            // Needed since we are lacking call-once closures
            var responseWriter: AsyncChannelConcludingAsyncWriter? = AsyncChannelConcludingAsyncWriter(
                source: responseSource,
                trailersChannel: trailersChannel
            )
            // Needed since we are lacking call-once closures
            var responseReader: AsyncChannelConcludingAsyncReader? = AsyncChannelConcludingAsyncReader(
                channel: responseChannel,
                trailersChannel: trailersChannel
            )

            // Needed since we are lacking call-once closures
            let body = request.takeBody()
            group.addTask {
                try await requestWriter.take()!.produceAndConclude { writer in
                    try await body?.produce(into: writer)
                }
            }

            let responseContinuation = request.responseContinuation
            let responseSender = HTTPResponseSender { response in
                responseContinuation
                    .resume(
                        returning: .init(
                            response: response,
                            // Needed since we are lacking call-once closures
                            responseReader: responseReader.take()!
                        )
                    )
                // Needed since we are lacking call-once closures
                return responseWriter.take()!
            } sendInformational: { _ in
            }

            try await handler
                .handle(
                    request: request.request,
                    requestContext: .init(),
                    requestBodyAndTrailers: requestReader,
                    responseSender: responseSender
                )
        }
    }
}
