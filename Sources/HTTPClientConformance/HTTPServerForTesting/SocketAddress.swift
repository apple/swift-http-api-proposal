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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension NIOHTTPServer {
    /// Represents an IPv4 address.
    public struct IPv4: Hashable, Sendable {
        /// The resolved host address.
        public var host: String
        /// The port to connect to.
        public var port: Int

        /// Creates a new IPv4 address.
        ///
        /// - Parameters:
        ///   - host: Resolved host address.
        ///   - port: Port to connect to.
        public init(host: String, port: Int) {
            self.host = host
            self.port = port
        }
    }

    /// Represents an IPv6 address.
    public struct IPv6: Hashable, Sendable {
        /// The resolved host address.
        public var host: String
        /// The port to connect to.
        public var port: Int

        /// Creates a new IPv6 address.
        ///
        /// - Parameters:
        ///   - host: Resolved host address.
        ///   - port: Port to connect to.
        public init(host: String, port: Int) {
            self.host = host
            self.port = port
        }
    }

    /// An address to which a socket may connect or bind to.
    public struct SocketAddress: Hashable, Sendable {
        enum Base: Hashable, Sendable {
            case ipv4(IPv4)
            case ipv6(IPv6)
        }

        let base: Base

        /// Creates an IPv4 socket address.
        public static func ipv4(host: String, port: Int) -> Self {
            Self(base: .ipv4(.init(host: host, port: port)))
        }

        /// Creates an IPv6 socket address.
        public static func ipv6(host: String, port: Int) -> Self {
            Self(base: .ipv6(.init(host: host, port: port)))
        }

        /// Returns the address as an IPv4 address, if possible.
        public var ipv4: IPv4? {
            guard case .ipv4(let address) = self.base else {
                return nil
            }

            return address
        }

        /// Returns the address as an IPv6 address, if possible.
        public var ipv6: IPv6? {
            guard case .ipv6(let address) = self.base else {
                return nil
            }

            return address
        }

        /// The ``SocketAddress``'s host.
        public var host: String {
            switch self.base {
            case .ipv4(let ipv4):
                return ipv4.host
            case .ipv6(let ipv6):
                return ipv6.host
            }
        }

        /// The ``SocketAddress``'s port.
        public var port: Int {
            switch self.base {
            case .ipv4(let ipv4):
                return ipv4.port

            case .ipv6(let ipv6):
                return ipv6.port
            }
        }
    }
}
