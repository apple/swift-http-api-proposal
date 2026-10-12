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

/// The start of a request body that a client can send along with the request
/// head, before the connection is established, for example in TLS early data
/// (RFC 8470).
///
/// A seekable ``HTTPClientRequestBody`` provides it through
/// ``HTTPClientRequestBody/earlyData``.
@available(anyAppleOS 27.0, *)
public struct HTTPEarlyData: Sendable, Hashable {
    /// The first bytes of the body.
    public var bytes: [UInt8]

    /// Whether ``bytes`` is the whole body.
    public var isComplete: Bool

    /// Creates early data from the first bytes of a body.
    /// - Parameters:
    ///   - bytes: The first bytes of the body.
    ///   - isComplete: Whether `bytes` is the whole body.
    public init(bytes: [UInt8], isComplete: Bool) {
        self.bytes = bytes
        self.isComplete = isComplete
    }
}
