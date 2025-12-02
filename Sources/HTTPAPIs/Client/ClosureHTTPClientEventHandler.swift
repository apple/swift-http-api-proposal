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

/// A custom HTTP client event handler that uses closures to handle events.
///
/// `CustomHTTPClientEventHandler` provides a flexible way to implement custom logic for handling
/// HTTP redirections and TLS server trust evaluation by accepting closure-based implementations.
/// This is useful when you need to customize client behavior without creating a full conforming type.
///
/// ## Example
///
/// ```swift
/// let eventHandler = CustomHTTPClientEventHandler(
///     handleRedicretion: { response, newRequest in
///         // Custom redirection logic
///         if response.status == .movedPermanently {
///             return .follow
///         }
///         return .deliver
///     },
///     handleServerTrust: { trust in
///         // Custom trust evaluation
///         return .useDefaultEvaluation
///     }
/// )
/// ```
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct ClosureHTTPClientEventHandler: ~Copyable, HTTPClientEventHandler {
    private let _handleRedicretion: (HTTPResponse, HTTPRequest) async throws -> HTTPClientRedirectionAction
    #if canImport(Security)
    private let _handleServerTrust: (SecTrust) async throws -> HTTPClientTrustResult
    #endif

    #if canImport(Security)
    /// Creates a custom HTTP client event handler with the specified redirection and server trust handlers.
    ///
    /// - Parameters:
    ///   - handleRedicretion: A closure that determines how to handle HTTP redirections. The closure takes the following parameters:
    ///     - `response`: The HTTP response containing the redirect status code.
    ///     - `newRequest`: The new HTTP request that would be made if the redirect is followed.
    ///   - handleServerTrust: A closure that evaluates server trust during TLS handshake. The closure takes the following parameters:
    ///     - `trust`: The server trust object to evaluate.
    public init(
        handleRedicretion:
            @escaping (
                HTTPResponse,
                HTTPRequest
            ) async throws -> HTTPClientRedirectionAction,
        handleServerTrust:
            @escaping (
                SecTrust
            ) async throws -> HTTPClientTrustResult
    ) {
        self._handleRedicretion = handleRedicretion
        self._handleServerTrust = handleServerTrust
    }
    #else
    /// Creates a custom HTTP client event handler with the specified redirection.
    ///
    /// - Parameters:
    ///   - handleRedicretion: A closure that determines how to handle HTTP redirections. The closure takes the following parameters:
    ///     - `response`: The HTTP response containing the redirect status code.
    ///     - `newRequest`: The new HTTP request that would be made if the redirect is followed.
    public init(
        handleRedicretion:
            @escaping (
                HTTPResponse,
                HTTPRequest
            ) async throws -> HTTPClientRedirectionAction
    ) {
        self._handleRedicretion = handleRedicretion
    }
    #endif

    /// Handles HTTP redirection by delegating to the configured redirection closure.
    ///
    /// - Parameters:
    ///   - response: The HTTP response containing the redirect status code.
    ///   - newRequest: The new HTTP request that would be made if the redirect is followed.
    ///
    /// - Returns: An action indicating whether to follow the redirect or deliver the response.
    public func handleRedirection(
        response: HTTPResponse,
        newRequest: HTTPRequest
    ) async throws -> HTTPClientRedirectionAction {
        try await self._handleRedicretion(response, newRequest)
    }

    #if canImport(Security)
    /// Evaluates server trust by delegating to the configured trust evaluation closure.
    ///
    /// This method is called during the TLS handshake to determine whether the server's
    /// certificate should be trusted. The implementation delegates to the closure provided
    /// during initialization.
    ///
    /// - Parameter trust: The server trust object containing the certificate chain to evaluate.
    ///
    /// - Returns: A result indicating whether to use default evaluation, allow the connection, or deny it.
    public func handleServerTrust(
        _ trust: SecTrust
    ) async throws -> HTTPClientTrustResult {
        try await self._handleServerTrust(trust)
    }
    #endif
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension HTTPClientEventHandler where Self == ClosureHTTPClientEventHandler {
    #if canImport(Security)
    /// Creates a custom HTTP client event handler using the provided closures.
    ///
    /// This convenience factory method creates a ``CustomHTTPClientEventHandler`` instance,
    /// providing an easier API when configuring HTTP clients with custom event handling logic.
    ///
    /// - Parameters:
    ///   - handleRedicretion: A closure that determines how to handle HTTP redirections. The closure takes the following parameters:
    ///     - `response`: The HTTP response containing the redirect status code.
    ///     - `newRequest`: The new HTTP request that would be made if the redirect is followed.
    ///   - handleServerTrust: A closure that evaluates server trust during TLS handshake. The closure takes the following parameters:
    ///     - `trust`: The server trust object to evaluate.
    ///
    /// - Returns: A custom HTTP client event handler configured with the specified closures.
    public static func custom(
        handleRedicretion:
            @escaping (
                HTTPResponse,
                HTTPRequest
            ) async throws -> HTTPClientRedirectionAction = { .follow($1) },
        handleServerTrust:
            @escaping (
                SecTrust
            ) async throws -> HTTPClientTrustResult = { _ in .default }
    ) -> ClosureHTTPClientEventHandler {
        return ClosureHTTPClientEventHandler(
            handleRedicretion: handleRedicretion,
            handleServerTrust: handleServerTrust
        )
    }
    #else
    /// Creates a custom HTTP client event handler using the provided closures.
    ///
    /// This convenience factory method creates a ``CustomHTTPClientEventHandler`` instance,
    /// providing an easier API when configuring HTTP clients with custom event handling logic.
    ///
    /// - Parameters:
    ///   - handleRedicretion: A closure that determines how to handle HTTP redirections. The closure takes the following parameters:
    ///     - `response`: The HTTP response containing the redirect status code.
    ///     - `newRequest`: The new HTTP request that would be made if the redirect is followed.
    ///
    /// - Returns: A custom HTTP client event handler configured with the specified closures.
    public static func custom(
        handleRedicretion:
            @escaping (
                HTTPResponse,
                HTTPRequest
            ) async throws -> HTTPClientRedirectionAction = { .follow($1) }
    ) -> ClosureHTTPClientEventHandler {
        return ClosureHTTPClientEventHandler(
            handleRedicretion: handleRedicretion
        )
    }
    #endif
}
