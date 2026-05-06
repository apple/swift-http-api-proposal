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

import JavaScriptKit

/// # Javascript Imports
/// This file defines the Javascript classes and functions imported into Swift.

// https://developer.mozilla.org/en-US/docs/Web/API/Headers
@JSClass(from: .global) struct Headers {
    @JSFunction init() throws(JSException)
    @JSFunction func append(_ name: String, _ value: String) throws(JSException)
    @JSFunction func delete(_ name: String) throws(JSException)
    @JSFunction func get(_ name: String) throws(JSException) -> String?
    @JSFunction func has(_ name: String) throws(JSException) -> Bool
    @JSFunction func set(_ name: String, _ value: String) throws(JSException)
    @JSFunction func entries() throws(JSException) -> Iterator
}

@JS struct HeaderIteratorResult {
    let done: Bool?
    let value: [String]?

    init(done: Bool?, value: [String]?) {
        self.done = done
        self.value = value
    }
}

// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Iteration_protocols
@JSClass(from: .global) struct Iterator {
    @JSFunction func next() throws(JSException) -> HeaderIteratorResult
}

// https://developer.mozilla.org/en-US/docs/Web/API/ReadableStreamDefaultReader/read
@JS struct Chunk {
    let value: [UInt8]?
    let done: Bool

    init(value: [UInt8]?, done: Bool) {
        self.value = value
        self.done = done
    }
}

// https://developer.mozilla.org/en-US/docs/Web/API/RequestInit
@JS struct RequestInit {
    let body: JSObject?
    let method: String?
    let headers: Headers?

    init(body: JSObject?, method: String?, headers: Headers?) {
        self.body = body
        self.method = method
        self.headers = headers
    }
}

// https://developer.mozilla.org/en-US/docs/Web/API/ReadableStreamDefaultController
@JSClass(from: .global) struct ReadableStreamDefaultController {
    @JSFunction func enqueue(bytes: [UInt8]) throws(JSException)
    @JSFunction func close() throws(JSException)
}

// https://developer.mozilla.org/en-US/docs/Web/API/ReadableStreamDefaultReader
// TODO: Find a way to remove the @unchecked. This object has to be moved through the different Swift reader types.
@JSClass(from: .global) struct ReadableStreamDefaultReader: @unchecked Sendable {
    @JSFunction func read() async throws(JSException) -> Chunk
}

// https://developer.mozilla.org/en-US/docs/Web/API/ReadableStream
@JSClass(from: .global) struct ReadableStream {
    @JSFunction func getReader() throws(JSException) -> ReadableStreamDefaultReader
}

// https://developer.mozilla.org/en-US/docs/Web/API/Response
@JSClass(from: .global) struct Response {
    @JSGetter var headers: Headers
    @JSGetter var ok: Bool
    @JSGetter var status: Int
    @JSGetter var statusText: String
    @JSGetter var url: String
    @JSGetter var type: String
    @JSGetter var body: ReadableStream
}

// https://developer.mozilla.org/en-US/docs/Web/API/Window/fetch
@JSFunction(from: .global) func fetch(_ resource: String, _ options: RequestInit) async throws(JSException) -> Response
