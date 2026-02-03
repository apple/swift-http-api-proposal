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
import HTTPServerForTesting
import HTTPTypes
import Logging
import Synchronization
import Testing

let testsEnabled: Bool = {
    #if canImport(Darwin)
    true
    #else
    false
    #endif
}()

// HTTP request as received by the server.
// Encoded into JSON and written back to the client.
struct JSONHTTPRequest: Codable {
    // Headers from the request
    let headers: [String: [String]]

    // Body of the request
    let body: String

    // Method of the request
    let method: String
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
actor TestHTTPServer {
    let logger: Logger
    let server: NIOHTTPServer
    var serverTask: Task<Void, any Error>?

    init() {
        logger = Logger(label: "TestHTTPServer")
        server = NIOHTTPServer(logger: logger, configuration: .init(bindTarget: .hostAndPort(host: "127.0.0.1", port: 12345)))
    }

    deinit {
        if let serverTask {
            serverTask.cancel()
        }
    }

    func serve() {
        // Since this is one server running for all test cases, only serve it once.
        if serverTask != nil {
            return
        }
        print("Serving HTTP on localhost:12345")
        serverTask = Task {
            try await server.serve { request, requestContext, requestBodyAndTrailers, responseSender in
                switch request.path {
                case "/request":
                    // Returns a JSON describing the request received.

                    // Collect the headers that were sent in with the request
                    var headers: [String: [String]] = [:]
                    for field in request.headerFields {
                        headers[field.name.rawName, default: []].append(field.value)
                    }

                    // Parse the body as a UTF8 string
                    let (body, _) = try await requestBodyAndTrailers.collect(upTo: 1024) { span in
                        return String(copying: try UTF8Span(validating: span))
                    }

                    let method = request.method.rawValue

                    // Construct the JSON request object and send it as a response
                    let response = JSONHTTPRequest(headers: headers, body: body, method: method)

                    let responseData = try JSONEncoder().encode(response)
                    let responseSpan = responseData.span
                    let writer = try await responseSender.send(HTTPResponse(status: .ok))
                    try await writer.writeAndConclude(responseSpan, finalElement: nil)
                case "/200":
                    // OK
                    let writer = try await responseSender.send(HTTPResponse(status: .ok))
                    try await writer.writeAndConclude("".utf8.span, finalElement: nil)
                case "/gzip":
                    // If the client didn't say that they supported this encoding,
                    // then fallback to no encoding.
                    let acceptEncoding = request.headerFields[.acceptEncoding]
                    var bytes: [UInt8]
                    var headers: HTTPFields
                    if let acceptEncoding,
                        acceptEncoding.contains("gzip")
                    {
                        // "TEST\n" as gzip
                        bytes = [
                            0x1f, 0x8b, 0x08, 0x00, 0xfd, 0xd6, 0x77, 0x69, 0x04, 0x03, 0x0b, 0x71, 0x0d, 0x0e,
                            0xe1, 0x02, 0x00, 0xbe, 0xd7, 0x83, 0xf7, 0x05, 0x00, 0x00, 0x00,
                        ]
                        headers = [.contentEncoding: "gzip"]
                    } else {
                        // "TEST\n" as raw ASCII
                        bytes = [84, 69, 83, 84, 10]
                        headers = [:]
                    }

                    let writer = try await responseSender.send(HTTPResponse(status: .ok, headerFields: headers))
                    try await writer.writeAndConclude(bytes.span, finalElement: nil)
                case "/deflate":
                    // If the client didn't say that they supported this encoding,
                    // then fallback to no encoding.
                    let acceptEncoding = request.headerFields[.acceptEncoding]
                    var bytes: [UInt8]
                    var headers: HTTPFields
                    if let acceptEncoding,
                        acceptEncoding.contains("deflate")
                    {
                        // "TEST\n" as deflate
                        bytes = [0x78, 0x9c, 0x0b, 0x71, 0x0d, 0x0e, 0xe1, 0x02, 0x00, 0x04, 0x68, 0x01, 0x4b]
                        headers = [.contentEncoding: "deflate"]
                    } else {
                        // "TEST\n" as raw ASCII
                        bytes = [84, 69, 83, 84, 10]
                        headers = [:]
                    }

                    let writer = try await responseSender.send(HTTPResponse(status: .ok, headerFields: headers))
                    try await writer.writeAndConclude(bytes.span, finalElement: nil)
                case "/brotli":
                    // If the client didn't say that they supported this encoding,
                    // then fallback to no encoding.
                    let acceptEncoding = request.headerFields[.acceptEncoding]
                    var bytes: [UInt8]
                    var headers: HTTPFields
                    if let acceptEncoding,
                        acceptEncoding.contains("br")
                    {
                        // "TEST\n" as brotli
                        bytes = [0x0f, 0x02, 0x80, 0x54, 0x45, 0x53, 0x54, 0x0a, 0x03]
                        headers = [.contentEncoding: "br"]
                    } else {
                        // "TEST\n" as raw ASCII
                        bytes = [84, 69, 83, 84, 10]
                        headers = [:]
                    }

                    let writer = try await responseSender.send(HTTPResponse(status: .ok, headerFields: headers))
                    try await writer.writeAndConclude(bytes.span, finalElement: nil)
                case "/identity":
                    // This will always write out the body with no encoding.
                    // Used to check that a client can handle fallback to no encoding.
                    let writer = try await responseSender.send(HTTPResponse(status: .ok))
                    try await writer.writeAndConclude("TEST\n".utf8.span, finalElement: nil)
                case "/301":
                    // Redirect to /request
                    let writer = try await responseSender.send(
                        HTTPResponse(status: .movedPermanently, headerFields: HTTPFields([HTTPField(name: .location, value: "/request")]))
                    )
                    try await writer
                        .writeAndConclude("".utf8.span, finalElement: nil)
                case "/308":
                    // Redirect to /request
                    let writer = try await responseSender.send(
                        HTTPResponse(
                            status: .permanentRedirect,
                            headerFields: HTTPFields(
                                [HTTPField(name: .location, value: "/request")]
                            )
                        )
                    )
                    try await writer
                        .writeAndConclude("".utf8.span, finalElement: nil)
                case "/404":
                    let writer = try await responseSender.send(
                        HTTPResponse(status: .notFound)
                    )
                    try await writer
                        .writeAndConclude("".utf8.span, finalElement: nil)
                case "/999":
                    let writer = try await responseSender.send(
                        HTTPResponse(status: 999)
                    )
                    try await writer
                        .writeAndConclude("".utf8.span, finalElement: nil)
                case "/echo":
                    // Bad method
                    if request.method != .post {
                        let writer = try await responseSender.send(
                            HTTPResponse(status: .methodNotAllowed)
                        )
                        try await writer
                            .writeAndConclude(
                                "Incorrect method".utf8.span,
                                finalElement: nil
                            )
                        return
                    }

                    // Needed since we are lacking call-once closures
                    var responseSender = Optional(responseSender)

                    _ =
                        try await requestBodyAndTrailers
                        .consumeAndConclude { reader in
                            // Needed since we are lacking call-once closures
                            var reader = Optional(reader)

                            // This header stops MIME type sniffing, which can cause delays in receiving
                            // the chunked bytes.
                            let headers: HTTPFields = [.xContentTypeOptions: "nosniff"]
                            let responseBodyAndTrailers = try await responseSender.take()!.send(.init(status: .ok, headerFields: headers))
                            try await responseBodyAndTrailers.produceAndConclude { responseBody in
                                var responseBody = responseBody
                                try await responseBody.write(reader.take()!)
                                return nil
                            }
                        }
                case "/stall":
                    // Wait for an hour (effectively never giving an answer)
                    try! await Task.sleep(for: .seconds(60 * 60))
                    assertionFailure("Not expected to complete hour-long wait")
                case "/stall_body":
                    // Send the headers, but not the body
                    let _ = try await responseSender.send(.init(status: .ok))
                    // Wait for an hour (effectively never giving an answer)
                    try! await Task.sleep(for: .seconds(60 * 60))
                    assertionFailure("Not expected to complete hour-long wait")
                default:
                    let writer = try await responseSender.send(HTTPResponse(status: .internalServerError))
                    try await writer.writeAndConclude("Bad/unknown path".utf8.span, finalElement: nil)
                }
            }
        }
    }
}

@Suite
struct HTTPClientTests {
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    static let server = TestHTTPServer()

    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    init() async {
        await HTTPClientTests.server.serve()
    }

    @Test(
        .enabled(if: testsEnabled),
        arguments: [HTTPRequest.Method.head, .get, .put, .post, .delete]
    )
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func ok(_ method: HTTPRequest.Method) async throws {
        let request = HTTPRequest(
            method: method,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/200"
        )
        try await HTTP.perform(
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

    // TODO: Writing just an empty span causes an indefinite stall. The terminating chunk (size 0) is not written out on the wire.
    @Test(.enabled(if: false))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func emptyChunkedBody() async throws {
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/request"
        )
        try await HTTP.perform(
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

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func echoString() async throws {
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/echo"
        )
        try await HTTP.perform(
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

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func gzip() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/gzip"
        )
        try await HTTP.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)

            // If gzip is not advertised by the client, a fallback to no-encoding
            // will occur, which should be supported.
            let contentEncoding = response.headerFields[.contentEncoding]
            #expect(contentEncoding == nil || contentEncoding == "gzip" || contentEncoding == "identity")

            let (body, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                return String(copying: try UTF8Span(validating: span))
            }
            #expect(body == "TEST\n")
        }
    }

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func deflate() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/deflate"
        )
        try await HTTP.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)

            // If deflate is not advertised by the client, a fallback to no-encoding
            // will occur, which should be supported.
            let contentEncoding = response.headerFields[.contentEncoding]
            #expect(contentEncoding == nil || contentEncoding == "deflate" || contentEncoding == "identity")

            let (body, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                return String(copying: try UTF8Span(validating: span))
            }
            #expect(body == "TEST\n")
        }
    }

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func brotli() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/brotli",
        )
        try await HTTP.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)

            // If brotli is not advertised by the client, a fallback to no-encoding
            // will occur, which should be supported.
            let contentEncoding = response.headerFields[.contentEncoding]
            #expect(contentEncoding == nil || contentEncoding == "br" || contentEncoding == "identity")

            let (body, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                return String(copying: try UTF8Span(validating: span))
            }
            #expect(body == "TEST\n")
        }
    }

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func identity() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/identity",
        )
        try await HTTP.perform(
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

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func customHeader() async throws {
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/request",
            headerFields: HTTPFields([HTTPField(name: .init("X-Foo")!, value: "BARbaz")])
        )

        try await HTTP.perform(
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

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func redirect308() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/308"
        )

        var options = HTTPRequestOptions()
        options.redirectionHandlerClosure = { response, newRequest in
            #expect(response.status == .permanentRedirect)
            return .follow(newRequest)
        }

        try await HTTP.perform(
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

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func redirect301() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/301"
        )

        var options = HTTPRequestOptions()
        options.redirectionHandlerClosure = { response, newRequest in
            #expect(response.status == .movedPermanently)
            return .follow(newRequest)
        }

        try await HTTP.perform(
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

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func notFound() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/404"
        )

        try await HTTP.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .notFound)
            let (_, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let isEmpty = span.isEmpty
                #expect(isEmpty)
            }
        }
    }

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func statusOutOfRangeButValid() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/999"
        )

        try await HTTP.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == 999)
            let (_, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let isEmpty = span.isEmpty
                #expect(isEmpty)
            }
        }
    }

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
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
                    try await HTTP.perform(
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

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func echoInterleave() async throws {
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/echo"
        )

        // Used to ping-pong between the client-side writer and reader
        let writerWaiting: Mutex<CheckedContinuation<Void, Never>?> = .init(nil)

        try await HTTP.perform(
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

    // TODO: This test crashes. It can be enabled once we have correctly dealt with task cancellation.
    @Test(.enabled(if: false), .timeLimit(.minutes(1)))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func cancelPreHeaders() async throws {
        // The /stall HTTP endpoint is not expected to return at all.
        // Because of the cancellation, we're expected to return from this task group
        // within 100ms.
        try await withThrowingTaskGroup { group in
            group.addTask {
                let request = HTTPRequest(
                    method: .get,
                    scheme: "http",
                    authority: "127.0.0.1:12345",
                    path: "/stall",
                )

                try await HTTP.perform(
                    request: request,
                ) { response, responseBodyAndTrailers in
                    assertionFailure("Never expected to actually receive a response")
                }
            }
            try await Task.sleep(for: .milliseconds(100))
            group.cancelAll()
        }
    }

    // TODO: This test crashes. It can be enabled once we have correctly dealt with task cancellation.
    @Test(.enabled(if: false), .timeLimit(.minutes(1)))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func cancelPreBody() async throws {
        // The /stall_body HTTP endpoint gives headers, but is not expected to return a
        // body. Because of the cancellation, we're expected to return from this task group
        // within 100ms.
        try await withThrowingTaskGroup { group in
            group.addTask {
                let request = HTTPRequest(
                    method: .get,
                    scheme: "http",
                    authority: "127.0.0.1:12345",
                    path: "/stall_body",
                )

                try await HTTP.perform(
                    request: request,
                ) { response, responseBodyAndTrailers in
                    #expect(response.status == .ok)
                    let _ = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                        assertionFailure("Not expected to receive a body")
                    }
                }
            }

            try await Task.sleep(for: .milliseconds(100))
            group.cancelAll()
        }
    }
}
