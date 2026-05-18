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

    /// A request receiver backed by an MPSCAsyncChannel — used as request receiver on the server side.
    struct AsyncChannelRequestReceiver: HTTPRequestReceiver, ~Copyable, SendableMetatype {
        typealias Reader = UnderlyingChannel

        var channel: Disconnected<UnderlyingChannel?>
        var trailersChannel: AsyncChannel<HTTPFields?>

        init(
            channel: consuming sending UnderlyingChannel,
            trailersChannel: AsyncChannel<HTTPFields?>
        ) {
            self.channel = Disconnected(value: channel)
            self.trailersChannel = trailersChannel
        }

        consuming func receive<Return, Failure: Error>(
            body: (consuming sending UnderlyingChannel) async throws(Failure) -> Return
        ) async throws(Failure) -> (Return, HTTPFields?) {
            let channel = self.channel.swap(newValue: nil)!
            let result = try await body(channel)
            let trailers = await self.trailersChannel.first { _ in true } ?? nil
            return (result, trailers)
        }
    }

    /// A response receiver backed by an MPSCAsyncChannel — used as response receiver on the client side.
    struct AsyncChannelResponseReceiver: HTTPResponseReceiver, ~Copyable, SendableMetatype {
        typealias Reader = UnderlyingChannel

        var channel: Disconnected<UnderlyingChannel?>
        var trailersChannel: AsyncChannel<HTTPFields?>

        init(
            channel: consuming sending UnderlyingChannel,
            trailersChannel: AsyncChannel<HTTPFields?>
        ) {
            self.channel = Disconnected(value: channel)
            self.trailersChannel = trailersChannel
        }

        consuming func receive<Return, Failure: Error>(
            body: (consuming sending UnderlyingChannel) async throws(Failure) -> Return
        ) async throws(Failure) -> (Return, HTTPFields?) {
            let channel = self.channel.swap(newValue: nil)!
            let result = try await body(channel)
            let trailers = await self.trailersChannel.first { _ in true } ?? nil
            return (result, trailers)
        }
    }

    /// A request sender backed by an MPSCAsyncChannel.Source.
    struct AsyncChannelRequestSender: HTTPRequestSender, ~Copyable, SendableMetatype {
        typealias Writer = UnderlyingSource

        var source: Disconnected<UnderlyingSource?>
        var trailersChannel: AsyncChannel<HTTPFields?>

        init(
            source: consuming sending UnderlyingSource,
            trailersChannel: AsyncChannel<HTTPFields?>
        ) {
            self.source = Disconnected(value: consume source)
            self.trailersChannel = trailersChannel
        }

        consuming func send<Return>(
            body: (consuming sending UnderlyingSource) async throws -> (Return, HTTPFields?)
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

    /// A response sender backed by an MPSCAsyncChannel.Source.
    struct AsyncChannelResponseSender: HTTPResponseSender, ~Copyable, SendableMetatype {
        typealias Writer = UnderlyingSource

        let resumeWith: @Sendable (HTTPResponse, consuming sending AsyncChannelResponseReceiver) -> Void
        var source: Disconnected<UnderlyingSource?>
        let responseReceiver: Disconnected<AsyncChannelResponseReceiver?>
        var trailersChannel: AsyncChannel<HTTPFields?>

        init(
            resumeWith: @escaping @Sendable (HTTPResponse, consuming sending AsyncChannelResponseReceiver) -> Void,
            source: consuming sending UnderlyingSource,
            responseReceiver: consuming sending AsyncChannelResponseReceiver,
            trailersChannel: AsyncChannel<HTTPFields?>
        ) {
            self.resumeWith = resumeWith
            self.source = Disconnected(value: consume source)
            self.responseReceiver = Disconnected(value: consume responseReceiver)
            self.trailersChannel = trailersChannel
        }

        func sendInformational(_ response: HTTPResponse) async throws {
            // No-op
        }

        consuming func send<Return>(
            _ response: HTTPResponse,
            body: (consuming sending UnderlyingSource) async throws -> (Return, HTTPFields?)
        ) async throws -> Return {
            self.resumeWith(response, self.responseReceiver.take()!)
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
            private var responseReceiver: AsyncChannelResponseReceiver?

            init(response: HTTPResponse, responseReceiver: consuming AsyncChannelResponseReceiver) {
                self.response = response
                self.responseReceiver = consume responseReceiver
            }

            func takeResponseReceiver() -> AsyncChannelResponseReceiver {
                self.responseReceiver.take()!
            }
        }
        var request: HTTPRequest
        var body: Disconnected<HTTPClientRequestBody<AsyncChannelRequestSender>??>
        var responseContinuation: CheckedContinuation<Response, any Error>

        init(
            request: HTTPRequest,
            body: consuming sending HTTPClientRequestBody<AsyncChannelRequestSender>?,
            responseContinuation: CheckedContinuation<Response, any Error>
        ) {
            self.request = request
            self.body = Disconnected(value: consume body)
            self.responseContinuation = responseContinuation
        }

        mutating func takeBody() -> sending HTTPClientRequestBody<AsyncChannelRequestSender>? {
            self.body.swap(newValue: nil)!
        }
    }

    typealias RequestSender = AsyncChannelRequestSender
    typealias ResponseReceiver = AsyncChannelResponseReceiver
    typealias RequestReceiver = AsyncChannelRequestReceiver
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
        body: consuming HTTPClientRequestBody<AsyncChannelRequestSender>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming AsyncChannelResponseReceiver) async throws -> Return
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
            response.takeResponseReceiver()
        )
    }

    func serve(
        handler: some HTTPServerRequestHandler<AsyncChannelRequestReceiver, AsyncChannelResponseSender>
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
        handler: some HTTPServerRequestHandler<AsyncChannelRequestReceiver, AsyncChannelResponseSender>
    ) async throws {
        try await withThrowingTaskGroup { group in
            let trailersChannel = AsyncChannel<HTTPFields?>()
            var requestChannelAndSource = UnderlyingChannel.makeChannel(
                throwing: (any Error).self,
                backpressureStrategy: .watermark(low: 10, high: 20)
            )
            let requestChannel = requestChannelAndSource.takeChannel()
            let requestSource = requestChannelAndSource.source
            // Needed since we are lacking call-once closures
            var requestSender: AsyncChannelRequestSender? = AsyncChannelRequestSender(
                source: requestSource,
                trailersChannel: trailersChannel
            )
            let requestReceiver = AsyncChannelRequestReceiver(
                channel: requestChannel,
                trailersChannel: trailersChannel
            )
            var responseChannelAndSource = UnderlyingChannel.makeChannel(
                throwing: (any Error).self,
                backpressureStrategy: .watermark(low: 10, high: 20)
            )
            let responseChannel = responseChannelAndSource.takeChannel()
            let responseSource = responseChannelAndSource.source
            let responseReceiver: AsyncChannelResponseReceiver = AsyncChannelResponseReceiver(
                channel: responseChannel,
                trailersChannel: trailersChannel
            )

            // Needed since we are lacking call-once closures
            let body = request.takeBody()
            group.addTask {
                if let body {
                    try await body.produce(into: requestSender.take()!)
                } else {
                    // No body: just signal end-of-stream with no trailers.
                    try await requestSender.take()!.send(trailers: nil)
                }
            }

            let responseContinuation = request.responseContinuation
            let responseSender = AsyncChannelResponseSender(
                resumeWith: { response, receiver in
                    responseContinuation.resume(
                        returning: .init(response: response, responseReceiver: receiver)
                    )
                },
                source: responseSource,
                responseReceiver: responseReceiver,
                trailersChannel: trailersChannel
            )

            try await handler
                .handle(
                    request: request.request,
                    requestContext: .init(),
                    requestReceiver: requestReceiver,
                    responseSender: responseSender
                )
        }
    }
}
