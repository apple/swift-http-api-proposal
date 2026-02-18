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

#if ServiceLifecycle
public import ServiceLifecycle

/// Conforms to the `Service` protocol from `ServiceLifecycle` to enable lifecycle management and graceful shutdown of
/// an `HTTPServer`.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPService<
    Server: HTTPServer & GracefulShutdownService,
    Handler: HTTPServerRequestHandler
>: Service
where
    Server.RequestConcludingReader == Handler.RequestReader,
    Server.ResponseConcludingWriter == Handler.ResponseWriter
{
    let server: Server
    let serverHandler: Handler

    /// - Parameters:
    ///   - server: The underlying ``HTTPServer`` instance.
    ///   - serverHandler: The request handler that `server` will use.
    public init(
        server: Server,
        serverHandler: Handler,
        onGracefulShutdown gracefulShutdownHandler: @Sendable @escaping () -> Void = {}
    ) {
        self.server = server
        self.serverHandler = serverHandler
    }

    /// Runs the HTTP server and handles graceful shutdown when signaled.
    public func run() async throws {
        try await withGracefulShutdownHandler(
            operation: {
                try await self.server.serve(handler: self.serverHandler)
            },
            onGracefulShutdown: {
                self.server.beginGracefulShutdown()
            }
        )
    }
}
#endif  // ServiceLifecycle
