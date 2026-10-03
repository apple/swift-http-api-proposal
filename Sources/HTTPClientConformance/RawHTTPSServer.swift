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

import Crypto
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import SwiftASN1
public import X509

/// A self-signed identity for `localhost`, for exercising TLS trust evaluation.
@available(anyAppleOS 26.0, *)
public struct SelfSignedIdentity: Sendable {
    public let certificate: Certificate
    public let privateKey: Certificate.PrivateKey

    public init() throws {
        let privateKey = Certificate.PrivateKey(P256.Signing.PrivateKey())
        let name = try DistinguishedName {
            CommonName("localhost")
        }
        let now = Date()
        self.privateKey = privateKey
        self.certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: privateKey.publicKey,
            notValidBefore: now.addingTimeInterval(-60 * 60),
            notValidAfter: now.addingTimeInterval(60 * 60),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true, keyEncipherment: true))
                try ExtendedKeyUsage([.serverAuth])
                SubjectAlternativeNames([
                    .dnsName("localhost"),
                    .ipAddress(ASN1OctetString(contentBytes: [127, 0, 0, 1])),
                ])
            },
            issuerPrivateKey: privateKey
        )
    }

    fileprivate func makeServerTLSConfiguration(trustingClientRoot clientRoot: Certificate?) throws -> TLSConfiguration {
        let certificateBytes = Array(try self.certificate.serializeAsPEM().pemString.utf8)
        let privateKeyBytes = Array(try self.privateKey.serializeAsPEM().pemString.utf8)
        var configuration = TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(try NIOSSLCertificate(bytes: certificateBytes, format: .pem))],
            privateKey: .privateKey(try NIOSSLPrivateKey(bytes: privateKeyBytes, format: .pem))
        )
        configuration.applicationProtocols = ["http/1.1"]
        if let clientRoot {
            // On a server, this demands a client certificate and fails the handshake without one.
            configuration.certificateVerification = .noHostnameVerification
            let rootBytes = Array(try clientRoot.serializeAsPEM().pemString.utf8)
            configuration.trustRoots = .certificates([try NIOSSLCertificate(bytes: rootBytes, format: .pem)])
        }
        return configuration
    }
}

/// A throwaway certificate authority plus one client certificate it issued, for exercising TLS
/// client authentication.
@available(anyAppleOS 26.0, *)
public struct ClientCertificateAuthority: Sendable {
    /// The root the server is configured to trust.
    public let rootCertificate: Certificate
    /// The client leaf certificate, issued by ``rootCertificate``.
    public let clientCertificate: Certificate
    /// The key matching ``clientCertificate``.
    public let clientPrivateKey: Certificate.PrivateKey

    public init() throws {
        let now = Date()
        let rootKey = Certificate.PrivateKey(P256.Signing.PrivateKey())
        let rootName = try DistinguishedName {
            CommonName("HTTP API Proposal Test CA")
        }
        self.rootCertificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: rootKey.publicKey,
            notValidBefore: now.addingTimeInterval(-60 * 60),
            notValidAfter: now.addingTimeInterval(60 * 60),
            issuer: rootName,
            subject: rootName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
                Critical(KeyUsage(keyCertSign: true))
            },
            issuerPrivateKey: rootKey
        )

        let clientKey = Certificate.PrivateKey(P256.Signing.PrivateKey())
        self.clientPrivateKey = clientKey
        self.clientCertificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: clientKey.publicKey,
            notValidBefore: now.addingTimeInterval(-60 * 60),
            notValidAfter: now.addingTimeInterval(60 * 60),
            issuer: rootName,
            subject: try DistinguishedName { CommonName("HTTP API Proposal Test Client") },
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true))
                try ExtendedKeyUsage([.clientAuth])
            },
            issuerPrivateKey: rootKey
        )
    }
}

/// Runs an HTTPS server on `localhost` that presents a freshly minted self-signed certificate and
/// answers every request with `200 OK`.
///
/// The certificate does not chain to any trusted root, so default trust evaluation rejects it. That
/// makes the server useful for telling apart the ``TrustEvaluationResult`` cases: only a request
/// whose server trust handler returns ``TrustEvaluationResult/allow`` can talk to it.
@available(anyAppleOS 26.0, *)
public func withRawHTTPSServer(
    trustingClientRoot clientRoot: Certificate? = nil,
    perform: (_ port: Int, _ identity: SelfSignedIdentity) async throws -> Void
) async throws {
    let identity = try SelfSignedIdentity()
    let server = try await RawHTTPSServer(identity: identity, clientRoot: clientRoot)
    let port = await server.port
    try await withThrowingTaskGroup { group in
        group.addTask {
            try await server.run()
        }
        try await perform(port, identity)
        group.cancelAll()
    }
}

@available(anyAppleOS 26.0, *)
private actor RawHTTPSServer {
    private let serverChannel: NIOAsyncChannel<NIOAsyncChannel<HTTPServerRequestPart, IOData>, Never>

    var port: Int { self.serverChannel.channel.localAddress!.port! }

    init(identity: SelfSignedIdentity, clientRoot: Certificate?) async throws {
        let sslContext = try NIOSSLContext(
            configuration: identity.makeServerTLSConfiguration(trustingClientRoot: clientRoot)
        )
        self.serverChannel = try await ServerBootstrap(
            group: .singletonMultiThreadedEventLoopGroup
        )
        .bind(host: "127.0.0.1", port: 0) { channel in
            channel.eventLoop.makeCompletedFuture {
                let sync = channel.pipeline.syncOperations
                try sync.addHandler(NIOSSLServerHandler(context: sslContext))
                try sync.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)))
                return try NIOAsyncChannel<HTTPServerRequestPart, IOData>(wrappingChannelSynchronously: channel)
            }
        }
    }

    func run() async throws {
        try await self.serverChannel.executeThenClose { inbound in
            for try await httpChannel in inbound {
                do {
                    try await httpChannel.executeThenClose { inbound, outbound in
                        var iterator = inbound.makeAsyncIterator()
                        guard case .head = try await iterator.next() else { return }
                        let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
                        try await outbound.write(.byteBuffer(ByteBuffer(string: response)))
                    }
                } catch {
                    // Do not let one connection take down the entire server. Handshake failures are
                    // expected here: they are what several of the tests assert on.
                    print("HTTPS server caught error handling client: \(error)")
                }
            }
        }
    }
}
