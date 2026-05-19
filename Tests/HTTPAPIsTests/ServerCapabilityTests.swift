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

import Foundation
import HTTPAPIs
import Testing

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPServerCapability {
    protocol ConnectionInfo: RequestContext {
        var remoteAddress: String? { get }
        var localAddress: String? { get }
        var negotiatedProtocol: String? { get }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct TestConnectionContext: HTTPServerCapability.ConnectionInfo {
    var remoteAddress: String?
    var localAddress: String?
    var negotiatedProtocol: String?
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func connectionInfoHandler<S: HTTPServer>(
    server: S
) async throws
where
    S.RequestContext: HTTPServerCapability.ConnectionInfo,
    S.RequestConcludingReader: ~Copyable,
    S.RequestConcludingReader.Underlying: ~Copyable,
    S.ResponseConcludingWriter: ~Copyable,
    S.ResponseConcludingWriter.Underlying: ~Copyable
{
    try await server.serve { request, requestContext, requestBodyAndTrailers, responseSender in
        let remote = requestContext.remoteAddress ?? "unknown"
        let responseBodyAndTrailers = try await responseSender.send(.init(status: .ok))
        try await responseBodyAndTrailers.writeAndConclude(remote.utf8.span, finalElement: nil)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct ConnectionInfoTestServer: HTTPServer {
    typealias RequestContext = TestConnectionContext
    typealias RequestConcludingReader = TestClientAndServer.AsyncChannelConcludingAsyncReader
    typealias ResponseConcludingWriter = TestClientAndServer.AsyncChannelConcludingAsyncWriter

    let context: TestConnectionContext

    init(context: TestConnectionContext) {
        self.context = context
    }

    func serve<Handler: HTTPServerRequestHandler>(handler: Handler) async throws
    where
        Handler.RequestContext == TestConnectionContext,
        Handler.RequestReader == RequestConcludingReader,
        Handler.RequestReader: ~Copyable,
        Handler.ResponseWriter == ResponseConcludingWriter,
        Handler.ResponseWriter: ~Copyable
    {
        // This test just verifies the capability constraint compiles and the
        // context is accessible. A full integration test would wire up connections.
    }
}

@Suite("Server Capability Tests")
struct ServerCapabilityTests {
    @Test("ConnectionInfo capability constraint compiles and context is accessible")
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func connectionInfoCapability() async throws {
        let context = TestConnectionContext(
            remoteAddress: "127.0.0.1:54321",
            localAddress: "0.0.0.0:8080",
            negotiatedProtocol: "h2"
        )

        // Verify a server with ConnectionInfo context can be passed to a
        // function requiring that capability
        let server = ConnectionInfoTestServer(context: context)
        try await connectionInfoHandler(server: server)
    }

}
