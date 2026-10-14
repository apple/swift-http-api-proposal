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

public import AsyncStreaming
import BasicContainers

@available(anyAppleOS 27.0, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable {
    /// Collects body bytes into the supplied buffer until end-of-stream, and
    /// returns the unwrapped trailing fields.
    ///
    /// Convenience for HTTP body readers (`FinalElement == HTTPFields?`).
    /// The buffer's initial free capacity is a hard cap: a body longer than
    /// it throws `AsyncReaderLeftOverElementsError` (wrapped in an
    /// `EitherError`, as AsyncStreaming's `collect(into:)` throws it), after
    /// the bytes that fit were appended. Truncating silently would look like
    /// a complete body without trailers.
    // TODO: This should be moved to the AsyncStreaming module
    public consuming func collect<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        into buffer: inout Buffer
    ) async throws -> HTTPFields?
    where ReadElement == UInt8, FinalElement == HTTPFields? {
        var reader = self
        var trailers: HTTPFields? = nil
        var done = false
        while !done {
            try await reader.read { (chunk: inout Self.Buffer, finalElement: consuming HTTPFields??) throws(AsyncReaderLeftOverElementsError) in
                if let finalElement {
                    trailers = finalElement
                    done = true
                }
                if chunk.count == 0 { return }
                let remaining = buffer.freeCapacity
                guard chunk.count <= remaining else {
                    let endIdx = chunk.index(chunk.startIndex, offsetBy: remaining)
                    buffer.append(moving: chunk.startIndex..<endIdx, from: &chunk)
                    throw AsyncReaderLeftOverElementsError()
                }
                buffer.append(moving: chunk.startIndex..<chunk.endIndex, from: &chunk)
            }
        }
        return trailers
    }
}
