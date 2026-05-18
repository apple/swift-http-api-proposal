//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import BasicContainers

/// A protocol for receiving an HTTP response body and trailing fields.
///
/// ``HTTPResponseReceiver`` is used on the client side to incrementally consume
/// the body bytes of an incoming HTTP response and capture any trailing
/// ``HTTPFields`` that follow the body.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPResponseReceiver<Reader>: ~Copyable, ~Escapable {
    /// The asynchronous reader type that supplies response body bytes.
    associatedtype Reader: AsyncReader, ~Copyable, ~Escapable
    where Reader.ReadElement == UInt8

    /// Receives the response body bytes and concludes with optional trailing fields.
    ///
    /// - Parameter body: A closure that takes the underlying ``AsyncReader`` and returns a value.
    /// - Returns: A tuple containing the value returned by `body` and any trailing HTTP fields.
    /// - Throws: Any error thrown by `body` or while reading the underlying stream.
    ///
    /// - Note: This method consumes the receiver, ensuring it can be called only once.
    // TODO: Make `Return: ~Copyable` once Swift tuples support non-copyable elements.
    consuming func receive<Return, Failure: Error>(
        body: (consuming sending Reader) async throws(Failure) -> Return
    ) async throws(Failure) -> (Return, HTTPFields?)
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPResponseReceiver where Self: ~Copyable, Reader: ~Copyable {
    /// Reads body bytes into the supplied buffer until either its free capacity is
    /// exhausted or the response stream ends, and returns any trailing fields.
    ///
    /// The buffer's remaining capacity acts as the collection limit. Any bytes the
    /// reader produces beyond what fits in `buffer` are discarded.
    ///
    /// - Parameter buffer: The destination container that receives the collected bytes.
    /// - Returns: The HTTP trailing fields, if any were sent.
    public consuming func collect<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        into buffer: inout Buffer
    ) async throws -> HTTPFields? {
        try await self.receive { reader in
            var reader = reader
            var eof = false
            while buffer.freeCapacity > 0 && !eof {
                try await reader.read { (readBuffer: inout Reader.Buffer) in
                    if readBuffer.count == 0 {
                        eof = true
                        return
                    }
                    let remaining = buffer.freeCapacity
                    if readBuffer.count <= remaining {
                        buffer.append(
                            moving: readBuffer.startIndex..<readBuffer.endIndex,
                            from: &readBuffer
                        )
                    } else {
                        let endIdx = readBuffer.index(readBuffer.startIndex, offsetBy: remaining)
                        buffer.append(moving: readBuffer.startIndex..<endIdx, from: &readBuffer)
                        var consumer = readBuffer.consumeAll()
                        while consumer.next() != nil {}
                    }
                }
            }
        }.1
    }

    /// Collects up to `limit` bytes from the response body and processes them via `body`.
    ///
    /// Convenience over ``collect(into:)`` for callers that want to operate on a span of
    /// the collected bytes inline.
    public consuming func collect<Result>(
        upTo limit: Int,
        body: (consuming InputSpan<UInt8>) async throws -> Result
    ) async throws -> (Result, HTTPFields?) {
        var accumulated = UniqueArray<UInt8>(minimumCapacity: limit)
        let trailers = try await self.collect(into: &accumulated)
        var consumer = accumulated.consumeAll()
        let result = try await body(consumer.drainNext())
        return (result, trailers)
    }
}
