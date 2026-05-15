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

public import AsyncStreaming
import BasicContainers
public import ContainersPreview

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension ConcludingAsyncReader where Self: ~Copyable, Underlying: ~Copyable {
    /// Collects elements from the underlying async reader and returns both the processed result and final element.
    ///
    /// Reads elements from the underlying reader until either the accumulated count reaches `limit`
    /// or the stream ends. Any elements the reader produces beyond `limit` are discarded.
    ///
    /// - Parameters:
    ///   - limit: The maximum number of elements to collect from the underlying reader.
    ///   - body: A closure that processes the collected elements as an `InputSpan` and returns a result.
    ///
    /// - Returns: A tuple containing the result from processing the collected elements and the final element.
    ///
    /// - Throws: Any error thrown by the underlying read operations or the body closure during
    ///   the collection and processing of elements.
    public consuming func collect<Result>(
        upTo limit: Int,
        body: (consuming InputSpan<Underlying.ReadElement>) async throws -> Result
    ) async throws -> (Result, FinalElement) {
        try await self.consumeAndConclude { reader in
            var reader = reader
            var accumulated = UniqueArray<Underlying.ReadElement>()
            var eof = false
            while accumulated.count < limit && !eof {
                try await reader.read { buffer in
                    if buffer.count == 0 {
                        eof = true
                        return
                    }
                    let remainingCapacity = limit - accumulated.count
                    if buffer.count <= remainingCapacity {
                        accumulated.append(
                            moving: buffer.startIndex..<buffer.endIndex,
                            from: &buffer
                        )
                    } else {
                        let endIdx = buffer.index(buffer.startIndex, offsetBy: remainingCapacity)
                        accumulated.append(moving: buffer.startIndex..<endIdx, from: &buffer)
                        var consumer = buffer.consumeAll()
                        while consumer.next() != nil {}
                    }
                }
            }
            var consumer = accumulated.consumeAll()
            return try await body(consumer.drainNext())
        }
    }
}
