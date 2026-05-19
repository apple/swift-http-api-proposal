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

/// The namespace for all protocols defining HTTP server capabilities.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public enum HTTPServerCapability {
    /// The request context protocol.
    ///
    /// Child protocols define additional context that a subset of servers provide,
    /// allowing libraries to depend on specific capabilities.
    public protocol RequestContext: ~Copyable, ~Escapable {
    }
}
