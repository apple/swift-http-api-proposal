//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP API Proposal project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// A protocol that defines the interface for handling HTTP redirections.
///
/// Conform to ``HTTPClientRedirectionHandler`` to customize how an HTTP client handles
/// redirect responses (3xx status codes). The handler receives the redirect response and
/// a proposed new request, then determines whether to follow the redirect or deliver
/// the redirect response to the caller.
///
/// ## Overview
///
/// HTTP clients often encounter redirect responses (such as 301, 302, 307, or 308 status codes)
/// that indicate the requested resource is available at a different location. By implementing
/// this protocol, you can control redirection behavior, enforce security policies, track
/// redirect chains, or limit the number of redirects.
///
/// ## Example Implementation
///
/// ```swift
/// struct LimitedRedirectHandler: HTTPClientRedirectionHandler {
///     let maxRedirects: Int
///     var redirectCount = 0
///
///     func handleRedirection(
///         response: HTTPResponse,
///         newRequest: HTTPRequest
///     ) async throws -> HTTPClientRedirectionAction {
///         guard redirectCount < maxRedirects else {
///             // Too many redirects; deliver the response
///             return .deliverRedirectionResponse
///         }
///
///         // Follow the redirect
///         redirectCount += 1
///         return .follow(newRequest)
///     }
/// }
/// ```
///
/// - SeeAlso: ``HTTPClientRedirectionAction``
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPClientRedirectionHandler {
    /// Handles an HTTP redirection and determines the action to take.
    ///
    /// This method is called when the HTTP client receives a redirect response (3xx status code).
    /// You can inspect the redirect response and the proposed new request, then decide whether
    /// to follow the redirect or deliver the original redirect response.
    ///
    /// - Parameters:
    ///   - response: The HTTP redirect response received from the server.
    ///   - newRequest: The proposed HTTP request for following the redirect. This request
    ///     is constructed based on the redirect response's `Location` header and the original
    ///     request.
    ///
    /// - Returns: An ``HTTPClientRedirectionAction`` that specifies whether to follow the
    ///   redirect or deliver the redirect response.
    ///
    /// - Throws: An error if redirection handling fails. Throwing an error cancels the
    ///   request and propagates the error to the caller.
    func handleRedirection(response: HTTPResponse, newRequest: HTTPRequest) async throws -> HTTPClientRedirectionAction
}
