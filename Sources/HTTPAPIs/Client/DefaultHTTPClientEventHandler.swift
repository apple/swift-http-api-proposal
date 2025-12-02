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

/// A default HTTP client event handler that follows redirects and uses system trust evaluation.
///
/// `DefaultHTTPClientEventHandler` provides standard behavior for HTTP client events by
/// automatically following all redirects and using the system's default TLS trust evaluation.
/// Use this handler when you don't need custom redirection or trust evaluation logic.
///
/// ## Example
///
/// ```swift
/// let configuration = HTTPClientConfiguration(
///     eventHandler: .default()
/// )
/// ```
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct DefaultHTTPClientEventHandler: HTTPClientEventHandler, ~Copyable {
    /// Creates a default HTTP client event handler.
    public init() {}
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension HTTPClientEventHandler where Self == DefaultHTTPClientEventHandler {
    /// Creates a default HTTP client event handler.
    ///
    /// This convenience factory method provides a clean API for configuring HTTP clients
    /// with standard event handling behavior that follows redirects and uses system trust evaluation.
    ///
    /// - Returns: A default HTTP client event handler.
    public static var `default`: DefaultHTTPClientEventHandler {
        return DefaultHTTPClientEventHandler()
    }
}
