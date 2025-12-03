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

#if canImport(Darwin)
public import Security
#endif

/// A protocol that defines event handling methods for HTTP client operations.
///
/// ``HTTPClientEventHandler`` allows custom handling of HTTP redirections and server
/// trust evaluations during client request processing. Conforming types can implement
/// custom logic for these events to control client behavior.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol HTTPClientEventHandler: ~Escapable, ~Copyable {
    /// Handles 3xx redirection responses received by the HTTP client.
    ///
    /// This method is called when the client receives a redirect response, allowing
    /// custom logic to determine whether to follow the redirect or deliver the
    /// redirect response to the caller.
    ///
    /// - Parameters:
    ///   - response: The 3xx HTTP response that triggered the redirection.
    ///   - newRequest: The suggested new request for following the redirection.
    ///
    /// - Returns: An ``HTTPClientRedirectionAction`` indicating whether to follow
    ///   the redirect or deliver the redirect response.
    ///
    /// - Throws: An error if the redirection handling fails.
    func handleRedirection(
        response: HTTPResponse,
        newRequest: HTTPRequest
    ) async throws -> HTTPClientRedirectionAction

    #if canImport(Darwin)
    /// Handles the server trust challenge during the TLS handshake.
    ///
    /// This method is called when the client needs to evaluate the server's certificate
    /// during TLS connection establishment. Implementations can perform custom certificate
    /// validation or trust evaluation logic.
    ///
    /// - Parameter trust: The server trust object containing the certificate chain to evaluate.
    ///
    /// - Returns: An ``HTTPClientTrustResult`` indicating whether to use default trust
    ///   evaluation, explicitly allow, or explicitly deny the connection.
    ///
    /// - Throws: An error if the trust evaluation fails.
    // TODO: Can we introduce a more cross-platform way for this?
    func handleServerTrust(_ trust: SecTrust) async throws -> HTTPClientTrustResult
    #endif
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension HTTPClientEventHandler where Self: ~Escapable, Self: ~Copyable {
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
