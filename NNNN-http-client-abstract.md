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

Other languages, including Rust and Go, typically have a highly popular, if not built-in, HTTP client that works across platforms out-of-the-box, and also utilizes the patterns and capabilities of those languages. As outlined by [Swift networking vision](https://github.com/swiftlang/swift-evolution/blob/main/visions/networking.md), a cross-platform HTTP API is crucial for Swift competitiveness in networking applications.

## Proposed solution

We propose a new `HTTPClient` protocol that defines a single `perform` method for all HTTP interactions. This approach is better than the status quo because it:
- Leverages structured concurrency instead of delegate callbacks or completion handlers
- Enables dependency injection so libraries accept any conforming client without coupling to a specific implementation
- Works on every platform Swift supports.

Followup proposals about convenience methods and concrete implementations build on the protocol defined here.

### Core protocol

The `HTTPClient` protocol provides a single `perform` method that handles all HTTP interactions. The request and response metadata are expressed as `HTTPRequest` and `HTTPResponse` types from the Swift HTTP Types package. The protocol requires `Sendable`, ensuring all conforming clients are safe to share across concurrency domains.

Request bodies are written through an `AsyncWriter` and response bodies are read through a `ConcludingAsyncReader` (from the Swift Async Algorithms package), with trailer field support on both sides.

A simple GET request looks like this:

```swift
let data = try await client.perform(request: request) { response, body in
    let (data, trailer) = try await body.collect(upTo: 1024 * 1024) { $0 }
    return data
}
```

### Supplying request bodies

Request bodies are provided as closures that write to the client's writer. A `restartable` body supports retries (for redirects and authentication challenges), while a `seekable` body additionally supports resumable uploads:

```swift
// Restartable: can be replayed from the beginning for redirects or retries
let (response, data) = try await client.perform(request: request, body: .restartable { writer in
    try await writer.write(bodyBytes)
    return nil // no trailer
}) { response, body in
    let (data, trailer) = try await body.collect(upTo: 1024 * 1024) { $0 }
    return (response, data)
}

// Seekable: can resume from an arbitrary offset for resumable uploads
let (response, data) = try await client.perform(request: request, body: .seekable(knownLength: fileBytes.count) { offset, writer in
    try await writer.write(fileBytes[offset...])
    return nil
}) { response, body in
    let (data, trailer) = try await body.collect(upTo: 1024 * 1024) { $0 }
    return (response, data)
}
```

### Capability-based request options

Request options are modeled through capability protocols, allowing clients to advertise supported features. Library code can require specific capabilities via generic constraints:

```swift
// A library can require TLS version selection via generic constraints
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

This pattern allows future capabilities to be added without breaking existing clients, and provides clear separation between core functionality and optional features.

### Testability

Because `HTTPClient` is a protocol, libraries and applications can inject mock implementations for testing without depending on a real network stack. Any code written against a generic `some HTTPClient` parameter can be tested by passing a mock client instead, verifying requests and controlling responses without network access.

## Detailed design

### Module structure

The proposal consists of several interconnected modules, and the abstract API is defined as part of the `HTTPAPIs` module:
- **HTTPAPIs**: Protocol definitions for `HTTPClient` and shared types
- **NetworkTypes**: Currency types defined as needed for request option capabilities

### `HTTPClient` protocol

The `HTTPClient` protocol is the central abstraction. It allows `~Copyable` and `~Escapable` types to conform, and the `perform` method is mutating, allowing it to mutate state of the client instance.

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

extension HTTPClient where Self: ~Copyable & ~Escapable {
    public mutating func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>? = nil,
        options: RequestOptions? = nil,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return,
    ) async throws -> Return
}
```

The protocol's `perform` method takes a non-optional `RequestOptions` parameter. The convenience `perform` wraps this with an optional `options` parameter that falls back to `client.defaultRequestOptions` when `nil` is passed.

### `perform` lifecycle

A call to `perform` proceeds through the following stages:

1. If a `body` is provided, the implementation invokes its closure, passing a `RequestWriter`. The closure may optionally return trailing `HTTPFields`.
2. The implementation invokes `responseHandler` exactly once, passing an `HTTPResponse` and a `ResponseConcludingReader`. The response handler closure can be invoked concurrently with the request body closure in the case of bidirectional streaming.
3. `perform` returns only after the request body closure, `responseHandler`, and all other callbacks in `RequestOptions` complete, ensuring the entire request–response cycle is scoped within the call.

If `responseHandler` throws, the error propagates out of `perform`.

### `HTTPClientRequestBody`

`HTTPClientRequestBody` encapsulates a closure responsible for writing the request body. It is generic over the client's `RequestWriter` associated type, allowing each concrete implementation to use its own optimized writer without type erasure.

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

The optional `HTTPFields` return value supports trailers, and the `knownLength` parameter enables the Content-Length header field and progress tracking.

### `ConcludingAsyncReader`

`ConcludingAsyncReader` builds on top of `AsyncReader` (defined in the Swift Async Algorithms package), allowing a final element which is used for the trailer fields.

```swift
public protocol ConcludingAsyncReader<Underlying, FinalElement>: ~Copyable, ~Escapable {
    associatedtype Underlying: AsyncReader, ~Copyable, ~Escapable
    associatedtype FinalElement

    consuming func consumeAndConclude<Return, Failure: Error>(
        body: (consuming sending Underlying) async throws(Failure) -> Return
    ) async throws(Failure) -> (Return, FinalElement)
}
```

### Capability-based request options

`HTTPClientCapability` is a namespace for capability protocols:

```swift
public enum HTTPClientCapability {
    public protocol RequestOptions {}
}
```

Whenever possible, options are offered on an individual request basis. Options affecting the behaviors of the connection pool are configured on the concrete client implementation itself.

The abstract API offers the following request options, which may or may not be supported by a particular concrete implementation:

#### TLS Version Selection

```swift
extension HTTPClientCapability {
    public protocol TLSVersionSelection: RequestOptions {
        var minimumTLSVersion: TLSVersion { get set }
        var maximumTLSVersion: TLSVersion { get set }
    }
}
```

### `NetworkTypes`

NetworkTypes module includes common currency types such as IP addresses and TLS versions that are useful outside HTTP. It will become its own separate library.

```swift
public struct TLSVersion: Sendable, Hashable {
    public static var v1_2: TLSVersion
    public static var v1_3: TLSVersion
}
```

### Testability

Because `HTTPClient` is a protocol, libraries and applications can inject mock implementations for testing:

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

## Source compatibility

This proposal is purely additive and introduces new API surface. It does not modify or deprecate any existing Swift APIs, so there is no impact on source compatibility.

## ABI compatibility

This proposal is purely an extension of the Swift ecosystem which can be implemented as a package without any ABI support from the language runtime or standard library. It does not change any existing ABI.

## Implications on adoption

The `HTTPClient` protocol is distributed as a Swift package and does not require ABI support from the language runtime. Library authors can adopt the protocol without coupling to specific implementations, and adding conformance to a type is ABI-additive. A library that accepts `some HTTPClient` does not impose any deployment constraints on its users beyond the package version. Adopting the protocol in a library can be un-adopted later without breaking source or ABI compatibility for users of that library.

## Future directions

### URLClient abstraction

`HTTPClient` focuses exclusively on HTTP/HTTPS. A `URLClient` protocol could be built on top to support additional URL schemes (file://, data://, custom schemes), keeping `HTTPClient` focused on its core domain.

### Background transfer API

Background URLSession supports system-scheduled uploads, downloads, and media asset downloads. The current streaming-based design is not suited for file-based background transfers. A manifest-based bulk transfer API could complement `HTTPClient` by managing uploads and downloads both in-process and out-of-process.

### WebSocket support

WebSocket connections upgrade from HTTP but have significantly different semantics. A separate `WebSocketClient` protocol could share some abstractions with `HTTPClient` while providing message-oriented framing.

### Middleware standardization

The repository includes a generic, composable `Middleware` protocol for intercepting and transforming values through a chain. Middleware pipelines can be built declaratively using the `@MiddlewareBuilder` result builder:

```swift
@MiddlewareBuilder
var pipeline: some Middleware<MyRequest, MyRequest> {
    LoggingMiddleware()
    AuthenticationMiddleware()
    RetryMiddleware()
}
```

Standardizing middleware protocols specifically for HTTP clients could be addressed in a follow-up proposal.

## Alternatives considered

### Extending URLSession

Rather than creating a new protocol, URLSession could be modernized with async/await wrappers and streaming support. This would offer a familiar API for Apple platform developers and an incremental migration path. However, URLSession's delegate-based architecture does not map well to structured concurrency, its deep object hierarchies and platform-specific behaviors are hard to abstract across platforms, and mixing HTTP with other URL schemes complicates the abstraction. Source stability constraints on URLSession also limit how far the API can evolve.

### Standardizing AsyncHTTPClient

AsyncHTTPClient could be promoted to the standard Swift HTTP client. It is already proven in production server-side use and cross-platform. However, its EventLoop model does not align with structured concurrency, the SwiftNIO dependency is heavyweight for client applications, and Apple platform optimizations (the URLSession networking stack) would be lost.
