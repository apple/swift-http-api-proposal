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
public import NetworkTypes

/// The options for the URLSession HTTP client implementation.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct URLSessionRequestOptions:
    HTTPClientCapability.RedirectionHandler,
    HTTPClientCapability.TLSSecurityHandler,
    HTTPClientCapability.TLSVersionSelection
{
    public var redirectionHandler: (any HTTPClientRedirectionHandler)? = nil

    public var serverTrustHandler: (any HTTPClientServerTrustHandler)? = nil
    public var clientCertificateHandler: (any HTTPClientClientCertificateHandler)? = nil

    public var minimumTLSVersion: TLSVersion = .v1_2
    public var maximumTLSVersion: TLSVersion = .v1_3
    public var allowsExpensiveNetworkAccess: Bool = true
    public var allowsConstrainedNetworkAccess: Bool = true
    public var assumesHTTP3Capable: Bool = false
    public var stallTimeout: Duration? = nil

    public init() {}
}
#endif
