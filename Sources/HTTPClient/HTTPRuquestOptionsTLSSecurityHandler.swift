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
public import Foundation
public import Security

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPRequestOptionsTLSSecurityHandler: HTTPAPIs.HTTPRequestOptions, HTTPRequestOptionsDeclarativeTLS {
    var serverTrustHandler: (any ServerTrustHandler)? { get set }
    var clientCertificateHandler: (any ClientCertificateHandler)? { get set }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol ServerTrustHandler: Identifiable {
    func evaluateServerTrust(_ trust: SecTrust) async throws -> TrustEvaluationResult
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol ClientCertificateHandler: Identifiable {
    func handleClientCertificateChallenge(distinguishedNames: [Data]) async throws -> (SecIdentity, [SecCertificate])?
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
private struct DeclarativeServerTrustHandler: ServerTrustHandler {
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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
private struct DeclarativeClientCertificateHandler: ClientCertificateHandler {
    let data: Data
    var id: Data { data }
    func handleClientCertificateChallenge(distinguishedNames: [Data]) async throws -> (SecIdentity, [SecCertificate])? {
        var items: CFArray? = nil
        let error = unsafe SecPKCS12Import(data as CFData, [kSecImportToMemoryOnly: true] as CFDictionary, &items)
        guard let items = items as [CFTypeRef]?, let identity = items.first, CFGetTypeID(identity) == SecIdentityGetTypeID() else {
            struct OSStatusError: Error {
                var code: OSStatus
            }
            throw OSStatusError(code: error)
        }
        return (identity as! SecIdentity, [])
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPRequestOptionsTLSSecurityHandler {
    public var serverTrustPolicy: TrustEvaluationPolicy {
        get {
            if let serverTrustHandler = self.serverTrustHandler {
                // Crash if it's not our built-in handler
                (serverTrustHandler as! DeclarativeServerTrustHandler).policy
            } else {
                .default
            }
        }
        set {
            if newValue != .default {
                self.serverTrustHandler = DeclarativeServerTrustHandler(policy: newValue)
            } else {
                self.serverTrustHandler = nil
            }
        }
    }

    public var clientCertificate: Data? {
        get {
            if let clientCertificateHandler = self.clientCertificateHandler {
                // Crash if it's not our built-in handler
                (clientCertificateHandler as! DeclarativeClientCertificateHandler).data
            } else {
                nil
            }
        }
        set {
            if let newValue {
                self.clientCertificateHandler = DeclarativeClientCertificateHandler(data: newValue)
            } else {
                self.clientCertificateHandler = nil
            }
        }
    }
}
#endif
