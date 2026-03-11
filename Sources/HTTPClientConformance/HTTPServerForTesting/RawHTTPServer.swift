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
        let port = await server.port
        print("Raw HTTP Server: \(port)")
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
        return linesToData([
            "Http/1.1 200 OK",
            "Connection: close",
            "",
            "",
        ])
    case "/no_reason":
        return linesToData([
            "HTTP/1.1 200",
            "Connection: close",
            "",
            "",
        ])
    case "/204_with_cl":
        return linesToData([
            "HTTP/1.1 204 No Content",
            "Content-Length: 1000",
            "Connection: close",
            "",
            "",
        ])
    case "/304_with_cl":
        return linesToData([
            "HTTP/1.1 304 Not Modified",
            "Content-Length: 1000",
            "Connection: close",
            "",
            "",
        ])
    case "/incomplete_body":
        return linesToData([
            "HTTP/1.1 200 OK",
            "Content-Length: 1000",
            "Connection: close",
            "",
            "1234",
        ])
    case "/no_length_hint":
        return linesToData([
            "HTTP/1.1 200 OK",
            "Connection: close",
            "",
            "1234",
        ])
    case "/conflicting_cl":
        return linesToData([
            "HTTP/1.1 200 OK",
            "Content-Length: 10, 4",
            "Connection: close",
            "",
            "1234",
        ])
    default:
        return linesToData([
            "HTTP/1.1 500 Internal Server Error",
            "Connection: close",
            "",
            "",
        ])
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
                do {
                    try await httpChannel.executeThenClose { inbound, outbound in
                        // Read exactly one part of the request
                        var iter = inbound.makeAsyncIterator()
                        let requestPart = try await iter.next()

                        // It must be the header. We don't care about the rest.
                        guard case .head(let head) = requestPart else {
                            print("Server unexpectedly received non-header as first part of request: \(requestPart)")
                            return
                        }

                        // Get the response from the handler
                        let response = try await handler(head)

                        // Write the response out and then close the channel.
                        // This server is a simple one, it won't reuse connections.
                        let data = IOData.byteBuffer(ByteBuffer(bytes: response))
                        try await outbound.write(data)
                    }
                } catch {
                    // Do not let one connection take down the entire server.
                    // Print the error from the connection and move on.
                    print("Server caught error handling client: \(error)")
                }
            }
        }
    }
}
