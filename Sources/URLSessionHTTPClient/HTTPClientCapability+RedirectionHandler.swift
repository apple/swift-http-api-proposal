//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP API Proposal project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClientCapability {
    /// A protocol for HTTP request options that support custom redirection handling.
    public protocol RedirectionHandler: RequestOptions {
        /// The redirection handler to be invoked when a 3xx response is received and a
        /// redirection is about to be taken.
        var redirectionHandler: (any HTTPClientRedirectionHandler)? { get set }
    }

    struct ClosureHTTPClientRedirectionHandler: HTTPClientRedirectionHandler {
        var closure: (HTTPResponse, HTTPRequest) async throws -> HTTPClientRedirectionAction
        func handleRedirection(response: HTTPResponse, newRequest: HTTPRequest) async throws -> HTTPClientRedirectionAction {
            try await closure(response, newRequest)
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClientCapability.RedirectionHandler {
    /// The redirection handler closure to be invoked when a 3xx response is received and
    /// a redirection is about to be taken.
    public var redirectionHandlerClosure: ((HTTPResponse, HTTPRequest) async throws -> HTTPClientRedirectionAction)? {
        get {
            if let redirectionHandler = self.redirectionHandler {
                // Crash if it's not our built-in handler
                (redirectionHandler as! HTTPClientCapability.ClosureHTTPClientRedirectionHandler).closure
            } else {
                nil
            }
        }
        set {
            if let newValue {
                self.redirectionHandler = HTTPClientCapability.ClosureHTTPClientRedirectionHandler(closure: newValue)
            } else {
                self.redirectionHandler = nil
            }
        }
    }
}
