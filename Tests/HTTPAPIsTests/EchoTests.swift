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
        try await self.serve { request, requestContext, reader, responseSender in
            let writer = try await responseSender.send(.init(status: .ok))
            try await reader.pipe(into: writer)
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
                body: .restartable { writer in
                    var body = UniqueArray<UInt8>.init(copying: "Hello".utf8)
                    try await writer.finish(
                        copying: &body,
                        trailers: HTTPFields([.init(name: .date, value: "test")])
                    )
                }
            ) { (response: HTTPResponse, reader: consuming TestClientAndServer.AsyncChannelBodyReader) in
                #expect(response.status == .ok)
                var responseBody = UniqueArray<UInt8>(minimumCapacity: 100)
                let trailers = try await reader.collect(into: &responseBody)
                let isEqual = responseBody == UniqueArray(copying: "Hello".utf8)
                #expect(isEqual)
                #expect(trailers == HTTPFields([.init(name: .date, value: "test")]))
            }

            group.cancelAll()
        }
    }
}
