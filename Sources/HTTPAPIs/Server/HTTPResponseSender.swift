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

/// A protocol for sending an HTTP response, including the head, body, and trailing fields.
///
/// ``HTTPResponseSender`` is used on the server side to send exactly one
/// non-informational response per request. Conformers may also send any number
/// of informational (1xx) responses before the final response by calling
/// ``sendInformational(_:)``.
///
/// ``send(_:)`` writes the response head and returns an ``HTTPBodyWriter`` for
/// streaming the body. The caller is responsible for terminating the body via
/// ``HTTPBodyWriter/finish(body:)``.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPResponseSender<Writer>: ~Copyable, ~Escapable {
    /// The body writer type used to stream response body bytes and signal end-of-body.
    associatedtype Writer: HTTPBodyWriter, ~Copyable, ~Escapable

    /// Sends an informational HTTP response.
    ///
    /// This method may be called any number of times before the final response is sent
    /// with ``send(_:)``. Common informational responses include 100 Continue,
    /// 102 Processing, and 103 Early Hints.
    ///
    /// - Parameter response: An informational HTTP response. Must have a 1xx status.
    func sendInformational(_ response: HTTPResponse) async throws

    /// Sends the final HTTP response head and returns a body writer.
    ///
    /// The caller takes ownership of the writer and must terminate it by
    /// calling ``HTTPBodyWriter/finish(body:)`` exactly once before
    /// dropping it. The writer's lifetime is bounded by the enclosing server
    /// request handler scope. Dropping the writer without calling `finish`
    /// causes the response to be aborted when the handler scope exits.
    ///
    /// - Parameter response: The final HTTP response head. Must not be informational (1xx).
    /// - Returns: A body writer for streaming the response body.
    /// - Throws: Any error encountered while writing the response head.
    ///
    /// - Note: This method consumes the sender, ensuring exactly one final response is sent.
    @_lifetime(copy self)
    consuming func send(_ response: HTTPResponse) async throws -> Writer
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPResponseSender where Self: ~Copyable, Writer: ~Copyable {
    /// Sends the response head, the contents of `body`, and optional trailing fields in one call.
    public consuming func send(
        _ response: HTTPResponse,
        body: (inout Writer.Buffer) async throws -> HTTPFields?
    ) async throws {
        let writer = try await self.send(response)
        try await writer.finish(body: body)
    }

    /// Sends the response head, the contents of `body`, and optional trailing fields in one call.
    public consuming func send<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        _ response: HTTPResponse,
        copying buffer: inout Buffer,
        trailers: HTTPFields? = nil
    ) async throws {
        let writer = try await self.send(response)

        try await writer.finish { writerBuffer in
            writerBuffer.append(copying: buffer)
            return trailers
        }
    }

    /// Sends the response head and trailing fields with no body.
    public consuming func send(_ response: HTTPResponse, trailers: HTTPFields?) async throws {
        let writer = try await self.send(response)
        try await writer.finish(trailers: trailers)
    }

    /// Sends the response head with no body and no trailing fields.
    public consuming func send(_ response: HTTPResponse) async throws {
        let writer = try await self.send(response)
        try await writer.finish(trailers: nil)
    }
}
