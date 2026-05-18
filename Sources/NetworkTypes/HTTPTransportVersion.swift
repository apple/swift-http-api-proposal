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

/// An enumeration that represents a transport protocol used to carry HTTP
/// traffic.
///
/// ``HTTPTransportVersion`` provides type-safe access to supported transport
/// protocols, allowing clients and servers to communicate transport
/// capabilities. New transports may be added in future releases, so client
/// code must handle unknown cases.
@nonexhaustive
public enum HTTPTransportVersion: Sendable, Hashable {
    /// TCP transport.
    ///
    /// Whether TLS is layered on top is determined by the request's URL
    /// scheme (`http` vs. `https`).
    case tcp

    /// QUIC transport.
    ///
    /// QUIC is defined in RFC 9000 and is the transport used by HTTP/3
    /// (RFC 9114).
    case quic
}
