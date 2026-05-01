import JavaScriptKit

/// # Javascript Imports
/// This file defines the Javascript classes and functions imported into Swift.

// https://developer.mozilla.org/en-US/docs/Web/API/Headers
@JSClass(from: .global) public struct Headers {
    @JSFunction public init() throws(JSException)
    @JSFunction public func append(_ name: String, _ value: String) throws(JSException) -> Void
    @JSFunction public func delete(_ name: String) throws(JSException) -> Void
    @JSFunction public func get(_ name: String) throws(JSException) -> Optional<String>
    @JSFunction public func has(_ name: String) throws(JSException) -> Bool
    @JSFunction public func set(_ name: String, _ value: String) throws(JSException) -> Void
    @JSFunction public func entries() throws(JSException) -> Iterator
}

@JS public struct HeaderIteratorResult {
    public let done: Bool?
    public let value: [String]?

    public init(done: Bool?, value: [String]?) {
        self.done = done
        self.value = value
    }
}

@JSClass(from: .global) public struct Iterator {
    @JSFunction public func next() throws(JSException) -> HeaderIteratorResult
}

// https://developer.mozilla.org/en-US/docs/Web/API/ReadableStreamDefaultReader/read
@JS public struct Chunk {
    public let value: [UInt8]?
    public let done: Bool

    public init(value: [UInt8]?, done: Bool) {
        self.value = value
        self.done = done
    }
}

// https://developer.mozilla.org/en-US/docs/Web/API/RequestInit
@JS public struct RequestInit {
    public let body: [UInt8]?
    public let method: String?
    public let headers: Headers?

    public init(body: [UInt8]?, method: String?, headers: Headers?) {
        self.body = body
        self.method = method
        self.headers = headers
    }
}

// https://developer.mozilla.org/en-US/docs/Web/API/ReadableStreamDefaultController
@JSClass(from: .global) public struct ReadableStreamDefaultController {
    @JSFunction public func enqueue(bytes: [UInt8]) throws(JSException);
    @JSFunction public func close() throws(JSException);
}

// https://developer.mozilla.org/en-US/docs/Web/API/ReadableStreamDefaultReader
// TODO: Find a way to remove the @unchecked. This object has to be moved through the different Swift reader types.
@JSClass(from: .global) public struct ReadableStreamDefaultReader: @unchecked Sendable {
    @JSFunction public func read() async throws(JSException) -> Chunk
}

// https://developer.mozilla.org/en-US/docs/Web/API/ReadableStream
@JSClass(from: .global) public struct ReadableStream {
    @JSFunction public func getReader() throws(JSException) -> ReadableStreamDefaultReader;
}

// https://developer.mozilla.org/en-US/docs/Web/API/Response
@JSClass(from: .global) public struct Response {
    @JSGetter public var headers: Headers
    @JSGetter public var ok: Bool
    @JSGetter public var status: Int
    @JSGetter public var statusText: String
    @JSGetter public var url: String
    @JSGetter public var type: String
    @JSGetter public var body: ReadableStream
}

// https://developer.mozilla.org/en-US/docs/Web/API/Window/fetch
@JSFunction(from: .global) public func fetch(_ resource: String, _ options: RequestInit) async throws(JSException) -> Response
