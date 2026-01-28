//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP API Proposal project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import HTTPClient
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

let testsEnabled: Bool = {
    #if canImport(Darwin)
    true
    #else
    false
    #endif
}()

@Suite
struct HTTPClientTests {
    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func testHTTPBin() async throws {
        let request = HTTPRequest(
            method: .get,
            scheme: "https",
            authority: "httpbin.org",
            path: "/get"
        )
        try await HTTP.perform(
            request: request,
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            let (_, trailers) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let isEmpty = span.isEmpty
                #expect(!isEmpty)
            }
            #expect(trailers == nil)
        }
    }

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func testHTTPBinPost() async throws {
        let request = HTTPRequest(
            method: .post,
            scheme: "https",
            authority: "httpbin.org",
            path: "/post"
        )
        try await HTTP.perform(
            request: request,
            body: .restartable { writer in
                var writer = writer
                let body = "Hello World"
                try await writer.write(body.utf8Span.span)
                return nil
            }
        ) { response, responseBodyAndTrailers in
            #expect(response.status == .ok)
            let (_, trailers) = try await responseBodyAndTrailers.collect(upTo: 1024) { span in
                let isEmpty = span.isEmpty
                #expect(!isEmpty)
                let body = String(copying: try UTF8Span(validating: span))
                #expect(body.contains("Hello World"))
            }
            #expect(trailers == nil)
        }
    }

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func testHTTPBinConvenience() async throws {
        let (response, data) = try await HTTP.get(
            url: URL(string: "https://httpbin.org/get")!,
            collectUpTo: .max
        )
        #expect(response.status == .ok)
        #expect(!data.isEmpty)
    }

    @Test(.enabled(if: false))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func testHTTPBinPostConvenience() async throws {
        let (response, data) = try await HTTP.post(
            url: URL(string: "https://httpbin.org/post")!,
            body: Data("Hello World".utf8),
            collectUpTo: .max
        )
        #expect(response.status == .ok)
        let body = try #require(String(data: data, encoding: .utf8))
        #expect(body.contains("Hello World"))
    }
}
