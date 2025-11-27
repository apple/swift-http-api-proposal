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
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct HTTPClientRequestBody<Writer>: Sendable, ~Copyable
where Writer: ConcludingAsyncWriter & ~Copyable, Writer.Underlying.WriteElement == UInt8, Writer.FinalElement == HTTPFields?, Writer: SendableMetatype
{
    /// Extra information about the capabilities of the request body.
    public struct Hints: Sendable {

        /// The body can be asked to restart from the beginning.
        public var isRestartable: Bool = false

        /// The body can be asked to restart writing from an arbitrary offset.
        public var isSeekable: Bool = false

        /// The length of the body is known to be the provided value.
        public var length: Int64? = nil

        /// Default hints.
        public static var `default`: Self { .init() }
    }

    /// Inputs into the body creation closure.
    public struct Inputs: Sendable {

        /// The offset from which to start writing the body.
        /// 
        /// Only bodies with ``Hints/isSeekable`` set to true are expected to respect
        /// the provided offset.
        public var offset: Int64 = 0

        /// Default inputs.
        public static var `default`: Self { .init() }
    }

    /// Extra information about the capabilities of the request body.
    public let hints: Hints

    /// The underlying logic for writing the request obdy.
    private let writeBody: @Sendable (Inputs, consuming Writer) async throws -> Void

    /// Creates a new body.
    /// - Parameters:
    ///   - hints: Extra information about the capabilities of the request body.
    ///   - writeBody: The closure that writes the request body into the writer.
    public init(
        hints: Hints, 
        writeBody: @escaping @Sendable (Inputs, consuming Writer) async throws -> Void
    ) {
        self.hints = hints
        self.writeBody = writeBody
    }

    /// Requests the body to be written into the writer.
    /// - Parameters:
    ///   - inputs: Inputs into the body creation closure.
    ///   - writer: The destination into which to write the body.
    /// - Throws: An error thrown from the body closure.
    public func write(inputs: Inputs, writer: consuming Writer) async throws {
        try await writeBody(inputs, writer)
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
    /// - Parameter body: The closure that writes the request body using the provided writer.
    public static func restartable(
        _ body: @escaping @Sendable (consuming Writer) async throws -> Void
    ) -> Self {
        var hints: Hints = .default
        hints.isRestartable = true
        return Self.init(
            hints: hints,
            writeBody: { _, writer in
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
    ///   - offset: The byte offset from which to start writing the body.
    ///   - writer: The closure that writes the request body using the provided writer.
    public static func seekable(
        _ body: @escaping @Sendable (Int64, consuming Writer) async throws -> Void
    ) -> Self {
        var hints: Hints = .default
        hints.isRestartable = true
        hints.isSeekable = true
        return Self.init(
            hints: hints,
            writeBody: { inputs, writer in
                try await body(inputs.offset, writer)
            }
        )
    }
}
