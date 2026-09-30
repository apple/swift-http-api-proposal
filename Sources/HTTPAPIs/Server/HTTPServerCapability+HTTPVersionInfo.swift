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

public import NetworkTypes

@available(anyAppleOS 26.0, *)
extension HTTPServerCapability {
    /// A capability for request contexts that expose the HTTP version used for the
    /// connection a request arrived on.
    public protocol HTTPVersionInfo: RequestContext, ~Copyable, ~Escapable {
        /// The HTTP version used for this request
        var httpVersion: HTTPVersion { get }
    }
}
