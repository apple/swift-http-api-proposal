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

/// A writer that streams HTTP body bytes and is terminated with a single
/// `finish` call carrying the optional last body chunk and trailing fields.
///
/// Refines ``AsyncWriter`` for byte streams (``WriteElement`` is `UInt8`) by
/// adding a consuming `finish` that signals end-of-body. The `finish` call
/// communicates *both* the final body chunk (if any) and the trailing
/// ``HTTPFields`` (if any) in one operation, so implementations can fuse the
/// last DATA frame with the END_STREAM signal on transports that support it
/// (HTTP/2, HTTP/3, QUIC).
///
/// Conformers must accept zero, one, or many `write(...)` calls followed by
/// exactly one `finish(...)` call. After `finish` returns, the writer is
/// consumed and no further calls are valid.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPBodyWriter: AsyncWriter, ~Copyable, ~Escapable
where WriteElement == UInt8 {
    /// Sends the final body chunk and trailing fields, and signals end-of-body
    /// to the underlying transport.
    ///
    /// The `body` closure receives an `inout Buffer` to fill with the final
    /// chunk's bytes, and returns the trailing ``HTTPFields`` to send after
    /// it. Either may be empty:
    ///
    /// - Leave the buffer empty if there is no remaining body content to emit
    ///   alongside the terminator.
    /// - Return `nil` from the closure to send no trailers; return a (possibly
    ///   empty) `HTTPFields` to send trailers.
    ///
    /// Returning trailers from the closure (rather than passing them as a
    /// separate parameter) lets the closure compute trailers based on the
    /// bytes it just wrote — for example a checksum trailer over the body
    /// content — without needing a scratch buffer.
    ///
    /// - Parameter body: A closure that fills the buffer with the final body
    ///   bytes and returns the trailing fields, if any.
    /// - Throws: An ``EitherError`` carrying either the underlying write
    ///   failure or the failure thrown by `body`.
    consuming func finish<Failure: Error>(
        body: (inout Buffer) async throws(Failure) -> HTTPFields?
    ) async throws(EitherError<WriteFailure, Failure>)
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPBodyWriter where Self: ~Copyable, Self: ~Escapable {
    /// Concludes the body with no final chunk and the given trailers (if any).
    public consuming func finish(trailers: HTTPFields? = nil) async throws(WriteFailure) {
        do {
            try await self.finish { (_: inout Buffer) async throws(Never) -> HTTPFields? in
                return trailers
            }
        } catch {
            switch error {
            case .first(let e): throw e
            case .second: fatalError()
            }
        }
    }

    /// Concludes the body by copying the contents of `buffer` into the final
    /// chunk (fused with the terminator and any trailers).
    ///
    /// `buffer` is read but not drained; the caller retains its contents.
    ///
    /// - Parameters:
    ///   - buffer: The source container whose bytes form the final chunk.
    ///   - trailers: The trailing fields to send with the terminator, if any.
    public consuming func finish<B: RangeReplaceableContainer<UInt8> & ~Copyable>(
        copying buffer: inout B,
        trailers: HTTPFields? = nil
    ) async throws(WriteFailure) {
        do {
            try await self.finish { (writerBuffer: inout Buffer) async throws(Never) -> HTTPFields? in
                writerBuffer.append(copying: buffer)
                return trailers
            }
        } catch {
            switch error {
            case .first(let e): throw e
            case .second: fatalError()
            }
        }
    }
}
