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

public import NetworkTypes

/// The options for the default HTTP client implementation.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPRequestOptions: HTTPClientCapability.RedirectionHandler, HTTPClientCapability.TLSVersionSelection,
    HTTPClientCapability.DeclarativePathSelection
{
    public var redirectionHandler: (any HTTPClientRedirectionHandler)? = nil

    #if canImport(Darwin)
    public var serverTrustHandler: (any HTTPClientServerTrustHandler)? = nil
    public var clientCertificateHandler: (any HTTPClientClientCertificateHandler)? = nil
    #else
    public var serverTrustPolicy: TrustEvaluationPolicy = .default
    #endif

    public var minimumTLSVersion: TLSVersion = .v1_2
    public var maximumTLSVersion: TLSVersion = .v1_3
    public var allowsExpensiveNetworkAccess: Bool = true
    public var allowsConstrainedNetworkAccess: Bool = true
}

#if canImport(Darwin)
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPRequestOptions: HTTPClientCapability.TLSSecurityHandler {}
#else
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPRequestOptions: HTTPClientCapability.DeclarativeTLS {}
#endif
