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

import NIOSSL
import SwiftASN1
import X509

/// Some convenience helpers for converting between NIOSSL and X509 certificate and private key types.

// MARK: X509 to NIOSSL

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, visionOS 1.0, *)
extension NIOSSLCertificate {
    convenience init(_ certificate: Certificate) throws {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        try self.init(bytes: serializer.serializedBytes, format: .der)
    }
}

@available(macOS 11.0, iOS 14, tvOS 14, watchOS 7, macCatalyst 14, visionOS 1.0, *)
extension NIOSSLPrivateKey {
    convenience init(_ privateKey: Certificate.PrivateKey) throws {
        try self.init(bytes: try privateKey.serializeAsPEM().derBytes, format: .der)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, visionOS 1.0, *)
extension NIOSSLCertificateSource {
    init(_ certificate: Certificate) throws {
        self = .certificate(try NIOSSLCertificate(certificate))
    }
}

@available(macOS 11.0, iOS 14, tvOS 14, watchOS 7, macCatalyst 14, visionOS 1.0, *)
extension NIOSSLPrivateKeySource {
    init(_ privateKey: Certificate.PrivateKey) throws {
        self = .privateKey(try NIOSSLPrivateKey(privateKey))
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, visionOS 1.0, *)
extension NIOSSLTrustRoots {
    init(treatingNilAsSystemTrustRoots certificates: [Certificate]?) throws {
        if let certificates {
            self = .certificates(try certificates.map { try NIOSSLCertificate($0) })
        } else {
            self = .default
        }
    }
}

// MARK: NIOSSL to X509

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, visionOS 1.0, *)
extension Certificate {
    init(_ certificate: NIOSSLCertificate) throws {
        try self.init(derEncoded: certificate.toDERBytes())
    }
}
