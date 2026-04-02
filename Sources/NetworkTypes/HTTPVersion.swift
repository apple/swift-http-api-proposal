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

/// An enumeration that represents an HTTP protocol version.
///
/// ``HTTPVersion`` provides type-safe access to supported HTTP protocol versions,
/// allowing clients and servers to communicate version capabilities.
public enum HTTPVersion: UInt8, Sendable, Hashable {
    /// HTTP/1.
    ///
    /// HTTP/1 is defined in RFC 9112.
    case http1 = 1

    /// HTTP/2.
    ///
    /// HTTP/2 is defined in RFC 9113.
    case http2 = 2

    /// HTTP/3.
    ///
    /// HTTP/3 is defined in RFC 9114 and operates over QUIC.
    case http3 = 3
}
