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
import Synchronization

/// This examples shows an HTTP proxy server.
///
/// Every incoming request is proxied via an HTTP client. This supports full bi-directional streaming
/// and trailers.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
@main
struct ProxyServer {
    static func main() async throws {
        // TODO: Call proxy once we have a concrete server implementation
        fatalError("Waiting for a concrete HTTP server implementation")
    }

    static func proxy(server: some HTTPServer, client: some HTTPClient) async throws {
        try await server.serve { request, requestContext, serverRequestBodyAndTrailers, responseSender in
            // We need to use a mutex here to move the requestBodyAndTrailers into the
            // @Sendable restartable body
            let serverRequestBodyAndTrailers = Mutex(Optional(serverRequestBodyAndTrailers))
            // Needed since we are lacking call-once closures
            var responseSender = Optional(responseSender)

            try await client.perform(
                request: request,
                body: .restartable { clientRequestBody in
                    var clientRequestBody = clientRequestBody
                    // This takes the request body out of the mutex. Any restarts would hit
                    // a force-unwrap.
                    let serverRequestBodyAndTrailers = serverRequestBodyAndTrailers.withLock { $0.take()! }

                    return try await serverRequestBodyAndTrailers.consumeAndConclude { serverRequestBody in
                        try await clientRequestBody.write(serverRequestBody)
                    }.1
                }
            ) { response, clientResponseBodyAndTrailers in
                // Needed since we are lacking call-once closures
                var clientResponseBodyAndTrailers = Optional(clientResponseBodyAndTrailers)

                let serverResponseBodyAndTrailers = try await responseSender.take()!.send(response)
                try await serverResponseBodyAndTrailers.produceAndConclude { serverResponseBody in
                    var serverResponseBody = serverResponseBody
                    return try await clientResponseBodyAndTrailers.take()!.consumeAndConclude { clientResponseBody in
                        try await serverResponseBody.write(clientResponseBody)
                    }
                }
            }
        }
    }
}
