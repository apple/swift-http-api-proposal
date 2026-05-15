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
    /// A writer for HTTP response body chunks that implements the ``AsyncWriter`` protocol.
    public struct ResponseBodyAsyncWriter: AsyncWriter {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = any Error
        public typealias Buffer = UniqueArray<UInt8>

        private var writer: NIOAsyncChannelOutboundWriter<HTTPResponsePart>

        init(writer: NIOAsyncChannelOutboundWriter<HTTPResponsePart>) {
            self.writer = writer
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

    public consuming func send<Return>(
        _ response: HTTPResponse,
        body: (consuming sending ResponseBodyAsyncWriter) async throws -> (Return, HTTPFields?)
    ) async throws -> Return {
        precondition(response.status.kind != .informational)
        // TODO: This is a temporary fix that informs clients that this server does not support
        // keep-alive. This server should be updated to eventually support keep-alive.
        var response = response
        response.headerFields[.connection] = "close"
        try await self.writer.write(.head(response))

        let bodyWriter = ResponseBodyAsyncWriter(writer: self.writer)
        let (result, trailers) = try await body(bodyWriter)
        try await self.writer.write(.end(trailers))
        self.writerState.wrapped.withLock { $0.finishedWriting = true }
        return result
    }
}

@available(*, unavailable)
extension NIOHTTPResponseSender: Sendable {}

@available(*, unavailable)
extension NIOHTTPResponseSender.ResponseBodyAsyncWriter: Sendable {}
