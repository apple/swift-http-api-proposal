# HTTP Client Convenience Methods

* Proposal: [SE-NNNN](NNNN-http-client-conveniences.md)
* Authors: [Swift Networking Workgroup](https://github.com/apple/swift-http-api-proposal)
* Review Manager: TBD
* Status: **Awaiting review**
* Vision: [Networking](https://github.com/swiftlang/swift-evolution/blob/main/visions/networking.md)
* Implementation: [apple/swift-http-api-proposal](https://github.com/apple/swift-http-api-proposal)
* Review: ([pitch](https://forums.swift.org/t/designing-an-http-client-api-for-swift/85254))

## Summary of changes

This proposal introduces convenience methods for performing common HTTP requests. It builds on the abstract `HTTPClient` protocol defined in SE-NNNN (Abstract HTTP Client API) and adds two layers of convenience: protocol-level instance methods available on any `HTTPClient` conformance, and static methods on the `HTTP` namespace that use the default client.

## Motivation

The abstract `HTTPClient` protocol's `perform` method is powerful but verbose for the common case. Most HTTP interactions are simple request–response exchanges where the caller wants to send a request (optionally with a body) and collect the entire response body as `Data`. Without convenience methods, every caller must manually:
1. Construct an `HTTPRequest` with the appropriate method
2. Wrap the body data in an `HTTPClientRequestBody`
3. Pass a response handler closure that collects the body

This ceremony is acceptable for advanced streaming use cases, but is unnecessary friction for the majority of HTTP requests. A set of convenience methods eliminates this boilerplate while maintaining access to the full protocol when needed.

## Proposed solution

We propose convenience methods at two levels:

### Protocol-level convenience methods

Extension methods on `HTTPClient` provide shorthand for GET, POST, PUT, DELETE, and PATCH requests on any client instance:

```swift
let (response, data) = try await client.get(url: url, collectUpTo: 1024 * 1024)
```

These methods are available on any `HTTPClient` conformance, including custom or mock clients.

### Static convenience methods on `HTTP`

For the simplest use case, static methods on the `HTTP` enum use `DefaultHTTPClient.shared` by default:

```swift
let (response, data) = try await HTTP.get(url: url, collectUpTo: .max)
```

This provides the shortest possible path from "I want to fetch a URL" to working code, with progressive disclosure to more advanced features.

### Usage examples

```swift
import HTTPClient

// Simple GET
let (response, data) = try await HTTP.get(url: url, collectUpTo: .max)

// POST with JSON body
let (response, data) = try await HTTP.post(
    url: url,
    headerFields: [.contentType: "application/json"],
    bodyData: jsonData,
    collectUpTo: 1024 * 1024
)

// DELETE
let (response, data) = try await HTTP.delete(url: url, collectUpTo: .max)

// Using a custom client instance
let (response, data) = try await client.get(url: url, collectUpTo: 1024 * 1024)

// Advanced: streaming with HTTP.perform
try await HTTP.perform(request: request) { response, body in
    guard response.status == .ok else {
        throw MyNetworkingError.badResponse(response)
    }

    let (byteCount, trailer) = try await body.consumeAndConclude { reader in
        var byteCount = 0
        try await reader.forEach { span in
            print("Received \(span.count) bytes")
            byteCount += span.count
        }
        return byteCount
    }

    if let trailer {
        print("Trailer: \(trailer)")
    }
    print("Total \(byteCount) bytes")
}
```

## Detailed design

### Protocol-level convenience methods

These are defined as extensions on `HTTPClient where Self: ~Copyable & ~Escapable` in the `HTTPAPIs` module:

#### `perform` with defaults

```swift
extension HTTPClient where Self: ~Copyable & ~Escapable {
    public mutating func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>? = nil,
        options: RequestOptions? = nil,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return,
    ) async throws -> Return
}
```

When `options` is `nil`, the client's `defaultRequestOptions` is used.

#### `get`

```swift
extension HTTPClient where Self: ~Copyable & ~Escapable {
    public mutating func get(
        url: URL,
        headerFields: HTTPFields = [:],
        options: RequestOptions? = nil,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data)
}
```

Sends a GET request to the specified URL and collects the response body up to `limit` bytes. Throws `LengthLimitExceededError` if the response body exceeds the limit.

#### `post`

```swift
extension HTTPClient where Self: ~Copyable & ~Escapable {
    public mutating func post(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: RequestOptions? = nil,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data)
}
```

Sends a POST request with the provided body data.

#### `put`

```swift
extension HTTPClient where Self: ~Copyable & ~Escapable {
    public mutating func put(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: RequestOptions? = nil,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data)
}
```

Sends a PUT request with the provided body data.

#### `delete`

```swift
extension HTTPClient where Self: ~Copyable & ~Escapable {
    public mutating func delete(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data? = nil,
        options: RequestOptions? = nil,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data)
}
```

Sends a DELETE request with an optional body.

#### `patch`

```swift
extension HTTPClient where Self: ~Copyable & ~Escapable {
    public mutating func patch(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: RequestOptions? = nil,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data)
}
```

Sends a PATCH request with the provided body data.

### Static convenience methods on `HTTP`

These are defined in the `HTTPClient` module and operate on `DefaultHTTPClient`:

#### `HTTP.perform`

```swift
extension HTTP {
    public static func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<DefaultHTTPClient.RequestWriter>? = nil,
        options: HTTPRequestOptions = .init(),
        on client: DefaultHTTPClient = .shared,
        responseHandler: (HTTPResponse, consuming DefaultHTTPClient.ResponseConcludingReader) async throws -> Return,
    ) async throws -> Return
}
```

#### `HTTP.get`

```swift
extension HTTP {
    public static func get(
        url: URL,
        headerFields: HTTPFields = [:],
        options: HTTPRequestOptions = .init(),
        on client: DefaultHTTPClient = .shared,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data)
}
```

#### `HTTP.post`

```swift
extension HTTP {
    public static func post(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: HTTPRequestOptions = .init(),
        on client: DefaultHTTPClient = .shared,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data)
}
```

#### `HTTP.put`

```swift
extension HTTP {
    public static func put(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: HTTPRequestOptions = .init(),
        on client: DefaultHTTPClient = .shared,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data)
}
```

#### `HTTP.delete`

```swift
extension HTTP {
    public static func delete(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data? = nil,
        options: HTTPRequestOptions = .init(),
        on client: DefaultHTTPClient = .shared,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data)
}
```

#### `HTTP.patch`

```swift
extension HTTP {
    public static func patch(
        url: URL,
        headerFields: HTTPFields = [:],
        bodyData: Data,
        options: HTTPRequestOptions = .init(),
        on client: DefaultHTTPClient = .shared,
        collectUpTo limit: Int,
    ) async throws -> (response: HTTPResponse, bodyData: Data)
}
```

### Module structure

The convenience methods are split across two modules:
- **HTTPAPIs**: Protocol-level instance method extensions on `HTTPClient` (available to all conformances)
- **HTTPClient**: Static methods on `HTTP` that use `DefaultHTTPClient` (the primary import for end-user code)

## Source compatibility

This proposal is purely additive and introduces new API surface. It does not modify or deprecate any existing Swift APIs, so there is no impact on source compatibility.

## ABI compatibility

This proposal is purely an extension of the Swift ecosystem which can be implemented as a package without any ABI support from the language runtime or standard library. It does not change any existing ABI.

## Implications on adoption

The convenience methods are distributed as part of the same Swift package as the `HTTPClient` protocol. Protocol-level convenience methods are available to any `HTTPClient` conformance. The `HTTP` static methods require importing the `HTTPClient` module, which brings in `DefaultHTTPClient` and its platform-specific networking backend.

## Future directions

### JSON convenience methods

Methods like `HTTP.getJSON(url:as:)` could decode a response body directly into a JSON decodable type. This would further reduce boilerplate for the very common case of fetching JSON APIs.

## Alternatives considered

### Separate methods for streaming vs. collecting

An alternative design would provide distinct method families: one for streaming (returning the body reader) and one for collecting (returning `Data`). The chosen design uses a single `collectUpTo` parameter that makes the common collecting case concise while still exposing `HTTP.perform` for streaming use cases.

### Omitting the `collectUpTo` limit

Making the limit optional (defaulting to unlimited) would simplify the API further. However, requiring an explicit limit prevents accidental unbounded memory growth from unexpectedly large responses, preventing DoS attack for server usages of the client API. Callers who genuinely want no limit can pass `.max`.
