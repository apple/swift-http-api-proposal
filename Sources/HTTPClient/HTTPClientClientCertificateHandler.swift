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
public import Foundation
public import Security

/// A protocol that defines the interface for providing client certificates during TLS handshake.
///
/// Conform to ``HTTPClientClientCertificateHandler`` to respond to server requests for
/// client certificate authentication. When a server requires client certificate authentication,
/// the handler receives information about acceptable certificate authorities and returns
/// the appropriate client identity and certificate chain.
///
/// The `Identifiable` conformance allows a Hashable identifier for guiding connection reuse.
///
/// - SeeAlso: ``HTTPClientServerTrustHandler``
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPClientClientCertificateHandler: Identifiable {
    /// Handles a client certificate challenge from the server.
    ///
    /// This method is called during the TLS handshake when the server requests client
    /// certificate authentication. You should examine the list of acceptable certificate
    /// authorities and return an appropriate client identity and certificate chain, or
    /// return `nil` if no suitable certificate is available.
    ///
    /// - Parameter distinguishedNames: An array of distinguished names (DNs) representing
    ///   the certificate authorities that the server accepts. Each `Data` object contains
    ///   the DER-encoded distinguished name of a certificate authority. If this array is
    ///   empty, the server accepts certificates from any authority.
    ///
    /// - Returns: A tuple containing the client identity and certificate chain, or `nil`
    ///   if no suitable certificate is available:
    ///   - `SecIdentity`: The client's identity containing both the certificate and private key
    ///   - `[SecCertificate]`: The complete certificate chain, starting with intermediate
    ///     certificates and ending with the root CA certificate. This array may be empty
    ///     if only the identity certificate is needed.
    ///
    /// - Throws: An error if certificate handling fails. Throwing an error causes the
    ///   TLS handshake to fail and propagates the error to the caller.
    ///
    /// - Note: Returning `nil` indicates that the client cannot provide a certificate
    ///   matching the server's requirements. The server may allow the connection to
    ///   proceed without client authentication or may reject it, depending on its
    ///   configuration.
    func handleClientCertificateChallenge(distinguishedNames: [Data]) async throws -> (SecIdentity, [SecCertificate])?
}

#endif
