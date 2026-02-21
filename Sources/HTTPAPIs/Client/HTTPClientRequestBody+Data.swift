//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP API Proposal project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(FoundationEssentials)
public import struct FoundationEssentials.Data
#else
public import struct Foundation.Data
#endif

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClientRequestBody where Writer: ~Copyable {
    /// Creates a seekable request body from `Data` which does not require streaming.
    ///
    /// - Parameter data: The data to send as the request body.
    public static func data(_ data: Data) -> Self {
        var body = HTTPClientRequestBody.seekable(knownLength: Int64(data.count)) { offset, writer in
            var writer = writer
            try await writer.write(data.span.extracting(droppingFirst: Int(offset)))
            return nil
        }
        body.requiresStreaming = false
        return body
    }
}
