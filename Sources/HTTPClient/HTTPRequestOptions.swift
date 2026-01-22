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

#if !canImport(Darwin)
import FoundationEssentials
#endif

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPRequestOptions: HTTPRequestOptionsRedirectionHandler, HTTPRequestOptionsTLSVersion,
    HTTPRequestOptionsDeclarativePathSelection
{
    public var redirectionHandler: (any HTTPClientRedirectionHandler)? = nil

    #if canImport(Darwin)
    public var serverTrustHandler: (any ServerTrustHandler)? = nil
    public var clientCertificateHandler: (any ClientCertificateHandler)? = nil
    #else
    public var serverTrustPolicy: TrustEvaluationPolicy = .default
    public var clientCertificate: Data? = nil
    #endif

    public var minimumTLSVersion: TLSVersion = .v1_2
    public var maximumTLSVersion: TLSVersion = .v1_3
    public var allowsExpensiveNetworkAccess: Bool = true
    public var allowsConstrainedNetworkAccess: Bool = true

    public init() {}
}

#if canImport(Darwin)
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPRequestOptions: HTTPRequestOptionsTLSSecurityHandler {}
#else
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPRequestOptions: HTTPRequestOptionsDeclarativeTLS {}
#endif
