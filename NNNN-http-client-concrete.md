# Concrete HTTP Client Implementations

* Proposal: [SE-NNNN](NNNN-swift-http-client-concrete.md)
* Authors: [Swift Networking Workgroup](https://github.com/swiftlang/swift-evolution/blob/main/visions/networking.md)
* Review Manager: TBD
* Status: **Awaiting review**
* Vision: [Networking](https://github.com/swiftlang/swift-evolution/blob/main/visions/networking.md)
* Implementation: [apple/swift-http-api-proposal](https://github.com/apple/swift-http-api-proposal)
* Review: ([pitch](https://forums.swift.org/t/designing-an-http-client-api-for-swift/85254))

## Summary of changes

This proposal introduces concrete HTTP client implementations conforming to the `HTTPClient` protocol defined in SE-NNNN (Abstract HTTP Client API). It provides a `DefaultHTTPClient` that selects the best platform implementation, a URLSession-backed client for Apple platforms, and an AsyncHTTPClient-backed client.

## Motivation

The abstract `HTTPClient` protocol from SE-NNNN defines a common interface for HTTP operations, but callers need concrete implementations to actually make requests. The Swift ecosystem currently offers two major HTTP client libraries, URLSession and AsyncHTTPClient, each with platform-specific strengths:

- **URLSession** integrates deeply with Apple platform networking.
- **AsyncHTTPClient** is cross-platform and proven in server-side production.

This proposal bridges both to the abstract protocol and provides a `DefaultHTTPClient` that automatically selects the appropriate concrete implementation, so callers who `import HTTPClient` get a working client on every supported platform without choosing an implementation themselves.

## Proposed solution

Three concrete clients are introduced:

1. **`DefaultHTTPClient`**: a platform-selecting wrapper that delegates to the best available concrete implementation. It is the default client used by all `HTTP` convenience methods.
2. **`URLSessionHTTPClient`**: a URLSession-backed implementation available on Apple platforms, exposing URLSession-specific capabilities like TLS version selection, custom redirect handling, and client certificate authentication.
3. **`AHCHTTPClient` module**: an AsyncHTTPClient-backed implementation for non-Apple platforms, exposed as a conformance of the existing `AsyncHTTPClient.HTTPClient` type to the `HTTPAPIs.HTTPClient` protocol.

### `DefaultHTTPClient`

Most callers interact with `DefaultHTTPClient` through the `HTTP` static methods, which delegate to `DefaultHTTPClient.shared` by default:

```swift
import HTTPClient

// Uses DefaultHTTPClient.shared automatically
let (response, data) = try await HTTP.get(url: url, collectUpTo: .max)
```

For advanced use cases, callers can create scoped clients with custom connection pool configuration:

```swift
try await DefaultHTTPClient.withClient(
    poolConfiguration: .init()
) { client in
    try await HTTP.perform(request: request, on: client) { response, body in
        // Handle response with dedicated connection pool
    }
}
```

### Platform-specific clients

When callers need platform-specific capabilities, they can use the concrete implementation clients directly:

```swift
// URLSession-backed client with TLS version selection and redirect handling
let client = URLSessionHTTPClient.shared
var options = URLSessionRequestOptions()
options.minimumTLSVersion = .v1_3
options.redirectionHandler = MyRedirectHandler()
```

### Request options per implementation

Each concrete client defines its own `RequestOptions` type conforming to the capability protocols it supports.

- [ ] Add request options supported by `DefaultHTTPClient` and `AHCClient` when they have some.

**`URLSessionHTTPClient`** supports the following request options via capability protocols:
- **TLS Version Selection**: a minimum and maximum TLS version to allow during TLS handshake.
- **Redirection Handling**: a custom handler for controlling HTTP redirect behavior.
- **TLS Security Handling**: fine-grained server trust and client certificate authentication via Security framework types.

It also exposes additional properties not backed by capability protocols:
- **Stall timeout**: maximum duration waiting for new bytes before cancellation.
- **HTTP/3 capability hint**: indicates whether the server is assumed to support HTTP/3.
- **Network access constraints**: controls whether expensive or constrained network access is allowed.

## Detailed design

### Module structure

The concrete implementations are defined across three modules:

- **HTTPClient**: `DefaultHTTPClient`, `HTTPConnectionPoolConfiguration`, `HTTPRequestOptions`, and the `HTTP` convenience methods (which are generic over any `HTTPClient` but default to `DefaultHTTPClient.shared`, so they are defined here rather than in the abstract `HTTPAPIs` module). This is the primary import for most callers.
- **URLSessionHTTPClient**: `URLSessionHTTPClient`, `URLSessionRequestOptions`, `URLSessionConnectionPoolConfiguration`, and URLSession-specific security types. Available on Apple platforms only.
- **AHCHTTPClient**: Conformance of `AsyncHTTPClient.HTTPClient` to the `HTTPAPIs.HTTPClient` protocol. Available on all platforms where AsyncHTTPClient is supported.

### `DefaultHTTPClient`

```swift
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public final class DefaultHTTPClient: HTTPClient {
    public static var shared: DefaultHTTPClient { get }

    public static func withClient<Return: ~Copyable, Failure: Error>(
        poolConfiguration: HTTPConnectionPoolConfiguration,
        body: (borrowing DefaultHTTPClient) async throws(Failure) -> Return
    ) async throws(Failure) -> Return

    public var defaultRequestOptions: HTTPRequestOptions { get }

    public func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>?,
        options: HTTPRequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return
    ) async throws -> Return
}
```

`DefaultHTTPClient` is a final class that wraps the platform-appropriate concrete implementation. On Apple platforms it delegates to `URLSessionHTTPClient`; on other platforms it delegates to `AsyncHTTPClient.HTTPClient`.

**`shared` vs `withClient`**: The `shared` static property provides a singleton with default connection pool settings, suitable for most use cases. `withClient` creates a scoped client with custom pool configuration; the client is torn down when the closure returns, ensuring connection resources are released.

#### `HTTPConnectionPoolConfiguration`

```swift
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPConnectionPoolConfiguration: Hashable, Sendable {
    public var maximumConcurrentHTTP1ConnectionsPerHost: Int  // default: 6
    public init()
}
```

This configuration controls connection pooling behavior for `DefaultHTTPClient`. It currently supports customizing the HTTP/1.1 connection pool width.

#### `HTTPRequestOptions`

```swift
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPRequestOptions: HTTPClientCapability.RequestOptions {
    public init()
}
```

`HTTPRequestOptions` is the request options type for `DefaultHTTPClient`.

### `URLSessionHTTPClient`

```swift
#if canImport(Darwin)
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public final class URLSessionHTTPClient: HTTPClient, Sendable {
    public static var shared: URLSessionHTTPClient { get }

    public static func withClient<Return: ~Copyable, Failure: Error>(
        poolConfiguration: URLSessionConnectionPoolConfiguration,
        _ body: (URLSessionHTTPClient) async throws(Failure) -> Return
    ) async throws(Failure) -> Return

    public var defaultRequestOptions: URLSessionRequestOptions { get }

    public func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>?,
        options: URLSessionRequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return
    ) async throws -> Return
}
#endif
```

`URLSessionHTTPClient` manages URLSession instances and their delegate lifecycle. It conforms to `Sendable` as required by the `HTTPClient` protocol.

The client internally manages multiple `URLSession` instances, keyed by properties that can only be set on a session configuration rather than per-request (such as TLS version constraints). Sessions are created on demand and reused across requests with matching configurations.

#### `URLSessionRequestOptions`

```swift
#if canImport(Darwin)
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct URLSessionRequestOptions:
    HTTPClientCapability.RedirectionHandler,
    HTTPClientCapability.TLSSecurityHandler,
    HTTPClientCapability.TLSVersionSelection
{
    // TLS
    public var minimumTLSVersion: TLSVersion          // default: .v1_2
    public var maximumTLSVersion: TLSVersion          // default: .v1_3
    public var serverTrustHandler: (any HTTPClientServerTrustHandler)?  // default: nil
    public var clientCertificateHandler: (any HTTPClientClientCertificateHandler)?  // default: nil

    // Redirects
    public var redirectionHandler: (any HTTPClientRedirectionHandler)?  // default: nil

    // Timeouts
    public var stallTimeout: Duration?                 // default: nil

    // URLSession-specific
    public var allowsExpensiveNetworkAccess: Bool      // default: true
    public var allowsConstrainedNetworkAccess: Bool    // default: true
    public var assumesHTTP3Capable: Bool               // default: false

    public init()
}
#endif
```

`URLSessionRequestOptions` is the corresponding options type, exposing capabilities specific to Apple's networking stack.

#### Security types

**`TrustEvaluationPolicy`** is defined in the `URLSessionHTTPClient` module:

```swift
public enum TrustEvaluationPolicy: Hashable {
    case `default`         // System default validation
    case allowNameMismatch // Allow certificates without hostname match
    case allowAny          // Allow any certificate (e.g., self-signed)
}
```

**`HTTPClientServerTrustHandler`** and **`HTTPClientClientCertificateHandler`** are Apple-platform-only protocols that provide fine-grained control over TLS authentication challenges using Security framework types (`SecTrust`, `SecIdentity`, `SecCertificate`):

```swift
#if canImport(Darwin)
public protocol HTTPClientServerTrustHandler: Identifiable, Sendable {
    func evaluateServerTrust(_ trust: SecTrust) async throws -> TrustEvaluationResult
}

public protocol HTTPClientClientCertificateHandler: Identifiable, Sendable {
    func handleClientCertificateChallenge(
        distinguishedNames: [Data]
    ) async throws -> (SecIdentity, [SecCertificate])?
}
#endif
```

The `TLSSecurityHandler` capability extends `DeclarativeTLS` (both defined in the `URLSessionHTTPClient` module), providing a bridge: when a `serverTrustHandler` is not set, the `serverTrustPolicy` from `DeclarativeTLS` can be used instead. This means callers can use `TrustEvaluationPolicy` for basic trust control, or the handler protocols for full flexibility.

#### Redirect handling

```swift
#if canImport(Darwin)
public protocol HTTPClientRedirectionHandler: Sendable {
    func handleRedirection(
        response: HTTPResponse,
        newRequest: HTTPRequest
    ) async throws -> HTTPClientRedirectionAction
}

public enum HTTPClientRedirectionAction: Sendable {
    case follow(HTTPRequest)           // Follow the redirect (optionally modified)
    case deliverRedirectionResponse    // Return the 3xx response to the caller
}
#endif
```

When no `redirectionHandler` is set, URLSession follows its default redirect behavior.

### `AHCHTTPClient`

```swift
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, *)
extension AsyncHTTPClient.HTTPClient: HTTPAPIs.HTTPClient {
    public struct RequestOptions: HTTPClientCapability.RequestOptions {
        public init()
    }

    public var defaultRequestOptions: RequestOptions { get }

    public func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestBodyWriter>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseReader) async throws -> Return
    ) async throws -> Return
}
```

The AHC conformance is implemented as an extension on the existing `AsyncHTTPClient.HTTPClient` type rather than a new wrapper type. This allows callers who already use AsyncHTTPClient to adopt the `HTTPClient` protocol by importing `AHCHTTPClient` — their existing client instance gains the conformance without migration.

The `RequestOptions` type is currently minimal. AHC's existing configuration (connection pools, timeouts, TLS) is managed through its own initializers and configuration types. Per-request capability protocols will be added as the AHC integration matures.

### `NetworkTypes`

The `NetworkTypes` module defines cross-platform currency types used in request options:

```swift
public struct TLSVersion: Sendable, Hashable {
    public static var v1_2: TLSVersion  // TLS 1.2
    public static var v1_3: TLSVersion  // TLS 1.3
}
```

## Source compatibility

This proposal is purely additive. It does not modify or deprecate any existing Swift APIs, including URLSession or AsyncHTTPClient.

## ABI compatibility

This proposal introduces new packages and does not modify any existing ABI. Platform-specific implementations (URLSession-backed, AsyncHTTPClient-backed) can evolve independently without breaking ABI.

## Implications on adoption

- Using `URLSessionHTTPClient` requires targeting Apple platforms
- Using `AHCHTTPClient` requires AsyncHTTPClient as a dependency

## Future directions

### Additional capability protocols

The current set of capability protocols covers TLS configuration, redirects, and server trust. Future capabilities could include:
- Cookie jar management
- Proxy configuration
- HTTP caching policies
- Metrics and progress reporting

### Cross-platform security APIs

The `TLSSecurityHandler` capability is currently Apple-platform-only because it depends on Security framework types. The `RedirectionHandler` capability is Apple-platform-only because it is implemented through URLSession's delegate bridging. A future proposal could define cross-platform abstractions for certificate pinning and redirect control that work across all concrete implementations.

### Connection pool configuration

The current `HTTPConnectionPoolConfiguration` exposes only HTTP/1.1 connection concurrency. Future additions could include idle connection timeouts, connection-per-host limits for HTTP/2, and DNS resolution configuration.

## Alternatives considered

### Not exposing `URLSessionHTTPClient` or `AHCHTTPClient`

If `DefaultHTTPClient` is the only backend that internally picks URLSession or AHC, users would not be able to pick AHC on Apple platforms. Also URLSession specific options will be harder to support.
