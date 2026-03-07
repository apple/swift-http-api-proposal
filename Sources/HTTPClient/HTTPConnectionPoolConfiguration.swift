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

/// Configuration options for an HTTP connection pool.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPConnectionPoolConfiguration: Hashable, Sendable {
    /// The maximum number of concurrent HTTP/1.1 connections allowed per host.
    ///
    /// This limit helps prevent overwhelming a single host with too many simultaneous
    /// connections. HTTP/2 and HTTP/3 connections typically use multiplexing and are
    /// not subject to this limit.
    ///
    /// The default value is `6`.
    public var maximumConcurrentHTTP1ConnectionsPerHost: Int = 6

    public init() {}
}
