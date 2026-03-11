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

/// Describes whether a request body can be replayed across retry attempts.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public enum HTTPClientRequestBodyReplayability: Sendable {
    /// The request has no body.
    case none

    /// The request body can be replayed from the beginning.
    case restartable

    /// The request body can be replayed from any offset.
    case seekable
}

/// Context for a retry decision.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPClientRetryContext: Sendable {
    /// The request that produced the current response or error.
    public var request: HTTPRequest

    /// Whether the request body can be replayed.
    public var bodyReplayability: HTTPClientRequestBodyReplayability

    /// The current attempt number, starting at `1`.
    public var attempt: Int

    public init(
        request: HTTPRequest,
        bodyReplayability: HTTPClientRequestBodyReplayability,
        attempt: Int
    ) {
        self.request = request
        self.bodyReplayability = bodyReplayability
        self.attempt = attempt
    }
}

/// A policy object that decides whether a request should be retried.
///
/// Retry hooks are only consulted before the response is handed to the caller. Once the
/// response handler starts consuming the response, the request is no longer retryable.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public protocol HTTPClientRetryStrategy: Sendable {
    /// Decides whether to retry after receiving a response.
    func retryRequest(
        after response: HTTPResponse,
        context: HTTPClientRetryContext
    ) async throws -> HTTPClientRetryAction

    /// Decides whether to retry after a transport-level failure before the response is exposed.
    func retryRequest(
        after error: any Error,
        context: HTTPClientRetryContext
    ) async throws -> HTTPClientRetryAction
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClientRetryStrategy {
    public func retryRequest(
        after response: HTTPResponse,
        context: HTTPClientRetryContext
    ) async throws -> HTTPClientRetryAction {
        .doNotRetry
    }

    public func retryRequest(
        after error: any Error,
        context: HTTPClientRetryContext
    ) async throws -> HTTPClientRetryAction {
        .doNotRetry
    }
}

/// A backoff schedule for retrying requests.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPClientRetryBackoff: Sendable {
    private enum Storage: Sendable {
        case immediate
        case constant(Duration)
        case linear(Duration)
        case exponential(initialDelay: Duration, multiplier: Int)
    }

    private let storage: Storage

    /// The maximum total number of attempts, including the first attempt.
    public let maximumNumberOfAttempts: Int

    private init(storage: Storage, maximumNumberOfAttempts: Int) {
        precondition(maximumNumberOfAttempts >= 1, "maximumNumberOfAttempts must be at least 1")
        self.storage = storage
        self.maximumNumberOfAttempts = maximumNumberOfAttempts
    }

    /// Retries immediately until the maximum number of attempts is reached.
    public static func immediate(maximumNumberOfAttempts: Int) -> Self {
        .init(storage: .immediate, maximumNumberOfAttempts: maximumNumberOfAttempts)
    }

    /// Retries with a constant delay.
    public static func constant(_ delay: Duration, maximumNumberOfAttempts: Int) -> Self {
        .init(storage: .constant(delay), maximumNumberOfAttempts: maximumNumberOfAttempts)
    }

    /// Retries with a linearly increasing delay.
    public static func linear(_ delay: Duration, maximumNumberOfAttempts: Int) -> Self {
        .init(storage: .linear(delay), maximumNumberOfAttempts: maximumNumberOfAttempts)
    }

    /// Retries with an exponentially increasing delay.
    public static func exponential(
        initialDelay: Duration,
        multiplier: Int = 2,
        maximumNumberOfAttempts: Int
    ) -> Self {
        precondition(multiplier >= 1, "multiplier must be at least 1")
        return .init(
            storage: .exponential(initialDelay: initialDelay, multiplier: multiplier),
            maximumNumberOfAttempts: maximumNumberOfAttempts
        )
    }

    /// Returns the delay before retrying after the specified attempt.
    ///
    /// For example, if `attempt` is `1`, the returned duration is the delay before the second attempt.
    public func delay(afterAttempt attempt: Int) -> Duration? {
        guard attempt >= 1, attempt < self.maximumNumberOfAttempts else {
            return nil
        }

        switch self.storage {
        case .immediate:
            return .zero
        case .constant(let delay):
            return delay
        case .linear(let delay):
            return delay * attempt
        case .exponential(let initialDelay, let multiplier):
            return initialDelay * Self.power(multiplier, attempt - 1)
        }
    }

    private static func power(_ base: Int, _ exponent: Int) -> Int {
        guard exponent > 0 else {
            return 1
        }
        var result = 1
        for _ in 0..<exponent {
            result *= base
        }
        return result
    }
}

/// A retry strategy backed by closures.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPClientConditionalRetryStrategy: HTTPClientRetryStrategy {
    public typealias ResponseHandler = @Sendable (HTTPResponse, HTTPClientRetryContext) async throws -> HTTPClientRetryAction
    public typealias ErrorHandler = @Sendable (any Error, HTTPClientRetryContext) async throws -> HTTPClientRetryAction

    private let responseHandler: ResponseHandler?
    private let errorHandler: ErrorHandler?

    public init(
        onResponse responseHandler: ResponseHandler? = nil,
        onError errorHandler: ErrorHandler? = nil
    ) {
        self.responseHandler = responseHandler
        self.errorHandler = errorHandler
    }

    public func retryRequest(
        after response: HTTPResponse,
        context: HTTPClientRetryContext
    ) async throws -> HTTPClientRetryAction {
        try await self.responseHandler?(response, context) ?? .doNotRetry
    }

    public func retryRequest(
        after error: any Error,
        context: HTTPClientRetryContext
    ) async throws -> HTTPClientRetryAction {
        try await self.errorHandler?(error, context) ?? .doNotRetry
    }
}

/// Retries idempotent requests for transient server responses and selected transport errors.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPClientTransientFailureRetryStrategy: HTTPClientRetryStrategy {
    private let currentTimeSinceUnixEpoch: @Sendable () -> Duration

    public static let defaultRetryableMethods: Set<HTTPRequest.Method> = [
        .get,
        .head,
        .put,
        .delete,
        .options,
        .trace,
    ]

    public static let defaultRetryableStatusCodes: Set<HTTPResponse.Status> = [
        .requestTimeout,
        .tooManyRequests,
        .badGateway,
        .serviceUnavailable,
        .gatewayTimeout,
    ]

    public let backoff: HTTPClientRetryBackoff
    public var retryableMethods: Set<HTTPRequest.Method>
    public var retryableStatusCodes: Set<HTTPResponse.Status>
    public var respectsRetryAfter: Bool

    public init(
        backoff: HTTPClientRetryBackoff,
        retryableMethods: Set<HTTPRequest.Method> = Self.defaultRetryableMethods,
        retryableStatusCodes: Set<HTTPResponse.Status> = Self.defaultRetryableStatusCodes,
        respectsRetryAfter: Bool = true
    ) {
        self.init(
            backoff: backoff,
            retryableMethods: retryableMethods,
            retryableStatusCodes: retryableStatusCodes,
            respectsRetryAfter: respectsRetryAfter,
            currentTimeSinceUnixEpoch: {
                .milliseconds(Int64((Date().timeIntervalSince1970 * 1000).rounded()))
            }
        )
    }

    package init(
        backoff: HTTPClientRetryBackoff,
        retryableMethods: Set<HTTPRequest.Method> = Self.defaultRetryableMethods,
        retryableStatusCodes: Set<HTTPResponse.Status> = Self.defaultRetryableStatusCodes,
        respectsRetryAfter: Bool = true,
        currentTimeSinceUnixEpoch: @escaping @Sendable () -> Duration
    ) {
        self.backoff = backoff
        self.retryableMethods = retryableMethods
        self.retryableStatusCodes = retryableStatusCodes
        self.respectsRetryAfter = respectsRetryAfter
        self.currentTimeSinceUnixEpoch = currentTimeSinceUnixEpoch
    }

    public func retryRequest(
        after response: HTTPResponse,
        context: HTTPClientRetryContext
    ) async throws -> HTTPClientRetryAction {
        guard self.retryableMethods.contains(context.request.method),
            self.retryableStatusCodes.contains(response.status)
        else {
            return .doNotRetry
        }

        if self.respectsRetryAfter,
            let retryAfter = response.headerFields[.retryAfter],
            let delay = self.retryAfterDelay(from: retryAfter)
        {
            return .retry(context.request, after: delay)
        }

        guard let delay = self.backoff.delay(afterAttempt: context.attempt) else {
            return .doNotRetry
        }
        return .retry(context.request, after: delay)
    }

    public func retryRequest(
        after error: any Error,
        context: HTTPClientRetryContext
    ) async throws -> HTTPClientRetryAction {
        guard self.retryableMethods.contains(context.request.method),
            Self.isRetryableTransportError(error),
            let delay = self.backoff.delay(afterAttempt: context.attempt)
        else {
            return .doNotRetry
        }
        return .retry(context.request, after: delay)
    }

    static func isRetryableTransportError(_ error: any Error) -> Bool {
        if error is CancellationError {
            return false
        }
        guard let urlError = error as? URLError else {
            return false
        }
        switch urlError.code {
        case .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .resourceUnavailable,
            .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private func retryAfterDelay(from value: String) -> Duration? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Int(trimmedValue) {
            // RFC 9110 Section 10.2.3 defines `Retry-After` as either an `HTTP-date`
            // or `delay-seconds`, where `delay-seconds` is a non-negative integer.
            return .seconds(max(seconds, 0))
        }

        guard let date = HTTPDateFormatter().date(from: trimmedValue) else {
            return nil
        }

        let delay = Self.timeSinceUnixEpoch(for: date) - self.currentTimeSinceUnixEpoch()
        return max(delay, .zero)
    }

    private static func timeSinceUnixEpoch(for date: Date) -> Duration {
        .milliseconds(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }
}
