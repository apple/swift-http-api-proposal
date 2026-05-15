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

@available(anyAppleOS 26.0, *)
extension CallerAsyncWriter
where Self: ~Copyable, Self: ~Escapable, WriteElement == UInt8, FinalElement == HTTPFields? {
    /// Concludes an HTTP body writer with no remaining buffer and the supplied
    /// trailers. Sugar over ``finish(buffer:finalElement:)``.
    // TODO: This should be moved to the AsyncStreaming module as a general purpose convenience
    public consuming func finish(trailers: HTTPFields?) async throws(WriteFailure) {
        var empty = UniqueArray<UInt8>()
        try await self.finish(buffer: &empty, finalElement: trailers)
    }
}
