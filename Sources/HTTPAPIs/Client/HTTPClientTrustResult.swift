//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP API Proposal project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
/// An enumeration that represents the action to take when evaluating server trust during TLS handshake.
///
/// ``HTTPClientTrustResult`` specifies whether to use the system's default trust evaluation,
/// explicitly allow the connection, or explicitly deny it.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public enum HTTPClientTrustResult {
    /// Uses the system's default trust evaluation for the server certificate.
    ///
    /// The system evaluates the server's certificate chain using standard trust policies
    /// and certificate validation rules.
    case `default`

    /// Allows the connection regardless of trust evaluation results.
    ///
    /// When this action is taken, the client proceeds with the connection even if
    /// the server's certificate would normally fail validation. Use with caution as
    /// this bypasses security checks.
    case allow

    /// Denies the connection regardless of trust evaluation results.
    ///
    /// When this action is taken, the client refuses the connection even if
    /// the server's certificate passes standard validation. This can be used to
    /// enforce additional security policies beyond system defaults.
    case deny
}
#endif
