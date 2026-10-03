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

import AHCHTTPClient
import AsyncHTTPClient
import Foundation
import HTTPAPIs
import HTTPClientConformance
import Synchronization
import Testing
import X509

#if canImport(Darwin)
import URLSessionHTTPClient
#endif

/// Answers a client certificate challenge with a fixed identity, recording what it was asked.
@available(anyAppleOS 26.0, *)
private final class StubClientCertificateHandler: HTTPClientClientCertificateHandler {
    let id = "test-client-certificate"
    private let authority: ClientCertificateAuthority
    private let observedNames = Mutex<[DistinguishedName]?>(nil)

    init(authority: ClientCertificateAuthority) {
        self.authority = authority
    }

    var distinguishedNames: [DistinguishedName]? {
        self.observedNames.withLock { $0 }
    }

    func handleClientCertificateChallenge(
        distinguishedNames: [DistinguishedName]
    ) async throws -> (Certificate.PrivateKey, [Certificate])? {
        self.observedNames.withLock { $0 = distinguishedNames }
        return (self.authority.clientPrivateKey, [self.authority.clientCertificate])
    }
}

/// Accepts any server certificate.
@available(anyAppleOS 26.0, *)
private struct AllowingServerTrustHandler: HTTPClientServerTrustHandler {
    let id = "allowing-server-trust"

    func evaluateServerTrust(certificateChain: [Certificate]) async throws -> TrustEvaluationResult {
        .allow
    }
}

/// Declines to provide a client certificate.
@available(anyAppleOS 26.0, *)
private struct DecliningClientCertificateHandler: HTTPClientClientCertificateHandler {
    let id = "declining-client-certificate"

    func handleClientCertificateChallenge(
        distinguishedNames: [DistinguishedName]
    ) async throws -> (Certificate.PrivateKey, [Certificate])? {
        nil
    }
}

/// Performs a single request against a fresh HTTPS server that demands a client certificate
/// issued by `authority`, and reports whether it succeeded.
@available(anyAppleOS 26.0, *)
private func requestSucceeds<Client: HTTPAPIs.HTTPClient & ~Copyable & ~Escapable>(
    _ client: inout Client,
    authority: ClientCertificateAuthority,
    configure: (inout Client.RequestOptions) -> Void
) async throws -> Bool
where
    Client.RequestOptions: HTTPClientCapability.TLSHandler,
    Client.Reader: ~Copyable,
    Client.Writer: ~Copyable
{
    var succeeded = false
    try await withRawHTTPSServer(trustingClientRoot: authority.rootCertificate) { port, _ in
        var options = client.defaultRequestOptions
        // The server's own certificate is self-signed, which is a separate concern from the
        // client certificate under test here.
        options.serverTrustHandler = AllowingServerTrustHandler()
        configure(&options)

        do {
            let url = URL(string: "https://localhost:\(port)/")!
            let (response, _) = try await client.get(url: url, options: options, collectUpTo: 1024)
            succeeded = response.status.code == 200
        } catch {
            succeeded = false
        }
    }
    return succeeded
}

/// Exercises client certificate authentication against servers that demand and verify a client
/// certificate.
///
/// Every check gets its own server and authority, so that a pooled connection authenticated by
/// one check cannot let a later one through.
@available(anyAppleOS 26.0, *)
private func runClientCertificateChecks<Client: HTTPAPIs.HTTPClient & ~Copyable & ~Escapable>(
    _ client: inout Client
) async throws
where
    Client.RequestOptions: HTTPClientCapability.TLSHandler,
    Client.Reader: ~Copyable,
    Client.Writer: ~Copyable
{
    // The control: the server refuses a client that presents no certificate. Without this, a
    // passing handshake below would not tell us the client certificate did anything.
    let declined = try await requestSucceeds(&client, authority: try ClientCertificateAuthority()) {
        $0.clientCertificateHandler = DecliningClientCertificateHandler()
    }
    #expect(declined == false)

    // A handler is consulted when the server asks, and the handshake only completes if the server
    // verified a certificate signed with the handler's key. The name list is whatever the server
    // advertised, which NIOSSL leaves empty, so only its presence is asserted.
    let authority = try ClientCertificateAuthority()
    let handler = StubClientCertificateHandler(authority: authority)
    let handled = try await requestSucceeds(&client, authority: authority) {
        $0.clientCertificateHandler = handler
    }
    #expect(handled)
    #expect(handler.distinguishedNames != nil)

    // The convenience supplies the identity upfront.
    let upfrontAuthority = try ClientCertificateAuthority()
    let upfront = try await requestSucceeds(&client, authority: upfrontAuthority) {
        $0.setClientCertificate(
            privateKey: upfrontAuthority.clientPrivateKey,
            certificateChain: [upfrontAuthority.clientCertificate]
        )
    }
    #expect(upfront)
}

@Suite
struct ClientCertificateTests {
    @Test(.enabled(if: testsEnabled))
    @available(anyAppleOS 26.0, *)
    func asyncHTTPClient() async throws {
        try await AsyncHTTPClient.HTTPClient.withHTTPClient { client in
            var client = client
            try await runClientCertificateChecks(&client)
        }
    }

    #if canImport(Darwin)
    @Test(.enabled(if: testsEnabled))
    @available(anyAppleOS 26.0, *)
    func urlSessionHTTPClient() async throws {
        var client = URLSessionHTTPClient.shared
        try await runClientCertificateChecks(&client)
    }
    #endif
}
