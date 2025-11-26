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

/// A struct that represents a TLS protocol version.
///
/// ``TLSVersion`` provides type-safe access to supported TLS protocol versions
/// for secure network communication.
public struct TLSVersion: Sendable, Hashable {
    private let rawValue: UInt16

    private init?(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    /// The TLS 1.2 protocol version.
    ///
    /// TLS 1.2 is defined in RFC 5246 and uses protocol version 0x0303.
    public static var v1_2: TLSVersion {
        .init(rawValue: 0x0303)!
    }

    /// The TLS 1.3 protocol version.
    ///
    /// TLS 1.3 is defined in RFC 8446 and uses protocol version 0x0304.
    public static var v1_3: TLSVersion {
        .init(rawValue: 0x0304)!
    }
}
