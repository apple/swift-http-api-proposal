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
/// let body: HTTPClientRequestBody = .seekable { byteOffset, writer in
///     // Inspect byteOffset and start writing contents into writer
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
/// let body: HTTPClientRequestBody = .restartable { writer in
///     // Start writing contents into writer from the beginning
/// }
/// ```
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct HTTPClientRequestBody<Writer>: Sendable, ~Copyable
where Writer: ConcludingAsyncWriter & ~Copyable, Writer.Underlying.WriteElement == UInt8, Writer.FinalElement == HTTPFields?, Writer: SendableMetatype
{
    /// The body can be asked to restart writing from an arbitrary offset.
    public var isSeekable: Bool

    /// The length of the body is known upfront and can be specified in
    /// the `content-length` header field.
    public var knownLength: Int64?

    /// Inputs into the body creation closure.
    /// 
    /// This information is provided by the HTTP client implementation and passed with the writer.
    public struct Inputs: Sendable {

        /// The offset from which to start writing the body.
        ///
        /// Only bodies with ``Hints/isSeekable`` set to true are expected to respect
        /// the provided offset.
        public var offset: Int64

        /// Creates new inputs.
        /// - Parameter offset: The offset from which to start writing the body. Set to 0 to start from the beginning.
        public init(offset: Int64) {
            self.offset = offset
        }
    }

    /// The underlying logic for writing the request obdy.
    private let writeBody: @Sendable (Inputs, consuming Writer) async throws -> Void

    /// Creates a new body.
    /// - Parameters:
    ///   - isSeekable: The body can be asked to restart writing from an arbitrary offset.
    ///   - knownLength: The length of the body is known upfront and can be specified in
    ///     the `content-length` header field.
    ///   - writeBody: The closure that writes the request body into the writer.
    internal init(
        isSeekable: Bool,
        knownLength: Int64?,
        writeBody: @escaping @Sendable (Inputs, consuming Writer) async throws -> Void
    ) {
        self.isSeekable = isSeekable
        self.knownLength = knownLength
        self.writeBody = writeBody
    }

    /// Requests the body to be written into the writer.
    /// - Parameters:
    ///   - inputs: Inputs into the body creation closure.
    ///   - writer: The destination into which to write the body.
    /// - Throws: An error thrown from the body closure.
    public mutating func write(inputs: Inputs, writer: consuming Writer) async throws {
        try await writeBody(inputs, writer)
    }
}

/// An error type used when a restartable (non-seekable) body is asked to seek to a non-0 offset.
private enum HTTPClientRequestBodyError: Error, CustomStringConvertible {

    /// Client tried to seek a non-seekable body to a non-0 offset.
    case seekingNonSeekable

    var description: String {
        switch self {
        case .seekingNonSeekable:
            "HTTPClientRequestBody: tried to seek to a non-0 offset in a non-seekable body"
        }
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension HTTPClientRequestBody {

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
            isSeekable: false,
            knownLength: knownLength,
            writeBody: { inputs, writer in
                guard inputs.offset == 0 else {
                    throw HTTPClientRequestBodyError.seekingNonSeekable
                }
                try await body(writer)
            }
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
            isSeekable: true,
            knownLength: knownLength,
            writeBody: { inputs, writer in
                try await body(inputs.offset, writer)
            }
        )
    }
}
