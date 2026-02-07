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
import HTTPClient
import HTTPTypes
import Synchronization
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
protocol HTTPClientConformanceValidator<Client>: Sendable {
    associatedtype Client: HTTPClient & Sendable & ~Copyable where Client.RequestOptions: HTTPClientCapability.RedirectionHandler
    
    func newClient() async -> Client
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClientConformanceValidator {
    func runAllConformanceTests() async throws  {
        let server = TestHTTPServer()
        await server.serve()
        
        let cases = [
            Self.ok,
            
            // TODO: Writing just an empty span causes an indefinite stall. The terminating chunk (size 0) is not written out on the wire.
            // Self.emptyChunkedBody,
            
            Self.echoString,
            Self.gzip,
            Self.deflate,
            Self.brotli,
            Self.identity,
            Self.customHeader,
            Self.redirect301,
            Self.redirect308,
            Self.notFound,
            Self.statusOutOfRangeButValid,
            Self.stressTest,
            Self.echoInterleave,
            
            // TODO: These tests crash. It can be enabled once we have correctly dealt with task cancellation.
            // Self.cancelPreHeaders,
            // Self.cancelPreBody,
            
            Self.getConvenience,
            Self.postConvenience
        ]
        
        for testCase in cases {
            let testCaseWithSelf = testCase(self)
            try await testCaseWithSelf()
        }
    }
    
    func ok() async throws {
        let methods = [HTTPRequest.Method.head, .get, .put, .post, .delete]
        for method in methods {
            let request = HTTPRequest(
                method: method,
                scheme: "http",
                authority: "127.0.0.1:12345",
                path: "/200"
            )
            try await newClient().perform(
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

    func emptyChunkedBody() async throws {
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/request"
        )
        try await newClient().perform(
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

    func echoString() async throws {
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/echo"
        )
        try await newClient().perform(
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

    func gzip() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/gzip"
        )
        try await newClient().perform(
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

    func deflate() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/deflate"
        )
        try await newClient().perform(
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

    func brotli() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/brotli",
        )
        try await newClient().perform(
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

    func identity() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/identity",
        )
        try await newClient().perform(
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

    func customHeader() async throws {
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/request",
            headerFields: HTTPFields([HTTPField(name: .init("X-Foo")!, value: "BARbaz")])
        )

        try await newClient().perform(
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

    func redirect308() async throws {
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

        try await newClient().perform(
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

    func redirect301() async throws {
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

        try await newClient().perform(
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

    func notFound() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/404"
        )

        try await newClient().perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .notFound)
            let (_, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let isEmpty = span.isEmpty
                #expect(isEmpty)
            }
        }
    }

    func statusOutOfRangeButValid() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/999"
        )

        try await newClient().perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == 999)
            let (_, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let isEmpty = span.isEmpty
                #expect(isEmpty)
            }
        }
    }

    func stressTest() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/request"
        )

        try await withThrowingTaskGroup { group in
            for _ in 0..<100 {
                group.addTask {
                    try await newClient().perform(
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

    func echoInterleave() async throws {
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/echo"
        )

        // Used to ping-pong between the client-side writer and reader
        let writerWaiting: Mutex<CheckedContinuation<Void, Never>?> = .init(nil)

        try await newClient().perform(
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

    func cancelPreHeaders() async throws {
        // The /stall HTTP endpoint is not expected to return at all.
        // Because of the cancellation, we're expected to return from this task group
        // within 100ms.
        let task = Task {
            let request = HTTPRequest(
                method: .get,
                scheme: "http",
                authority: "127.0.0.1:12345",
                path: "/stall",
            )

            try await newClient().perform(
                request: request,
            ) { response, responseBodyAndTrailers in
                assertionFailure("Never expected to actually receive a response")
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        try await task.value
    }

    func cancelPreBody() async throws {
        // The /stall_body HTTP endpoint gives headers, but is not expected to return a
        // body. Because of the cancellation, we're expected to return from this task group
        // within 100ms.
        let task = Task {
            let request = HTTPRequest(
                method: .get,
                scheme: "http",
                authority: "127.0.0.1:12345",
                path: "/stall_body",
            )

            try await newClient().perform(
                request: request,
            ) { response, responseBodyAndTrailers in
                #expect(response.status == .ok)
                let _ = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                    assertionFailure("Not expected to receive a body")
                }
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        try await task.value
    }

    func getConvenience() async throws {
        let (response, data) = try await newClient().get(
            url: URL(string: "http://127.0.0.1:12345/request")!,
            collectUpTo: .max
        )
        #expect(response.status == .ok)
        let jsonRequest = try JSONDecoder().decode(JSONHTTPRequest.self, from: data)
        #expect(jsonRequest.method == "GET")
        #expect(!jsonRequest.headers.isEmpty)
        #expect(jsonRequest.body.isEmpty)
    }

    func postConvenience() async throws {
        let (response, data) = try await newClient().post(
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
}
