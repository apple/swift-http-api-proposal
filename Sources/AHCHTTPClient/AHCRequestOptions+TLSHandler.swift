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

public import AsyncHTTPClient
public import HTTPAPIs
import NIOSSL
import SwiftASN1
import X509

#if canImport(Security)
import Security
#endif

@available(anyAppleOS 26.0, *)
extension AsyncHTTPClient.HTTPClient {
    /// The options for the AsyncHTTPClient HTTP client implementation.
    public struct RequestOptions: HTTPClientCapability.TLSHandler {
        public var serverTrustHandler: (any HTTPClientServerTrustHandler)? = nil

        /// - Note: When AsyncHTTPClient runs on SwiftNIO SSL rather than Network.framework, it
        ///   does not surface the certificate authorities the server accepts, so the handler
        ///   receives an empty `distinguishedNames` list.
        public var clientCertificateHandler: (any HTTPClientClientCertificateHandler)? = nil

        public init() {}
    }
}

/// Identifies the verification logic of a request so that the connection pool only shares a
/// connection between requests that verify the peer identically.
@available(anyAppleOS 26.0, *)
private struct ServerTrustIdentity: Hashable, Sendable {
    var handlerID: AnyHashableSendable
    var serverHostname: String?
}

/// Identifies the client certificate selection logic of a request, so that the connection pool
/// only shares a connection between requests that would present the same certificate.
@available(anyAppleOS 26.0, *)
private struct ClientCertificateIdentity: Hashable, Sendable {
    var handlerID: AnyHashableSendable
}

/// A `Hashable & Sendable` box, so that a handler's `ID` can key the connection pool.
@available(anyAppleOS 26.0, *)
private struct AnyHashableSendable: Hashable, Sendable {
    private let base: any Hashable & Sendable

    init(_ base: any Hashable & Sendable) {
        self.base = base
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        Self.erase(lhs.base) == Self.erase(rhs.base)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(Self.erase(self.base))
    }

    private static func erase(_ value: some Hashable) -> AnyHashable {
        AnyHashable(value)
    }
}

@available(anyAppleOS 26.0, *)
extension AsyncHTTPClient.HTTPClient.RequestOptions {
    /// Applies the TLS options to `request`.
    ///
    /// The handlers become per-request callbacks and leave the client-wide TLS configuration
    /// alone.
    func apply(to request: inout HTTPClientRequest, serverHostname: String?) {
        if let certificateHandler = self.clientCertificateHandler {
            request._tlsClientCertificateHandler = _TLSClientCertificateHandler(
                identity: ClientCertificateIdentity(handlerID: AnyHashableSendable(certificateHandler.id))
            ) { challenge in
                guard
                    let (privateKey, certificateChain) =
                        try await certificateHandler.handleClientCertificateChallenge(
                            distinguishedNames: DistinguishedName.decoding(derEncoded: challenge.distinguishedNames)
                        )
                else {
                    return nil
                }
                return try _TLSClientCertificateHandler.Identity(
                    privateKey: privateKey,
                    certificateChain: certificateChain,
                    transport: challenge.transport
                )
            }
        }

        guard let trustHandler = self.serverTrustHandler else {
            return
        }

        request._tlsVerificationHandler = _TLSVerificationHandler(
            identity: ServerTrustIdentity(
                handlerID: AnyHashableSendable(trustHandler.id),
                serverHostname: serverHostname
            )
        ) { presentedCertificates in
            let certificateChain = try presentedCertificates.map { certificate in
                try Certificate(derEncoded: certificate.toDERBytes())
            }
            switch try await trustHandler.evaluateServerTrust(certificateChain: certificateChain) {
            case .allow:
                return .certificateVerified
            case .deny:
                return .failed
            case .default:
                let isTrusted = try await DefaultServerTrustEvaluation.isTrusted(
                    certificateChain: certificateChain,
                    serverHostname: serverHostname
                )
                return isTrusted ? .certificateVerified : .failed
            }
        }
    }
}

@available(anyAppleOS 26.0, *)
extension _TLSClientCertificateHandler.Identity {
    /// Converts a swift-certificates key and chain to the form `transport` consumes.
    ///
    /// Keys without a representation in that form cannot be converted: on NIOSSL, keys without a
    /// PEM encoding, such as Secure Enclave keys; on Network.framework, keys without a `SecKey`
    /// equivalent, such as Ed25519 keys.
    init(
        privateKey: Certificate.PrivateKey,
        certificateChain: [Certificate],
        transport: _TLSClientCertificateHandler.Challenge.Transport
    ) throws {
        do {
            switch transport {
            case .nioSSL:
                let certificates = try certificateChain.map { certificate in
                    var serializer = DER.Serializer()
                    try serializer.serialize(certificate)
                    return try NIOSSLCertificate(bytes: serializer.serializedBytes, format: .der)
                }
                let keyBytes = Array(try privateKey.serializeAsPEM().pemString.utf8)
                self.init(
                    certificateChain: certificates,
                    privateKey: try NIOSSLPrivateKey(bytes: keyBytes, format: .pem)
                )
            case .networkFramework:
                #if canImport(Security)
                let certificates = try certificateChain.map(SecCertificate.makeWithCertificate)
                guard let leaf = certificates.first,
                    // Returns nil if the key does not match the certificate's public key.
                    let identity = SecIdentityCreate(nil, leaf, try SecKey.makeWithPrivateKey(privateKey))
                else {
                    throw HTTPClientTLSError.couldNotSerializeClientCertificate
                }
                self.init(secIdentity: identity, certificateChain: certificates)
                #else
                throw HTTPClientTLSError.couldNotSerializeClientCertificate
                #endif
            }
        } catch {
            throw HTTPClientTLSError.couldNotSerializeClientCertificate
        }
    }
}

@available(anyAppleOS 26.0, *)
extension DistinguishedName {
    /// Decodes the DER-encoded distinguished names offered in a client certificate challenge.
    ///
    /// Names that fail to decode are dropped: a handler is better served by the subset it can
    /// understand than by a failed handshake.
    fileprivate static func decoding(derEncoded names: [[UInt8]]) -> [DistinguishedName] {
        // Binding the initializer to an explicit function type picks the `DERParseable` overload,
        // rather than the deprecated `DERImplicitlyTaggable` one Swift otherwise prefers.
        let parse: ([UInt8]) throws -> DistinguishedName = DistinguishedName.init(derEncoded:)
        return names.compactMap { try? parse($0) }
    }
}
