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
public import BasicContainers
import HTTPAPIs
public import HTTPTypes
import NIOCore
import NIOHTTPTypes
import Synchronization

/// A NIO-backed HTTP request body reader used by the test server.
@available(anyAppleOS 26.0, *)
public struct NIORequestBodyReader: AsyncReader, ~Copyable {
    public typealias ReadElement = UInt8
    public typealias ReadFailure = any Error
    public typealias Buffer = UniqueArray<UInt8>
    public typealias FinalElement = HTTPFields?

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

    private var state: ReaderState
    private var iterator: NIOAsyncChannelInboundStream<HTTPRequestPart>.AsyncIterator

    init(
        iterator: consuming sending NIOAsyncChannelInboundStream<HTTPRequestPart>.AsyncIterator,
        readerState: ReaderState
    ) {
        self.iterator = iterator
        self.state = readerState
    }

    public mutating func read<Return: ~Copyable, Failure: Error>(
        body: nonisolated(nonsending) (inout UniqueArray<UInt8>, consuming HTTPFields??) async throws(Failure) -> Return
    ) async throws(EitherError<ReadFailure, Failure>) -> Return {
        var buffer = UniqueArray<UInt8>()
        var finalElement: HTTPFields?? = nil

        let alreadyFinished = self.state.wrapped.withLock { $0.finishedReading }
        if !alreadyFinished {
            let requestPart: HTTPRequestPart?
            do {
                requestPart = try await self.iterator.next(isolation: #isolation)
            } catch {
                throw .first(error)
            }

            switch requestPart {
            case .head:
                fatalError()
            case .body(let element):
                buffer.reserveCapacity(element.readableBytes)
                unsafe element.withUnsafeReadableBytes { rawBufferPtr in
                    let usbptr = unsafe rawBufferPtr.assumingMemoryBound(to: UInt8.self)
                    unsafe buffer.append(copying: usbptr)
                }
            case .end(let t):
                self.state.wrapped.withLock { state in
                    state.trailers = t
                    state.finishedReading = true
                }
                finalElement = .some(t)
            case .none:
                self.state.wrapped.withLock { $0.finishedReading = true }
                finalElement = .some(nil)
            }
        }

        do {
            return try await body(&buffer, finalElement)
        } catch {
            throw .second(error)
        }
    }
}

@available(*, unavailable)
extension NIORequestBodyReader: Sendable {}
