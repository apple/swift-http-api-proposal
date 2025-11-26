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

// swift-format-ignore: AmbiguousTrailingClosureOverload
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension AsyncReader where Self: ~Copyable, Self: ~Escapable {
    /// Iterates over all elements from the reader, executing the provided body for each span.
    ///
    /// This method continuously reads elements from the async reader until the stream ends,
    /// executing the provided closure for each span of elements read. The iteration terminates
    /// when the reader produces an empty span, indicating the end of the stream.
    ///
    /// - Parameter body: An asynchronous closure that processes each span of elements read
    ///   from the stream. The closure receives a `Span<ReadElement>` for each read operation.
    ///
    /// - Throws: An `EitherError` containing either a `ReadFailure` from the read operation
    ///   or a `Failure` from the body closure.
    ///
    /// ## Example
    ///
    /// ```swift
    /// var fileReader: FileAsyncReader = ...
    ///
    /// // Process each chunk of data from the file
    /// try await fileReader.forEach { chunk in
    ///     print("Processing \(chunk.count) elements")
    ///     // Process the chunk
    /// }
    /// ```
    public consuming func forEach<Failure: Error>(
        body: (consuming Span<ReadElement>) async throws(Failure) -> Void
    ) async throws(EitherError<ReadFailure, Failure>) {
        var shouldContinue = true
        while shouldContinue {
            try await self.read(maximumCount: nil) { (next) throws(Failure) -> Void in
                guard next.count > 0 else {
                    shouldContinue = false
                    return
                }

                try await body(next)
            }
        }
    }

    /// Iterates over all elements from the reader, executing the provided body for each span.
    ///
    /// This method continuously reads elements from the async reader until the stream ends,
    /// executing the provided closure for each span of elements read. The iteration terminates
    /// when the reader produces an empty span, indicating the end of the stream.
    ///
    /// - Parameter body: An asynchronous closure that processes each span of elements read
    ///   from the stream. The closure receives a `Span<ReadElement>` for each read operation.
    ///
    /// - Throws: An error of type `Failure` from the body closure. Since this reader never fails,
    ///   only the body closure can throw errors.
    ///
    /// ## Example
    ///
    /// ```swift
    /// var fileReader: FileAsyncReader = ...
    ///
    /// // Process each chunk of data from the file
    /// try await fileReader.forEach { chunk in
    ///     print("Processing \(chunk.count) elements")
    ///     // Process the chunk
    /// }
    /// ```
    public consuming func forEach<Failure: Error>(
        body: (consuming Span<ReadElement>) async throws(Failure) -> Void
    ) async throws(Failure) where ReadFailure == Never {
        var shouldContinue = true
        while shouldContinue {
            do {
                try await self.read(maximumCount: nil) { (next) throws(Failure) -> Void in
                    guard next.count > 0 else {
                        shouldContinue = false
                        return
                    }

                    try await body(next)
                }
            } catch {
                switch error {
                case .first:
                    fatalError()
                case .second(let error):
                    throw error
                }
            }
        }
    }
}
