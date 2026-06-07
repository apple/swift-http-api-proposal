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

import BasicContainers

#if canImport(FoundationEssentials)
public import struct FoundationEssentials.Data
#else
public import struct Foundation.Data
#endif

@available(anyAppleOS 26.0, *)
extension HTTPClientRequestBody where Writer: ~Copyable {
    /// Creates a seekable request body from `Data`.
    ///
    /// - Parameter data: The data to send as the request body.
    public static func data(_ data: Data) -> Self {
        .seekable(knownLength: Int64(data.count)) { offset, writer in
            // TODO: Once data conforms to RangeReplaceableContainer we should remove this copy
            var buffer = UniqueArray<UInt8>(
                copying: data.span.extracting(droppingFirst: Int(offset))
            )
            try await writer.finish(buffer: &buffer, finalElement: nil)
        }
    }
}
