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
import BasicContainers
public import ContainersPreview
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
@available(anyAppleOS 26.0, *)
public struct NIOHTTPResponseSender: HTTPResponseSender, ~Copyable {
    /// A writer for HTTP response body chunks that implements the ``CallerAsyncWriter`` protocol.
    public struct ResponseBodyWriter: CallerAsyncWriter {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = any Error
        public typealias FinalElement = HTTPFields?

        private var writer: NIOAsyncChannelOutboundWriter<HTTPResponsePart>
        private var writerState: WriterState
        private var byteBuffer: ByteBuffer

        init(
            writer: NIOAsyncChannelOutboundWriter<HTTPResponsePart>,
            writerState: WriterState
        ) {
            self.writer = writer
            self.writerState = writerState
            self.byteBuffer = ByteBuffer()
            self.byteBuffer.reserveCapacity(1 << 14)
        }

        public mutating func write<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
            buffer: inout Buffer
        ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
            guard buffer.count > 0 else { return }
            self.byteBuffer.clear()
            var consumer = buffer.consumeAll()
            while true {
                let span = consumer.drainNext()
                if span.isEmpty { break }
                unsafe self.byteBuffer.writeBytes(span.span.bytes)
            }
            try await self.writer.write(.body(self.byteBuffer))
        }

        public consuming func finish<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
            buffer: inout Buffer,
            finalElement: consuming HTTPFields?
        ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
            if buffer.count > 0 {
                self.byteBuffer.clear()
                var consumer = buffer.consumeAll()
                while true {
                    let span = consumer.drainNext()
                    if span.isEmpty { break }
                    unsafe self.byteBuffer.writeBytes(span.span.bytes)
                }
                try await self.writer.write(.body(self.byteBuffer))
            }
            try await self.writer.write(.end(finalElement))
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

    public typealias Writer = ResponseBodyWriter

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

    public consuming func send(_ response: HTTPResponse) async throws -> ResponseBodyWriter {
        precondition(response.status.kind != .informational)
        // TODO: This is a temporary fix that informs clients that this server does not support
        // keep-alive. This server should be updated to eventually support keep-alive.
        var response = response
        response.headerFields[.connection] = "close"
        try await self.writer.write(.head(response))

        return ResponseBodyWriter(writer: self.writer, writerState: self.writerState)
    }
}

@available(*, unavailable)
extension NIOHTTPResponseSender: Sendable {}

@available(*, unavailable)
extension NIOHTTPResponseSender.ResponseBodyWriter: Sendable {}
