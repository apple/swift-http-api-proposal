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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension ConcludingAsyncReader where Self: ~Copyable {
    /// Collects elements from the underlying async reader and returns both the processed result and final element.
    ///
    /// This method provides a convenient way to collect elements from the underlying reader while
    /// capturing both the processing result and the final element that concludes the reading operation.
    /// It combines the functionality of ``AsyncReader/collect(upTo:body:)-(_,(Span<Element>) -> Result)`` from ``AsyncReader`` with the concluding
    /// behavior of ``ConcludingAsyncReader``.
    ///
    /// - Parameters:
    ///   - limit: The maximum number of elements to collect from the underlying reader.
    ///   - body: A closure that processes the collected elements as a `Span` and returns a result.
    ///
    /// - Returns: A tuple containing the result from processing the collected elements and the final element.
    ///
    /// - Throws: Any error thrown by the underlying read operations or the body closure during
    ///   the collection and processing of elements.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let responseReader: HTTPConcludingReader = ...
    ///
    /// // Collect response data and get final headers
    /// let (processedData, finalHeaders) = try await responseReader.collect(upTo: 1024 * 1024) { span in
    ///     // Process all collected elements
    /// }
    /// ```
    public consuming func collect<Result>(
        upTo limit: Int,
        body: (Span<Underlying.ReadElement>) async throws -> Result
    ) async throws -> (Result, FinalElement) where Underlying.ReadElement: Copyable {
        try await self.consumeAndConclude { reader in
            var reader = reader
            return try await reader.collect(upTo: limit) { span in
                try await body(span)
            }
        }
    }
}
