//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP API Proposal project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import Security

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClientCapability {
    /// A protocol for HTTP request options that support custom TLS callbacks.
    public protocol TLSSecurityHandler: RequestOptions, DeclarativeTLS {
        /// The server trust handler to be called during TLS handshakes.
        var serverTrustHandler: (any HTTPClientServerTrustHandler)? { get set }
        /// The client certificate handler to be called if requested during TLS handshakes.
        var clientCertificateHandler: (any HTTPClientClientCertificateHandler)? { get set }
    }

    private struct DeclarativeServerTrustHandler: HTTPClientServerTrustHandler {
        let policy: TrustEvaluationPolicy
        var id: TrustEvaluationPolicy { policy }
        func evaluateServerTrust(_ trust: SecTrust) async throws -> TrustEvaluationResult {
            switch self.policy {
            case .default:
                return .default
            case .allowNameMismatch:
                let policy = SecPolicyCreateSSL(true, nil)
                SecTrustSetPolicies(trust, policy)
                return .default
            case .allowAny:
                return .allow
            }
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClientCapability.TLSSecurityHandler {
    public var serverTrustPolicy: TrustEvaluationPolicy {
        get {
            if let serverTrustHandler = self.serverTrustHandler {
                // Crash if it's not our built-in handler
                (serverTrustHandler as! HTTPClientCapability.DeclarativeServerTrustHandler).policy
            } else {
                .default
            }
        }
        set {
            if newValue != .default {
                self.serverTrustHandler = HTTPClientCapability.DeclarativeServerTrustHandler(policy: newValue)
            } else {
                self.serverTrustHandler = nil
            }
        }
    }
}
#endif
