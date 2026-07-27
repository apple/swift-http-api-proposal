//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
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
import FetchHTTPClient
import HTTPAPIs
import JavaScriptEventLoop
import JavaScriptKit

// This is needed before any async work is done.
typealias DefaultExecutorFactory = JavaScriptEventLoop
JavaScriptEventLoop.installGlobalExecutor()

let client = FetchHTTPClient()
let status = Status()

// This browser demo has no graceful recovery path, so bad input is reported on
// the status line and then aborts.
func fail(_ message: String) -> Never {
    status.set(message)
    fatalError()
}

// Parse the user-entered URL with the host's WHATWG parser (imported via
// BridgeJS). Invalid input throws.
let urlString = try prompt("URL:", "http://localhost:8000/")
let url: JSURL
do {
    url = try JSURL(urlString)
} catch {
    fail("❌ Not a valid URL")
}

let scheme = String(try url.`protocol`.dropLast())
let authority = try url.host
let path = try url.pathname + url.search

let methodString = try prompt("Method (GET, POST, etc.):", "GET").uppercased()
guard let method = HTTPRequest.Method(methodString) else {
    fail("❌ Not a valid method")
}

// Optionally accept a body
var body: HTTPClientRequestBody<FetchHTTPClient.RequestBodyWriter>? = nil
if method == .post || method == .put {
    let bodyString = try prompt("Body:", "Hello World!")
    body = .restartable { writer in
        let bytes = bodyString.utf8
        status.set("⏳ Writing \(bytes.count) bytes")
        var buffer = UniqueArray<UInt8>(copying: bytes)
        try await writer.finish(buffer: &buffer, finalElement: nil)
    }
}

status.set("⏳ Making \(method) request to \(urlString)")

do {
    try await client.perform(
        request: .init(
            method: method,
            scheme: scheme,
            authority: authority,
            path: path,
            headerFields: [
                .init("Client")!: "Swift-Wasm"
            ]
        ),
        body: body,
        options: .init()
    ) { (response, reader) in
        h2("Response")
        div("\(response.status)")

        var contentLength: Int? = nil
        for header in response.headerFields {
            div("\(header.name): \(header.value)")

            if header.name == .contentLength {
                contentLength = Int(header.value)
            }
        }

        h2("Body")
        status.set("⏳ Reading response body")

        var bytes = [UInt8]()
        if let contentLength = contentLength {
            bytes.reserveCapacity(contentLength)
        }

        status.set("⏳ Read \(bytes.count) bytes")
        _ = try await reader.forEachBuffer { buffer in
            var consumer = buffer.consumeAll()
            while let b = consumer.next() {
                bytes.append(b)
            }
            status.set("⏳ Read \(bytes.count) bytes")
        }
        status.set("✅ Read \(bytes.count) bytes")

        // Display the body if possible
        if let utf8Span = try? UTF8Span(validating: bytes.span) {
            div(String(copying: utf8Span))
        } else {
            div("<binary>")
        }
    }
} catch {
    // Embedded Swift can't reflect over an existential `any Error`, so report a
    // fixed message rather than interpolating `error`.
    status.set("❌ Fetch failed")
}
