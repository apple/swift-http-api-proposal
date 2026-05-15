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

/// A reader that streams HTTP body bytes and signals end-of-body by delivering
/// trailing fields together with the last body chunk.
///
/// Refines ``AsyncReader`` for byte streams (``ReadElement`` is `UInt8`) by
/// adding a `read` overload whose closure receives an additional
/// ``HTTPFields`` argument. A non-`nil` value in that argument marks the
/// chunk as the last one and carries any trailing fields (which themselves
/// may be empty). Callers that don't care about trailers can use the
/// inherited ``AsyncReader/read(body:)`` overload, which silently drops the
/// trailers.
///
/// Conformers must, after delivering a chunk with non-`nil` trailers,
/// continue to accept further `read(...)` calls and return an empty
/// buffer with `nil` trailers. This keeps callers that drive the reader via
/// the inherited ``AsyncReader/read(body:)`` overload (which loops until
/// they see an empty buffer) terminating correctly.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPBodyReader: AsyncReader, ~Copyable, ~Escapable
where ReadElement == UInt8 {
    /// Reads the next body chunk and signals end-of-body via `trailers`.
    ///
    /// - Parameter body: A closure that receives the body chunk (as an `inout`
    ///   buffer) together with the trailing fields, if any. A `nil` value for
    ///   trailers means more body bytes may follow. A non-`nil` value
    ///   (possibly empty) marks this chunk as the last one.
    /// - Returns: The value the body closure returns.
    /// - Throws: An ``EitherError`` carrying either the underlying read
    ///   failure or the failure thrown by `body`.
    mutating func read<Return: ~Copyable, Failure: Error>(
        body: (inout Buffer, HTTPFields?) async throws(Failure) -> Return
    ) async throws(EitherError<ReadFailure, Failure>) -> Return
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPBodyReader where Self: ~Copyable {
    /// Satisfies the ``AsyncReader`` requirement by forwarding to the
    /// trailers-aware `read` and silently discarding any trailers.
    public mutating func read<Return: ~Copyable, Failure: Error>(
        body: (inout Buffer) async throws(Failure) -> Return
    ) async throws(EitherError<ReadFailure, Failure>) -> Return {
        try await self.read { (buf: inout Buffer, _: HTTPFields?) async throws(Failure) -> Return in
            try await body(&buf)
        }
    }

    /// Streams every body chunk from this reader into `writer`, fusing the
    /// last chunk with the trailers and FIN signal in a single
    /// ``HTTPBodyWriter/finish(body:)`` call. No intermediate copy is made.
    ///
    /// Use this when forwarding a request body straight into a response
    /// (echo, proxy) or any other reader-into-writer pipe where you want the
    /// transport to see one fused write at the end of the body.
    ///
    /// - Parameter writer: The body writer to pipe into. Consumed.
    // TODO: This moves a full reader chunk into the writer's buffer in a
    // single `write` call. Today every conformer uses an unbounded
    // `UniqueArray` so this works, but if a future writer ships a
    // fixed-capacity buffer per `write` we'd silently truncate. Either
    // document the capacity contract on `AsyncWriter` so we can rely on it,
    // or loop here on `wbuf.freeCapacity` and split the source chunk across
    // multiple writes.
    public consuming func pipe<W: HTTPBodyWriter & ~Copyable>(
        into writer: consuming W
    ) async throws where W.Buffer == Self.Buffer {
        var reader = self
        var writerOpt: W? = .some(writer)
        var done = false
        while !done {
            try await reader.read { rbuf, trailers in
                if let trailers {
                    let w = writerOpt.take()!
                    try await w.finish { wbuf in
                        wbuf.append(
                            moving: rbuf.startIndex..<rbuf.endIndex,
                            from: &rbuf
                        )
                        return trailers
                    }
                    done = true
                } else {
                    var w = writerOpt.take()!
                    try await w.write { wbuf in
                        wbuf.append(
                            moving: rbuf.startIndex..<rbuf.endIndex,
                            from: &rbuf
                        )
                    }
                    writerOpt = .some(consume w)
                }
            }
        }
    }

    /// Reads body bytes into the supplied buffer until either its free capacity
    /// is exhausted or the stream ends, and returns any trailing fields.
    ///
    /// The buffer's **initial free capacity** acts as a hard byte cap. Pre-size
    /// the buffer with `UniqueArray<UInt8>(minimumCapacity: limit)` (or
    /// equivalent) to control how many bytes are kept; any bytes the reader
    /// produces beyond what fits are read and discarded.
    ///
    /// > Important: A default-constructed `UniqueArray<UInt8>()` has free
    /// > capacity zero, which causes this method to discard the entire body
    /// > without storing anything. If you want to read the whole body, use
    /// > ``collect(upTo:body:)`` (which collects up to a caller-supplied
    /// > limit) or call ``read(body:)`` directly in a loop.
    ///
    /// - Parameter buffer: The destination container that receives the collected bytes.
    /// - Returns: The HTTP trailing fields, if any were sent.
    public consuming func collect<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        into buffer: inout Buffer
    ) async throws -> HTTPFields? {
        var reader = self
        var trailers: HTTPFields? = nil
        var done = false
        while !done {
            try await reader.read { (readBuffer: inout Self.Buffer, t: HTTPFields?) in
                if let t {
                    trailers = t.isEmpty ? nil : t
                    done = true
                }
                if readBuffer.count == 0 {
                    if t == nil {
                        done = true
                    }
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
            if buffer.freeCapacity == 0 { break }
        }
        return trailers
    }

    /// Collects up to `limit` body bytes and processes them via `body`.
    ///
    /// Reads chunks from the body, accumulating up to `limit` bytes. Bytes
    /// beyond `limit` are silently discarded. The accumulated bytes are
    /// passed to `body` as an `InputSpan` for processing.
    ///
    /// - Parameters:
    ///   - limit: The maximum number of bytes to collect.
    ///   - body: A closure that processes the collected bytes.
    /// - Returns: A tuple of the closure's result and any trailing fields.
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
