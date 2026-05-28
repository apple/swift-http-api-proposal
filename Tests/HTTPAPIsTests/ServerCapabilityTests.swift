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

@available(anyAppleOS 26.0, *)
extension HTTPServerCapability {
    protocol ConnectionInfo: RequestContext {
        var remoteAddress: String? { get }
        var localAddress: String? { get }
    }
}

@available(anyAppleOS 26.0, *)
extension TestClientAndServer.HTTPRequestContext: HTTPServerCapability.ConnectionInfo {}

@available(anyAppleOS 26.0, *)
extension TestClientAndServer {
    func serveWithContextAssertions() async throws {
        try await self.serve { request, requestContext, requestBodyAndTrailers, responseSender in
            #expect(requestContext.remoteAddress == "127.0.0.1:54321")
            #expect(requestContext.localAddress == "0.0.0.0:8080")

            let responseBodyAndTrailers = try await responseSender.send(.init(status: .ok))
            try await responseBodyAndTrailers.writeAndConclude("".utf8.span, finalElement: nil)
        }
    }
}

@Suite("Server Capability Tests")
struct ServerCapabilityTests {
    @Test("RequestContext values flow through to handler")
    @available(anyAppleOS 26.0, *)
    func connectionInfoCapability() async throws {
        let clientAndServer = TestClientAndServer()
        try await withThrowingTaskGroup { group in
            group.addTask {
                try await clientAndServer.serveWithContextAssertions()
            }

            let request = HTTPRequest(
                method: .get,
                scheme: "http",
                authority: nil,
                path: nil
            )
            var client = clientAndServer
            try await client.perform(
                request: request,
                body: nil
            ) { response, responseBodyAndTrailers in
                #expect(response.status == .ok)
                _ = try await responseBodyAndTrailers.consumeAndConclude { reader in
                    var reader = reader
                    try await reader.collect(upTo: 100) { _ in }
                }
            }

            group.cancelAll()
        }
    }
}
