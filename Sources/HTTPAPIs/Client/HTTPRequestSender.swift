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

/// A protocol for sending an HTTP request body and trailing fields.
///
/// ``HTTPRequestSender`` is used on the client side to write the body bytes of
/// an outgoing HTTP request and conclude with any trailing ``HTTPFields``.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPRequestSender<Writer>: ~Copyable, ~Escapable {
    /// The asynchronous writer type that accepts request body bytes.
    associatedtype Writer: AsyncWriter, ~Copyable, ~Escapable
    where Writer.WriteElement == UInt8

    /// Sends the request body bytes and concludes with optional trailing fields.
    ///
    /// - Parameter body: A closure that takes the underlying ``AsyncWriter`` and returns
    ///   a tuple of the result value and the optional trailing fields to send after the body.
    /// - Returns: The value returned by the body closure.
    /// - Throws: Any error thrown by `body` or while writing to the underlying stream.
    ///
    /// - Note: This method consumes the sender, ensuring it can be called only once.
    // TODO: Make `Return: ~Copyable` once Swift tuples support non-copyable elements.
    consuming func send<Return>(
        body: (consuming sending Writer) async throws -> (Return, HTTPFields?)
    ) async throws -> Return

    /// Sends the contents of `body` followed by optional trailing fields.
    ///
    /// The buffer's contents are moved into the writer. On return, `body` may be empty
    /// or partially drained.
    ///
    /// Conformers may override this to provide a fast-path implementation
    /// (for example, by writing the entire buffer in a single call to the
    /// underlying transport).
    ///
    /// - Parameters:
    ///   - body: A range-replaceable container holding the bytes to send.
    ///   - trailers: The HTTP trailing fields to send after the body, if any.
    consuming func send<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        body: inout Buffer,
        trailers: HTTPFields?
    ) async throws

    /// Sends the contents of `body` (as a span) followed by optional trailing fields.
    ///
    /// Conformers may override this to provide a fast-path implementation.
    consuming func send(
        body: Span<UInt8>,
        trailers: HTTPFields?
    ) async throws

    /// Concludes the request with only trailing fields and no body.
    ///
    /// Conformers may override this to provide a fast-path implementation.
    consuming func send(trailers: HTTPFields?) async throws
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPRequestSender where Self: ~Copyable, Writer: ~Copyable {
    public consuming func send<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        body: inout Buffer,
        trailers: HTTPFields? = nil
    ) async throws {
        try await self.send { writer in
            var writer = writer
            while body.startIndex != body.endIndex {
                try await writer.write { (writeBuffer: inout Writer.Buffer) in
                    let toMove = Swift.min(body.count, writeBuffer.freeCapacity)
                    let endIdx = body.index(body.startIndex, offsetBy: toMove)
                    writeBuffer.append(moving: body.startIndex..<endIdx, from: &body)
                }
            }
            return ((), trailers)
        }
    }

    public consuming func send(
        body: Span<UInt8>,
        trailers: HTTPFields? = nil
    ) async throws {
        try await self.send { writer in
            var writer = writer
            try await writer.write(body)
            return ((), trailers)
        }
    }

    public consuming func send(trailers: HTTPFields?) async throws {
        try await self.send { _ in
            ((), trailers)
        }
    }
}
