import AsyncStreaming
import HTTPAPIs
import FetchHTTPClient
import JavaScriptKit
import JavaScriptEventLoop
import Foundation

// This is needed before any async work is done.
typealias DefaultExecutorFactory = JavaScriptEventLoop
JavaScriptEventLoop.installGlobalExecutor();

let client = FetchHTTPClient()
let status = Status()

// Ask the user for the URL string.
let urlString = try prompt("URL:", "http://localhost:8000/").trimmingCharacters(in: .whitespacesAndNewlines);
guard let url = URL(string: urlString) else {
    status.set("❌ Not a valid URL");
    fatalError()
}

// Parse the method
let methodString = try prompt("Method (GET, POST, etc.):", "GET").trimmingCharacters(in: .whitespacesAndNewlines).uppercased();
guard let method = HTTPRequest.Method(methodString) else {
    status.set("❌ Not a valid method");
    fatalError()
}

// Optionally accept a body
var body: HTTPClientRequestBody<FetchHTTPClient.RequestBodyWriter>? = nil;
if method == .post || method == .put {
    let bodyString = try prompt("Body:", "Hello World!");
    body = .restartable { writer in
        var writer = writer
        let span = bodyString.utf8Span.span
        status.set("⏳ Writing \(span.count) bytes")
        try await writer.write(span)
        return nil;
    }
}

status.set("⏳ Making \(method) request to \(url)")

do {
    try await client.perform(
        request: .init(method: method, url: url, headerFields: [
            .init("Client")! : "Swift-WASM"
        ]),
        body: body,
        options: .init()
    ) { (response, reader) in
        h2("Response")
        div("\(response.status)");

        var contentLength: Int? = nil
        for header in response.headerFields {
            div("\(header.name): \(header.value)")

            if (header.name == .contentLength) {
                contentLength = Int(header.value)
            }
        }

        h2("Body")
        status.set("⏳ Reading response body")

        // Read the body as it is streamed in
        let (bytes, _) = try await reader.consumeAndConclude { reader in
            var bytes = [UInt8]()

            if let contentLength = contentLength {
                bytes.reserveCapacity(contentLength)
            }

            var reader = reader
            status.set("⏳ Read \(bytes.count) bytes")
            while (true) {
                let shouldContinue = try await reader.read(maximumCount: nil) { span in
                    if (span.isEmpty) {
                        return false;
                    }
                    for i in span.indices {
                        bytes.append(span[i])
                    }
                    status.set("⏳ Read \(bytes.count) bytes")
                    return true;
                }
                if (!shouldContinue) {
                    break;
                }
            }
            return bytes;
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
    status.set("❌ Fetch failed: \(error)")
}

