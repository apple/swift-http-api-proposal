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

/// An enumeration that represents the action to take when handling HTTP redirections.
///
/// ``HTTPClientRedirectionAction`` specifies whether to follow a redirect to a new location
/// or deliver the original redirect response to the caller.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public enum HTTPClientRedirectionAction: Sendable {
    /// Follows the HTTP redirection by performing the new request.
    ///
    /// The associated ``HTTPRequest`` value contains the request to perform for the redirection.
    /// The client automatically handles the redirect and processes the new response.
    case follow(HTTPRequest)

    /// Delivers the redirection response without following the redirect.
    ///
    /// When this action is taken, the client returns the original 3xx redirect response
    /// instead of automatically following it. This allows the caller to inspect the
    /// redirect response or handle it manually.
    case deliverRedirectionResponse
}
