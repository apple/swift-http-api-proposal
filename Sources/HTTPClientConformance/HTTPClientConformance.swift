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

// These tests confirm that a basic HTTP client (no extension protocols supported)
// conforms to the minimum expectations of the HTTP client API.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public func runBasicConformanceTests<Client: HTTPClient & ~Copyable>(
    _ clientFactory: @escaping () async throws -> Client
) async throws {
    try await withTestHTTPServer { port in
        try await BasicConformanceTests(port: port, clientFactory: clientFactory).run()
    }
    try await withBadHTTPServer { port in
        try await BadServerConformanceTests(port: port, clientFactory: clientFactory).run()
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct BadServerConformanceTests<Client: HTTPClient & ~Copyable> {
    let port: Int
    let clientFactory: () async throws -> Client

    func run() async throws {
        try await testNotHTTP()
        try await testLFOnly()
        try await testBadHttpCase()
        try await testNoReason()
    }

    func testNotHTTP() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/not_http"
        )
        await #expect(throws: (any Error).self) {
            try await client.perform(
                request: request,
            ) { _, _ in }
        }
    }

    func testLFOnly() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/lf_only"
        )
        try await client.perform(
            request: request,
        ) { response, _ in
            #expect(response.status == .ok)
        }
    }

    func testNoReason() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/no_reason"
        )
        try await client.perform(
            request: request,
        ) { response, _ in
            #expect(response.status == .ok)
        }
    }

    func testBadHttpCase() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/http_case"
        )
        await #expect(throws: (any Error).self) {
            try await client.perform(
                request: request,
            ) { _, _ in }
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct BasicConformanceTests<Client: HTTPClient & ~Copyable> {
    let port: Int
    let clientFactory: () async throws -> Client

    func run() async throws {
        try await testOk()
        try await testEchoString()
        try await testGzip()
        try await testDeflate()
        try await testBrotli()
        try await testIdentity()
        try await testCustomHeader()
        try await testBasicRedirect()
        try await testNotFound()
        try await testStatusOutOfRangeButValid()
        try await testStressTest()
        try await testEchoInterleave()
        try await testGetConvenience()
        try await testPostConvenience()
        try await testCancelPreHeaders()
        try await testCancelPreBody()

        // TODO: Writing just an empty span causes an indefinite stall. The terminating chunk (size 0) is not written out on the wire.
        // try await testEmptyChunkedBody()
    }

    func testOk() async throws {
        let client = try await clientFactory()
        let methods = [HTTPRequest.Method.head, .get, .put, .post, .delete]
        for method in methods {
            let request = HTTPRequest(
                method: method,
                scheme: "http",
                authority: "127.0.0.1:\(port)",
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

    func testEmptyChunkedBody() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
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

    func testEchoString() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
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

    func testGzip() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
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

    func testDeflate() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
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

    func testBrotli() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
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

    func testIdentity() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
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

    func testCustomHeader() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
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

    func testBasicRedirect() async throws {
        let client = try await clientFactory()
        let paths = ["/301", "/308"]

        for path in paths {
            let request = HTTPRequest(
                method: .get,
                scheme: "http",
                authority: "127.0.0.1:\(port)",
                path: path
            )

            try await client.perform(
                request: request,
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
    }

    func testNotFound() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
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

    func testStatusOutOfRangeButValid() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
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

    func testStressTest() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
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

    func testEchoInterleave() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
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

    func testCancelPreHeaders() async throws {
        try await withThrowingTaskGroup { group in
            let client = try await clientFactory()
            let port = self.port

            group.addTask {
                // The /stall HTTP endpoint is not expected to return at all.
                // Because of the cancellation, we're expected to return from this task group
                // within 100ms.
                let request = HTTPRequest(
                    method: .get,
                    scheme: "http",
                    authority: "127.0.0.1:\(port)",
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

    func testCancelPreBody() async throws {
        try await withThrowingTaskGroup { group in
            // Used by the task to notify when the task group should be cancelled
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            let client = try await clientFactory()
            let port = self.port

            group.addTask {
                // The /stall_body HTTP endpoint gives headers and an incomplete 1000-byte body.
                let request = HTTPRequest(
                    method: .get,
                    scheme: "http",
                    authority: "127.0.0.1:\(port)",
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

    func testGetConvenience() async throws {
        let client = try await clientFactory()
        let (response, data) = try await client.get(
            url: URL(string: "http://127.0.0.1:\(port)/request")!,
            collectUpTo: .max
        )
        #expect(response.status == .ok)
        let jsonRequest = try JSONDecoder().decode(JSONHTTPRequest.self, from: data)
        #expect(jsonRequest.method == "GET")
        #expect(!jsonRequest.headers.isEmpty)
        #expect(jsonRequest.body.isEmpty)
    }

    func testPostConvenience() async throws {
        let client = try await clientFactory()
        let (response, data) = try await client.post(
            url: URL(string: "http://127.0.0.1:\(port)/request")!,
            bodyData: Data("Hello World".utf8),
            collectUpTo: .max
        )
        #expect(response.status == .ok)
        let jsonRequest = try JSONDecoder().decode(JSONHTTPRequest.self, from: data)
        #expect(jsonRequest.method == "POST")
        #expect(!jsonRequest.headers.isEmpty)
        #expect(jsonRequest.body == "Hello World")
    }
}
