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

public import HTTPTypes

/// A struct that ensures a single non-informational HTTP response is sent per request.
///
/// ``HTTPResponseSender`` enforces structured response handling by allowing only one call to
/// ``send(_:)`` before the sender is consumed. Informational responses can be sent zero or
/// more times using ``sendInformational(_:)`` before sending the final response. This design
/// ensures proper HTTP semantics where exactly one non-informational response is sent, followed
/// by optional response body streaming and trailers.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPResponseSender<ResponseWriter: ConcludingAsyncWriter & ~Copyable>: ~Copyable {
    private let _sendInformational: (HTTPResponse) async throws -> Void
    private let _send: (HTTPResponse) async throws -> ResponseWriter

    /// Creates a new HTTP response sender.
    ///
    /// - Parameters:
    ///   - send: A closure that sends the final HTTP response and returns a writer for the response body.
    ///   - sendInformational: A closure that sends informational (1xx) HTTP responses.
    public init(
        send: @escaping (HTTPResponse) async throws -> ResponseWriter,
        sendInformational: @escaping (HTTPResponse) async throws -> Void
    ) {
        self._send = send
        self._sendInformational = sendInformational
    }

    /// Sends the final HTTP response and returns a writer for the response body.
    ///
    /// This method consumes the sender, ensuring only one non-informational response can be sent.
    /// After calling this method, the sender cannot be used again. For informational (1xx) responses,
    /// use ``sendInformational(_:)`` instead.
    ///
    /// - Parameter response: The final HTTP response to send to the client. Must not be an
    ///   informational (1xx) response.
    ///
    /// - Returns: A writer for streaming the response body data and optional trailers.
    ///
    /// - Throws: An error if sending the response fails.
    consuming public func send(_ response: HTTPResponse) async throws -> ResponseWriter {
        precondition(response.status.kind != .informational)
        return try await self._send(response)
    }

    /// Sends an informational HTTP response.
    ///
    /// This method can be called multiple times to send informational (1xx) responses before
    /// sending the final response with ``send(_:)``. Common informational responses include
    /// 100 Continue, 102 Processing, and 103 Early Hints.
    ///
    /// - Parameter response: An informational HTTP response to send to the client. Must be a
    ///   1xx status response.
    ///
    /// - Throws: An error if sending the informational response fails.
    public func sendInformational(_ response: HTTPResponse) async throws {
        precondition(response.status.kind == .informational)
        return try await _sendInformational(response)
    }
}

@available(*, unavailable)
extension HTTPResponseSender: Sendable {}
