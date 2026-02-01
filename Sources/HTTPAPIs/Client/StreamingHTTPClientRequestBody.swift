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

import AsyncStreaming

/// A type that represents the body of an HTTP client request.
///
/// ``HTTPClientRequestBody`` wraps a closure the encapsulates the logic
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
/// try await HTTP.perform(request: request, body: .seekable { byteOffset, writer in
///     // Inspect byteOffset and start writing contents into writer
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
/// try await HTTP.perform(request: request, body: .restartable { writer in
///     // Start writing contents into writer from the beginning
/// }) { response, body in
///     // Handle the response
/// }
/// ```
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct StreamingHTTPClientRequestBody<Writer: AsyncWriter & ~Copyable>: Sendable
where Writer.WriteElement == UInt8, Writer: SendableMetatype {
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
        case restartable(@Sendable (consuming Writer) async throws -> HTTPFields?)
        case seekable(@Sendable (Int64, consuming Writer) async throws -> HTTPFields?)
    }
    private let writeBody: WriteBody

    /// Requests the body to be written into the writer.
    /// - Parameters:
    ///   - writer: The destination into which to write the body.
    /// - Throws: An error thrown from the body closure.
    public func produce(into writer: consuming Writer) async throws -> HTTPFields? {
        switch self.writeBody {
        case .restartable(let writeBody):
            try await writeBody(writer)
        case .seekable(let writeBody):
            try await writeBody(0, writer)
        }
    }

    /// Requests the partial body at the specified offset to be written into the writer.
    /// - Precondition: The body must be seekable.
    /// - Parameters:
    ///   - offset: The offset from which to start writing the body.
    ///   - writer: The destination into which to write the body.
    /// - Throws: An error thrown from the body closure.
    public func produce(offset: Int64, into writer: consuming Writer) async throws -> HTTPFields? {
        switch self.writeBody {
        case .restartable:
            fatalError("Request body is not seekable")
        case .seekable(let writeBody):
            try await writeBody(offset, writer)
        }
    }

    /// A restartable request body that can be replayed from the beginning.
    ///
    /// This case is used when the client may need to retry or follow redirects with
    /// the same request body. The closure receives a writer and streams the entire
    /// body content. The closure may be called multiple times if the request needs
    /// to be retried.
    ///
    /// - Parameters:
    ///   - knownLength: The length of the body is known upfront and can be specified in
    ///     the `content-length` header field.
    ///   - body: The closure that writes the request body using the provided writer and
    ///     returns an optional trailer.
    ///     - writer: The closure that writes the request body using the provided writer.
    public static func restartable(
        knownLength: Int64? = nil,
        _ body: @escaping @Sendable (consuming Writer) async throws -> HTTPFields?
    ) -> Self {
        Self.init(
            knownLength: knownLength,
            writeBody: .restartable(body)
        )
    }

    /// A seekable request body that supports resuming from a specific byte offset.
    ///
    /// This case is used for resumable uploads where the client can start streaming
    /// from a specific position in the body. The closure receives an offset indicating
    /// where to begin writing and a writer for streaming the body content.
    ///
    /// - Parameters:
    ///   - knownLength: The length of the body is known upfront and can be specified in
    ///     the `content-length` header field.
    ///   - body: The closure that writes the request body using the provided writer and
    ///     returns an optional trailer.
    ///     - offset: The byte offset from which to start writing the body.
    ///     - writer: The closure that writes the request body using the provided writer.
    public static func seekable(
        knownLength: Int64? = nil,
        _ body: @escaping @Sendable (Int64, consuming Writer) async throws -> HTTPFields?
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

    package init<OtherWriter: ~Copyable>(
        other: StreamingHTTPClientRequestBody<OtherWriter>,
        transform: @escaping @Sendable (consuming Writer) -> OtherWriter
    ) {
        self.knownLength = other.knownLength
        self.writeBody =
            switch other.writeBody {
            case .restartable(let writeBody):
                .restartable { writer in
                    try await writeBody(transform(writer))
                }
            case .seekable(let writeBody):
                .seekable { offset, writer in
                    try await writeBody(offset, transform(writer))
                }
            }
    }
}
