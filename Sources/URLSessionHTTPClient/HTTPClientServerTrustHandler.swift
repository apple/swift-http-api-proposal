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

#if canImport(Darwin)
public import Security

/// A protocol that defines the interface for evaluating server trust during TLS handshake.
///
/// The `Identifiable` conformance allows a Hashable identifier for guiding connection reuse.
///
/// - Important: Be careful when overriding default trust evaluation. Allowing invalid
///   certificates can expose users to security risks. Only bypass validation for
///   development or testing purposes, or when implementing well-understood security
///   policies like certificate pinning.
///
/// - SeeAlso: ``TrustEvaluationResult``
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPClientServerTrustHandler: Identifiable {
    /// Evaluates the server's trust and determines whether to allow the connection.
    ///
    /// This method is called during the TLS handshake when the server presents its
    /// certificate. You can inspect the certificate chain and apply custom validation
    /// logic to determine whether the connection should proceed.
    ///
    /// - Parameter trust: The `SecTrust` object containing the server's certificate chain
    ///   and trust evaluation information. You can use Security framework APIs to inspect
    ///   the certificates and perform custom validation.
    ///
    /// - Returns: A ``TrustEvaluationResult`` that specifies whether to use default
    ///   validation, explicitly allow the connection, or explicitly deny it.
    ///
    /// - Throws: An error if trust evaluation fails. Throwing an error denies the connection
    ///   and propagates the error to the caller.
    func evaluateServerTrust(_ trust: SecTrust) async throws -> TrustEvaluationResult
}

#endif
