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

/// Errors returned from other network types.
@nonexhaustive
public enum NetworkTypeError: Error {
    /// A input value exceeds the maximum by the specification.
    case exceedsMaximumValue

    /// A value cannot be written to a buffer because the buffer
    /// does not have sufficient capacity to hold it.
    case insufficientCapacity
}
