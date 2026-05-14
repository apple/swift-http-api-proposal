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

/// An enumeration that represents a transport protocol used to carry HTTP
/// traffic.
///
/// ``TransportVersion`` provides type-safe access to supported transport
/// protocols, allowing clients and servers to communicate transport
/// capabilities. New transports may be added in future releases, so client
/// code must handle unknown cases.
@nonexhaustive
public enum TransportVersion: Sendable, Hashable {
    /// Plaintext TCP transport.
    case tcp

    /// TCP with TLS transport.
    case tcpWithTLS

    /// QUIC transport.
    ///
    /// QUIC is defined in RFC 9000 and is the transport used by HTTP/3
    /// (RFC 9114).
    case quic
}
