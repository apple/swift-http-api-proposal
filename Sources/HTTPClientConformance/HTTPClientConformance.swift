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

// An identifier for a single HTTP conformance test case.
public enum ConformanceTestCase: Sendable, Hashable, CaseIterable {
    /// **WARNING**: Every new conformance test case must be added
    /// as an enum case below.

    case testNotHTTP
    case testBadHTTPCase
    case testNoReason
    case test204WithContentLength
    case test304WithContentLength
    case testIncompleteBody
    case testNoLengthHint
    case testConflictingContentLength
    case testOk
    case testEchoString
    case testGzip
    case testDeflate
    case testBrotli
    case testIdentity
    case testCustomHeader
    case testBasicRedirect
    case testNotFound
    case testStatusOutOfRangeButValid
    case testStressTest
    case testGetConvenience
    case testPostConvenience
    case testCancelPreHeaders
    case testCancelPreBody
    case testEcho1MBBody
    case testUnderRead
    case testClientSendsEmptyHeaderValue
    case testInfiniteRedirect
    case testHeadWithContentLength
    case testServerSendsMultiValueHeader
    case testClientSendsMultiValueHeader
    case testBasicCookieSetAndUse
    case testEchoInterleave
    case testSpeakInterleave
    case testEmptyChunkedBody
    case testURLParams
    case testETag
}

// Runs an HTTP client through all the conformance tests,
// except the ones specified in `excluding`.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public func runConformanceTests<Client: HTTPClient & ~Copyable>(
    excluding: [ConformanceTestCase] = [],
    _ clientFactory: @escaping () async throws -> Client
) async throws {
    var testCases: [ConformanceTestCase] = []
    for testCase in ConformanceTestCase.allCases {
        if excluding.contains(testCase) {
            print("➜ Test \(testCase) skipped.")
            continue
        }
        testCases.append(testCase)
    }

    try await withTestHTTPServer { testServerPort in
        try await withRawHTTPServer { rawServerPort in
            let suite = ConformanceTestSuite(testServerPort: testServerPort, rawServerPort: rawServerPort, clientFactory: clientFactory)
            for testCase in testCases {
                do {
                    print("◇ Test \(testCase) started.")
                    try await suite.run(testCase)
                    print("◇ Test \(testCase) finished.")
                } catch {
                    print("✘ Test \(testCase) failed with error: \(error)")
                    Issue.record(error, "\(testCase)")
                }
            }
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct ConformanceTestSuite<Client: HTTPClient & ~Copyable> {
    let testServerPort: Int
    let rawServerPort: Int
    let clientFactory: () async throws -> Client

    func run(_ testCase: ConformanceTestCase) async throws {
        /// **WARNING**: Every new conformance test case must be added to this switch
        switch testCase {
        case .testNotHTTP: try await testNotHTTP()
        case .testBadHTTPCase: try await testBadHTTPCase()
        case .testNoReason: try await testNoReason()
        case .test204WithContentLength: try await test204WithContentLength()
        case .test304WithContentLength: try await test304WithContentLength()
        case .testIncompleteBody: try await testIncompleteBody()
        case .testNoLengthHint: try await testNoLengthHint()
        case .testConflictingContentLength: try await testConflictingContentLength()
        case .testOk: try await testOk()
        case .testEchoString: try await testEchoString()
        case .testGzip: try await testGzip()
        case .testDeflate: try await testDeflate()
        case .testBrotli: try await testBrotli()
        case .testIdentity: try await testIdentity()
        case .testCustomHeader: try await testCustomHeader()
        case .testBasicRedirect: try await testBasicRedirect()
        case .testNotFound: try await testNotFound()
        case .testStatusOutOfRangeButValid: try await testStatusOutOfRangeButValid()
        case .testStressTest: try await testStressTest()
        case .testGetConvenience: try await testGetConvenience()
        case .testPostConvenience: try await testPostConvenience()
        case .testCancelPreHeaders: try await testCancelPreHeaders()
        case .testCancelPreBody: try await testCancelPreBody()
        case .testEcho1MBBody: try await testEcho1MBBody()
        case .testUnderRead: try await testUnderRead()
        case .testClientSendsEmptyHeaderValue: try await testClientSendsEmptyHeaderValue()
        case .testInfiniteRedirect: try await testInfiniteRedirect()
        case .testHeadWithContentLength: try await testHeadWithContentLength()
        case .testServerSendsMultiValueHeader: try await testServerSendsMultiValueHeader()
        case .testClientSendsMultiValueHeader: try await testClientSendsMultiValueHeader()
        case .testBasicCookieSetAndUse: try await testBasicCookieSetAndUse()
        case .testEchoInterleave: try await testEchoInterleave()
        case .testSpeakInterleave: try await testSpeakInterleave()
        case .testEmptyChunkedBody: try await testEmptyChunkedBody()
        case .testURLParams: try await testURLParams()
        case .testETag: try await testETag()
        }
    }

    func testNotHTTP() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(rawServerPort)",
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
            authority: "127.0.0.1:\(rawServerPort)",
            path: "/no_reason"
        )
        try await client.perform(
            request: request,
        ) { response, _ in
            #expect(response.status == .ok)
        }
    }

    func testBadHTTPCase() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(rawServerPort)",
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
            authority: "127.0.0.1:\(rawServerPort)",
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
            authority: "127.0.0.1:\(rawServerPort)",
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
            authority: "127.0.0.1:\(rawServerPort)",
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
            authority: "127.0.0.1:\(rawServerPort)",
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
            authority: "127.0.0.1:\(rawServerPort)",
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

    func testOk() async throws {
        let client = try await clientFactory()
        let methods = [HTTPRequest.Method.head, .get, .put, .post, .delete]
        for method in methods {
            let request = HTTPRequest(
                method: method,
                scheme: "http",
                authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
                authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            let port = self.testServerPort

            group.addTask {
                // The /stall HTTP endpoint is not expected to return at all.
                // Because of the cancellation, we're expected to return from this task group
                // within 100ms.
                let request = HTTPRequest(
                    method: .get,
                    scheme: "http",
                    authority: "127.0.0.1:\(port) ",
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
            let port = self.testServerPort

            group.addTask {
                // The /stall_body HTTP endpoint gives headers and an incomplete 1000-byte body.
                let request = HTTPRequest(
                    method: .get,
                    scheme: "http",
                    authority: "127.0.0.1:\(port) ",
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
            url: URL(string: "http://127.0.0.1:\(testServerPort)/request")!,
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
            url: URL(string: "http://127.0.0.1:\(testServerPort)/request")!,
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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
            authority: "127.0.0.1:\(testServerPort)",
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

    func testETag() async throws {
        let client = try await clientFactory()
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:\(testServerPort)",
            path: "/etag"
        )

        for i in 0..<3 {
            // The server starts a counter from 0 and uses it as the
            // `ETag` and request body. It will only increment the
            // counter when the client sends an `If-None-Match` with
            // the same counter value.
            //
            // So the 6 requests we make must have the following
            // headers, response codes and body:
            //
            // # |If-None-Match| Code | ETag  | Body |
            // 1 |    nil      | 200  |   0   |  0   |
            // 2 |     0       | 304  |   0   | nil  |
            // 3 |     0       | 200  |   1   |  1   |
            // 4 |     1       | 304  |   1   | nil  |
            // 5 |     1       | 200  |   2   |  2   |
            // 6 |     2       | 304  |   2   | nil  |
            //
            // If a client does not send `If-None-Match` or the
            // wrong value, then the server won't increment the
            // counter, so this test should break.

            let expectedResponse = String(i)
            for _ in 0..<2 {
                try await client.perform(
                    request: request
                ) { response, responseBodyAndTrailers in
                    #expect(response.status == .ok)
                    let (response, _) = try await responseBodyAndTrailers.collect(upTo: 5) { span in
                        return String(copying: try UTF8Span(validating: span))
                    }
                    #expect(response == expectedResponse)
                }
            }
        }
    }

    func testURLParams() async throws {
        let client = try await clientFactory()
        var components = URLComponents(string: "http://127.0.0.1:\(testServerPort)/request")!
        components.queryItems = [
            URLQueryItem(name: "foo", value: "bar"),
            URLQueryItem(name: "bar", value: "baz"),
            URLQueryItem(name: "baz", value: "qux"),
            URLQueryItem(name: "qux", value: ""),
            URLQueryItem(name: "foo", value: "phew"),
        ]
        let request = HTTPRequest(url: components.url!)
        try await client.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            let (jsonRequest, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let body = String(copying: try UTF8Span(validating: span))
                let data = body.data(using: .utf8)!
                return try JSONDecoder().decode(JSONHTTPRequest.self, from: data)
            }

            #expect(
                jsonRequest.params == [
                    "foo": ["bar", "phew"],
                    "bar": ["baz"],
                    "baz": ["qux"],
                    "qux": [""],
                ]
            )
        }
    }
}
