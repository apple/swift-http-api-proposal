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
import SwiftASN1
import X509

@available(anyAppleOS 26.0, *)
extension SecTrust {
    /// The certificates presented by the peer, in the order the peer presented them.
    func certificateChain() throws -> [Certificate] {
        guard let certificates = SecTrustCopyCertificateChain(self) as? [SecCertificate] else {
            throw HTTPClientTLSError.couldNotParseCertificateChain
        }
        do {
            return try certificates.map { certificate in
                let derBytes = SecCertificateCopyData(certificate) as Data
                return try Certificate(derEncoded: Array(derBytes))
            }
        } catch {
            throw HTTPClientTLSError.couldNotParseCertificateChain
        }
    }
}

@available(anyAppleOS 26.0, *)
extension DistinguishedName {
    /// Decodes the DER-encoded distinguished names offered in a client certificate challenge.
    ///
    /// Names that fail to decode are dropped: a handler is better served by the subset it can
    /// understand than by a failed handshake.
    static func decoding(derEncoded names: [Data]) -> [DistinguishedName] {
        // Binding the initializer to an explicit function type picks the `DERParseable` overload.
        // Spelled as a plain call, Swift prefers the deprecated `DERImplicitlyTaggable` one, whose
        // defaulted `withIdentifier:` argument makes it look like the better match. swift-certificates
        // works around this the same way in `DistinguishedName.derEncoded(_:)`.
        let parse: ([UInt8]) throws -> DistinguishedName = DistinguishedName.init(derEncoded:)
        return names.compactMap { try? parse(Array($0)) }
    }
}
#endif
