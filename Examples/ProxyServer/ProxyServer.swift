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
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
@main
struct ProxyServer {
    static func main() async throws {
        // TODO: Call proxy once we have a concrete server implementation
        fatalError("Waiting for a concrete HTTP server implementation")
    }

    static func proxy(server: some HTTPServer, client: some HTTPClient) async throws {
        try await server.serve {
            request,
            requestContext,
            serverRequestReceiver,
            responseSender in
            // We need to use a mutex here to move the requestReceiver into the
            // @Sendable restartable body
            let serverRequestReceiver = Mutex(Disconnected(value: Optional(serverRequestReceiver)))
            // Needed since we are lacking call-once closures
            var responseSender = Optional(responseSender)

            var client = client
            try await client.perform(
                request: request,
                body: .restartable { clientRequestSender in
                    // This takes the request receiver out of the mutex. Any restarts would hit
                    // a force-unwrap.
                    let serverRequestReceiver = serverRequestReceiver.withLock {
                        $0.swap(newValue: nil)
                    }!

                    try await clientRequestSender.send { clientRequestBody in
                        var clientRequestBody = clientRequestBody
                        let (_, trailers) = try await serverRequestReceiver.receive { serverRequestBody in
                            try await clientRequestBody.write(serverRequestBody)
                        }
                        return ((), trailers)
                    }
                }
            ) { response, clientResponseReceiver in
                // Needed since we are lacking call-once closures
                var clientResponseReceiver = Optional(clientResponseReceiver)

                try await responseSender.take()!.send(response) { serverResponseBody in
                    var serverResponseBody = serverResponseBody
                    let (_, trailers) = try await clientResponseReceiver.take()!.receive { clientResponseBody in
                        try await serverResponseBody.write(clientResponseBody)
                    }
                    return ((), trailers)
                }
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
