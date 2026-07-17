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

/// A capsule type, as defined in RFC 9297, Section 3.2.
///
/// Capsule types occupy an open 62-bit IANA registry. They define the meaning of the value carried
/// in the capsule. As an example, a `DATAGRAM` capsule (0x00, RFC 9297) simply carries the payload
/// of an HTTP datagram with meaning left to the application. In contrast, an `ADDRESS_ASSIGN`
/// capsule (0x01, RFC 9484) defines the structure of the value and the inforamtion it carries.
///
/// The capsule types defined here are not exhaustive. New standards can define new ones.
public struct CapsuleType: Sendable, Hashable {

    /// The largest representable value, `2^62 - 1`.
    static var maxRawValue: UInt64 { 0x3FFF_FFFF_FFFF_FFFF }

    /// The numeric type rawValue.
    ///
    /// Must be in the range `0 ... 2^62 - 1`.
    public var rawValue: UInt64 {
        didSet {
            precondition(rawValue <= Self.maxRawValue, "capsule type \(rawValue) exceeds the allowed maximum value")
        }
    }

    /// Creates a capsule type from its numeric rawValue.
    ///
    /// - Precondition: `rawValue` is less than or equal to ``VariableLengthInteger/max``.
    public init(_ rawValue: UInt64) {
        precondition(rawValue <= Self.maxRawValue, "capsule type \(rawValue) exceeds the variable-length integer maximum")
        self.rawValue = rawValue
    }
}

// Enable direct initialization from integer literals
extension CapsuleType: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt64) {
        self.init(value)
    }
}

extension CapsuleType {
    /// The `DATAGRAM` capsule type (RFC 9297, Section 3.5).
    public static var datagram: Self { 0x00 }

    /// The `ADDRESS_ASSIGN` capusle type (RFC 9484, Section 4.7.1).
    public static var addressAssign: Self { 0x01 }

    /// The `ADDRESS_REQUEST` capusle type (RFC 9484, Section 4.7.2).
    public static var addressRequest: Self { 0x02 }

    /// The `ROUTE_ADVERTISEMENT` capsule type (RFC 9484, Section 4.7.3).
    public static var routeAdvertisement: Self { 0x03 }
}
