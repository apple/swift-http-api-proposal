//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import BasicContainers
import Foundation
import HTTPAPIs
import Testing

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension TestClientAndServer {
    func echo() async throws {
        try await self.serve { request, requestContext, requestReceiver, responseSender in
            // Needed since we are lacking call-once closures
            var requestReceiver = Optional(requestReceiver)

            try await responseSender.send(.init(status: .ok)) { writer in
                var writer = writer
                let (_, trailers) = try await requestReceiver.take()!.receive { reader in
                    try await writer.write(reader)
                }
                return ((), trailers)
            }
        }
    }
}

@Suite("HTTP Client and Server Tests")
struct HTTPClientAndServerTests {
    @Test("Simple echo test")
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func simpleEcho() async throws {
        let clientAndServer = TestClientAndServer()
        try await withThrowingTaskGroup { group in
            group.addTask {
                try await clientAndServer.echo()
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
                body: .restartable { sender in
                    try await sender.send(
                        body: "Hello".utf8.span,
                        trailers: HTTPFields([.init(name: .date, value: "test")])
                    )
                }
            ) { response, responseBodyAndTrailers in
                #expect(response.status == .ok)
                let (response, trailers) = try await responseBodyAndTrailers.collect(upTo: 100) { span in
                    String(copying: try UTF8Span(validating: span.span))
                }
                #expect(response == "Hello")
                #expect(trailers == HTTPFields([.init(name: .date, value: "test")]))
            }

            group.cancelAll()
        }
    }
}
