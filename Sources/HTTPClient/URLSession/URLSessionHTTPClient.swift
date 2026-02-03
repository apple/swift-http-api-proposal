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

#if canImport(Darwin)
import HTTPAPIs
import Foundation
import HTTPTypesFoundation
import NetworkTypes
import Synchronization

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
final class URLSessionHTTPClient: HTTPClient, IdleTimerEntryProvider, Sendable {
    typealias RequestWriter = URLSessionRequestStreamBridge
    typealias ResponseConcludingReader = URLSessionTaskDelegateBridge

    let poolConfiguration: HTTPConnectionPoolConfiguration

    init(poolConfiguration: HTTPConnectionPoolConfiguration) {
        self.poolConfiguration = poolConfiguration
    }

    struct SessionConfiguration: Hashable {
        let poolConfiguration: HTTPConnectionPoolConfiguration
        let minimumTLSVersion: TLSVersion
        let maximumTLSVersion: TLSVersion

        init(_ options: HTTPRequestOptions, poolConfiguration: HTTPConnectionPoolConfiguration) {
            self.minimumTLSVersion = options.minimumTLSVersion
            self.maximumTLSVersion = options.maximumTLSVersion
            self.poolConfiguration = poolConfiguration
        }

        var configuration: URLSessionConfiguration {
            let configuration = URLSessionConfiguration.default
            configuration.usesClassicLoadingMode = false
            configuration.httpMaximumConnectionsPerHost = poolConfiguration.maximumConcurrentHTTP1ConnectionsPerHost
            if let version = self.minimumTLSVersion.tlsProtocolVersion {
                configuration.tlsMinimumSupportedProtocolVersion = version
            }
            if let version = self.maximumTLSVersion.tlsProtocolVersion {
                configuration.tlsMaximumSupportedProtocolVersion = version
            }
            return configuration
        }
    }

    final class Session: NSObject, URLSessionDelegate, IdleTimerEntry {
        private weak let client: URLSessionHTTPClient?
        let configuration: SessionConfiguration
        private struct State {
            var session: URLSession! = nil
            var tasks: UInt8 = 0
            var idleTime: ContinuousClock.Instant? = nil
        }

        private let state: Mutex<State> = .init(.init())

        var idleDuration: Duration? {
            self.state.withLock {
                if let idleTime = $0.idleTime {
                    .now - idleTime
                } else {
                    nil
                }
            }
        }

        init(configuration: SessionConfiguration, client: URLSessionHTTPClient) {
            self.client = client
            self.configuration = configuration
            super.init()
            self.state.withLock {
                $0.session = URLSession(configuration: configuration.configuration, delegate: self, delegateQueue: nil)
            }
        }

        func startTask() -> URLSession {
            self.state.withLock {
                $0.tasks += 1
                $0.idleTime = nil
                return $0.session
            }
        }

        func finishTask() {
            self.state.withLock {
                $0.tasks -= 1
                if $0.tasks == 0 {
                    $0.idleTime = .now
                }
            }
        }

        func idleTimeoutFired() {
            self.invalidate()
        }

        func invalidate() {
            self.client?.sessionInvalidating(self)
            self.state.withLock {
                $0.session.invalidateAndCancel()
            }
        }

        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
            self.client?.sessionInvalidated(self)
        }
    }

    private struct Sessions: ~Copyable {
        var sessions: [SessionConfiguration: Session] = [:]
        var invalidatingSession: Set<Session> = []
        var idleTimer: IdleTimer<URLSessionHTTPClient>? = nil
        var invalidateContinuation: CheckedContinuation<Void, Never>? = nil
    }

    private let sessions: Mutex<Sessions> = .init(.init())

    func session(for options: HTTPRequestOptions) -> Session {
        let configuration = SessionConfiguration(options, poolConfiguration: self.poolConfiguration)
        return self.sessions.withLock {
            if let session = $0.sessions[configuration] {
                return session
            }
            let session = Session(configuration: configuration, client: self)
            $0.sessions[configuration] = session
            if $0.idleTimer == nil {
                $0.idleTimer = .init(timeout: .seconds(5 * 60), provider: self)
            }
            return session
        }
    }

    func sessionInvalidating(_ session: Session) {
        self.sessions.withLock {
            $0.sessions[session.configuration] = nil
            $0.invalidatingSession.insert(session)
        }
    }

    func sessionInvalidated(_ session: Session) {
        self.sessions.withLock {
            $0.invalidatingSession.remove(session)
            if let continuation = $0.invalidateContinuation, $0.sessions.isEmpty && $0.invalidatingSession.isEmpty {
                continuation.resume()
            }
        }
    }

    func invalidate() async {
        await withCheckedContinuation { continuation in
            let sessionsToInvalidate = self.sessions.withLock {
                if $0.sessions.isEmpty && $0.invalidatingSession.isEmpty {
                    continuation.resume()
                } else {
                    $0.invalidateContinuation = continuation
                }
                return $0.sessions.values
            }
            for session in sessionsToInvalidate {
                session.invalidate()
            }
        }
    }

    var idleTimerEntries: some Sequence<Session> {
        self.sessions.withLock { $0.sessions.values }
    }

    func request(for request: HTTPRequest, options: HTTPRequestOptions) throws -> URLRequest {
        guard var request = URLRequest(httpRequest: request) else {
            throw HTTPTypeConversionError.failedToConvertHTTPTypesToURLType
        }
        request.allowsExpensiveNetworkAccess = options.allowsExpensiveNetworkAccess
        request.allowsConstrainedNetworkAccess = options.allowsConstrainedNetworkAccess
        return request
    }

    func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>?,
        options: HTTPRequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return
    ) async throws -> Return {
        let request = try self.request(for: request, options: options)
        let session = self.session(for: options)
        let task: URLSessionTask
        let delegateBridge: URLSessionTaskDelegateBridge
        if let body {
            task = session.startTask().uploadTask(withStreamedRequest: request)
            delegateBridge = URLSessionTaskDelegateBridge(task: task, body: body)
        } else {
            task = session.startTask().dataTask(with: request)
            delegateBridge = URLSessionTaskDelegateBridge(task: task, body: nil)
        }
        task.delegate = delegateBridge
        task.resume()
        defer {
            session.finishTask()
        }
        // withTaskCancellationHandler does not support ~Copyable result type
        var result: Result<Return, any Error>? = nil
        try await withTaskCancellationHandler {
            do {
                let response = try await delegateBridge.processDelegateCallbacksBeforeResponse(options)
                guard let response = (response as? HTTPURLResponse)?.httpResponse else {
                    throw HTTPTypeConversionError.failedToConvertURLTypeToHTTPTypes
                }
                result = .success(try await responseHandler(response, delegateBridge))
            } catch {
                result = .failure(error)
            }
            try await delegateBridge.processDelegateCallbacksAfterResponse(options)
        } onCancel: {
            task.cancel()
        }
        return try result!.get()
    }
}
#endif
