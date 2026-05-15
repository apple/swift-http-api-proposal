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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClientCapability {
    /// A protocol for HTTP request options that support timeout configuration.
    public protocol Timeouts: RequestOptions {
        /// The maximum duration a request can wait for new bytes before being cancelled.
        ///
        /// This timeout applies to both connection establishment and waiting for
        /// additional data after a connection is established. A value of `nil`
        /// indicates no stall timeout is configured, and the client's default
        /// behavior applies.
        var stallTimeout: Duration? { get set }
    }
}
