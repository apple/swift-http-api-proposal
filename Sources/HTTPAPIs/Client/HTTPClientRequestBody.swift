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
/// try await httpClient.perform(request: request, body: .seekable { byteOffset, writer in
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
/// try await httpClient.perform(request: request, body: .restartable { writer in
///     // Start writing contents into writer from the beginning
/// }) { response, body in
///     // Handle the response
/// }
/// ```
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPClientRequestBody<Writer>: Sendable
where Writer: ConcludingAsyncWriter & ~Copyable, Writer.Underlying.WriteElement == UInt8, Writer.FinalElement == HTTPFields?, Writer: SendableMetatype
{
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

    fileprivate enum WriteBody {
        case restartable(@Sendable (consuming Writer) async throws -> Void)
        case seekable(@Sendable (Int64, consuming Writer) async throws -> Void)
    }
    fileprivate let writeBody: WriteBody

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
    ///   - body: The closure that writes the request body using the provided writer.
    ///     - writer: The closure that writes the request body using the provided writer.
    public static func restartable(
        knownLength: Int64? = nil,
        _ body: @escaping @Sendable (consuming Writer) async throws -> Void
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
    ///   - body: The closure that writes the request body using the provided writer.
    ///     - offset: The byte offset from which to start writing the body.
    ///     - writer: The closure that writes the request body using the provided writer.
    public static func seekable(
        knownLength: Int64? = nil,
        _ body: @escaping @Sendable (Int64, consuming Writer) async throws -> Void
    ) -> Self {
        Self.init(
            knownLength: knownLength,
            writeBody: .seekable(body)
        )
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension ConcludingAsyncWriter where Self: ~Copyable & SendableMetatype, Underlying.WriteElement == UInt8, FinalElement == HTTPFields? {
    /// Write the HTTP request body from the beginning.
    /// - Parameters:
    ///   - requestBody: The HTTP client request body.
    /// - Throws: An error thrown from the body closure.
    consuming public func write(_ requestBody: HTTPClientRequestBody<Self>) async throws {
        switch requestBody.writeBody {
        case .restartable(let writeBody):
            try await writeBody(self)
        case .seekable(let writeBody):
            try await writeBody(0, self)
        }
    }

    /// Write the partial HTTP request body from the specified offset.
    /// - Precondition: The body must be seekable.
    /// - Parameters:
    ///   - requestBody: The HTTP client request body.
    ///   - offset: The offset from which to start writing the body.
    /// - Throws: An error thrown from the body closure.
    consuming public func write(_ requestBody: HTTPClientRequestBody<Self>, from offset: Int64) async throws {
        switch requestBody.writeBody {
        case .restartable:
            fatalError("Request body is not seekable")
        case .seekable(let writeBody):
            try await writeBody(offset, self)
        }
    }
}
