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
import Testing
import Logging
import Synchronization

let testsEnabled: Bool = {
    #if canImport(Darwin)
    true
    #else
    false
    #endif
}()

// Request as received by the server
struct Request: Codable {
    // Headers from the request
    let headers: [String: [String]]
    
    // Body of the request
    let body: String
    
    // Method of the request
    let method: String
}

actor TestHTTPServer {
    let logger: Logger
    let server: NIOHTTPServer
    var running: Bool
    
    init() {
        logger = Logger(label: "TestHTTPServer")
        server = NIOHTTPServer(logger: logger, configuration: .init(bindTarget: .hostAndPort(host: "127.0.0.1", port: 12345)))
        running = false
    }
    
    func serve() {
        // Since this is one server running for all test cases, only serve it once.
        if running {
            return
        }
        print("Serving HTTP on localhost:12345")
        running = true
        Task {
            try await server.serve { request, requestContext, requestBodyAndTrailers, responseSender in
                switch request.path {
                case "/request":
                    // Returns a JSON describing the request received.
                    
                    // Collect the headers that were sent in with the request
                    var headers: [String: [String]] = [:]
                    for field in request.headerFields {
                        if var header = headers[field.name.rawName] {
                            header.append(field.value)
                        } else {
                            headers[field.name.rawName] = [field.value]
                        }
                    }
                    
                    // Parse the body as a UTF8 string
                    let (body, _) = try await requestBodyAndTrailers.collect(upTo: 1024) { span in
                        return String(copying: try UTF8Span(validating: span))
                    }
                    
                    let method = request.method.rawValue;
                    
                    // Construct the JSON request object and send it as a response
                    let response = Request(headers: headers, body: body, method: method)
                    
                    let response_data = try JSONEncoder().encode(response)
                    let response_span = response_data.span
                    let writer = try await responseSender.send(HTTPResponse(status: .ok))
                    try await writer.writeAndConclude(response_span, finalElement: nil)
                case "/200":
                    // OK
                    let writer = try await responseSender.send(HTTPResponse(status: .ok))
                    try await writer.writeAndConclude("".utf8.span, finalElement: nil)
                case "/gzip":
                    // OK
                    let response_headers = HTTPFields([HTTPField(name: .contentEncoding, value: "gzip")])
                    let writer = try await responseSender.send(HTTPResponse(status: .ok, headerFields: response_headers))
                    
                    // "TEST\n" as gzip-encode
                    let bytes: [UInt8] = [0x1f,0x8b,0x08,0x00,0xfd,0xd6,0x77,0x69,0x04,0x03,0x0b,0x71,0x0d,0x0e,0xe1,0x02,0x00,0xbe,0xd7,0x83,0xf7,0x05,0x00,0x00,0x00]
                    
                    try await writer.writeAndConclude(bytes.span, finalElement: nil)
                case "/brotli":
                    // OK
                    let response_headers = HTTPFields([HTTPField(name: .contentEncoding, value: "br")])
                    let writer = try await responseSender.send(HTTPResponse(status: .ok, headerFields: response_headers))
                    
                    // "TEST\n" as brotli-encode
                    let bytes: [UInt8] = [0x0f,0x02,0x80,0x54,0x45,0x53,0x54,0x0a,0x03]
                    
                    try await writer.writeAndConclude(bytes.span, finalElement: nil)
                case "/301":
                    // Redirect to /request
                    let writer = try await responseSender.send(HTTPResponse(status: .movedPermanently, headerFields: HTTPFields([HTTPField(name: .location, value: "/request")])))
                    try await writer.writeAndConclude("".utf8.span, finalElement: nil)
                case "/308":
                    // Redirect to /request
                    let writer = try await responseSender.send(HTTPResponse(status: .permanentRedirect, headerFields: HTTPFields([HTTPField(name: .location, value: "/request")])))
                    try await writer.writeAndConclude("".utf8.span, finalElement: nil)
                case "/404":
                    let writer = try await responseSender.send(HTTPResponse(status: .notFound))
                    try await writer.writeAndConclude("".utf8.span, finalElement: nil)
                case "/999":
                    let writer = try await responseSender.send(HTTPResponse(status: .init(integerLiteral: 999)))
                    try await writer.writeAndConclude("".utf8.span, finalElement: nil)
                case "/echo":
                    // Bad method
                    if request.method != .post {
                        let writer = try await responseSender.send(HTTPResponse(status: .methodNotAllowed))
                        try await writer.writeAndConclude("Incorrect method".utf8.span, finalElement: nil)
                        return
                    }
                
                    // Needed since we are lacking call-once closures
                    var responseSender = Optional(responseSender)

                    _ = try await requestBodyAndTrailers.consumeAndConclude { reader in
                        // Needed since we are lacking call-once closures
                        var reader = Optional(reader)
                        
                        // This header stops MIME type sniffing, which can cause delays in receiving
                        // the chunked bytes.
                        let headers = HTTPFields([HTTPField(name: .xContentTypeOptions, value: "nosniff")])
                        let responseBodyAndTrailers = try await responseSender.take()!.send(.init(status: .ok, headerFields: headers))
                        try await responseBodyAndTrailers.produceAndConclude { responseBody in
                            var responseBody = responseBody
                            try await responseBody.write(reader.take()!)
                            return nil
                        }
                    }
                case "/hang":
                    // Wait for an hour (effectively never giving an answer)
                    try! await Task.sleep(for: .seconds(60 * 60))
                    assertionFailure("Not expected to complete hour-long wait")
                case "/hang_body":
                    // Send the headers, but not the body
                    let responseBodyAndTrailers = try await responseSender.send(.init(status: .ok))
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
    static let server = TestHTTPServer()
    
    let httpMethods: [HTTPRequest.Method] = [.head, .get, .put, .post, .delete]
    
    init() async {
        await HTTPClientTests.server.serve()
    }
    
    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func ok() async throws {
        for method in httpMethods {
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
    }
    
    @Test(.enabled(if: false))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func empty_chunked_body() async throws {
        // TODO: This test hangs.
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/request"
        )
        try await HTTP.perform(
            request: request,
            
            // TODO: This is causing the hang
            body: .restartable(knownLength: 0) { writer in
                var writer = writer
                try await writer.write(Span())
                return nil
            }
            
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            let (json_request, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let body = String(copying: try UTF8Span(validating: span))
                let data = body.data(using: .utf8)!
                return try JSONDecoder().decode(Request.self, from: data)
            }
            #expect(json_request.body.isEmpty)
        }
    }

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func echo_string() async throws {
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
            #expect(response.headerFields[.contentEncoding]!.contains("gzip"))
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
            headerFields: [.acceptEncoding: "br"]
        )
        try await HTTP.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            #expect(response.headerFields[.contentEncoding]!.contains("br"))
            let (body, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                return String(copying: try UTF8Span(validating: span))
            }
            #expect(body == "TEST\n")
        }
    }
    
    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func custom_headers() async throws {
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
            let (json_request, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let body = String(copying: try UTF8Span(validating: span))
                let data = body.data(using: .utf8)!
                return try JSONDecoder().decode(Request.self, from: data)
            }
            #expect(json_request.headers["X-Foo"] == ["BARbaz"])
        }
    }
    
    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func redirect_308() async throws {
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
            let (json_request, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let body = String(copying: try UTF8Span(validating: span))
                let data = body.data(using: .utf8)!
                return try JSONDecoder().decode(Request.self, from: data)
            }
            #expect(json_request.method == "GET")
            #expect(json_request.body.isEmpty)
            #expect(!json_request.headers.isEmpty)
        }
    }
    
    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func redirect_301() async throws {
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
            let (json_request, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let body = String(copying: try UTF8Span(validating: span))
                let data = body.data(using: .utf8)!
                return try JSONDecoder().decode(Request.self, from: data)
            }
            #expect(json_request.method == "GET")
            #expect(json_request.body.isEmpty)
            #expect(!json_request.headers.isEmpty)
        }
    }
    
    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func not_found() async throws {
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
    func status_out_of_range_but_valid() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/999"
        )
        
        try await HTTP.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .init(integerLiteral: 999))
            let (_, _) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let isEmpty = span.isEmpty
                #expect(isEmpty)
            }
        }
    }
    
    @Test(.enabled(if: false))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func timeout() async throws {
        // TODO: This test is technically exercising Darwin-specific timeouts.
        let request = HTTPRequest(
            method: .get,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/hang"
        )
        
        do {
            try await HTTP.perform(
                request: request,
            ) { response, responseBodyAndTrailers in
                assertionFailure("Expected error but got none")
            }
        } catch let error as NSError {
            #expect(error.domain == NSURLErrorDomain)
            #expect(error.code == NSURLErrorTimedOut)
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
                        try await responseBodyAndTrailers.collect(upTo: 1024) { span in
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
    func echo_interleave() async throws {
        // This header stops MIME type sniffing, which can cause delays in receiving
        // the chunked bytes.
        let headers = HTTPFields([HTTPField(name: .xContentTypeOptions, value: "nosniff")])
        let request = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "127.0.0.1:12345",
            path: "/echo",
            headerFields: headers
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
                        writerWaiting.withLock{ $0 = continuation }
                    }
                }
                return nil
            }
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            try await responseBodyAndTrailers.consumeAndConclude { reader in
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
    func cancel_hang() async throws {
        // The /hang HTTP endpoint is not expected to return at all.
        // Because of the cancellation, we're expected to return from this task group
        // within 100ms.
        try await withThrowingTaskGroup { group in
            group.addTask {
                let request = HTTPRequest(
                    method: .get,
                    scheme: "http",
                    authority: "127.0.0.1:12345",
                    path: "/hang",
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
    func cancel_hang_body() async throws {
        // The /hang_body HTTP endpoint gives headers, but is not expected to return a
        // body. Because of the cancellation, we're expected to return from this task group
        // within 100ms.
        try await withThrowingTaskGroup { group in
            group.addTask {
                let request = HTTPRequest(
                    method: .get,
                    scheme: "http",
                    authority: "127.0.0.1:12345",
                    path: "/hang_body",
                )
                
                try await HTTP.perform(
                    request: request,
                ) { response, responseBodyAndTrailers in
                    #expect(response.status == .ok)
                    try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                        assertionFailure("Not expected to receive a body")
                    }
                }
            }
            
            try await Task.sleep(for: .milliseconds(100))
            group.cancelAll()
        }
    }
}
