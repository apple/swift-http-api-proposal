//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP API Proposal project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public import NetworkTypes

/// A struct that defines configuration options for an HTTP client.
///
/// ``HTTPClientConfiguration`` provides settings for controlling security protocols,
/// network access policies, and other client behavior. Use this configuration to
/// customize how the HTTP client establishes connections and handles requests.
///
/// ## Example
///
/// ```swift
/// var configuration = HTTPClientConfiguration()
/// configuration.security.minimumTLSVersion = .v1_3
/// configuration.path.allowsExpensiveNetworkAccess = false
/// ```
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct HTTPClientConfiguration: Sendable {
    /// A struct that defines security-related configuration options.
    ///
    /// ``Security`` specifies TLS version requirements and other security policies
    /// for HTTP client connections.
    public struct Security: Sendable {
        /// The minimum TLS protocol version allowed for connections.
        ///
        /// Connections using TLS versions below this value are rejected.
        /// The default value is TLS 1.2.
        public var minimumTLSVersion: TLSVersion = .v1_2

        /// The maximum TLS protocol version allowed for connections.
        ///
        /// Connections using TLS versions above this value are rejected.
        /// The default value is TLS 1.3.
        public var maximumTLSVersion: TLSVersion = .v1_3

        /// Creates a security configuration with default values.
        ///
        /// The default configuration allows TLS 1.2 and TLS 1.3 connections.
        public init() {}
    }

    /// A struct that defines network path configuration options.
    ///
    /// ``Path`` specifies network access policies including constraints for
    /// expensive and limited network connections.
    public struct Path: Sendable {
        /// A Boolean value that indicates whether the client allows connections over expensive networks.
        ///
        /// When `true`, the client can establish connections over networks marked as expensive,
        /// such as cellular data or personal hotspots. When `false`, the client only uses
        /// inexpensive networks like Wi-Fi. The default value is `true`.
        public var allowsExpensiveNetworkAccess: Bool = true

        /// A Boolean value that indicates whether the client allows connections over constrained networks.
        ///
        /// When `true`, the client can establish connections over networks marked as constrained,
        /// such as networks in Low Data Mode. When `false`, the client avoids constrained networks.
        /// The default value is `true`.
        public var allowsConstrainedNetworkAccess: Bool = true

        /// Creates a network path configuration with default values.
        ///
        /// The default configuration allows both expensive and constrained network access.
        public init() {}
    }

    /// The security configuration for the HTTP client.
    ///
    /// This property controls TLS version requirements and other security policies
    /// for client connections.
    public var security: Security = .init()

    /// The network path configuration for the HTTP client.
    ///
    /// This property controls network access policies including expensive and
    /// constrained network handling.
    public var path: Path = .init()

    /// Creates an HTTP client configuration with default values.
    public init() {}
}
