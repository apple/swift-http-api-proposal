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

import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public func withRawHTTPServer(perform: (Int) async throws -> Void) async throws {
    try await withThrowingTaskGroup {
        let server = try await RawHTTPServer()
        $0.addTask {
            try await server.run(handler: handler)
        }
        try await perform(server.port)
        $0.cancelAll()
    }
}

func linesToData(_ lines: [String]) -> Data {
    return lines.joined(separator: "\r\n").data(using: .ascii)!
}

func handler(request: HTTPRequestHead) -> Data {
    switch request.uri {
    case "/not_http":
        return "FOOBAR".data(using: .ascii)!
    case "/http_case":
        return "Http/1.1 200 OK\r\n\r\n".data(using: .ascii)!
    case "/no_reason":
        return "HTTP/1.1 200\r\n\r\n".data(using: .ascii)!
    case "/204_with_cl":
        return linesToData([
            "HTTP/1.1 204 No Content",
            "Content-Length: 1000",
            "",
            "",
        ])
    case "/304_with_cl":
        return linesToData([
            "HTTP/1.1 304 Not Modified",
            "Content-Length: 1000",
            "",
            "",
        ])
    case "/incomplete_body":
        return linesToData([
            "HTTP/1.1 200 OK",
            "Content-Length: 1000",
            "",
            "1234",
        ])
    case "/no_length_hint":
        return linesToData([
            "HTTP/1.1 200 OK",
            "",
            "1234",
        ])
    case "/conflicting_cl":
        return linesToData([
            "HTTP/1.1 200 OK",
            "Content-Length: 10, 4",
            "",
            "1234",
        ])
    default:
        return "HTTP/1.1 500 Internal Server Error\r\n\r\n".data(using: .ascii)!
    }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
actor RawHTTPServer {
    let server_channel:
        NIOAsyncChannel<
            NIOAsyncChannel<
                HTTPServerRequestPart, IOData
            >, Never
        >

    var port: Int {
        server_channel.channel.localAddress!.port!
    }

    init() async throws {
        server_channel = try await ServerBootstrap(
            group: .singletonMultiThreadedEventLoopGroup
        )
        .bind(
            host: "127.0.0.1",
            port: 0,
        ) { channel in
            channel.eventLoop.makeCompletedFuture {
                let requestDecoder = ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
                channel.pipeline.addHandler(requestDecoder)

                return try NIOAsyncChannel<
                    HTTPServerRequestPart, IOData
                >(wrappingChannelSynchronously: channel)
            }
        }
    }

    func run(handler: @Sendable @escaping (HTTPRequestHead) async throws -> Data) async throws {
        try await server_channel.executeThenClose { inbound in
            for try await httpChannel in inbound {
                try await httpChannel.executeThenClose { inbound, outbound in
                    for try await requestPart in inbound {
                        // Wait for a request header.
                        // Ignore request bodies for now.
                        guard case .head(let head) = requestPart else {
                            return
                        }

                        // Get the response from the handler
                        let response = try await handler(head)

                        // Write the response out
                        let data = IOData.byteBuffer(ByteBuffer(bytes: response))
                        try await outbound.write(data)
                    }
                }
            }
        }
    }
}
