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
    /// A protocol for HTTP request options that support TLS version constraints.
    public protocol TLSVersionSelection: RequestOptions {
        /// The minimum TLS version allowed for the connection.
        var minimumTLSVersion: TLSVersion { get set }

        /// The maximum TLS version allowed for the connection.
        var maximumTLSVersion: TLSVersion { get set }
    }
}
