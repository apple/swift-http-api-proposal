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

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
public actor RawHTTPServer {
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
