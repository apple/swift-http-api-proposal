# Abstract HTTP Client API

* Proposal: [SE-NNNN](NNNN-swift-http-client.md)
* Authors: [Swift Networking Workgroup](https://github.com/apple/swift-http-api-proposal)
* Review Manager: TBD
* Status: **Awaiting review**
* Vision: [Networking](https://github.com/swiftlang/swift-evolution/blob/main/visions/networking.md)
* Implementation: [apple/swift-http-api-proposal](https://github.com/apple/swift-http-api-proposal)
* Review: ([pitch](https://forums.swift.org/t/designing-an-http-client-api-for-swift/85254))

## Summary of changes

This proposal introduces an abstract HTTP client protocol with capability-based request options. It utilizes modern Swift language features and offers ease-of-use for library authors. A separate proposal covers concrete client implementations.

## Motivation

HTTP is the Internet's foundational application-layer protocol, yet the Swift ecosystem lacks a standardized HTTP client API that:
1. Utilizes Swift's modern, evolving language capabilities
2. Operates uniformly across the various platforms that the Swift language supports
3. Offers a dependency injection model that allows libraries to work with different client implementations
4. Supports advanced HTTP features, like bidirectional streaming, trailers, and resumable uploads, with progressive disclosure
5. Enables middleware usage to extend HTTP client functionality

Other languages, including Rust and Go, typically have a highly popular, if not built-in, HTTP client that works across platforms out-of-the-box, and also utilizes the patterns and capabilities of those languages.

## Proposed solution

We propose a new HTTP Client API built on two pieces:

1. **Abstract protocol interface** (`HTTPClient`) for dependency injection and testability
2. **Convenience methods** for common use cases with progressive disclosure

### Core protocol

The `HTTPClient` protocol provides a single `perform` method that handles all HTTP interactions. The request and response metadata are expressed as `HTTPRequest` and `HTTPResponse` types, from the Swift HTTP types package. The protocol requires `Sendable`, ensuring all conforming clients are safe to share across concurrency domains.

```swift
public protocol HTTPClient<RequestOptions>: Sendable, ~Copyable, ~Escapable {
    associatedtype RequestOptions: HTTPClientCapability.RequestOptions
    associatedtype RequestWriter: AsyncWriter, ~Copyable, SendableMetatype
        where RequestWriter.WriteElement == UInt8
    associatedtype ResponseConcludingReader: ConcludingAsyncReader, ~Copyable, SendableMetatype
        where ResponseConcludingReader.Underlying.ReadElement == UInt8,
              ResponseConcludingReader.FinalElement == HTTPFields?

    var defaultRequestOptions: RequestOptions { get }

    mutating func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return
    ) async throws -> Return
}
```

### Convenience methods for progressive disclosure

Simple HTTP requests use static methods on the `HTTP` enum. Methods are provided for `get`, `post`, `put`, `delete`, and `patch`, each collecting the response body up to a specified limit. For example, the `get` method signature:

```swift
public static func get<Client: HTTPClient & ~Copyable & ~Escapable>(
    url: URL,
    headerFields: HTTPFields = [:],
    options: Client.RequestOptions? = nil,
    on client: borrowing Client = DefaultHTTPClient.shared,
    collectUpTo limit: Int
) async throws -> (response: HTTPResponse, bodyData: Data)
```

The other methods (`post`, `put`, `delete`, `patch`) follow the same pattern, with `post`, `put`, and `patch` accepting a required `bodyData: Data` parameter and `delete` accepting an optional one. Usage examples:

```swift
import HTTPClient

// Simple GET request
let (response, data) = try await HTTP.get(url: url, collectUpTo: .max)

// POST with a body
let (response, data) = try await HTTP.post(
    url: url,
    bodyData: jsonData,
    collectUpTo: 1024 * 1024
)

// DELETE
let (response, data) = try await HTTP.delete(url: url, collectUpTo: .max)

// Advanced usage with streaming
try await HTTP.perform(request: request) { response, body in
    guard response.status == .ok else {
        throw MyNetworkingError.badResponse(response)
    }

    // Stream the response body
    let (_, trailer) = try await body.consumeAndConclude { reader in
        try await reader.forEach { span in
            print("Received \(span.count) bytes")
        }
    }

    if let trailer = trailer {
        print("Trailer: \(trailer)")
    }
}
```

### Supplying request bodies and reading response bodies

Request bodies are supported via an `HTTPClientRequestBody`, which encapsulates a closure responsible for writing the request body, in a way that is either `seekable` or `restartable`. A `restartable` request body supports retries (for redirects and authentication challenges), and a `seekable` request body additionally supports resumable uploads. Trailer fields can also be returned from the closure.

```swift
public struct HTTPClientRequestBody<Writer: AsyncWriter & ~Copyable>: Sendable
where Writer.WriteElement == UInt8, Writer: SendableMetatype {
    public static func restartable(
        knownLength: Int64? = nil,
        _ body: @escaping @Sendable (consuming Writer) async throws -> HTTPFields?
    ) -> Self

    public static func seekable(
        knownLength: Int64? = nil,
        _ body: @escaping @Sendable (Int64, consuming Writer) async throws -> HTTPFields?
    ) -> Self
}

extension HTTPClientRequestBody {
    public static func data(_ data: Data) -> Self
}
```

Responses are delivered via a closure passed into the `responseHandler` parameter of `perform`, which supplies an `HTTPResponse` for HTTP response metadata and a body reader. The return value of the closure is forwarded to the `perform` method.

### Capability-based request options

Request options are modeled through capability protocols, allowing clients to advertise supported features. `HTTPClientCapability` is a namespace for these protocols:

```swift
public enum HTTPClientCapability {
    public protocol RequestOptions {}

    public protocol TLSVersionSelection: RequestOptions {
        var minimumTLSVersion: TLSVersion { get set }
        var maximumTLSVersion: TLSVersion { get set }
    }
}
```

Whenever possible, options are offered on an individual request basis.

The abstract API offers the following request options, which may or may not be supported by a particular concrete implementation:
- **TLS Version Selection**: a minimum and maximum TLS version to allow during TLS handshake.

### Middleware

A separate `Middleware` module provides a generic, composable protocol for intercepting and transforming values through a chain. The `Middleware` protocol defines a single `intercept(input:next:)` method that receives a value, processes it, and passes a (potentially transformed) value to the next stage. Middleware pipelines can be built declaratively using the `@MiddlewareBuilder` result builder:

```swift
@MiddlewareBuilder
var pipeline: some Middleware<MyRequest, MyRequest> {
    LoggingMiddleware()
    AuthenticationMiddleware()
    RetryMiddleware()
}
```

## Detailed design

### Module structure

The proposal consists of several interconnected modules, and the abstract API is defined as part of the `HTTPAPIs` module:
- **HTTPAPIs**: Protocol definitions for `HTTPClient` and shared types
- **NetworkTypes**: Currency types defined as needed for request option capabilities

### `perform` lifecycle

A call to `perform` proceeds through the following stages:

1. If a `body` is provided, the implementation invokes its closure, passing a `RequestWriter`. The closure may optionally return trailing `HTTPFields`.
2. The implementation invokes `responseHandler` exactly once, passing an `HTTPResponse` and a `ResponseConcludingReader`. The response handler closure can be invoked concurrently with the request body closure in the case of bidirectional streaming.
3. `perform` returns only after `responseHandler` completes, ensuring the entire request–response cycle is scoped within the call.

If `responseHandler` throws, the error propagates out of `perform`.

### Request body

Request bodies support both retransmission and resumable uploads:

```swift
// Restartable: can be replayed from the beginning for redirects or retries
let (response, data) = try await HTTP.perform(request: request, body: .restartable { writer in
    try await writer.write(bodyBytes)
    return nil // no trailer
}) { response, body in
    let (data, _) = try await body.collect(upTo: 1024 * 1024) { $0 }
    return (response, data)
}

// Seekable: can resume from an arbitrary offset for resumable uploads
let (response, data) = try await HTTP.perform(request: request, body: .seekable { offset, writer in
    try await writer.write(fileBytes[offset...])
    return nil
}) { response, body in
    let (data, _) = try await body.collect(upTo: 1024 * 1024) { $0 }
    return (response, data)
}
```

The closure-based design allows lazy generation of body content. The optional `HTTPFields` return value supports trailers, and the `knownLength` parameter enables the Content-Length header field and progress tracking.

`HTTPClientRequestBody` is generic over the client's `RequestWriter` associated type. This means request bodies are tied to a specific client type, allowing each concrete implementation to use its own optimized writer without type erasure.

### Request options and capabilities

```swift
// A library can require specific capabilities via generic constraints
func fetchMoreSecurely(
    using client: borrowing some HTTPClient<some HTTPClientCapability.TLSVersionSelection>
) async throws {
    var options = client.defaultRequestOptions
    options.minimumTLSVersion = .tls13
    try await client.perform(request: request, options: options) { response, body in
        // Handle response
    }
}
```

**Capability pattern benefits:**

- Clients advertise supported features through protocol conformance
- Library code can require specific capabilities via generic constraints
- Future capabilities can be added without breaking existing clients
- Clear separation between core functionality and optional features

The protocol's `perform` method takes a non-optional `RequestOptions` parameter. The convenience layer (`HTTP.get`, `HTTP.perform`, etc.) wraps this with an optional `options` parameter that falls back to `client.defaultRequestOptions` when `nil` is passed. This two-layer design keeps the protocol contract explicit while making the common case concise.

### Middleware

The `Middleware` protocol and its composition primitives (`ChainedMiddleware`, `@MiddlewareBuilder`) are described in the Proposed solution. This proposal does not define a standardized HTTP middleware contract — the concrete input/output types, response-side interception, and integration with `HTTPClient.perform` are left to a future proposal.

### Testability

Because `HTTPClient` is a protocol, libraries and applications can inject mock implementations for testing without depending on a real network stack:

```swift
struct MockHTTPClient: HTTPClient {
    struct RequestOptions: HTTPClientCapability.RequestOptions {
        init() {}
    }

    var defaultRequestOptions: RequestOptions { .init() }

    func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return
    ) async throws -> Return {
        // Return a canned response for testing
        ...
    }
}
```

Any code written against a generic `some HTTPClient` parameter can be tested by passing a `MockHTTPClient` instead of a real client, verifying requests and controlling responses without network access.

## Source compatibility

This proposal is purely additive and introduces new API surface. It does not modify or deprecate any existing Swift APIs, so there is no impact on source compatibility.

## ABI compatibility

This proposal is purely an extension of the Swift ecosystem with new packages and does not modify any existing ABI.

## Implications on adoption

The core `HTTPClient` protocol and convenience methods can be back-deployed as a Swift package. Library authors can adopt the `HTTPClient` protocol without coupling to specific implementations, and adding conformance to a type is ABI-additive. The initial release will be marked as pre-1.0 during evolution review.

## Future directions

### URLClient abstraction

While `HTTPClient` focuses exclusively on HTTP/HTTPS, a future `URLClient` protocol could be built on top to support additional URL schemes (file://, data://, custom schemes). This separation keeps `HTTPClient` focused and simple.

### Background transfer API

Background URLSession supports system-scheduled uploads, downloads, and media asset downloads. The current streaming-based design is not suitable for file-based background transfers. A future manifest-based bulk transfer API could manage uploads and downloads both in-process and out-of-process, complementing `HTTPClient` for different use cases.

### WebSocket support

WebSocket connections upgrade from HTTP but have significantly different semantics. A separate `WebSocketClient` API could be designed in the future, potentially sharing some abstractions with `HTTPClient`.

### Middleware standardization

While the repository explores middleware patterns, standardizing middleware protocols for HTTP clients could be addressed in a follow-up proposal, enabling composable request/response transformations.

## Alternatives considered

### Extending URLSession

Rather than creating a new API, we could modernize URLSession with async/await wrappers and streaming support.

**Advantages:**
- Familiar API for Apple platform developers
- Incremental migration path

**Disadvantages:**
- URLSession's delegate-based architecture doesn't map well to structured concurrency
- Deep object hierarchies and platform-specific behaviors are hard to abstract
- Supporting non-Apple platforms would require re-implementing URLSession semantics
- Mixing HTTP with other URL schemes complicates the abstraction
- Source stability constraints limit evolution

### Standardizing AsyncHTTPClient

We could promote AsyncHTTPClient to be the standard Swift HTTP client across all platforms.

**Advantages:**
- Proven in production server-side use
- Already cross-platform

**Disadvantages:**
- EventLoop model doesn't align with structured concurrency
- NIO dependency is heavyweight for client applications
- Apple platform optimizations (URLSession networking stack) would be lost
