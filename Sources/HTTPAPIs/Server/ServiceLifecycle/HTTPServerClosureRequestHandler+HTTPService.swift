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
import AsyncStreaming
import HTTPTypes

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPService
where Handler == HTTPServerClosureRequestHandler<Server.RequestConcludingReader, Server.ResponseConcludingWriter> {
    /// - Parameters:
    ///   - server: The underlying HTTPServer instance.
    ///   - serverHandler: The request handler closure.
    public init(
        server: Server,
        serverHandler:
            nonisolated(nonsending) @Sendable @escaping (
                _ request: HTTPRequest,
                _ requestContext: HTTPRequestContext,
                _ requestBodyAndTrailers: consuming sending Server.RequestConcludingReader,
                _ responseSender: consuming sending HTTPResponseSender<Server.ResponseConcludingWriter>
            ) async throws -> Void
    ) {
        self.server = server
        self.serverHandler = HTTPServerClosureRequestHandler(handler: serverHandler)
    }
}
#endif  // ServiceLifecycle
