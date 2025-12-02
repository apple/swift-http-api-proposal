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

#if canImport(Security)
public import Security
#endif

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct DefaultHTTPClientEventHandler: ~Copyable {
    public init() {}
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension DefaultHTTPClientEventHandler: HTTPClientEventHandler {
    public func handleRedirection(
        response: HTTPResponse,
        newRequest: HTTPRequest
    ) async throws -> HTTPClientRedirectionAction {
        .follow(newRequest)
    }

    #if canImport(Security)
    public func handleServerTrust(_ trust: SecTrust) async throws -> HTTPClientTrustResult {
        .default
    }
    #endif
}
