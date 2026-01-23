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
public protocol HTTPClientRedirectionHandler {
    func handleRedirection(response: HTTPResponse, newRequest: HTTPRequest) async throws -> HTTPClientRedirectionAction
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPRequestOptionsRedirectionHandler: HTTPAPIs.HTTPRequestOptions {
    var redirectionHandler: (any HTTPClientRedirectionHandler)? { get set }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
private struct ClosureHTTPClientRedirectionHandler: HTTPClientRedirectionHandler {
    var closure: (HTTPResponse, HTTPRequest) async throws -> HTTPClientRedirectionAction
    func handleRedirection(response: HTTPResponse, newRequest: HTTPRequest) async throws -> HTTPClientRedirectionAction {
        try await closure(response, newRequest)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPRequestOptionsRedirectionHandler {
    public var redirectionHandlerClosure: ((HTTPResponse, HTTPRequest) async throws -> HTTPClientRedirectionAction)? {
        get {
            if let redirectionHandler = self.redirectionHandler {
                // Crash if it's not our built-in handler
                (redirectionHandler as! ClosureHTTPClientRedirectionHandler).closure
            } else {
                nil
            }
        }
        set {
            if let newValue {
                self.redirectionHandler = ClosureHTTPClientRedirectionHandler(closure: newValue)
            } else {
                self.redirectionHandler = nil
            }
        }
    }
}
