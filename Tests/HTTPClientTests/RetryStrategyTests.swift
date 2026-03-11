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

#if canImport(Foundation)
import Foundation
#endif
import HTTPClient
import HTTPClientConformance
import Testing

@Suite
struct RetryStrategyTests {
    @Test
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func linearBackoffGrowsPerAttempt() {
        let backoff = HTTPClientRetryBackoff.linear(.milliseconds(50), maximumNumberOfAttempts: 4)

        #expect(backoff.delay(afterAttempt: 1) == .milliseconds(50))
        #expect(backoff.delay(afterAttempt: 2) == .milliseconds(100))
        #expect(backoff.delay(afterAttempt: 3) == .milliseconds(150))
        #expect(backoff.delay(afterAttempt: 4) == nil)
    }

    @Test
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func exponentialBackoffDoublesPerAttempt() {
        let backoff = HTTPClientRetryBackoff.exponential(
            initialDelay: .milliseconds(25),
            maximumNumberOfAttempts: 5
        )

        #expect(backoff.delay(afterAttempt: 1) == .milliseconds(25))
        #expect(backoff.delay(afterAttempt: 2) == .milliseconds(50))
        #expect(backoff.delay(afterAttempt: 3) == .milliseconds(100))
        #expect(backoff.delay(afterAttempt: 4) == .milliseconds(200))
        #expect(backoff.delay(afterAttempt: 5) == nil)
    }

    @Test
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func transientFailureStrategyHonorsRetryAfterHeader() async throws {
        let strategy = HTTPClientTransientFailureRetryStrategy(
            backoff: .constant(.seconds(10), maximumNumberOfAttempts: 3)
        )
        let request = HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/")
        let context = HTTPClientRetryContext(request: request, bodyReplayability: .none, attempt: 1)
        let response = HTTPResponse(
            status: .serviceUnavailable,
            headerFields: [
                .retryAfter: "2"
            ]
        )

        let action = try await strategy.retryRequest(after: response, context: context)
        switch action {
        case .retry(let retriedRequest, let delay):
            #expect(retriedRequest == request)
            #expect(delay == .seconds(2))
        case .doNotRetry:
            Issue.record("Expected retry action")
        }
    }

    @Test
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func transientFailureStrategyParsesRetryAfterHttpDate() async throws {
        let now = Duration.seconds(1_700_000_000)
        let strategy = HTTPClientTransientFailureRetryStrategy(
            backoff: .constant(.seconds(10), maximumNumberOfAttempts: 3),
            currentTimeSinceUnixEpoch: { now }
        )
        let request = HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/")
        let context = HTTPClientRetryContext(request: request, bodyReplayability: .none, attempt: 1)

        let formatter = HTTPDateFormatter()
        let retryAfterDate = Date(timeIntervalSince1970: 1_700_000_002)
        let retryAfterValue = formatter.string(from: retryAfterDate)
        let response = HTTPResponse(
            status: .tooManyRequests,
            headerFields: [
                .retryAfter: retryAfterValue
            ]
        )

        let action = try await strategy.retryRequest(after: response, context: context)
        switch action {
        case .retry(_, let delay):
            #expect(delay == .seconds(2))
        case .doNotRetry:
            Issue.record("Expected retry action")
        }
    }

    @Test
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func transientFailureStrategyDoesNotRetryPostByDefault() async throws {
        let strategy = HTTPClientTransientFailureRetryStrategy(
            backoff: .immediate(maximumNumberOfAttempts: 3)
        )
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        let context = HTTPClientRetryContext(request: request, bodyReplayability: .none, attempt: 1)
        let response = HTTPResponse(status: .serviceUnavailable)

        let action = try await strategy.retryRequest(after: response, context: context)
        switch action {
        case .doNotRetry:
            break
        case .retry:
            Issue.record("Expected doNotRetry action")
        }
    }

    @Test
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func transientFailureStrategyRetriesBadGatewayByDefault() async throws {
        let strategy = HTTPClientTransientFailureRetryStrategy(
            backoff: .immediate(maximumNumberOfAttempts: 3)
        )
        let request = HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/")
        let context = HTTPClientRetryContext(request: request, bodyReplayability: .none, attempt: 1)
        let response = HTTPResponse(status: .badGateway)

        let action = try await strategy.retryRequest(after: response, context: context)
        switch action {
        case .retry(let retriedRequest, let delay):
            #expect(retriedRequest == request)
            #expect(delay == .zero)
        case .doNotRetry:
            Issue.record("Expected retry action")
        }
    }

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func conditionalRetryCanMutateTheRequest() async throws {
        struct RetriedRequest: Decodable {
            let headers: [String: [String]]
        }

        try await withTestHTTPServer { port in
            let request = HTTPRequest(
                method: .get,
                scheme: "http",
                authority: "127.0.0.1:\(port)",
                path: "/request"
            )
            let retryHeader = HTTPField.Name("X-Retry-Attempt")!
            var options = HTTPRequestOptions()
            options.retryStrategy = HTTPClientConditionalRetryStrategy(onResponse: { response, context in
                guard context.attempt == 1,
                    response.status == .ok
                else {
                    return .doNotRetry
                }

                var request = context.request
                request.headerFields[retryHeader] = "2"
                return .retry(request, after: .zero)
            })

            try await DefaultHTTPClient.shared.perform(
                request: request,
                options: options
            ) { response, responseBodyAndTrailers in
                #expect(response.status == .ok)
                let (body, _) = try await responseBodyAndTrailers.collect(upTo: 4096) { span in
                    String(copying: try UTF8Span(validating: span))
                }
                let echoedRequest = try JSONDecoder().decode(RetriedRequest.self, from: Data(body.utf8))
                #expect(echoedRequest.headers["X-Retry-Attempt"] == ["2"])
            }
        }
    }

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func transientFailureStrategyRetriesRetryAfterResponses() async throws {
        try await withTestHTTPServer { port in
            let request = HTTPRequest(
                method: .get,
                scheme: "http",
                authority: "127.0.0.1:\(port)",
                path: "/retry_after"
            )
            var options = HTTPRequestOptions()
            options.retryStrategy = HTTPClientTransientFailureRetryStrategy(
                backoff: .constant(.milliseconds(10), maximumNumberOfAttempts: 3)
            )

            try await DefaultHTTPClient.shared.perform(
                request: request,
                options: options
            ) { response, responseBodyAndTrailers in
                #expect(response.status == .ok)
                let (body, _) = try await responseBodyAndTrailers.collect(upTo: 8) { span in
                    String(copying: try UTF8Span(validating: span))
                }
                #expect(body == "2")
            }
        }
    }

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func transientFailureStrategyFallsBackToBackoffWithoutRetryAfter() async throws {
        try await withTestHTTPServer { port in
            let request = HTTPRequest(
                method: .get,
                scheme: "http",
                authority: "127.0.0.1:\(port)",
                path: "/retry_after_no_header"
            )
            var options = HTTPRequestOptions()
            options.retryStrategy = HTTPClientTransientFailureRetryStrategy(
                backoff: .immediate(maximumNumberOfAttempts: 3)
            )

            try await DefaultHTTPClient.shared.perform(
                request: request,
                options: options
            ) { response, responseBodyAndTrailers in
                #expect(response.status == .ok)
                let (body, _) = try await responseBodyAndTrailers.collect(upTo: 8) { span in
                    String(copying: try UTF8Span(validating: span))
                }
                #expect(body == "2")
            }
        }
    }

    @Test(.enabled(if: testsEnabled))
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func transientFailureStrategyDoesNotRetryPostResponsesByDefault() async throws {
        try await withTestHTTPServer { port in
            let request = HTTPRequest(
                method: .post,
                scheme: "http",
                authority: "127.0.0.1:\(port)",
                path: "/retry_after"
            )
            var options = HTTPRequestOptions()
            options.retryStrategy = HTTPClientTransientFailureRetryStrategy(
                backoff: .immediate(maximumNumberOfAttempts: 3)
            )

            try await DefaultHTTPClient.shared.perform(
                request: request,
                options: options
            ) { response, responseBodyAndTrailers in
                #expect(response.status == .serviceUnavailable)
                let (body, _) = try await responseBodyAndTrailers.collect(upTo: 8) { span in
                    String(copying: try UTF8Span(validating: span))
                }
                #expect(body == "1")
            }
        }
    }
}
