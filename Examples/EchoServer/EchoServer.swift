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

import HTTPAPIs

/// This examples shows an HTTP echo server.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
@main
struct EchoServer {
    static func main() async throws {
        // TODO: Call echo once we have a concrete server implementation
        fatalError("Waiting for a concrete HTTP server implementation")
    }

    static func echo<Server: HTTPServer>(server: Server) async throws {
        try await server.serve { request, requestContext, requestBodyAndTrailers, responseSender in
            // Needed since we are lacking call-once closures
            var requestBodyAndTrailers = Optional(requestBodyAndTrailers)
            let responseBodyAndTrailers = try await responseSender.send(.init(status: .ok))

            try await responseBodyAndTrailers.produceAndConclude { responseBody in
                // Needed since we are lacking call-once closures
                var responseBody = responseBody
                return try await requestBodyAndTrailers.take()!.consumeAndConclude { reader in
                    try await responseBody.write(reader)
                }
            }
        }
    }
}
