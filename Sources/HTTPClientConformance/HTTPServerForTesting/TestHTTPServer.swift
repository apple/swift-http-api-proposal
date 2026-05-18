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

import AsyncStreaming
import BasicContainers
import ContainersPreview
import Foundation
import HTTPAPIs
import HTTPTypes
import Logging
import Synchronization

extension HTTPField.Name {
    // Used in ETag tests
    static let cached: Self = .init("Cached")!
}

// HTTP request as received by the server.
// Encoded into JSON and written back to the client.
struct JSONHTTPRequest: Codable {
    // Params from the request
    let params: [String: [String]]

    // Headers from the request
    let headers: [String: [String]]

    // Body of the request
    let body: String

    // Method of the request
    let method: String

    // Trailers from the request
    let trailers: [String: [String]]
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public func withTestHTTPServer(perform: (Int) async throws -> Void) async throws {
    try await withThrowingTaskGroup {
        let logger = Logger(label: "TestHTTPServer")
        let server = NIOHTTPServer(logger: logger, configuration: .init(bindTarget: .hostAndPort(host: "127.0.0.1", port: 0)))
        $0.addTask {
            try await serve(server: server)
        }
        let port = try await server.listeningAddress.port
        print("Test HTTP Server: \(port)")
        try await perform(port)
        $0.cancelAll()
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct ETag: Sendable & ~Copyable {
    let eTag: Mutex<Int> = .init(0)

    func next(clientETag: String?) -> (String, Bool) {
        eTag.withLock { currentETag in
            guard let clientETag, Int(clientETag) == currentETag else {
                // Client doesn't have an ETag or it
                // doesn't match ours. Give ours.
                return (String(currentETag), false)
            }
            // Client's ETag is the same as ours.
            // Nothing changed.

            // Every time the client ETag matches
            // ours, we change the ETag for the
            // next attempt.
            let oldETag = currentETag
            currentETag += 1

            return (String(oldETag), true)
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
func serve(server: NIOHTTPServer) async throws {
    let eTag = ETag()
    try await server.serve { request, requestContext, requestReceiver, responseSender in
        // This server expects a path
        guard let path = request.path else {
            try await responseSender.send(
                HTTPResponse(status: .internalServerError),
                body: "No path specified".utf8.span
            )
            return
        }

        // This server expects a valid path
        guard let components = URLComponents(string: path) else {
            try await responseSender.send(
                HTTPResponse(status: .internalServerError),
                body: "Malformed path".utf8.span
            )
            return
        }

        switch components.path {
        case "/request":
            // Returns a JSON describing the request received.

            // Collect the params that were sent in with the request
            var params: [String: [String]] = [:]
            if let queryItems = components.queryItems {
                for query in queryItems {
                    params[query.name, default: []].append(query.value ?? "")
                }
            }

            // Collect the headers that were sent in with the request
            var headers: [String: [String]] = [:]
            for field in request.headerFields {
                headers[field.name.rawName, default: []].append(field.value)
            }

            // Parse the body as a UTF8 string and capture trailers
            var bodyBuffer = UniqueArray<UInt8>(minimumCapacity: 1024)
            let requestTrailers = try await requestReceiver.collect(into: &bodyBuffer)
            let body = String(copying: try UTF8Span(validating: bodyBuffer.span))

            // Collect the trailers that were sent in with the request
            var trailers: [String: [String]] = [:]
            if let requestTrailers {
                for field in requestTrailers {
                    trailers[field.name.rawName, default: []].append(field.value)
                }
            }

            let method = request.method.rawValue

            // Construct the JSON request object and send it as a response
            let response = JSONHTTPRequest(params: params, headers: headers, body: body, method: method, trailers: trailers)

            let responseData = try JSONEncoder().encode(response)
            try await responseSender.send(HTTPResponse(status: .ok), body: responseData.span)
        case "/head_with_cl":
            if request.method != .head {
                try await responseSender.send(HTTPResponse(status: .methodNotAllowed))
                break
            }

            // OK with a theoretical 1000-byte body
            try await responseSender.send(
                HTTPResponse(
                    status: .ok,
                    headerFields: [
                        .contentLength: "1000"
                    ]
                )
            )
        case "/200":
            // Do not write a response body for a HEAD request
            if request.method == .head {
                try await responseSender.send(HTTPResponse(status: .ok))
            } else {
                try await responseSender.send(HTTPResponse(status: .ok), body: "".utf8.span)
            }
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

            try await responseSender.send(HTTPResponse(status: .ok, headerFields: headers), body: bytes.span)
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

            try await responseSender.send(HTTPResponse(status: .ok, headerFields: headers), body: bytes.span)
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

            try await responseSender.send(HTTPResponse(status: .ok, headerFields: headers), body: bytes.span)
        case "/header_multivalue":
            try await responseSender.send(
                HTTPResponse(
                    status: .ok,
                    headerFields: [
                        .init("X-Test")!: "one",
                        .init("X-Test")!: "two",
                    ]
                )
            )
        case "/identity":
            // This will always write out the body with no encoding.
            // Used to check that a client can handle fallback to no encoding.
            try await responseSender.send(HTTPResponse(status: .ok), body: "TEST\n".utf8.span)
        case "/redirect_ping":
            // Infinite redirection as a result of arriving here
            try await responseSender.send(
                HTTPResponse(status: .movedPermanently, headerFields: HTTPFields([HTTPField(name: .location, value: "/redirect_pong")])),
                body: "".utf8.span
            )
        case "/redirect_pong":
            // Infinite redirection as a result of arriving here
            try await responseSender.send(
                HTTPResponse(status: .movedPermanently, headerFields: HTTPFields([HTTPField(name: .location, value: "/redirect_ping")])),
                body: "".utf8.span
            )
        case "/301":
            // Redirect to /request
            try await responseSender.send(
                HTTPResponse(status: .movedPermanently, headerFields: HTTPFields([HTTPField(name: .location, value: "/request")])),
                body: "".utf8.span
            )
        case "/308":
            // Redirect to /request
            try await responseSender.send(
                HTTPResponse(
                    status: .permanentRedirect,
                    headerFields: HTTPFields(
                        [HTTPField(name: .location, value: "/request")]
                    )
                ),
                body: "".utf8.span
            )
        case "/404":
            try await responseSender.send(HTTPResponse(status: .notFound), body: "".utf8.span)
        case "/999":
            try await responseSender.send(HTTPResponse(status: 999), body: "".utf8.span)
        case "/echo":
            // Bad method
            if request.method != .post {
                try await responseSender.send(
                    HTTPResponse(status: .methodNotAllowed),
                    body: "Incorrect method".utf8.span
                )
                return
            }

            // Move requestReceiver into Optional so it can be taken across the closure boundary.
            var requestReceiver = Optional(requestReceiver)
            try await responseSender.send(.init(status: .ok)) { writer in
                var writer = writer
                let (_, trailers) = try await requestReceiver.take()!.receive { reader in
                    try await writer.write(reader)
                }
                return ((), trailers)
            }
        case "/speak":
            // Server writes 1000 1-byte chunks of "A" and expects each
            // chunk to be written back by the client before proceeding
            // with the next one.
            var requestReceiver = Optional(requestReceiver)
            try await responseSender.send(.init(status: .ok)) { writer in
                var writer = writer
                let (_, _) = try await requestReceiver.take()!.receive { reader in
                    var reader = reader
                    for _ in 0..<1000 {
                        // Write a single-byte chunk
                        try await writer.write("A".utf8.span)

                        // Wait for the client to write the same chunk to the request body
                        try await reader.read { buffer in
                            if buffer.count != 1 || buffer[buffer.startIndex] != UInt8(ascii: "A") {
                                assertionFailure("Received unexpected span")
                            }
                            buffer.removeAll()
                        }
                    }
                }
                return ((), nil)
            }
        case "/stall":
            do {
                // Wait for an hour (effectively never giving an answer)
                try await Task.sleep(for: .seconds(60 * 60))
                assertionFailure("Not expected to complete hour-long wait")
            } catch {
                // It is okay for the client to give up on the connection due to the stall.
            }
        case "/stall_body":
            do {
                try await responseSender.send(.init(status: .ok)) { writer in
                    var writer = writer
                    try await writer.write([UInt8](repeating: UInt8(ascii: "A"), count: 1000).span)

                    // Wait for an hour (effectively never giving an answer)
                    try await Task.sleep(for: .seconds(60 * 60))

                    assertionFailure("Not expected to complete hour-long wait")

                    return ((), nil)
                }
            } catch {
                // It is okay for the client to give up on the connection due to the stall.
            }
        case "/1mb_body":
            let data = String(repeating: "A", count: 1_000_000).data(using: .ascii)!
            do {
                try await responseSender.send(.init(status: .ok), body: data.span)
            } catch {
                // It is okay for the client to give up while reading this response.
                // Example: a client may only want the first byte from this response.
                // TCP flow control would stop the entire body from being written out,
                // and then the client would just close the connection. That is an
                // acceptable outcome here.
            }
        case "/cookie":
            let cookie = UUID().uuidString
            try await responseSender.send(
                .init(
                    status: .ok,
                    headerFields: [
                        .setCookie: "foo=\(cookie)"
                    ]
                ),
                body: Span<UInt8>()
            )
        case "/etag":
            let clientETag = request.headerFields[.ifNoneMatch]
            let (serverETag, isNotModified) = eTag.next(clientETag: clientETag)
            if isNotModified {
                // Nothing has changed, so 304 Not Modified.
                try await responseSender.send(
                    .init(
                        status: .notModified,
                        headerFields: [
                            .eTag: serverETag,
                            .cached: "true",
                        ]
                    ),
                    body: Span<UInt8>()
                )
            } else {
                // The server wants to give a new ETag to the client
                // Give the etag itself as the new body
                let data = serverETag.data(using: .ascii)!
                try await responseSender.send(
                    .init(
                        status: .ok,
                        headerFields: [
                            .eTag: serverETag,
                            .cached: "false",
                        ]
                    ),
                    body: data.span
                )
            }
        case "/trailers":
            // Send a response with custom trailers
            try await responseSender.send(.init(status: .ok)) { writer in
                var writer = writer
                // Write the body
                try await writer.write("Response body".utf8.span)
                // Return custom trailers
                return (
                    (),
                    [
                        .init("X-Trailer-One")!: "first-value",
                        .init("X-Trailer-Two")!: "second-value",
                        .init("X-Checksum")!: "abc123",
                    ]
                )
            }
        default:
            try await responseSender.send(
                HTTPResponse(status: .internalServerError),
                body: "Unknown path".utf8.span
            )
        }
    }
}
