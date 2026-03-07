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
    /// A protocol for HTTP request options that support path selection.
    public protocol DeclarativePathSelection: RequestOptions {
        /// Allows the request to route over expensive (certain cellular and personal hotspot) networks.
        var allowsExpensiveNetworkAccess: Bool { get set }

        /// Allows the request to route over networks in Low Data Mode.
        var allowsConstrainedNetworkAccess: Bool { get set }
    }
}
