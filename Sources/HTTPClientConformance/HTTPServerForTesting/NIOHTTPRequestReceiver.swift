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

/// A NIO-backed HTTP request receiver used by the test server.
///
/// ``NIOHTTPRequestReceiver`` reads the body bytes of an incoming HTTP request from a NIO
/// async channel inbound stream and captures any trailing ``HTTPFields`` that follow the body.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct NIOHTTPRequestReceiver: HTTPRequestReceiver, ~Copyable {
    /// A reader for HTTP request body chunks that implements the ``AsyncReader`` protocol.
    public struct RequestBodyAsyncReader: AsyncReader, ~Copyable {
        public typealias ReadElement = UInt8
        public typealias ReadFailure = any Error
        public typealias Buffer = UniqueArray<UInt8>

        fileprivate var state: ReaderState

        private var iterator: NIOAsyncChannelInboundStream<HTTPRequestPart>.AsyncIterator

        fileprivate init(
            iterator: consuming sending NIOAsyncChannelInboundStream<HTTPRequestPart>.AsyncIterator,
            readerState: ReaderState
        ) {
            self.iterator = iterator
            self.state = readerState
        }

        public mutating func read<Return: ~Copyable, Failure: Error>(
            body: nonisolated(nonsending) (inout UniqueArray<UInt8>) async throws(Failure) -> Return
        ) async throws(EitherError<ReadFailure, Failure>) -> Return {
            let requestPart: HTTPRequestPart?
            do {
                requestPart = try await self.iterator.next(isolation: #isolation)
            } catch {
                throw .first(error)
            }

            var buffer = UniqueArray<UInt8>()
            switch requestPart {
            case .head:
                fatalError()
            case .body(let element):
                buffer.reserveCapacity(element.readableBytes)
                unsafe element.withUnsafeReadableBytes { rawBufferPtr in
                    let usbptr = unsafe rawBufferPtr.assumingMemoryBound(to: UInt8.self)
                    unsafe buffer.append(copying: usbptr)
                }
            case .end(let trailers):
                self.state.wrapped.withLock { state in
                    state.trailers = trailers
                    state.finishedReading = true
                }
            case .none:
                break
            }

            do {
                return try await body(&buffer)
            } catch {
                throw .second(error)
            }
        }
    }

    public final class ReaderState: Sendable {
        struct Wrapped {
            var trailers: HTTPFields? = nil
            var finishedReading: Bool = false
        }

        let wrapped: Mutex<Wrapped>

        public init() {
            self.wrapped = .init(.init())
        }
    }

    public typealias Reader = RequestBodyAsyncReader

    private var iterator: Disconnected<NIOAsyncChannelInboundStream<HTTPRequestPart>.AsyncIterator?>

    internal var state: ReaderState

    /// Initializes a new HTTP request body and trailers receiver with the given NIO async channel iterator.
    init(
        iterator: consuming sending NIOAsyncChannelInboundStream<HTTPRequestPart>.AsyncIterator,
        readerState: ReaderState
    ) {
        self.iterator = .init(value: iterator)
        self.state = readerState
    }

    public consuming func receive<Return, Failure: Error>(
        body: nonisolated(nonsending) (consuming sending RequestBodyAsyncReader) async throws(Failure) -> Return
    ) async throws(Failure) -> (Return, HTTPFields?) {
        if let iterator = self.iterator.take() {
            let partsReader = RequestBodyAsyncReader(iterator: iterator, readerState: self.state)
            let result = try await body(partsReader)
            let trailers = self.state.wrapped.withLock { $0.trailers }
            return (result, trailers)
        } else {
            fatalError("receive called more than once")
        }
    }
}

@available(*, unavailable)
extension NIOHTTPRequestReceiver: Sendable {}

@available(*, unavailable)
extension NIOHTTPRequestReceiver.RequestBodyAsyncReader: Sendable {}

@usableFromInline
struct Disconnected<Value: ~Copyable>: ~Copyable, Sendable {
    // This is safe since we take the value as sending and take consumes it
    // and returns it as sending.
    private nonisolated(unsafe) var value: Value?

    @usableFromInline
    init(value: consuming sending Value) {
        unsafe self.value = .some(value)
    }

    @usableFromInline
    consuming func take() -> sending Value {
        nonisolated(unsafe) let value = unsafe self.value.take()!
        return unsafe value
    }

    @usableFromInline
    mutating func swap(newValue: consuming sending Value) -> sending Value {
        nonisolated(unsafe) let value = unsafe self.value.take()!
        unsafe self.value = consume newValue
        return unsafe value
    }
}
