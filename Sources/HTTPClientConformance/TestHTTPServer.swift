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

import AsyncStreaming
import Foundation
import HTTPServerForTesting
import HTTPTypes
import Logging

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
