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
public import HTTPTypes

/// This type ensures that a single non-informational (1xx) `HTTPResponse` is sent back to the client when handling a request.
///
/// The user will get a ``HTTPResponseSender`` as part of
/// ``HTTPServerRequestHandler/handle(request:requestContext:requestBodyAndTrailers:responseSender:)``, and they
/// will only be allowed to call ``send(_:)`` once before the sender is consumed and cannot be referenced again.
/// ``sendInformational(_:)`` may be called zero or more times.
///
/// This forces structure in the response flow, requiring users to send a single response before they can stream a response body and
/// trailers using the returned `ResponseWriter`.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPResponseSender<ResponseWriter: ConcludingAsyncWriter & ~Copyable>: ~Copyable {
    private let _sendInformational: (HTTPResponse) async throws -> Void
    private let _send: (HTTPResponse) async throws -> ResponseWriter

    public init(
        send: @escaping (HTTPResponse) async throws -> ResponseWriter,
        sendInformational: @escaping (HTTPResponse) async throws -> Void
    ) {
        self._send = send
        self._sendInformational = sendInformational
    }

    /// Send the given `HTTPResponse` and get back a `ResponseWriter` to which to write a response body and trailers.
    /// - Parameter response: The final `HTTPResponse` to send back to the client.
    /// - Returns: The `ResponseWriter` to which to write a response body and trailers.
    /// - Important: Note this method is consuming: after you send this response, you won't be able to send any more responses.
    ///             If you need to send an informational (1xx) response, use ``sendInformational(_:)`` instead.
    consuming public func send(_ response: HTTPResponse) async throws -> ResponseWriter {
        precondition(response.status.kind != .informational)
        return try await self._send(response)
    }

    /// Send the given informational (1xx) response.
    /// - Parameter response: An informational `HTTPResponse` to send back to the client.
    public func sendInformational(_ response: HTTPResponse) async throws {
        precondition(response.status.kind == .informational)
        return try await _sendInformational(response)
    }
}

@available(*, unavailable)
extension HTTPResponseSender: Sendable {}
