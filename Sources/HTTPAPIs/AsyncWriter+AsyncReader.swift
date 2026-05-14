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
    /// Writes all elements from an async reader to this writer.
    ///
    /// This method consumes an async reader and writes all its elements to the underlying
    /// writer destination. It continuously reads buffers of elements from the reader and
    /// moves them into the writer until the reader stream ends.
    ///
    /// - Parameter reader: An ``AsyncReader`` providing elements to write. The reader is
    ///   consumed by this operation.
    ///
    /// - Throws: An error originating from the read or write operations.
    ///
    /// ## Example
    ///
    /// ```swift
    /// var fileWriter: FileAsyncWriter = ...
    /// let dataReader: DataAsyncReader = ...
    ///
    /// // Copy all data from reader to writer
    /// try await fileWriter.write(dataReader)
    /// ```
    #if compiler(<6.3)
    @_lifetime(self: copy self)
    #endif
    public mutating func write<Reader>(
        _ reader: consuming Reader
    ) async throws
    where
        Reader: AsyncReader & ~Copyable & ~Escapable,
        Reader.ReadElement == WriteElement
    {
        try await reader.forEachBuffer { (readBuffer: inout Reader.Buffer) in
            try await self.write { (writeBuffer: inout Self.Buffer) in
                writeBuffer.append(
                    moving: readBuffer.startIndex..<readBuffer.endIndex,
                    from: &readBuffer
                )
            }
        }
    }
}
