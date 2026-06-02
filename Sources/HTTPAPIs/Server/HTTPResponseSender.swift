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

public import AsyncStreaming
import BasicContainers

/// A protocol for sending an HTTP response, including the head, body, and trailing fields.
///
/// ``HTTPResponseSender`` is used on the server side to send exactly one
/// non-informational response per request. Conformers may also send any number
/// of informational (1xx) responses before the final response by calling
/// ``sendInformational(_:)``.
///
/// ``send(_:)`` writes the response head and returns a ``CallerAsyncWriter``
/// for streaming the body. The caller is responsible for terminating the body
/// via ``CallerAsyncWriter/finish(buffer:finalElement:)``.
///
/// For the common case where the entire body and trailers are already in hand
/// before the response head is sent, ``sendAndFinish(_:copying:trailers:)``
/// completes the entire response in a single call. It has a default
/// implementation on top of ``send(_:)``, but conformers are encouraged to
/// override it when the underlying transport can coalesce the head, body, and
/// trailing fields into a single frame.
@available(anyAppleOS 26.0, *)
public protocol HTTPResponseSender<Writer>: ~Copyable, ~Escapable {
    /// The body writer type used to stream response body bytes and signal end-of-body.
    ///
    /// Conforms to ``CallerAsyncWriter`` with ``HTTPFields`` as the optional
    /// trailing payload delivered alongside the FIN signal.
    associatedtype Writer: CallerAsyncWriter, ~Copyable, ~Escapable
    where Writer.WriteElement == UInt8, Writer.FinalElement == HTTPFields?

    /// Sends an informational HTTP response.
    ///
    /// This method may be called any number of times before the final response is sent
    /// with ``send(_:)``. Common informational responses include 100 Continue,
    /// 102 Processing, and 103 Early Hints.
    ///
    /// - Parameter response: An informational HTTP response. Must have a 1xx status.
    mutating func sendInformational(_ response: HTTPResponse) async throws

    /// Sends the final HTTP response head and returns a body writer.
    ///
    /// The caller takes ownership of the writer and must terminate it by
    /// calling ``CallerAsyncWriter/finish(buffer:finalElement:)`` exactly once
    /// before dropping it. The writer's lifetime is bounded by the enclosing
    /// server request handler scope. Dropping the writer without calling
    /// `finish` causes the response to be aborted when the handler scope exits.
    ///
    /// - Parameter response: The final HTTP response head. Must not be informational (1xx).
    /// - Returns: A body writer for streaming the response body.
    /// - Throws: Any error encountered while writing the response head.
    ///
    /// - Note: This method consumes the sender, ensuring exactly one final response is sent.
    @_lifetime(copy self)
    consuming func send(_ response: HTTPResponse) async throws -> Writer

    /// Sends the final HTTP response head, the contents of `buffer`, and the
    /// optional trailing HTTP fields, completing the response in a single call.
    ///
    /// This is equivalent to calling ``send(_:)`` to obtain a writer and then
    /// invoking ``CallerAsyncWriter/finish(buffer:finalElement:)`` on it, but
    /// conformers may override this to optimize writing the head, body, and trailing
    /// fields into a single write where the wire protocol allows.
    /// The default implementation does the two-step expansion via ``send(_:)``.
    ///
    /// On return the response is fully sent and no further calls are possible
    /// on the sender. For empty-body responses (such as `204 No Content`,
    /// `304 Not Modified`, or error responses without a body), pass `nil` for
    /// `buffer` or use the ``sendAndFinish(_:)`` convenience; for responses
    /// without trailers, pass `nil` for `trailers`.
    ///
    /// - Parameters:
    ///   - response: The final HTTP response head. Must not be informational (1xx).
    ///   - buffer: The full response body, or `nil` for an empty body. When
    ///     non-`nil`, the buffer is drained as part of the call; on return
    ///     it is `nil`.
    ///   - trailers: The optional trailing HTTP fields, or `nil` to terminate
    ///     the body without trailers.
    /// - Throws: Any error encountered while writing the head, body, or trailing fields.
    consuming func sendAndFinish<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        _ response: HTTPResponse,
        buffer: inout Buffer?,
        trailers: HTTPFields?
    ) async throws where Buffer.Element: ~Copyable
}

@available(anyAppleOS 26.0, *)
extension HTTPResponseSender where Self: ~Copyable, Writer: ~Copyable {
    public consuming func sendAndFinish<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        _ response: HTTPResponse,
        buffer: inout Buffer?,
        trailers: HTTPFields?
    ) async throws where Buffer.Element: ~Copyable {
        let writer = try await self.send(response)
        if var unwrapped = buffer.take() {
            try await writer.finish(buffer: &unwrapped, finalElement: trailers)
        } else {
            var empty = UniqueArray<UInt8>()
            try await writer.finish(buffer: &empty, finalElement: trailers)
        }
    }

    /// Sends the final HTTP response head with no body and no trailing fields,
    /// completing the response in a single call.
    ///
    /// Convenience for empty-body responses such as `204 No Content`,
    /// `304 Not Modified`, or error responses without a body. Equivalent to
    /// ``sendAndFinish(_:buffer:trailers:)`` with `nil` for both `buffer` and
    /// `trailers`; conformers that override that requirement to fuse into a
    /// single transport frame benefit here too.
    ///
    /// - Parameter response: The final HTTP response head. Must not be informational (1xx).
    /// - Throws: Any error encountered while writing the response head or the FIN signal.
    public consuming func sendAndFinish(_ response: HTTPResponse) async throws {
        var noBody: UniqueArray<UInt8>? = nil
        try await self.sendAndFinish(response, buffer: &noBody, trailers: nil)
    }
}
