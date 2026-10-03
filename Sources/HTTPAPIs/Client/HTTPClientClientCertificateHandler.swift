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

/// A protocol that defines the interface for providing client certificates during TLS handshake.
///
/// Conform to ``HTTPClientClientCertificateHandler`` to respond to server requests for
/// client certificate authentication. When a server requires client certificate authentication,
/// the handler receives information about acceptable certificate authorities and returns
/// the appropriate client certificate chain and private key.
///
/// The `Identifiable` conformance allows a Hashable identifier for guiding connection reuse.
///
/// - SeeAlso: ``HTTPClientServerTrustHandler``
@available(anyAppleOS 26.0, *)
public protocol HTTPClientClientCertificateHandler: Identifiable, Sendable where ID: Sendable {
    /// Handles a client certificate challenge from the server.
    ///
    /// This method is called during the TLS handshake when the server requests client
    /// certificate authentication. You should examine the list of acceptable certificate
    /// authorities and return an appropriate client certificate chain and private key, or
    /// return `nil` if no suitable certificate is available.
    ///
    /// - Parameter distinguishedNames: The distinguished names of the certificate authorities
    ///   that the server accepts. If this array is empty, the server accepts certificates from
    ///   any authority.
    ///
    /// - Returns: A tuple containing the client's private key and certificate chain, or `nil`
    ///   if no suitable certificate is available:
    ///   - `Certificate.PrivateKey`: The private key matching the leaf certificate.
    ///   - `[Certificate]`: The certificate chain, starting with the leaf certificate and
    ///     followed by any intermediate certificates.
    ///
    /// - Throws: An error if certificate handling fails. Throwing an error causes the
    ///   TLS handshake to fail and propagates the error to the caller.
    ///
    /// - Note: Returning `nil` indicates that the client cannot provide a certificate
    ///   matching the server's requirements. The server may allow the connection to
    ///   proceed without client authentication or may reject it, depending on its
    ///   configuration.
    func handleClientCertificateChallenge(
        distinguishedNames: [DistinguishedName]
    ) async throws -> (Certificate.PrivateKey, [Certificate])?
}
