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

/// Representation of an HTTP version.
public struct HTTPVersion: Sendable, Hashable {
    private enum Representation: UInt8, Sendable, Hashable {
        case http1_0
        case http1_1
        case http2
        case http3
    }

    private let representation: Representation

    private init(_ representation: Representation) {
        self.representation = representation
    }

    /// HTTP/1.0, as defined in RFC 1945.
    public static var http1_0: HTTPVersion {
        .init(.http1_0)
    }

    /// HTTP/1.1, as defined in RFC 9112.
    public static var http1_1: HTTPVersion {
        .init(.http1_1)
    }

    /// HTTP/2, as defined in RFC 9113.
    public static var http2: HTTPVersion {
        .init(.http2)
    }

    /// HTTP/3, as defined in RFC 9114.
    public static var http3: HTTPVersion {
        .init(.http3)
    }
}

extension HTTPVersion: CustomStringConvertible {
    public var description: String {
        switch self.representation {
        case .http1_0: "HTTP/1.0"
        case .http1_1: "HTTP/1.1"
        case .http2: "HTTP/2"
        case .http3: "HTTP/3"
        }
    }
}
