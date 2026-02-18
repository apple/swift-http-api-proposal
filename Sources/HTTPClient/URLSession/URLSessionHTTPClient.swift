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
final class URLSessionHTTPClient: HTTPClient, IdleTimerEntryProvider {
    typealias RequestWriter = URLSessionRequestStreamBridge
    typealias ResponseConcludingReader = URLSessionTaskDelegateBridge

    let poolConfiguration: HTTPConnectionPoolConfiguration

    private init(poolConfiguration: HTTPConnectionPoolConfiguration, shared: Bool) {
        self.poolConfiguration = poolConfiguration
        self.sessions = .init(.init(shared: shared))
    }

    static func withClient<Return: ~Copyable, Failure: Error>(
        poolConfiguration: HTTPConnectionPoolConfiguration,
        _ body: (URLSessionHTTPClient) async throws(Failure) -> Return
    ) async throws(Failure) -> Return {
        // withTaskGroup does not support ~Copyable result type
        var result: Result<Return, Failure>? = nil
        await withTaskGroup { group in
            let client = URLSessionHTTPClient(poolConfiguration: poolConfiguration, shared: false)
            group.addTask {
                await IdleTimer.run(timeout: .seconds(5 * 60), provider: client)
            }
            do throws(Failure) {
                result = .success(try await body(client))
            } catch {
                result = .failure(error)
            }
            await client.invalidate()
            group.cancelAll()
        }
        return try result!.get()
    }

    static let shared: URLSessionHTTPClient = {
        let client = URLSessionHTTPClient(poolConfiguration: .init(), shared: true)
        // This is the only expected unstructured task since the singleton client doesn't have a parent task to attach to.
        Task.detached {
            await IdleTimer.run(timeout: .seconds(5 * 60), provider: client)
        }
        return client
    }()

    fileprivate struct SessionConfiguration: Hashable {
        let poolConfiguration: HTTPConnectionPoolConfiguration
        let minimumTLSVersion: TLSVersion
        let maximumTLSVersion: TLSVersion

        init(_ options: HTTPRequestOptions, poolConfiguration: HTTPConnectionPoolConfiguration) {
            self.minimumTLSVersion = options.minimumTLSVersion
            self.maximumTLSVersion = options.maximumTLSVersion
            self.poolConfiguration = poolConfiguration
        }

        func sessionConfiguration(storage: Sessions.Storage) -> URLSessionConfiguration {
            let configuration: URLSessionConfiguration =
                switch storage {
                case .persistent:
                    .default
                case .ephemeral(let storageConfiguration):
                    storageConfiguration.copy() as! URLSessionConfiguration
                }
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
        fileprivate let configuration: SessionConfiguration
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

        fileprivate init(
            configuration: SessionConfiguration,
            storage: Sessions.Storage,
            client: URLSessionHTTPClient
        ) {
            self.client = client
            self.configuration = configuration
            super.init()
            self.state.withLock {
                let configuration = configuration.sessionConfiguration(storage: storage)
                $0.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            }
        }

        fileprivate func startTask() -> URLSession {
            self.state.withLock {
                $0.tasks += 1
                $0.idleTime = nil
                return $0.session
            }
        }

        fileprivate func finishTask() {
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

        fileprivate func invalidate() {
            self.client?.sessionInvalidating(self)
            self.state.withLock {
                $0.session.invalidateAndCancel()
            }
        }

        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
            self.client?.sessionInvalidated(self)
        }
    }

    fileprivate struct Sessions: ~Copyable {
        enum Storage {
            case persistent
            case ephemeral(URLSessionConfiguration)
        }
        let storage: Storage
        var sessions: [SessionConfiguration: Session] = [:]
        var invalidatingSession: Set<Session> = []
        var invalidateContinuation: CheckedContinuation<Void, Never>? = nil
        var invalidated = false

        init(shared: Bool) {
            self.storage = shared ? .persistent : .ephemeral(.ephemeral)
        }
    }

    private let sessions: Mutex<Sessions>

    private func session(for options: HTTPRequestOptions) -> Session {
        let configuration = SessionConfiguration(options, poolConfiguration: self.poolConfiguration)
        return self.sessions.withLock {
            if $0.invalidated {
                fatalError("DefaultHTTPClient used outside its scope")
            }
            if let session = $0.sessions[configuration] {
                return session
            }
            let session = Session(configuration: configuration, storage: $0.storage, client: self)
            $0.sessions[configuration] = session
            return session
        }
    }

    private func sessionInvalidating(_ session: Session) {
        self.sessions.withLock {
            $0.sessions[session.configuration] = nil
            $0.invalidatingSession.insert(session)
        }
    }

    private func sessionInvalidated(_ session: Session) {
        self.sessions.withLock {
            $0.invalidatingSession.remove(session)
            if let continuation = $0.invalidateContinuation, $0.sessions.isEmpty && $0.invalidatingSession.isEmpty {
                continuation.resume()
                $0.invalidateContinuation = nil
            }
        }
    }

    private func invalidate() async {
        await withCheckedContinuation { continuation in
            let sessionsToInvalidate = self.sessions.withLock {
                $0.invalidated = true
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

    private func request(for request: HTTPRequest, options: HTTPRequestOptions) throws -> URLRequest {
        guard var request = URLRequest(httpRequest: request) else {
            throw HTTPTypeConversionError.failedToConvertHTTPTypesToURLType
        }
        request.allowsExpensiveNetworkAccess = options.allowsExpensiveNetworkAccess
        request.allowsConstrainedNetworkAccess = options.allowsConstrainedNetworkAccess

        // Disable Content-Type sniffing
        let urlRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(false, forKey: "_kCFURLConnectionPropertyShouldSniff", in: urlRequest)
        return urlRequest as URLRequest
    }

    func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>?,
        options: HTTPRequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return
    ) async throws -> Return {
        guard request.schemeSupported else {
            throw HTTPTypeConversionError.unsupportedScheme
        }
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
