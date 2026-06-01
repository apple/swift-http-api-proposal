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

/// The namespace for all protocols defining HTTP server capabilities.
///
/// `HTTPServerCapability` groups protocols that represent optional features a server can provide.
/// Each capability protocol defines a set of properties or methods that a server's request context
/// must implement. Libraries and middleware can constrain their generic parameters to require
/// specific capabilities, enabling compile-time verification that a server supports the needed features.
///
/// ## Defining a capability
///
/// ```swift
/// extension HTTPServerCapability {
///     protocol ConnectionInfo: RequestContext {
///         var remoteAddress: String? { get }
///         var localAddress: String? { get }
///     }
/// }
/// ```
///
/// ## Using a capability in middleware or handlers
///
/// ```swift
/// func logConnection<Server: HTTPServer>(server: Server) async throws
/// where Server.RequestContext: HTTPServerCapability.ConnectionInfo {
///     try await server.serve { request, context, body, sender in
///         print("Request from: \(context.remoteAddress ?? "unknown")")
///         // ...
///     }
/// }
/// ```
@available(anyAppleOS 26.0, *)
public enum HTTPServerCapability {
    /// A protocol that all server request contexts must conform to.
    ///
    /// `RequestContext` is the base protocol for request contexts provided by HTTP servers.
    /// Servers create a context for each incoming request and pass it to the request handler.
    /// The context carries metadata about the request that isn't part of the HTTP message itself,
    /// such as connection information, routing state, or server-specific data.
    ///
    /// Child protocols (capabilities) extend `RequestContext` with additional properties that
    /// a subset of servers provide, allowing libraries to depend on specific capabilities
    /// without coupling to a concrete server implementation.
    ///
    /// ## Implementing a custom context
    ///
    /// ```swift
    /// struct MyServerContext: HTTPServerCapability.ConnectionInfo {
    ///     var remoteAddress: String?
    ///     var localAddress: String?
    /// }
    /// ```
    public protocol RequestContext: ~Copyable, ~Escapable {
    }
}
