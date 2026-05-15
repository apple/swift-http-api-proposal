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
/// ``HTTPClientRequestBody`` wraps a closure that writes a request body using
/// an ``HTTPBodyWriter`` provided by the client. It also carries hints such
/// as the known body length so the client can set `Content-Length` correctly.
///
/// ## Usage
///
/// ### Seekable bodies
///
/// If the source of the request body bytes can be restarted from an arbitrary
/// offset, prefer to create a seekable body. This allows the HTTP client to
/// support resumable uploads.
///
/// ```swift
/// try await client.perform(request: request, body: .seekable { offset, writer in
///     var writer = writer
///     // ... write from `offset` ...
///     try await writer.finish(trailers: nil)
/// }) { response, reader in
///     // Handle the response
/// }
/// ```
///
/// ### Restartable bodies
///
/// If the source of the request body bytes can only be restarted from the
/// beginning, use a restartable body. This allows the client to handle
/// redirects and retries.
///
/// ```swift
/// try await client.perform(request: request, body: .restartable { writer in
///     var writer = writer
///     // ... write the body ...
///     try await writer.finish(trailers: nil)
/// }) { response, reader in
///     // Handle the response
/// }
/// ```
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPClientRequestBody<Writer: HTTPBodyWriter & ~Copyable>: Sendable
where Writer: SendableMetatype {
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
        case restartable(@Sendable (consuming sending Writer) async throws -> Void)
        case seekable(@Sendable (Int64, consuming sending Writer) async throws -> Void)
    }
    private let writeBody: WriteBody

    /// Requests the body to be written into the writer.
    /// - Parameters:
    ///   - writer: The destination into which to write the body.
    /// - Throws: An error thrown from the body closure.
    public func produce(into writer: consuming sending Writer) async throws {
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
    public func produce(offset: Int64, into writer: consuming sending Writer) async throws {
        switch self.writeBody {
        case .restartable:
            fatalError("Request body is not seekable")
        case .seekable(let writeBody):
            try await writeBody(offset, writer)
        }
    }

    /// A restartable request body that can be replayed from the beginning.
    ///
    /// The closure receives a body writer and streams the entire body. The
    /// closure may be called multiple times if the request needs to be
    /// retried.
    ///
    /// - Parameters:
    ///   - knownLength: The length of the body is known upfront and can be
    ///     specified in the `content-length` header field.
    ///   - body: The closure that writes the request body using the provided
    ///     writer. The closure must call ``HTTPBodyWriter/finish(body:)``
    ///     to terminate the body.
    public static func restartable(
        knownLength: Int64? = nil,
        _ body: @escaping @Sendable (consuming sending Writer) async throws -> Void
    ) -> Self {
        Self.init(
            knownLength: knownLength,
            writeBody: .restartable(body)
        )
    }

    /// A seekable request body that supports resuming from a specific byte offset.
    ///
    /// - Parameters:
    ///   - knownLength: The length of the body is known upfront and can be
    ///     specified in the `content-length` header field.
    ///   - body: The closure that writes the request body using the provided
    ///     writer. The closure must call ``HTTPBodyWriter/finish(body:)``
    ///     to terminate the body.
    public static func seekable(
        knownLength: Int64? = nil,
        _ body: @escaping @Sendable (Int64, consuming sending Writer) async throws -> Void
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

    package init<OtherWriter: HTTPBodyWriter & ~Copyable>(
        other: HTTPClientRequestBody<OtherWriter>,
        transform: @escaping @Sendable (consuming sending Writer) -> sending OtherWriter
    )
    where OtherWriter: SendableMetatype {
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
