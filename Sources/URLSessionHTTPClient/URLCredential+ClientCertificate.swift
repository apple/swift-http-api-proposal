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

#if canImport(Darwin)
import Foundation
import HTTPAPIs
import Security
import X509

@available(anyAppleOS 26.0, *)
extension URLCredential {
    /// Creates a client certificate credential from a swift-certificates key and chain.
    ///
    /// - Parameters:
    ///   - privateKey: The private key for the leaf certificate. Ed25519, Secure Enclave, and
    ///     custom keys have no `SecKey` representation and cause this initializer to throw.
    ///   - certificateChain: The client certificate chain, starting with the leaf.
    convenience init(privateKey: Certificate.PrivateKey, certificateChain: [Certificate]) throws {
        guard let leaf = certificateChain.first else {
            throw TLSHandlerError.couldNotSerializeClientCertificate
        }
        let secKey = try SecKey.makeWithPrivateKey(privateKey)
        let leafCertificate = try SecCertificate.makeWithCertificate(leaf)
        // Returns nil if the key does not match the certificate's public key.
        guard let identity = SecIdentityCreate(nil, leafCertificate, secKey) else {
            throw TLSHandlerError.couldNotSerializeClientCertificate
        }
        // The leaf travels inside the identity, so only the intermediates go here.
        let intermediates = try certificateChain.dropFirst().map(SecCertificate.makeWithCertificate)
        self.init(
            identity: identity,
            // CFNetwork indexes this array without checking, so an empty one is a crash rather
            // than a no-op: pass nil when there are no intermediates.
            certificates: intermediates.isEmpty ? nil : intermediates,
            persistence: .none
        )
    }
}
#endif
