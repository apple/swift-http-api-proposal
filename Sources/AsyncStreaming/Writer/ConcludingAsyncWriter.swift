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

/// A protocol that represents an asynchronous writer that produces a final value upon completion.
///
/// ``ConcludingAsyncWriter`` adds functionality to asynchronous writers that need to
/// provide a conclusive element after writing is complete. This is particularly useful
/// for streams that have meaningful completion states, such as HTTP response that need
/// to finalize with optional trailers.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol ConcludingAsyncWriter<Underlying, FinalElement>: ~Copyable, ~Escapable {
    /// The underlying asynchronous writer type.
    associatedtype Underlying: AsyncWriter, ~Copyable, ~Escapable

    /// The type of the final element produced after writing is complete.
    associatedtype FinalElement

    /// Allows writing to the underlying async writer and produces a final element upon completion.
    ///
    /// - Parameter body: A closure that takes the underlying writer and returns both a value and a final element.
    /// - Returns: The value returned by the body closure.
    /// - Throws: Any error thrown by the body closure or encountered while writing.
    ///
    /// - Note: This method consumes the concluding async writer, meaning it can only be called once on a value type.
    ///
    /// ```swift
    /// let responseWriter: HTTPResponseWriter = ...
    ///
    /// // Write the response body and produce a final status
    /// let result = try await responseWriter.produceAndConclude { writer in
    ///     try await writer.write(data)
    ///     return (true, trailers)
    /// }
    /// ```
    consuming func produceAndConclude<Return>(
        body: (consuming sending Underlying) async throws -> (Return, FinalElement)
    ) async throws -> Return
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension ConcludingAsyncWriter where Self: ~Copyable {
    /// Produces a final element using the underlying async writer without returning a separate value.
    ///
    /// This is a convenience method for cases where you only need to produce a final element
    /// and don't need to return any other value from the operation. It simplifies the interface
    /// when the primary goal is to generate the concluding element.
    ///
    /// - Parameter body: A closure that takes the underlying writer and returns a final element.
    ///
    /// - Throws: Any error thrown by the body closure or encountered while writing.
    ///
    /// ```swift
    /// let logWriter: LogConcludingWriter = ...
    ///
    /// // Write log entries and produce final statistics
    /// try await logWriter.produceAndConclude { writer in
    ///     for entry in logEntries {
    ///         try await writer.write(entry)
    ///     }
    ///     return LogStatistics(entriesWritten: logEntries.count)
    /// }
    /// ```
    public consuming func produceAndConclude(
        body: (consuming sending Underlying) async throws -> FinalElement
    ) async throws {
        try await self.produceAndConclude { writer in
            ((), try await body(writer))
        }
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension ConcludingAsyncWriter where Self: ~Copyable {
    /// Writes a single element to the underlying writer and concludes with a final element.
    ///
    /// This is a convenience method for simple scenarios where you need to write exactly one
    /// element and then conclude the writing operation with a final element. It provides a
    /// streamlined interface for single-write operations.
    ///
    /// - Parameter element: The element to write to the underlying writer.
    /// - Parameter finalElement: The final element to produce after writing is complete.
    ///
    /// - Throws: Any error encountered while writing the element or during the concluding operation.
    ///
    /// ```swift
    /// let responseWriter: HTTPResponseWriter = ...
    ///
    /// // Write a single response chunk and conclude with headers
    /// try await responseWriter.writeAndConclude(
    ///     element: responseData,
    ///     finalElement: responseHeaders
    /// )
    /// ```
    public consuming func writeAndConclude(
        _ element: consuming Underlying.WriteElement,
        finalElement: FinalElement
    ) async throws {
        var element = Optional.some(element)
        try await self.produceAndConclude { writer in
            var writer = writer
            try await writer.write(element.take()!)
            return finalElement
        }
    }

    /// Writes a span of elements to the underlying writer and concludes with a final element.
    ///
    /// This is a convenience method for scenarios where you need to write multiple elements
    /// from a span and then conclude the writing operation with a final element. It provides a
    /// streamlined interface for batch write operations.
    ///
    /// - Parameter span: The span of elements to write to the underlying writer.
    /// - Parameter finalElement: The final element to produce after writing is complete.
    ///
    /// - Throws: Any error encountered while writing the elements or during the concluding operation.
    ///
    /// ```swift
    /// let responseWriter: HTTPResponseWriter = ...
    ///
    /// // Write multiple response chunks and conclude with headers
    /// try await responseWriter.writeAndConclude(
    ///     dataSpan,
    ///     finalElement: responseHeaders
    /// )
    /// ```
    public consuming func writeAndConclude(
        _ span: consuming Span<Underlying.WriteElement>,
        finalElement: FinalElement
    ) async throws where Underlying.WriteElement: Copyable {
        try await self.produceAndConclude { writer in
            var writer = writer
            try await writer.write(span)
            return finalElement
        }
    }
}
