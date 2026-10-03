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

/// Records the certificate chain it is shown and answers with a fixed result.
@available(anyAppleOS 26.0, *)
private final class StubTrustHandler: HTTPClientServerTrustHandler {
    let id: String
    private let result: TrustEvaluationResult
    private let observedChain = Mutex<[Certificate]?>(nil)

    init(id: String, result: TrustEvaluationResult) {
        self.id = id
        self.result = result
    }

    var chain: [Certificate]? {
        self.observedChain.withLock { $0 }
    }

    func evaluateServerTrust(certificateChain: [Certificate]) async throws -> TrustEvaluationResult {
        self.observedChain.withLock { $0 = certificateChain }
        return self.result
    }
}

/// The outcome of one request against a server presenting an untrusted self-signed certificate.
@available(anyAppleOS 26.0, *)
private struct TrustCheckOutcome {
    var succeeded: Bool
    var observedChain: [Certificate]?
    var serverCertificate: Certificate
}

/// Performs a single request against a freshly started HTTPS server.
///
/// Every check gets its own server, port, and certificate: URLSession caches accepted trust per
/// session and both clients pool connections, so reusing a server would let an earlier `allow`
/// decision mask a later `deny` or `default`.
@available(anyAppleOS 26.0, *)
private func check<Client: HTTPAPIs.HTTPClient & ~Copyable & ~Escapable>(
    _ client: inout Client,
    handler: StubTrustHandler? = nil
) async throws -> TrustCheckOutcome
where
    Client.RequestOptions: HTTPClientCapability.TLSHandler,
    Client.Reader: ~Copyable,
    Client.Writer: ~Copyable
{
    var outcome: TrustCheckOutcome?
    try await withRawHTTPSServer { port, identity in
        var options = client.defaultRequestOptions
        options.serverTrustHandler = handler

        var succeeded = false
        do {
            let url = URL(string: "https://localhost:\(port)/")!
            let (response, _) = try await client.get(url: url, options: options, collectUpTo: 1024)
            succeeded = response.status.code == 200
        } catch {
            succeeded = false
        }
        outcome = TrustCheckOutcome(
            succeeded: succeeded,
            observedChain: handler?.chain,
            serverCertificate: identity.certificate
        )
    }
    return outcome!
}

/// Exercises ``HTTPClientCapability/TLSHandler`` against servers presenting a self-signed
/// certificate that no platform trusts.
@available(anyAppleOS 26.0, *)
private func runTrustHandlerChecks<Client: HTTPAPIs.HTTPClient & ~Copyable & ~Escapable>(
    _ client: inout Client
) async throws
where
    Client.RequestOptions: HTTPClientCapability.TLSHandler,
    Client.Reader: ~Copyable,
    Client.Writer: ~Copyable
{
    // An untrusted certificate is rejected by default.
    #expect(try await check(&client).succeeded == false)

    // A handler that pins the certificate sees the chain the peer presented and can accept it,
    // even though no platform trusts it.
    let allowing = try await check(&client, handler: StubTrustHandler(id: "allow", result: .allow))
    #expect(allowing.succeeded)
    #expect(allowing.observedChain?.first == allowing.serverCertificate)

    // A handler that rejects is consulted and its verdict stands.
    //
    // Against an untrusted certificate `deny` and `default` both refuse the connection, so these
    // two checks cannot be told apart by their outcome alone. What distinguishes them from `allow`
    // above is that the same certificate succeeded there.
    let denying = try await check(&client, handler: StubTrustHandler(id: "deny", result: .deny))
    #expect(denying.succeeded == false)
    #expect(denying.observedChain?.first == denying.serverCertificate)

    // Deferring to the default evaluation still rejects the untrusted certificate.
    let deferring = try await check(&client, handler: StubTrustHandler(id: "default", result: .default))
    #expect(deferring.succeeded == false)
    #expect(deferring.observedChain?.first == deferring.serverCertificate)
}

@Suite
struct TLSHandlerTests {
    @Test(.enabled(if: testsEnabled))
    @available(anyAppleOS 26.0, *)
    func asyncHTTPClient() async throws {
        try await AsyncHTTPClient.HTTPClient.withHTTPClient { client in
            var client = client
            try await runTrustHandlerChecks(&client)
        }
    }

    #if canImport(Darwin)
    @Test(.enabled(if: testsEnabled))
    @available(anyAppleOS 26.0, *)
    func urlSessionHTTPClient() async throws {
        var client = URLSessionHTTPClient.shared
        try await runTrustHandlerChecks(&client)
    }
    #endif
}
