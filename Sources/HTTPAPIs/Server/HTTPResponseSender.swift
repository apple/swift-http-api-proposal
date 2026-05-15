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

/// A protocol for sending an HTTP response, including the head, body, and trailing fields.
///
/// ``HTTPResponseSender`` is used on the server side to send exactly one
/// non-informational response per request. Conformers may also send any number
/// of informational (1xx) responses before the final response by calling
/// ``sendInformational(_:)``.
///
/// The streaming form ``send(_:body:)`` takes the response head together with a
/// body-writing closure that returns the trailing fields. The one-shot variants
/// take the body bytes directly and have default implementations on top of the
/// streaming form, but conformers may override them to provide fast paths.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPResponseSender<Writer>: ~Copyable, ~Escapable {
    /// The asynchronous writer type that accepts response body bytes.
    associatedtype Writer: AsyncWriter, ~Copyable, ~Escapable
    where Writer.WriteElement == UInt8

    /// Sends an informational HTTP response.
    ///
    /// This method may be called any number of times before the final response is sent
    /// with ``send(_:body:)``. Common informational responses include 100 Continue,
    /// 102 Processing, and 103 Early Hints.
    ///
    /// - Parameter response: An informational HTTP response. Must have a 1xx status.
    func sendInformational(_ response: HTTPResponse) async throws

    /// Sends the final HTTP response head and streams the body, concluding with trailing fields.
    ///
    /// - Parameters:
    ///   - response: The final HTTP response head. Must not be informational (1xx).
    ///   - body: A closure that takes the underlying ``AsyncWriter`` and returns a tuple of
    ///     the result value and any trailing ``HTTPFields`` to send after the body.
    /// - Returns: The value returned by the body closure.
    /// - Throws: Any error thrown by `body` or while writing the response.
    ///
    /// - Note: This method consumes the sender, ensuring exactly one final response is sent.
    // TODO: Make `Return: ~Copyable` once Swift tuples support non-copyable elements.
    consuming func send<Return>(
        _ response: HTTPResponse,
        body: (consuming sending Writer) async throws -> (Return, HTTPFields?)
    ) async throws -> Return

    /// Sends the response head, the contents of `body`, and optional trailing fields in one call.
    ///
    /// The buffer's contents are moved into the writer. On return, `body` may be empty
    /// or partially drained.
    ///
    /// Conformers may override this to provide a fast-path implementation
    /// (for example, by writing the head, body, and trailers in a single
    /// transport call without the streaming closure).
    ///
    /// - Parameters:
    ///   - response: The final HTTP response head. Must not be informational (1xx).
    ///   - body: A range-replaceable container holding the bytes to send.
    ///   - trailers: The HTTP trailing fields to send after the body, if any.
    consuming func send<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        _ response: HTTPResponse,
        body: inout Buffer,
        trailers: HTTPFields?
    ) async throws

    /// Sends the response head, the contents of `body` (as a span), and optional trailing fields.
    ///
    /// Conformers may override this to provide a fast-path implementation.
    consuming func send(
        _ response: HTTPResponse,
        body: Span<UInt8>,
        trailers: HTTPFields?
    ) async throws

    /// Sends the response head and trailing fields with no body.
    ///
    /// Conformers may override this to provide a fast-path implementation.
    consuming func send(_ response: HTTPResponse, trailers: HTTPFields?) async throws

    /// Sends the response head with no body and no trailing fields.
    ///
    /// Conformers may override this to provide a fast-path implementation.
    consuming func send(_ response: HTTPResponse) async throws
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPResponseSender where Self: ~Copyable, Writer: ~Copyable {
    public consuming func send<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        _ response: HTTPResponse,
        body: inout Buffer,
        trailers: HTTPFields? = nil
    ) async throws {
        try await self.send(response) { writer in
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
        _ response: HTTPResponse,
        body: Span<UInt8>,
        trailers: HTTPFields? = nil
    ) async throws {
        try await self.send(response) { writer in
            var writer = writer
            try await writer.write(body)
            return ((), trailers)
        }
    }

    public consuming func send(_ response: HTTPResponse, trailers: HTTPFields?) async throws {
        try await self.send(response) { _ in
            ((), trailers)
        }
    }

    public consuming func send(_ response: HTTPResponse) async throws {
        try await self.send(response) { _ in
            ((), nil)
        }
    }
}
