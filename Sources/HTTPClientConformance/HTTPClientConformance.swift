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
public import HTTPClient
import HTTPTypes
import Synchronization
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public func runAllConformanceTests<Client: HTTPClient & Sendable & ~Copyable>(
    _ clientFactory: () async throws -> Client
) async throws where Client.RequestOptions: HTTPClientCapability.RedirectionHandler {
    // Start the server that the conformance tests will interact with
    let server = TestHTTPServer()
    await server.serve()

    // Run all the test cases
    try await ok(try await clientFactory())
    try await echoString(try await clientFactory())
    try await gzip(try await clientFactory())
    try await deflate(try await clientFactory())
    try await brotli(try await clientFactory())
    try await identity(try await clientFactory())
    try await customHeader(try await clientFactory())
    try await redirect301(try await clientFactory())
    try await redirect308(try await clientFactory())
    try await notFound(try await clientFactory())
    try await statusOutOfRangeButValid(try await clientFactory())
    try await stressTest(clientFactory)
    try await echoInterleave(try await clientFactory())
    try await getConvenience(try await clientFactory())
    try await postConvenience(try await clientFactory())

    // TODO: Writing just an empty span causes an indefinite stall. The terminating chunk (size 0) is not written out on the wire.
    // try await emptyChunkedBody(try await clientFactory())

    try await cancelPreHeaders(clientFactory)
    try await cancelPreBody(clientFactory)
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func ok<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let methods = [HTTPRequest.Method.head, .get, .put, .post, .delete]
    for method in methods {
        let request = HTTPRequest(
            method: method,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/200"
        )
        try await client.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            let (body, trailers) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                return String(copying: try UTF8Span(validating: span))
            }
            #expect(body.isEmpty)
            #expect(trailers == nil)
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func emptyChunkedBody<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let request = HTTPRequest(
        method: .post,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/request"
    )
    try await client.perform(
        request: request,
        body: .restartable(knownLength: 0) { writer in
            var writer = writer
            try await writer.write(Span())
            return nil
        }
    ) { response, responseBodyAndTrailers in
        #expect(response.status == .ok)
        let (jsonRequest, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
            let body = String(copying: try UTF8Span(validating: span))
            let data = body.data(using: .utf8)!
            return try JSONDecoder().decode(JSONHTTPRequest.self, from: data)
        }
        #expect(jsonRequest.body.isEmpty)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func echoString<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let request = HTTPRequest(
        method: .post,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/echo"
    )
    try await client.perform(
        request: request,
        body: .restartable { writer in
            var writer = writer
            let body = "Hello World"
            try await writer.write(body.utf8Span.span)
            return nil
        }
    ) { response, responseBodyAndTrailers in
        #expect(response.status == .ok)
        let (body, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
            let body = String(copying: try UTF8Span(validating: span))
            return body
        }

        // Check that the request body was in the response
        #expect(body == "Hello World")
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func gzip<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let request = HTTPRequest(
        method: .get,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/gzip"
    )
    try await client.perform(
        request: request
    ) { response, responseBodyAndTrailers in
        #expect(response.status == .ok)

        // If gzip is not advertised by the client, a fallback to no-encoding
        // will occur, which should be supported.
        let contentEncoding = response.headerFields[.contentEncoding]
        withKnownIssue("gzip may not be supported by the client") {
            #expect(contentEncoding == "gzip")
        } when: {
            contentEncoding == nil || contentEncoding == "identity"
        }

        let (body, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
            return String(copying: try UTF8Span(validating: span))
        }
        #expect(body == "TEST\n")
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func deflate<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let request = HTTPRequest(
        method: .get,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/deflate"
    )
    try await client.perform(
        request: request
    ) { response, responseBodyAndTrailers in
        #expect(response.status == .ok)

        // If deflate is not advertised by the client, a fallback to no-encoding
        // will occur, which should be supported.
        let contentEncoding = response.headerFields[.contentEncoding]
        withKnownIssue("deflate may not be supported by the client") {
            #expect(contentEncoding == "deflate")
        } when: {
            contentEncoding == nil || contentEncoding == "identity"
        }

        let (body, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
            return String(copying: try UTF8Span(validating: span))
        }
        #expect(body == "TEST\n")
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func brotli<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let request = HTTPRequest(
        method: .get,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/brotli",
    )
    try await client.perform(
        request: request
    ) { response, responseBodyAndTrailers in
        #expect(response.status == .ok)

        // If brotli is not advertised by the client, a fallback to no-encoding
        // will occur, which should be supported.
        let contentEncoding = response.headerFields[.contentEncoding]
        withKnownIssue("brotli may not be supported by the client") {
            #expect(contentEncoding == "br")
        } when: {
            contentEncoding == nil || contentEncoding == "identity"
        }

        let (body, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
            return String(copying: try UTF8Span(validating: span))
        }
        #expect(body == "TEST\n")
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func identity<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let request = HTTPRequest(
        method: .get,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/identity",
    )
    try await client.perform(
        request: request,
    ) { response, responseBodyAndTrailers in
        #expect(response.status == .ok)
        let contentEncoding = response.headerFields[.contentEncoding]
        #expect(contentEncoding == nil || contentEncoding == "identity")
        let (body, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
            return String(copying: try UTF8Span(validating: span))
        }
        #expect(body == "TEST\n")
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func customHeader<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let request = HTTPRequest(
        method: .post,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/request",
        headerFields: HTTPFields([HTTPField(name: .init("X-Foo")!, value: "BARbaz")])
    )

    try await client.perform(
        request: request,
        body: .restartable { writer in
            var writer = writer
            try await writer.write("Hello World".utf8.span)
            return nil
        }
    ) { response, responseBodyAndTrailers in
        #expect(response.status == .ok)
        let (jsonRequest, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
            let body = String(copying: try UTF8Span(validating: span))
            let data = body.data(using: .utf8)!
            return try JSONDecoder().decode(JSONHTTPRequest.self, from: data)
        }
        #expect(jsonRequest.headers["X-Foo"] == ["BARbaz"])
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func redirect308<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws
where Client.RequestOptions: HTTPClientCapability.RedirectionHandler {
    let request = HTTPRequest(
        method: .get,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/308"
    )

    var options = Client.RequestOptions()
    options.redirectionHandlerClosure = { response, newRequest in
        #expect(response.status == .permanentRedirect)
        return .follow(newRequest)
    }

    try await client.perform(
        request: request,
        options: options,
    ) { response, responseBodyAndTrailers in
        #expect(response.status == .ok)
        let (jsonRequest, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
            let body = String(copying: try UTF8Span(validating: span))
            let data = body.data(using: .utf8)!
            return try JSONDecoder().decode(JSONHTTPRequest.self, from: data)
        }
        #expect(jsonRequest.method == "GET")
        #expect(jsonRequest.body.isEmpty)
        #expect(!jsonRequest.headers.isEmpty)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func redirect301<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws
where Client.RequestOptions: HTTPClientCapability.RedirectionHandler {
    let request = HTTPRequest(
        method: .get,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/301"
    )

    var options = Client.RequestOptions()
    options.redirectionHandlerClosure = { response, newRequest in
        #expect(response.status == .movedPermanently)
        return .follow(newRequest)
    }

    try await client.perform(
        request: request,
        options: options,
    ) { response, responseBodyAndTrailers in
        #expect(response.status == .ok)
        let (jsonRequest, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
            let body = String(copying: try UTF8Span(validating: span))
            let data = body.data(using: .utf8)!
            return try JSONDecoder().decode(JSONHTTPRequest.self, from: data)
        }
        #expect(jsonRequest.method == "GET")
        #expect(jsonRequest.body.isEmpty)
        #expect(!jsonRequest.headers.isEmpty)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func notFound<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let request = HTTPRequest(
        method: .get,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/404"
    )

    try await client.perform(
        request: request,
    ) { response, responseBodyAndTrailers in
        #expect(response.status == .notFound)
        let (_, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
            let isEmpty = span.isEmpty
            #expect(isEmpty)
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func statusOutOfRangeButValid<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let request = HTTPRequest(
        method: .get,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/999"
    )

    try await client.perform(
        request: request,
    ) { response, responseBodyAndTrailers in
        #expect(response.status == 999)
        let (_, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
            let isEmpty = span.isEmpty
            #expect(isEmpty)
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func stressTest<Client: HTTPClient & Sendable & ~Copyable>(_ clientFactory: () async throws -> Client) async throws {
    let request = HTTPRequest(
        method: .get,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/request"
    )

    try await withThrowingTaskGroup { group in
        for _ in 0..<100 {
            let client = try await clientFactory()
            group.addTask {
                try await client.perform(
                    request: request,
                ) { response, responseBodyAndTrailers in
                    #expect(response.status == .ok)
                    let _ = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                        let isEmpty = span.isEmpty
                        #expect(!isEmpty)
                    }
                }
            }
        }

        var count = 0
        for try await _ in group {
            count += 1
        }

        #expect(count == 100)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func echoInterleave<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let request = HTTPRequest(
        method: .post,
        scheme: "http",
        authority: "127.0.0.1:12345",
        path: "/echo"
    )

    // Used to ping-pong between the client-side writer and reader
    let writerWaiting: Mutex<CheckedContinuation<Void, Never>?> = .init(nil)

    try await client.perform(
        request: request,
        body: .restartable { writer in
            var writer = writer

            for _ in 0..<1000 {
                // TODO: There's a bug that prevents a single byte from being
                // successfully written out as a chunk. So write 2 bytes for now.
                try await writer.write("AB".utf8.span)

                // Only proceed once the client receives the echo.
                await withCheckedContinuation { continuation in
                    writerWaiting.withLock { $0 = continuation }
                }
            }
            return nil
        }
    ) { response, responseBodyAndTrailers in
        #expect(response.status == .ok)
        let _ = try await responseBodyAndTrailers.consumeAndConclude { reader in
            var numberOfChunks = 0
            try await reader.forEach { span in
                numberOfChunks += 1
                #expect(span.count == 2)
                #expect(span[0] == UInt8(ascii: "A"))
                #expect(span[1] == UInt8(ascii: "B"))

                // Unblock the writer
                writerWaiting.withLock { $0!.resume() }
            }
            #expect(numberOfChunks == 1000)
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func cancelPreHeaders<Client: HTTPClient & Sendable & ~Copyable>(_ clientFactory: () async throws -> Client) async throws {
    try await withThrowingTaskGroup { group in
        let client = try await clientFactory()

        group.addTask {
            // The /stall HTTP endpoint is not expected to return at all.
            // Because of the cancellation, we're expected to return from this task group
            // within 100ms.
            let request = HTTPRequest(
                method: .get,
                scheme: "http",
                authority: "127.0.0.1:12345",
                path: "/stall",
            )

            try await client.perform(
                request: request,
            ) { response, responseBodyAndTrailers in
                assertionFailure("Never expected to actually receive a response")
            }
        }

        // Wait for a short amount of time for the request to be made.
        try await Task.sleep(for: .milliseconds(100))

        // Now cancel the task group
        group.cancelAll()

        // This should result in the task throwing an exception because
        // the server didn't send any headers or body and the task is now
        // cancelled.
        await #expect(throws: (any Error).self) {
            try await group.next()
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func cancelPreBody<Client: HTTPClient & Sendable & ~Copyable>(_ clientFactory: () async throws -> Client) async throws {
    try await withThrowingTaskGroup { group in
        // Used by the task to notify when the task group should be cancelled
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let client = try await clientFactory()

        group.addTask {
            // The /stall_body HTTP endpoint gives headers and an incomplete 1000-byte body.
            let request = HTTPRequest(
                method: .get,
                scheme: "http",
                authority: "127.0.0.1:12345",
                path: "/stall_body",
            )

            try await client.perform(
                request: request,
            ) { response, responseBodyAndTrailers in
                #expect(response.status == .ok)
                let _ = try await responseBodyAndTrailers.consumeAndConclude { reader in
                    var reader = reader

                    // Now trigger the task group cancellation.
                    continuation.yield()

                    // The client may choose to return however much of the body it already
                    // has downloaded, but eventually it must throw an exception because
                    // the response is incomplete and the task has been cancelled.
                    while true {
                        try await reader.collect(upTo: .max) {
                            #expect($0.count > 0)
                        }
                    }
                }
            }
        }

        // Wait to be notified about cancelling the task group
        await stream.first { true }

        // Now cancel the task group
        group.cancelAll()

        // This should result in the task throwing an exception.
        await #expect(throws: (any Error).self) {
            try await group.next()
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func getConvenience<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let (response, data) = try await client.get(
        url: URL(string: "http://127.0.0.1:12345/request")!,
        collectUpTo: .max
    )
    #expect(response.status == .ok)
    let jsonRequest = try JSONDecoder().decode(JSONHTTPRequest.self, from: data)
    #expect(jsonRequest.method == "GET")
    #expect(!jsonRequest.headers.isEmpty)
    #expect(jsonRequest.body.isEmpty)
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func postConvenience<Client: HTTPClient & Sendable & ~Copyable>(_ client: consuming Client) async throws {
    let (response, data) = try await client.post(
        url: URL(string: "http://127.0.0.1:12345/request")!,
        bodyData: Data("Hello World".utf8),
        collectUpTo: .max
    )
    #expect(response.status == .ok)
    let jsonRequest = try JSONDecoder().decode(JSONHTTPRequest.self, from: data)
    #expect(jsonRequest.method == "POST")
    #expect(!jsonRequest.headers.isEmpty)
    #expect(jsonRequest.body == "Hello World")
}
