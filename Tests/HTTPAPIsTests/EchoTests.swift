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

import BasicContainers
import Foundation
import HTTPAPIs
import Testing

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension TestClientAndServer {
    func echo() async throws {
        try await self.serve { request, requestContext, requestBodyAndTrailers, responseSender in
            // Needed since we are lacking call-once closures
            var requestBodyAndTrailers = Optional(requestBodyAndTrailers)
            let responseBodyAndTrailers = try await responseSender.send(.init(status: .ok))

            try await responseBodyAndTrailers.produceAndConclude { responseBody in
                // Needed since we are lacking call-once closures
                var responseBody = responseBody
                return try await requestBodyAndTrailers.take()!.consumeAndConclude { reader in
                    var reader: RequestConcludingReader.Underlying? = consume reader
                    try await responseBody.write(reader.take()!)
                }
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
            let client = clientAndServer
            try await client.perform(
                request: request,
                body: .restartable { (requestBody: consuming TestClientAndServer.RequestWriter) async throws -> HTTPFields? in
                    try await requestBody.write("Hello".utf8.span)
                    return HTTPFields([.init(name: .date, value: "test")])
                }
            ) { response, responseBodyAndTrailers in
                #expect(response.status == .ok)
                let (response, trailers) = try await responseBodyAndTrailers.consumeAndConclude { responseBody in
                    var responseBody = responseBody
                    return try await responseBody.collect(upTo: 100) { span in
                        String(bytes: Array(span), encoding: .utf8)
                    }
                }
                #expect(response == "Hello")
                #expect(trailers == HTTPFields([.init(name: .date, value: "test")]))
            }

            group.cancelAll()
        }
    }
}
