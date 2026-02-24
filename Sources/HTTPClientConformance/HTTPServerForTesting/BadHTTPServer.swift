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

import Foundation
import NIOHTTP1

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public func withBadHTTPServer(perform: (Int) async throws -> Void) async throws {
    try await withThrowingTaskGroup {
        let server = try await RawHTTPServer()
        $0.addTask {
            try await server.run(handler: handler)
        }
        try await perform(server.port)
        $0.cancelAll()
    }
}

func linesToData(_ lines: [String]) -> Data {
    return lines.joined(separator: "\r\n").data(using: .ascii)!
}

func handler(request: HTTPRequestHead) -> Data {
    switch request.uri {
    case "/not_http":
        return "FOOBAR".data(using: .ascii)!
    case "/lf_only":
        return "HTTP/1.1 200 OK\n\n".data(using: .ascii)!
    case "/http_case":
        return "Http/1.1 200 OK\r\n\r\n".data(using: .ascii)!
    case "/no_reason":
        return "HTTP/1.1 200\r\n\r\n".data(using: .ascii)!
    case "/204_with_cl":
        return linesToData([
            "HTTP/1.1 204 No Content",
            "Content-Length: 1000",
            "",
            "",
        ])
    case "/304_with_cl":
        return linesToData([
            "HTTP/1.1 304 Not Modified",
            "Content-Length: 1000",
            "",
            "",
        ])
    default:
        return "HTTP/1.1 500 Internal Server Error\r\n\r\n".data(using: .ascii)!
    }
}
