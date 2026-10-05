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

import Foundation
import HTTPAPIs
import SwiftASN1
import X509

#if canImport(Darwin)
import Security
#endif

/// The default trust evaluation used when a server trust handler returns
/// ``TrustEvaluationResult/default``.
///
/// A custom verification callback replaces *all* of the transport's verification logic, so once a
/// caller-provided handler is installed there is no way to ask the TLS stack to finish the job.
/// This type reproduces the platform's own decision instead: Security.framework on Apple platforms,
/// and swift-certificates against the system trust roots elsewhere.
@available(anyAppleOS 26.0, *)
enum DefaultServerTrustEvaluation {
    /// Whether `certificateChain` is a valid chain for `serverHostname`.
    static func isTrusted(
        certificateChain: [Certificate],
        serverHostname: String?
    ) async throws -> Bool {
        #if canImport(Darwin)
        let secCertificates = try certificateChain.map { certificate -> SecCertificate in
            let derBytes = try certificate.serializeAsPEM().derBytes
            guard let secCertificate = SecCertificateCreateWithData(nil, Data(derBytes) as CFData) else {
                throw TLSHandlerError.couldNotParseCertificateChain
            }
            return secCertificate
        }

        var trust: SecTrust?
        let policy = SecPolicyCreateSSL(true, serverHostname as CFString?)
        let status = unsafe SecTrustCreateWithCertificates(secCertificates as CFArray, policy, &trust)
        guard status == errSecSuccess, let trust else {
            throw TLSHandlerError.couldNotParseCertificateChain
        }
        return SecTrustEvaluateWithError(trust, nil)
        #else
        guard let leaf = certificateChain.first else {
            return false
        }
        var verifier = Verifier(rootCertificates: CertificateStore.systemTrustRoots) {
            RFC5280Policy(validationTime: Date())
            ServerIdentityPolicy(serverHostname: serverHostname, serverIP: nil)
        }
        switch await verifier.validate(leaf: leaf, intermediates: CertificateStore(certificateChain.dropFirst())) {
        case .validCertificate:
            return true
        case .couldNotValidate:
            return false
        }
        #endif
    }
}
