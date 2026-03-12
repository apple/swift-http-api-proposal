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

/// An enumeration that represents the policy for the server trust evaluation during TLS handshakes.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public enum TrustEvaluationPolicy: Hashable {
    /// The default system policy.
    case `default`

    /// Allows valid certificates that do not cover the hostname of the current request.
    case allowNameMismatch

    /// Allow any invalid certificates.
    case allowAny
}
