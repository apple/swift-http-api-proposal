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
        print("Test HTTP Server port: \(port)")
        try await BasicConformanceTests(port: port, clientFactory: clientFactory).run()
    }
    try await withRawHTTPServer { port in
        print("Raw HTTP Server: \(port)")
        try await RawServerConformanceTests(port: port, clientFactory: clientFactory).run()
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct RawServerConformanceTests<Client: HTTPClient & ~Copyable> {
    let port: Int
    let clientFactory: () async throws -> Client

    func run() async throws {
        try await testNotHTTP()
        try await testBadHttpCase()
        try await testNoReason()
        try await test204WithContentLength()
        try await test304WithContentLength()
        try await testIncompleteBody()
        try await testNoLengthHint()
        try await testConflictingContentLength()
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

    func test204WithContentLength() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/204_with_cl"
        )
        try await client.perform(
            request: request
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .noContent)
            let (_, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let isEmpty = span.isEmpty
                #expect(isEmpty)
            }
        }
    }

    func test304WithContentLength() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/304_with_cl"
        )
        try await client.perform(
            request: request
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .notModified)
            let (_, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let isEmpty = span.isEmpty
                #expect(isEmpty)
            }
        }
    }

    func testIncompleteBody() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/incomplete_body"
        )

        // An incomplete body based on content-length results in error
        await #expect(throws: (any Error).self) {
            try await client.perform(
                request: request
            ) { response, responseBodyAndTrailers in
                #expect(response.status == .ok)
                let (_, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                    let isEmpty = span.isEmpty
                    #expect(isEmpty)
                }
            }
        }
    }

    func testConflictingContentLength() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/conflicting_cl"
        )

        // Conflicting content-length results in error
        await #expect(throws: (any Error).self) {
            try await client.perform(
                request: request
            ) { response, responseBodyAndTrailers in
                #expect(response.status == .ok)
                let (_, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                    let isEmpty = span.isEmpty
                    #expect(isEmpty)
                }
            }
        }
    }

    func testNoLengthHint() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/no_length_hint"
        )

        try await client.perform(
            request: request
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            let (body, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                return String(copying: try UTF8Span(validating: span))
            }
            #expect(body == "1234")
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
        try await testGetConvenience()
        try await testPostConvenience()
        try await testCancelPreHeaders()
        try await testCancelPreBody()
        try await testEcho1MBBody()
        try await testUnderRead()
        try await testClientSendsEmptyHeaderValue()
        try await testInfiniteRedirect()
        try await testHeadWithContentLength()
        try await testServerSendsMultiValueHeader()
        try await testClientSendsMultiValueHeader()
        try await testBasicCookieSetAndUse()

        // TODO: URLSession client hangs because of a bug where single bytes cannot be sent.
        // try await testEchoInterleave()

        // TODO: URLSession client hangs because of a bug where single bytes cannot be sent and requests cannot outlive responses.
        // try await testSpeakInterleave()

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
            }
        }
    }

    func testInfiniteRedirect() async throws {
        let client = try await clientFactory()

        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/redirect_ping"
        )

        // Infinite redirection should cause an error to be thrown
        await #expect(throws: (any Error).self) {
            try await client.perform(
                request: request,
            ) { _, _ in }
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
        let (writerWaiting, continuation) = AsyncStream<Void>.makeStream()

        try await client.perform(
            request: request,
            body: .restartable { writer in
                var writer = writer

                for _ in 0..<1000 {
                    // Write a 1-byte chunk
                    try await writer.write("A".utf8.span)

                    // Only proceed once the client receives the echo.
                    await writerWaiting.first(where: { true })
                }
                return nil
            }
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            let _ = try await responseBodyAndTrailers.consumeAndConclude { reader in
                var numberOfChunks = 0
                try await reader.forEach { span in
                    numberOfChunks += 1
                    #expect(span.count == 1)
                    #expect(span[0] == UInt8(ascii: "A"))

                    // Unblock the writer
                    continuation.yield()
                }
                #expect(numberOfChunks == 1000)
            }
        }
    }

    func testClientSendsEmptyHeaderValue() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/request",
            headerFields: [
                .init("X-Test")!: ""
            ]
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

            #expect(jsonRequest.headers["X-Test"] == [""])
        }
    }

    func testSpeakInterleave() async throws {
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/speak"
        )

        let client = try await clientFactory()

        let (stream, continuation) = AsyncStream<String>.makeStream()

        try await client.perform(
            request: request,
            body: .restartable { writer in
                var writer = writer
                var iterator = stream.makeAsyncIterator()

                // Wait for a chunk from the server
                while let chunk = await iterator.next() {
                    // Write it back to the server
                    try await writer.write(chunk.utf8.span)
                }
                return nil
            }
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            let _ = try await responseBodyAndTrailers.consumeAndConclude { reader in
                // Read all chunks from server
                try await reader.forEach { span in
                    let chunk = String(copying: try UTF8Span(validating: span))
                    #expect(chunk == "A")

                    // Give chunk to the writer to echo back
                    continuation.yield(chunk)
                }

                // No more chunks from server. Stop writing as well.
                continuation.finish()
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
        #expect(jsonRequest.body == "Hello World")
    }

    func testEcho1MBBody() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/echo"
        )

        try await client.perform(
            request: request,
            body: .restartable(knownLength: 1_000_000) { writer in
                // Write out 1Mb of "A"
                var writer = writer
                let data = String(repeating: "A", count: 1_000_000).data(using: .ascii)!
                try await writer.write(data.span)
                return nil
            }
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            let (echo, _) = try await responseBodyAndTrailers.collect(upTo: 2_000_000) { span in
                return String(copying: try UTF8Span(validating: span))
            }
            #expect(echo == String(repeating: "A", count: 1_000_000))
        }
    }

    func testUnderRead() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/1mb_body"
        )

        // Read only a single byte from the body. We do not care about the rest of the 1Mb.
        try await client.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            let (character, _) = try await responseBodyAndTrailers.collect(upTo: 1) { span in
                return String(copying: try UTF8Span(validating: span))
            }
            #expect(character == "A")
        }
    }

    func testHeadWithContentLength() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .head,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/head_with_cl"
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

    func testServerSendsMultiValueHeader() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/header_multivalue"
        )
        try await client.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            let values = response.headerFields[values: .init("X-Test")!]

            // If the values are comma-separated, break them up.
            var split_values: [Substring] = []
            for value in values {
                let iter_splits = value.split(separator: /(\s)*,(\s)*/)
                split_values.append(contentsOf: iter_splits)
            }

            #expect(split_values == ["one", "two"])
        }
    }

    func testClientSendsMultiValueHeader() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/request",
            headerFields: [
                .init("X-Test")!: "one",
                .init("X-Test")!: "two",
            ]
        )
        try await client.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            let (jsonRequest, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let body = String(copying: try UTF8Span(validating: span))
                let data = body.data(using: .utf8)!
                return try JSONDecoder().decode(JSONHTTPRequest.self, from: data)
            }

            let values = jsonRequest.headers["X-Test"]!

            // If the values are comma-separated, break them up.
            var split_values: [Substring] = []
            for value in values {
                let iter_splits = value.split(separator: /(\s)*,(\s)*/)
                split_values.append(contentsOf: iter_splits)
            }

            #expect(split_values == ["one", "two"])
        }
    }

    func testBasicCookieSetAndUse() async throws {
        // Get a cookie from the server
        let client = try await clientFactory()
        let request1 = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/cookie"
        )
        let serverCookie = try await client.perform(request: request1) { response, responseBodyAndTrailers in
            // Parse the cookie
            #expect(response.headerFields.contains(.setCookie))
            let values = response.headerFields[values: .setCookie]
            #expect(values.count == 1)
            let cookie = values[0]
            #expect(cookie.starts(with: "foo="))
            return cookie.components(separatedBy: ";").first!
        }

        // The client should automatically use the cookie on the next request
        let request2 = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(port)",
            path: "/request"
        )
        let clientCookie = try await client.perform(request: request2) { response, responseBodyAndTrailers in
            // The server gave us the request back. Check that the cookie was in the request.
            let (jsonRequest, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let body = String(copying: try UTF8Span(validating: span))
                let data = body.data(using: .utf8)!
                return try JSONDecoder().decode(JSONHTTPRequest.self, from: data)
            }

            // Parse the cookie
            let values = jsonRequest.headers["Cookie"]!
            #expect(values.count == 1)
            let cookie = values[0]
            #expect(cookie.starts(with: "foo="))
            return cookie.components(separatedBy: ";").first!
        }

        // The cookie should be the same
        #expect(serverCookie == clientCookie)
    }
}
