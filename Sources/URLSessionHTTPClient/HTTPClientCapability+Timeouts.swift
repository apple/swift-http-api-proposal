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
    /// A protocol for specifying timeouts for HTTP requests.
    public protocol Timeouts: RequestOptions {
        /// Timeout indicating how long a request should wait for additional data to arrive before giving up.
        var requestTimeout: Duration? { get set }
        /// Timeout indicating how long to wait for an entire resource to transfer before giving up.
        var resourceTimeout: Duration? { get set }
    }
}
