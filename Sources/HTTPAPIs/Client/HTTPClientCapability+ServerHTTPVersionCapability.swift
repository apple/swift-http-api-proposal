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

public import NetworkTypes

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClientCapability {
    /// A protocol for HTTP request options that support specifying server HTTP version capabilities.
    ///
    /// Providing server HTTP version information allows the client to optimize
    /// connection establishment. For example, if a server is known to support HTTP/3,
    /// the client can attempt a QUIC connection directly.
    public protocol ServerHTTPVersionCapability: RequestOptions {
        /// The HTTP versions that the target server is known to support.
        ///
        /// An empty set indicates no prior knowledge of server capabilities,
        /// and the client uses its default protocol negotiation behavior.
        var serverSupportedHTTPVersions: Set<HTTPVersion> { get set }
    }
}
