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

/// The options for the default HTTP client implementation.
@available(anyAppleOS 26.0, *)
public struct HTTPRequestOptions: HTTPClientCapability.DeclarativeTLS {
    public var serverTrustPolicy: TrustEvaluationPolicy = .default

    public init() {}
}
