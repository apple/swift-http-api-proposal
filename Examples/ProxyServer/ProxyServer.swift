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

import HTTPAPIs
import Synchronization

/// This examples shows an HTTP proxy server.
///
/// Every incoming request is proxied via an HTTP client. This supports full bi-directional streaming
/// and trailers.
@available(anyAppleOS 26.0, *)
@main
struct ProxyServer {
    static func main() async throws {
        // TODO: Call proxy once we have a concrete server implementation
        fatalError("Waiting for a concrete HTTP server implementation")
    }

    static func proxy<Server: HTTPServer, Client: HTTPClient>(
        server: Server,
        client: Client
    ) async throws {
        try await server.serve {
            request,
            requestContext,
            serverReader,
            responseSender in
            // We need to use a mutex here to move the reader into the
            // @Sendable restartable body
            let serverReader = Mutex(Disconnected(value: Optional(serverReader)))
            // Needed since we are lacking call-once closures
            var responseSender = Optional(responseSender)

            var client = client
            try await client.perform(
                request: request,
                body: .restartable { upstreamWriter in
                    // This takes the reader out of the mutex. Any restarts would hit
                    // a force-unwrap.
                    let reader = serverReader.withLock {
                        $0.swap(newValue: nil)
                    }!
                    // Pipe the server request body straight into the upstream writer.
                    try await reader.pipe(into: upstreamWriter)
                    return nil
                }
            ) { response, upstreamReader, _ in
                // Pipe the upstream client response body straight into the
                // downstream response sender.
                let writer = try await responseSender.take()!.send(response)
                try await upstreamReader.pipe(into: writer)
            }
        }
    }
}

@usableFromInline
struct Disconnected<Value: ~Copyable>: ~Copyable, Sendable {
    // This is safe since we take the value as sending and take consumes it
    // and returns it as sending.
    private nonisolated(unsafe) var value: Value?

    @usableFromInline
    init(value: consuming sending Value) {
        unsafe self.value = .some(value)
    }

    @usableFromInline
    consuming func take() -> sending Value {
        nonisolated(unsafe) let value = unsafe self.value.take()!
        return unsafe value
    }

    @usableFromInline
    mutating func swap(newValue: consuming sending Value) -> sending Value {
        nonisolated(unsafe) let value = unsafe self.value.take()!
        unsafe self.value = consume newValue
        return unsafe value
    }
}
