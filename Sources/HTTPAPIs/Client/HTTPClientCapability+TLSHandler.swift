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

@available(anyAppleOS 26.0, *)
extension HTTPClientCapability {
    /// A protocol for HTTP request options that support custom TLS callbacks.
    public protocol TLSHandler: RequestOptions {
        /// The server trust handler to be called during TLS handshakes.
        var serverTrustHandler: (any HTTPClientServerTrustHandler)? { get set }
        /// The client certificate handler to be called if requested during TLS handshakes.
        var clientCertificateHandler: (any HTTPClientClientCertificateHandler)? { get set }
    }
}

@available(anyAppleOS 26.0, *)
extension HTTPClientCapability.TLSHandler {
    /// Presents the given client certificate whenever a server asks for one.
    ///
    /// This is a convenience for setting ``clientCertificateHandler`` to a handler that always
    /// answers with the same identity, regardless of which certificate authorities the server
    /// accepts. It replaces any handler set previously.
    ///
    /// - Parameters:
    ///   - privateKey: The private key matching the leaf certificate.
    ///   - certificateChain: The certificate chain, starting with the leaf certificate and
    ///     followed by any intermediate certificates.
    public mutating func setClientCertificate(
        privateKey: Certificate.PrivateKey,
        certificateChain: [Certificate]
    ) {
        self.clientCertificateHandler = FixedClientCertificateHandler(
            privateKey: privateKey,
            certificateChain: certificateChain
        )
    }
}

/// Answers every client certificate challenge with one identity.
@available(anyAppleOS 26.0, *)
private struct FixedClientCertificateHandler: HTTPClientClientCertificateHandler {
    let privateKey: Certificate.PrivateKey
    let certificateChain: [Certificate]

    // The leaf pins down the key, so the chain alone identifies what this handler presents.
    var id: [Certificate] { self.certificateChain }

    func handleClientCertificateChallenge(
        distinguishedNames: [DistinguishedName]
    ) async throws -> (Certificate.PrivateKey, [Certificate])? {
        (self.privateKey, self.certificateChain)
    }
}
