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

public import X509

/// A protocol that defines the interface for evaluating server trust during TLS handshake.
///
/// The `Identifiable` conformance allows a Hashable identifier for guiding connection reuse.
/// Two requests whose handlers have equal identifiers may share a connection, so the identifier
/// must capture everything that makes two handlers reach different decisions. The identifier is
/// `Sendable` because client implementations carry it across concurrency domains to key their
/// connection pools.
///
/// - Important: Be careful when overriding default trust evaluation. Allowing invalid
///   certificates can expose users to security risks. Only bypass validation for
///   development or testing purposes, or when implementing well-understood security
///   policies like certificate pinning.
///
/// - SeeAlso: ``TrustEvaluationResult``
@available(anyAppleOS 26.0, *)
public protocol HTTPClientServerTrustHandler: Identifiable, Sendable where ID: Sendable {
    /// Evaluates the server's certificate chain and determines whether to allow the connection.
    ///
    /// This method is called during the TLS handshake when the server presents its
    /// certificate. You can inspect the certificate chain and apply custom validation
    /// logic to determine whether the connection should proceed.
    ///
    /// - Parameter certificateChain: The certificates presented by the server, starting with
    ///   the leaf certificate. These are the certificates exactly as the peer presented them:
    ///   they have not been validated, and the chain may be incomplete or contain unrelated
    ///   certificates.
    ///
    /// - Returns: A ``TrustEvaluationResult`` that specifies whether to use default
    ///   validation, explicitly allow the connection, or explicitly deny it.
    ///
    /// - Throws: An error if trust evaluation fails. Throwing an error denies the connection
    ///   and propagates the error to the caller.
    func evaluateServerTrust(certificateChain: [Certificate]) async throws -> TrustEvaluationResult
}
