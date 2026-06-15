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
public import ContainersPreview

// TODO: This should be moved to the AsyncStreaming module
@available(anyAppleOS 26.0, *)
extension CallerAsyncWriter where Self: ~Copyable, Self: ~Escapable, WriteElement: ~Copyable {
    /// Concludes the writer with no remaining buffer and no payload, when the ``FinalElement`` is `Optional`.
    ///
    /// Equivalent to ``finish(buffer:finalElement:)`` with an empty buffer and `nil`.
    public consuming func finish<Wrapped>() async throws(WriteFailure)
    where FinalElement == Wrapped? {
        var empty = UniqueArray<WriteElement>()
        try await self.finish(buffer: &empty, finalElement: nil)
    }

    /// Concludes the writer with the supplied buffer and no payload, when the ``FinalElement`` is `Optional`.
    ///
    /// Equivalent to ``finish(buffer:finalElement:)`` with `finalElement: nil`.
    public consuming func finish<Wrapped, Buffer: RangeReplaceableContainer<WriteElement> & ~Copyable>(
        buffer: inout Buffer
    ) async throws(WriteFailure)
    where FinalElement == Wrapped?, Buffer.Element: ~Copyable {
        try await self.finish(buffer: &buffer, finalElement: nil)
    }
}
