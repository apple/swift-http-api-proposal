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

// We are using an exported import here since we don't want developers
// to have to import both this module and the HTTPAPIs module.
@_exported public import HTTPAPIs

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public var httpClient: some HTTPClient {
    #if canImport(Darwin)
    HTTPClientURLSession.shared
    #else
    UnsupportedPlatformHTTPClient()
    #endif
}
