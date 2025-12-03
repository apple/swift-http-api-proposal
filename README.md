# Swift HTTP API Proposal

This repository contains a proposal for standardized HTTP client and server APIs
for the Swift ecosystem. We're exploring new approaches that leverage Swift's
latest language features—including `~Copyable`, `~Escapable`, and structured
concurrency—to provide modern, safe, and efficient HTTP abstractions.

> [!NOTE]
> This is an active proposal and experimental implementation. Nothing here is
final—we're iterating on designs based on feedback and real-world usage. The
APIs and structure will continue to evolve as we refine the approach.

## Motivation

The Swift ecosystem currently lacks standardized, modern, and cross-platform
HTTP APIs that take full advantage of Swift's evolving language capabilities.
This proposal aims to establish a common foundation for HTTP communication that
can benefit the entire Swift community, from iOS and macOS apps to server-side
Swift applications.

## Goal

We intend to propose these APIs for consideration as part of the Swift
project, potentially as Swift packages or even standard library additions. The
modules in this repository will likely end up in separate places once the
designs stabilize. This repo exists primarily as a place to experiment with
different approaches and see how they interact before committing to separate
package boundaries.

## What's Inside

We're exploring several interconnected pieces:

- **AsyncStreaming** - Modern streaming primitives that integrate with the latest Swift concepts such as `~Copyabe`, `~Escapable` and structured concurrency. Checkout the [module's README](Sources/AsyncStreaming/README.md) for more details.
- **NetworkTypes** - Basic cross-platform network configuration types.
- **HTTPAPIs** - Protocol definitions for HTTP clients and servers.
- **HTTPClient** - A default platform HTTP client.
- **HTTPServer** - A default platform HTTP server.
- **Middleware** - A composable middleware system for processing requests

The general idea is that `AsyncStreaming` provides the foundation for streaming
HTTP bodies, `HTTPAPIs` defines the interfaces, and the client/server modules
provide concrete implementations. The middleware system works independently but
can be integrated with server and client implementations.

## Usage

The APIs are designed around streaming HTTP bodies using the `AsyncReader`
and `AsyncWriter` protocols. Both client and server support full bidirectional
streaming with optional trailers. We are still exploring adding more convenience
APIs to make simple things easier.

### HTTP Client

Making a simple get request with the default platform HTTP client:

```swift
import HTTPClient

let request = HTTPRequest(
    method: .get,
    scheme: "https",
    authority: "api.example.com",
    path: "/users"
)

try await httpClient.perform(
    request: request,
    body: nil
) { response, responseBodyAndTrailers in
    print("Status: \(response.status)")

    // Collect the response body.
    let (_, trailers) = try await responseBodyAndTrailers.collect(upTo: 1024 * 1024) { span in
        // Process the response body
        print("Received \(span.count) bytes")
    }

    // Check if there are response trailers
    if let trailers = trailers {
        print("Trailers: \(trailers)")
    }
}
```

### HTTP Server

Starting a simple echo HTTP server:

```swift
import HTTPServer

try await httpServer.serve { request, requestContext, requestBodyAndTrailers, responseSender in
    print("Received request \(request) with context \(requestContext)")
    
    // Needed since we are lacking call-once closures
    var responseSender = Optional(responseSender)

    _ = try await requestBodyAndTrailers.consumeAndConclude { reader in
        // Needed since we are lacking call-once closures
        var reader = Optional(reader)

        let responseBodyAndTrailers = try await responseSender.take()!.send(.init(status: .ok))
        try await responseBodyAndTrailers.produceAndConclude { responseBody in
            var responseBody = responseBody
            try await responseBody.write(reader.take()!)
            return nil
        }
    }
}
```

## Building and Testing

```bash
# Build everything
swift build

# Run tests
swift test
```

## Contributing

We are actively looking for feedback on these new APIs and encourage everyone to
try them out. As a proposal for the Swift ecosystem, community input during this
design phase is crucial and will help us shape the next generation of HTTP APIs
for Swift.

**How to contribute:**
- Try out the APIs in your projects and share your experience
- Open issues for bugs, design concerns, or missing functionality
- Participate in discussions about API design decisions
- Provide feedback on ergonomics and usability

Your feedback will directly influence what these APIs look like when they're proposed for broader adoption in the Swift ecosystem.
