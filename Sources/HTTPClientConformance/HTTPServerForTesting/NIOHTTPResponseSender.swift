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

public import BasicContainers
public import HTTPAPIs
public import HTTPTypes
import NIOCore
import NIOHTTPTypes
import Synchronization

/// A NIO-backed HTTP response sender used by the test server.
///
/// ``NIOHTTPResponseSender`` writes the response head, streams the body, and concludes with
/// optional trailing fields, all to a NIO async channel outbound writer. It also supports
/// sending informational (1xx) responses before the final response.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct NIOHTTPResponseSender: HTTPResponseSender, ~Copyable {
    /// A writer for HTTP response body chunks that implements the ``HTTPBodyWriter`` protocol.
    public struct ResponseBodyAsyncWriter: HTTPBodyWriter {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = any Error
        public typealias Buffer = UniqueArray<UInt8>

        private var writer: NIOAsyncChannelOutboundWriter<HTTPResponsePart>
        private var writerState: WriterState

        init(
            writer: NIOAsyncChannelOutboundWriter<HTTPResponsePart>,
            writerState: WriterState
        ) {
            self.writer = writer
            self.writerState = writerState
        }

        public mutating func write<Return: ~Copyable, Failure: Error>(
            _ body: nonisolated(nonsending) (inout UniqueArray<UInt8>) async throws(Failure) -> Return
        ) async throws(EitherError<WriteFailure, Failure>) -> Return {
            var buffer = UniqueArray<UInt8>()
            let result: Return
            do {
                result = try await body(&buffer)
            } catch {
                throw .second(error)
            }

            if buffer.count == 0 {
                return result
            }

            var byteBuffer = ByteBuffer()
            byteBuffer.reserveCapacity(buffer.count)
            unsafe byteBuffer.writeBytes(buffer.span.bytes)

            do {
                try await self.writer.write(.body(byteBuffer))
            } catch {
                throw .first(error)
            }

            return result
        }

        public consuming func finish<Failure: Error>(
            body: nonisolated(nonsending) (inout UniqueArray<UInt8>) async throws(Failure) -> HTTPFields?
        ) async throws(EitherError<WriteFailure, Failure>) {
            var buffer = UniqueArray<UInt8>()
            let trailers: HTTPFields?
            do {
                trailers = try await body(&buffer)
            } catch {
                throw .second(error)
            }

            if buffer.count > 0 {
                var byteBuffer = ByteBuffer()
                byteBuffer.reserveCapacity(buffer.count)
                unsafe byteBuffer.writeBytes(buffer.span.bytes)

                do {
                    try await self.writer.write(.body(byteBuffer))
                } catch {
                    throw .first(error)
                }
            }

            do {
                try await self.writer.write(.end(trailers))
            } catch {
                throw .first(error)
            }
            self.writerState.wrapped.withLock { $0.finishedWriting = true }
        }
    }

    public final class WriterState: Sendable {
        struct Wrapped {
            var finishedWriting: Bool = false
        }

        let wrapped: Mutex<Wrapped>

        public init() {
            self.wrapped = .init(.init())
        }
    }

    public typealias Writer = ResponseBodyAsyncWriter

    private var writer: NIOAsyncChannelOutboundWriter<HTTPResponsePart>
    private var writerState: WriterState

    init(
        writer: NIOAsyncChannelOutboundWriter<HTTPResponsePart>,
        writerState: WriterState
    ) {
        self.writer = writer
        self.writerState = writerState
    }

    public func sendInformational(_ response: HTTPResponse) async throws {
        precondition(response.status.kind == .informational)
        try await self.writer.write(.head(response))
    }

    public consuming func send(_ response: HTTPResponse) async throws -> ResponseBodyAsyncWriter {
        precondition(response.status.kind != .informational)
        // TODO: This is a temporary fix that informs clients that this server does not support
        // keep-alive. This server should be updated to eventually support keep-alive.
        var response = response
        response.headerFields[.connection] = "close"
        try await self.writer.write(.head(response))

        return ResponseBodyAsyncWriter(writer: self.writer, writerState: self.writerState)
    }
}

@available(*, unavailable)
extension NIOHTTPResponseSender: Sendable {}

@available(*, unavailable)
extension NIOHTTPResponseSender.ResponseBodyAsyncWriter: Sendable {}
