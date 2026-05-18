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

import AsyncStreaming

/// A type that represents the body of an HTTP client request.
///
/// ``HTTPClientRequestBody`` wraps a closure that encapsulates the logic
/// to write a request body. It also contains extra hints and inputs to inform
/// the custom request body writing.
///
/// ## Usage
///
/// ### Seekable bodies
///
/// If the source of the request body bytes can be not only restarted from the beginning,
/// but even restarted from an arbitrary offset, prefer to create a seekable body.
///
/// A seekable body allows the HTTP client to support resumable uploads.
///
/// ```swift
/// try await HTTP.perform(request: request, body: .seekable { byteOffset, sender in
///     // Inspect byteOffset and use the sender to send body and trailers
///     try await sender.send(body: ..., trailers: nil)
/// }) { response, body in
///     // Handle the response
/// }
/// ```
///
/// ### Restartable bodies
///
/// If the source of the request body bytes cannot be restarted from an arbitrary offset, but
/// can be restarted from the beginning, use a restartable body.
///
/// A restartable body allows the HTTP client to handle redirects and retries.
///
/// ```swift
/// try await HTTP.perform(request: request, body: .restartable { sender in
///     // Use the sender to send body and trailers from the beginning
///     try await sender.send(body: ..., trailers: nil)
/// }) { response, body in
///     // Handle the response
/// }
/// ```
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPClientRequestBody<Sender: HTTPRequestSender & ~Copyable>: Sendable
where Sender: SendableMetatype, Sender.Writer: ~Copyable {
    /// The body can be asked to restart writing from an arbitrary offset.
    public var isSeekable: Bool {
        switch self.writeBody {
        case .restartable:
            false
        case .seekable:
            true
        }
    }

    /// The length of the body is known upfront and can be specified in
    /// the `Content-Length` header field.
    public let knownLength: Int64?

    private enum WriteBody {
        case restartable(@Sendable (consuming sending Sender) async throws -> Void)
        case seekable(@Sendable (Int64, consuming sending Sender) async throws -> Void)
    }
    private let writeBody: WriteBody

    /// Requests the body to be written into the sender.
    /// - Parameters:
    ///   - sender: The destination into which to write the body.
    /// - Throws: An error thrown from the body closure.
    public func produce(into sender: consuming sending Sender) async throws {
        switch self.writeBody {
        case .restartable(let writeBody):
            try await writeBody(sender)
        case .seekable(let writeBody):
            try await writeBody(0, sender)
        }
    }

    /// Requests the partial body at the specified offset to be written into the sender.
    /// - Precondition: The body must be seekable.
    /// - Parameters:
    ///   - offset: The offset from which to start writing the body.
    ///   - sender: The destination into which to write the body.
    /// - Throws: An error thrown from the body closure.
    public func produce(offset: Int64, into sender: consuming sending Sender) async throws {
        switch self.writeBody {
        case .restartable:
            fatalError("Request body is not seekable")
        case .seekable(let writeBody):
            try await writeBody(offset, sender)
        }
    }

    /// A restartable request body that can be replayed from the beginning.
    ///
    /// Use this case when the client may need to retry or follow redirects with
    /// the same request body. The closure receives a sender and streams the entire
    /// body content. The closure may be called multiple times if the request needs
    /// to be retried.
    ///
    /// - Parameters:
    ///   - knownLength: The length of the body is known upfront and can be specified in
    ///     the `content-length` header field.
    ///   - body: The closure that writes the request body using the provided sender.
    ///     - sender: The sender used to write body and trailers.
    public static func restartable(
        knownLength: Int64? = nil,
        _ body: @escaping @Sendable (consuming sending Sender) async throws -> Void
    ) -> Self {
        Self.init(
            knownLength: knownLength,
            writeBody: .restartable(body)
        )
    }

    /// A seekable request body that supports resuming from a specific byte offset.
    ///
    /// Use this case for resumable uploads where the client can start streaming
    /// from a specific position in the body. The closure receives an offset indicating
    /// where to begin writing and a sender for streaming the body content.
    ///
    /// - Parameters:
    ///   - knownLength: The length of the body is known upfront and can be specified in
    ///     the `content-length` header field.
    ///   - body: The closure that writes the request body using the provided sender.
    ///     - offset: The byte offset from which to start writing the body.
    ///     - sender: The sender used to write body and trailers.
    public static func seekable(
        knownLength: Int64? = nil,
        _ body: @escaping @Sendable (Int64, consuming sending Sender) async throws -> Void
    ) -> Self {
        Self.init(
            knownLength: knownLength,
            writeBody: .seekable(body)
        )
    }

    private init(knownLength: Int64?, writeBody: WriteBody) {
        self.knownLength = knownLength
        self.writeBody = writeBody
    }

    package init<OtherSender: ~Copyable>(
        other: HTTPClientRequestBody<OtherSender>,
        transform: @escaping @Sendable (consuming sending Sender) -> sending OtherSender
    )
    where OtherSender: SendableMetatype, OtherSender.Writer: ~Copyable {
        self.knownLength = other.knownLength
        self.writeBody =
            switch other.writeBody {
            case .restartable(let writeBody):
                .restartable { sender in
                    try await writeBody(transform(sender))
                }
            case .seekable(let writeBody):
                .seekable { offset, sender in
                    try await writeBody(offset, transform(sender))
                }
            }
    }
}
