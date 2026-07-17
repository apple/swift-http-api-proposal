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

/// A single capsule containing a type code and its opaque value, per RFC 9297, Section 3.2.
///
/// The Capsule protocol can be used through HTTP upgrade tokens that support it. Both
/// endpoints must agree to use it, e.g., using Extended CONNECT in H2 and H3.
///
/// A capsule is a TLV type. `value` contains opaque bytes, with a meaning defined
/// by `type`. The length is `value.count`. 
public struct Capsule: Sendable {
    /// The capsule type.
    public var type: CapsuleType

    /// The value is an opaque byte sequence.
    public var value: [UInt8]

    /// Creates a capsule from a type and a value.
    public init(type: CapsuleType, value: [UInt8]) {
        self.type = type
        self.value = value
    }
}
