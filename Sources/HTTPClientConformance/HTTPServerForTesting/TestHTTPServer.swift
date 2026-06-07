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

@available(anyAppleOS 26.0, *)
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

@available(anyAppleOS 26.0, *)
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

@available(anyAppleOS 26.0, *)
func serve(server: NIOHTTPServer) async throws {
    let eTag = ETag()
    try await server.serve {
        request,
        requestContext,
        requestReader,
        responseSender in
        // This server expects a path
        guard let path = request.path else {
            var body = UniqueArray<UInt8>(
                capacity: 17,
                copying: "No path specified".utf8
            )
            try await responseSender.sendAndFinish(HTTPResponse(status: .internalServerError), buffer: &body, trailer: nil)
            return
        }

        // This server expects a valid path
        guard let components = URLComponents(string: path) else {
            var body = UniqueArray<UInt8>(
                capacity: 17,
                copying: "Malformed path".utf8
            )
            try await responseSender.sendAndFinish(HTTPResponse(status: .internalServerError), buffer: &body, trailer: nil)
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
            let (body, requestTrailers) = try await requestReader.collect(upTo: 1_000_000) { span in
                String(copying: try UTF8Span(validating: span.span))
            }

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
            var arrayResponseData = UniqueArray<UInt8>(copying: responseData)
            try await responseSender.sendAndFinish(HTTPResponse(status: .ok), buffer: &arrayResponseData, trailer: nil)
        case "/head_with_cl":
            if request.method != .head {
                try await responseSender.sendAndFinish(HTTPResponse(status: .methodNotAllowed))
                break
            }

            // OK with a theoretical 1000-byte body
            try await responseSender.sendAndFinish(
                HTTPResponse(
                    status: .ok,
                    headerFields: [
                        .contentLength: "1000"
                    ]
                )
            )
        case "/200":
            try await responseSender.sendAndFinish(HTTPResponse(status: .ok))
        case "/gzip":
            // If the client didn't say that they supported this encoding,
            // then fallback to no encoding.
            let acceptEncoding = request.headerFields[.acceptEncoding]
            var bytes: UniqueArray<UInt8>
            var headers: HTTPFields
            if let acceptEncoding,
                acceptEncoding.contains("gzip")
            {
                // "TEST\n" as gzip
                bytes = .init(copying: [
                    0x1f,
                    0x8b,
                    0x08,
                    0x00,
                    0xfd,
                    0xd6,
                    0x77,
                    0x69,
                    0x04,
                    0x03,
                    0x0b,
                    0x71,
                    0x0d,
                    0x0e,
                    0xe1,
                    0x02,
                    0x00,
                    0xbe,
                    0xd7,
                    0x83,
                    0xf7,
                    0x05,
                    0x00,
                    0x00,
                    0x00,
                ])
                headers = [.contentEncoding: "gzip"]
            } else {
                // "TEST\n" as raw ASCII
                bytes = .init(copying: [84, 69, 83, 84, 10])
                headers = [:]
            }

            try await responseSender.sendAndFinish(HTTPResponse(status: .ok, headerFields: headers), buffer: &bytes, trailer: nil)
        case "/deflate":
            // If the client didn't say that they supported this encoding,
            // then fallback to no encoding.
            let acceptEncoding = request.headerFields[.acceptEncoding]
            var bytes: UniqueArray<UInt8>
            var headers: HTTPFields
            if let acceptEncoding,
                acceptEncoding.contains("deflate")
            {
                // "TEST\n" as deflate
                bytes = .init(copying: [0x78, 0x9c, 0x0b, 0x71, 0x0d, 0x0e, 0xe1, 0x02, 0x00, 0x04, 0x68, 0x01, 0x4b])
                headers = [.contentEncoding: "deflate"]
            } else {
                // "TEST\n" as raw ASCII
                bytes = .init(copying: [84, 69, 83, 84, 10])
                headers = [:]
            }

            try await responseSender
                .sendAndFinish(HTTPResponse(status: .ok, headerFields: headers), buffer: &bytes, trailer: nil)
        case "/brotli":
            // If the client didn't say that they supported this encoding,
            // then fallback to no encoding.
            let acceptEncoding = request.headerFields[.acceptEncoding]
            var bytes: UniqueArray<UInt8>
            var headers: HTTPFields
            if let acceptEncoding,
                acceptEncoding.contains("br")
            {
                // "TEST\n" as brotli
                bytes = .init(copying: [0x0f, 0x02, 0x80, 0x54, 0x45, 0x53, 0x54, 0x0a, 0x03])
                headers = [.contentEncoding: "br"]
            } else {
                // "TEST\n" as raw ASCII
                bytes = .init(copying: [84, 69, 83, 84, 10])
                headers = [:]
            }

            try await responseSender.sendAndFinish(HTTPResponse(status: .ok, headerFields: headers), buffer: &bytes, trailer: nil)
        case "/header_multivalue":
            try await responseSender.sendAndFinish(
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
            var body = UniqueArray<UInt8>(copying: "TEST\n".utf8)
            try await responseSender.sendAndFinish(HTTPResponse(status: .ok), buffer: &body, trailer: nil)
        case "/redirect_ping":
            // Infinite redirection as a result of arriving here
            try await responseSender.sendAndFinish(
                HTTPResponse(status: .movedPermanently, headerFields: [.location: "/redirect_pong"])
            )
        case "/redirect_pong":
            // Infinite redirection as a result of arriving here
            try await responseSender.sendAndFinish(
                HTTPResponse(status: .movedPermanently, headerFields: [.location: "/redirect_ping"])
            )
        case "/301":
            // Redirect to /request
            try await responseSender.sendAndFinish(
                HTTPResponse(status: .movedPermanently, headerFields: [.location: "/request"])
            )
        case "/308":
            // Redirect to /request
            try await responseSender.sendAndFinish(
                HTTPResponse(status: .permanentRedirect, headerFields: [.location: "/request"])
            )
        case "/404":
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
        case "/999":
            try await responseSender.sendAndFinish(HTTPResponse(status: 999))
        case "/echo":
            // Bad method
            if request.method != .post {
                var body = UniqueArray<UInt8>(copying: "Incorrect method".utf8)
                try await responseSender.sendAndFinish(
                    HTTPResponse(status: .methodNotAllowed),
                    buffer: &body,
                    trailer: nil
                )
                return
            }

            // Pipe the request body straight back into the response,
            // fusing the last chunk + trailers + FIN into one writer.finish.
            let writer = try await responseSender.send(.init(status: .ok))
            try await requestReader.pipe(into: writer)
        case "/speak":
            // Server writes 1000 1-byte chunks of "A" and expects each
            // chunk to be written back by the client before proceeding
            // with the next one. The interleaving is genuine: read and
            // write are alternated within the same handler.
            var requestReader = requestReader
            var writer = try await responseSender.send(.init(status: .ok))
            for _ in 0..<1000 {
                var buffer = UniqueArray.init(repeating: UInt8(ascii: "A"), count: 1)
                try await writer
                    .write(buffer: &buffer)
                // Read back the echo before sending the next chunk.
                var got = 0
                while got == 0 {
                    try await requestReader.read { rbuf, _ in
                        var c = rbuf.consumeAll()
                        while c.next() != nil { got += 1 }
                    }
                }
            }
            try await writer.finish(trailer: nil)
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
                var writer = try await responseSender.send(.init(status: .ok))
                var buffer = UniqueArray<UInt8>(copying: [UInt8](repeating: UInt8(ascii: "A"), count: 1000))
                try await writer.write(buffer: &buffer)

                // Wait for an hour (effectively never giving an answer)
                try await Task.sleep(for: .seconds(60 * 60))

                assertionFailure("Not expected to complete hour-long wait")

                try await writer.finish(trailer: nil)
            } catch {
                // It is okay for the client to give up on the connection due to the stall.
            }
        case "/1mb_body":
            var body = UniqueArray<UInt8>(copying: String(repeating: "A", count: 1_000_000).data(using: .ascii)!)
            do {
                try await responseSender.sendAndFinish(.init(status: .ok), buffer: &body, trailer: nil)
            } catch {
                // It is okay for the client to give up while reading this response.
                // Example: a client may only want the first byte from this response.
                // TCP flow control would stop the entire body from being written out,
                // and then the client would just close the connection. That is an
                // acceptable outcome here.
            }
        case "/cookie":
            let cookie = UUID().uuidString
            try await responseSender.sendAndFinish(
                .init(
                    status: .ok,
                    headerFields: [
                        .setCookie: "foo=\(cookie)"
                    ]
                )
            )
        case "/etag":
            let clientETag = request.headerFields[.ifNoneMatch]
            let (serverETag, isNotModified) = eTag.next(clientETag: clientETag)
            if isNotModified {
                // Nothing has changed, so 304 Not Modified.
                try await responseSender.sendAndFinish(
                    .init(
                        status: .notModified,
                        headerFields: [
                            .eTag: serverETag,
                            .cached: "true",
                        ]
                    )
                )
            } else {
                // The server wants to give a new ETag to the client
                // Give the etag itself as the new body
                var body = UniqueArray<UInt8>(copying: serverETag.data(using: .ascii)!)
                try await responseSender.sendAndFinish(
                    .init(
                        status: .ok,
                        headerFields: [
                            .eTag: serverETag,
                            .cached: "false",
                        ]
                    ),
                    buffer: &body,
                    trailer: nil
                )
            }
        case "/trailers":
            // Send a response with custom trailers, fused with the body in a single finish call.
            let writer = try await responseSender.send(.init(status: .ok))
            var buffer = UniqueArray<UInt8>(copying: "Response body".utf8)
            try await writer.finish(
                buffer: &buffer,
                finalElement: [
                    .init("X-Trailer-One")!: "first-value",
                    .init("X-Trailer-Two")!: "second-value",
                    .init("X-Checksum")!: "abc123",
                ]
            )
        default:
            var body = UniqueArray<UInt8>(copying: "Unknown path".utf8)
            try await responseSender.sendAndFinish(HTTPResponse(status: .internalServerError), buffer: &body, trailer: nil)
        }
    }
}
