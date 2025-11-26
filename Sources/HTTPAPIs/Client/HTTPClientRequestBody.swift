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

/// An enumeration that represents the body of an HTTP client request.
///
/// ``HTTPClientRequestBody`` provides two strategies for streaming request body data:
/// restartable bodies that can be replayed from the beginning for retries or redirects,
/// and seekable bodies that support resuming from a specific byte offset.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public enum HTTPClientRequestBody<Writer>: Sendable, ~Copyable
where Writer: ConcludingAsyncWriter & ~Copyable, Writer.Underlying.WriteElement == UInt8, Writer.FinalElement == HTTPFields?, Writer: SendableMetatype
{
    /// A restartable request body that can be replayed from the beginning.
    ///
    /// This case is used when the client may need to retry or follow redirects with
    /// the same request body. The closure receives a writer and streams the entire
    /// body content. The closure may be called multiple times if the request needs
    /// to be retried.
    ///
    /// - Parameter writer: The closure that writes the request body using the provided writer.
    case restartable(@Sendable (consuming Writer) async throws -> Void)

    /// A seekable request body that supports resuming from a specific byte offset.
    ///
    /// This case is used for resumable uploads where the client can start streaming
    /// from a specific position in the body. The closure receives an offset indicating
    /// where to begin writing and a writer for streaming the body content.
    ///
    /// - Parameters:
    ///   - offset: The byte offset from which to start writing the body.
    ///   - writer: The closure that writes the request body using the provided writer.
    case seekable(@Sendable (Int64, consuming Writer) async throws -> Void)
}
