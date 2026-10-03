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

/// An error raised while applying ``HTTPClientCapability/TLSHandler`` options to a request.
@available(anyAppleOS 26.0, *)
public struct HTTPClientTLSError: Error, Hashable, Sendable, CustomStringConvertible {
    enum Code: Hashable, Sendable {
        case couldNotParseCertificateChain
        case couldNotSerializeClientCertificate
    }

    let code: Code

    /// The certificates presented by the peer could not be decoded.
    public static let couldNotParseCertificateChain = Self(code: .couldNotParseCertificateChain)

    /// A client certificate or private key could not be encoded for the platform's TLS stack.
    public static let couldNotSerializeClientCertificate = Self(code: .couldNotSerializeClientCertificate)

    public var description: String {
        switch self.code {
        case .couldNotParseCertificateChain:
            "The certificate chain presented by the server could not be decoded."
        case .couldNotSerializeClientCertificate:
            "The client certificate or private key could not be encoded for this TLS stack."
        }
    }
}
