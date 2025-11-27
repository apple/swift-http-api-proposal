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

/// A protocol that represents an asynchronous reader that produces elements and concludes with a final value.
///
/// ``ConcludingAsyncReader`` adds functionality to asynchronous readers that need to
/// provide a conclusive element after all reads are completed. This is particularly useful
/// for streams that have meaningful completion states beyond just terminating, such as
/// HTTP responses that include headers after the body is fully read.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol ConcludingAsyncReader<Underlying, FinalElement>: ~Copyable, ~Escapable {
    /// The underlying asynchronous reader type that produces elements.
    associatedtype Underlying: AsyncReader, ~Copyable, ~Escapable

    /// The type of the final element produced after all reads are completed.
    associatedtype FinalElement

    /// Processes the underlying async reader until completion and returns both the result of processing
    /// and a final element.
    ///
    /// - Parameter body: A closure that takes the underlying `AsyncReader` and returns a value.
    /// - Returns: A tuple containing the value returned by the body closure and the final element.
    /// - Throws: Any error thrown by the body closure or encountered while processing the reader.
    ///
    /// - Note: This method consumes the concluding async reader, meaning it can only be called once on a value type.
    ///
    /// ```swift
    /// let responseReader: HTTPResponseReader = ...
    ///
    /// // Process the body while capturing the final response status
    /// let (bodyData, statusCode) = try await responseReader.consumeAndConclude { reader in
    ///     var collectedData = Data()
    ///     while let chunk = try await reader.read(body: { $0 }) {
    ///         collectedData.append(chunk)
    ///     }
    ///     return collectedData
    /// }
    /// ```
    consuming func consumeAndConclude<Return, Failure: Error>(
        body: (consuming sending Underlying) async throws(Failure) -> Return
    ) async throws(Failure) -> (Return, FinalElement)
}
