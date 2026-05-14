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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension AsyncWriter where Self: ~Copyable, Self: ~Escapable {
    /// Writes the provided element to the underlying destination.
    ///
    /// This method asynchronously writes the given element to whatever destination the writer
    /// represents. The operation may complete immediately or may await resources or processing time.
    ///
    /// - Parameter element: The element to write. This typically represents a single item or a collection
    ///   of items depending on the specific writer implementation.
    ///
    /// - Throws: An error of type `WriteFailure` if the write operation cannot be completed successfully.
    ///
    /// - Note: This method requires `mutating` because writing operations often change the internal
    ///   state of the writer.
    ///
    /// ```swift
    /// var fileWriter: FileAsyncWriter = ...
    ///
    /// // Write data to a file asynchronously
    /// try await fileWriter.write(dataChunk)
    /// ```
    #if compiler(<6.3)
    @_lifetime(self: copy self)
    #endif
    public mutating func write(_ element: consuming WriteElement) async throws(WriteFailure) {
        // Since the element is ~Copyable but we don't have call-once closures
        // we need to move it into an Optional and then take it out once. This
        // also makes the below force unwrap safe.
        var opt = Optional(element)
        do {
            try await self.write { (buffer: inout Self.Buffer) in
                buffer.append(opt.take()!)
            }
        } catch {
            switch error {
            case .first(let error):
                throw error
            case .second:
                fatalError()
            }
        }
    }

    /// Writes the provided span of elements to the underlying destination.
    ///
    /// - Parameter span: The elements to write.
    ///
    /// - Throws: An error of type `WriteFailure` if the write operation cannot be completed successfully.
    #if compiler(<6.3)
    @_lifetime(self: copy self)
    #endif
    public mutating func write(_ span: Span<WriteElement>) async throws(WriteFailure)
    where WriteElement: Copyable {
        do {
            try await self.write { (buffer: inout Self.Buffer) in
                buffer.append(copying: span)
            }
        } catch {
            switch error {
            case .first(let error):
                throw error
            case .second:
                fatalError()
            }
        }
    }
}
