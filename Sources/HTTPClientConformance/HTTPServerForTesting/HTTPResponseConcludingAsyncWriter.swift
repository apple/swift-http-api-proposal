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

public import AsyncStreaming
import BasicContainers
public import HTTPTypes
import NIOCore
import NIOHTTPTypes
import Synchronization

/// A specialized writer for HTTP response bodies and trailers that manages the writing process
/// and the final trailer fields.
///
/// ``HTTPResponseConcludingAsyncWriter`` enables writing response body chunks incrementally
/// and concluding with optional HTTP trailer fields. This type follows the ``ConcludingAsyncWriter``
/// pattern, which allows for asynchronous production of data with a conclusive final element.
///
/// This writer is designed to work with HTTP responses where the body is streamed in chunks
/// and potentially followed by trailer fields.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPResponseConcludingAsyncWriter: ConcludingAsyncWriter, ~Copyable {
    /// A writer for HTTP response body chunks that implements the ``AsyncWriter`` protocol.
    ///
    /// This writer handles the body parts of an HTTP response, allowing them to be written
    /// incrementally as spans of bytes.
    public struct ResponseBodyAsyncWriter: AsyncWriter {
        /// The type of elements this writer accepts (byte arrays representing body chunks).
        public typealias WriteElement = UInt8

        /// The type of errors that can occur during writing operations.
        public typealias WriteFailure = any Error

        /// The underlying NIO writer for HTTP response parts.
        private var writer: NIOAsyncChannelOutboundWriter<HTTPResponsePart>

        /// Initializes a new response body writer with the given NIO async channel writer.
        ///
        /// - Parameter writer: The NIO async channel outbound writer to use for writing response parts.
        init(writer: NIOAsyncChannelOutboundWriter<HTTPResponsePart>) {
            self.writer = writer
        }

        /// Writes a chunk of response body data to the underlying writer.
        ///
        /// - Parameter element: A span of bytes representing the body chunk to write.
        /// - Throws: An error if the writing operation fails.
        public mutating func write<Result, Failure: Error>(
            _ body: nonisolated(nonsending) (inout OutputSpan<WriteElement>) async throws(Failure) -> Result
        ) async throws(EitherError<WriteFailure, Failure>) -> Result {
            var buffer = RigidArray<WriteElement>.init(capacity: 1024)

            let result: Result
            do {
                result = try await buffer.append(count: 1024) { span in
                    try await body(&span)
                }
            } catch {
                throw .first(error)
            }

            var byteBuffer = ByteBuffer()
            byteBuffer.reserveCapacity(buffer.count)
            for index in buffer.indices {
                byteBuffer.writeInteger(buffer[index])
            }

            //            buffer.span.withUnsafeBufferPointer { buffer in
            //                <#code#>
            //            }
            //            var byteBuffer = ByteBuffer()

            do {
                try await self.writer.write(.body(byteBuffer))
            } catch {
                throw .first(error)
            }

            return result

            //            let pointer = buffer.withUnsafeMutableBufferPointer { $0 }
            //            var span = OutputSpan<WriteElement>(
            //                buffer: pointer,
            //                initializedCount: 0
            //            )
            //            do {
            //                let bodyResult = try await body(&span)
            //
            //            } catch {
            //                throw .second(error)
            //            }
        }
    }

    final class WriterState: Sendable {
        struct Wrapped {
            var finishedWriting: Bool = false
        }

        let wrapped: Mutex<Wrapped>

        init() {
            self.wrapped = .init(.init())
        }
    }

    /// The underlying writer type for the HTTP response body.
    public typealias Underlying = ResponseBodyAsyncWriter

    /// The type of the final element that concludes the response (optional HTTP trailer fields).
    public typealias FinalElement = HTTPFields?

    /// The type of errors that can occur during writing operations.
    public typealias Failure = any Error

    /// The underlying NIO writer for HTTP response parts.
    private var writer: NIOAsyncChannelOutboundWriter<HTTPResponsePart>

    private var writerState: WriterState

    /// Initializes a new HTTP response body and trailers writer with the given NIO async channel writer.
    ///
    /// - Parameter writer: The NIO async channel outbound writer to use for writing response parts.
    init(
        writer: NIOAsyncChannelOutboundWriter<HTTPResponsePart>,
        writerState: WriterState
    ) {
        self.writer = writer
        self.writerState = writerState
    }

    /// Processes the body writing operation and concludes with optional trailer fields.
    ///
    /// This method provides a response body writer to the given closure, allowing it to write
    /// chunks of the response body incrementally. Once the closure completes, the resulting
    /// final element (trailer fields) is used to conclude the HTTP response.
    ///
    /// - Parameter body: A closure that takes a response body writer and returns both a result value
    ///                  and optional trailer fields to conclude the response.
    /// - Returns: The value returned by the body closure.
    /// - Throws: Any error encountered during the writing process.
    ///
    /// - Example:
    /// ```swift
    /// let responseWriter: HTTPResponseConcludingAsyncWriter = ...
    ///
    /// try await responseWriter.produceAndConclude { writer in
    ///     // Write response body chunks
    ///     try await writer.write([...])
    ///     try await writer.write([...])
    ///
    ///     // Return a result and optional trailers
    ///     return (true, HTTPFields(trailerFields))
    /// }
    /// ```
    public consuming func produceAndConclude<Return>(
        body: (consuming sending ResponseBodyAsyncWriter) async throws -> (Return, FinalElement)
    ) async throws -> Return {
        let responseBodyAsyncWriter = ResponseBodyAsyncWriter(writer: self.writer)
        let (result, finalElement) = try await body(responseBodyAsyncWriter)
        try await self.writer.write(.end(finalElement))
        self.writerState.wrapped.withLock { $0.finishedWriting = true }
        return result
    }
}

@available(*, unavailable)
extension HTTPResponseConcludingAsyncWriter: Sendable {}

@available(*, unavailable)
extension HTTPResponseConcludingAsyncWriter.ResponseBodyAsyncWriter: Sendable {}
