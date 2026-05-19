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

/// The namespace for all protocols defining HTTP client capabilities.
@available(anyAppleOS 26.0, *)
public enum HTTPClientCapability {
    /// The request options protocol.
    ///
    /// Child protocols define additional options that a subset of clients support,
    /// allowing libraries to depend on specific capabilities.
    public protocol RequestOptions: Sendable {
    }
}
