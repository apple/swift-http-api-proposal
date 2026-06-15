//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import NetworkTypes
import Security

@available(anyAppleOS 26.0, *)
extension TLSVersion {
    var tlsProtocolVersion: tls_protocol_version_t? {
        switch self {
        case .v1_2:
            .TLSv12
        case .v1_3:
            .TLSv13
        default:
            nil
        }
    }
}
#endif
