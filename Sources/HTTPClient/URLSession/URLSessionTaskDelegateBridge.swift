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
import Synchronization

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
final class URLSessionTaskDelegateBridge: NSObject, Sendable, URLSessionDataDelegate {
    private enum Callback: Sendable {
        case response(URLResponse)
        case redirection(
            response: HTTPURLResponse,
            newRequest: URLRequest,
            completionHandler: @Sendable (URLRequest?) -> Void
        )
        case challenge(
            challenge: URLAuthenticationChallenge,
            completionHandler: @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        )
        case error(any Error)
    }
    private weak let task: URLSessionTask?

    // This stream and the continuation are used for the events such as redirections.
    // There is no way to apply back pressure to these events hence this stream doesn't set buffer
    // limits.
    private let stream: AsyncStream<Callback>
    private let continuation: AsyncStream<Callback>.Continuation
    private let requestBody: HTTPClientRequestBody<URLSessionRequestStreamBridge>?
    // TODO: Can we get rid of this task and instead use on task group per client?
    private let requestBodyTask: Mutex<Task<Void, Never>?> = .init(nil)

    init(task: URLSessionTask, body: consuming HTTPClientRequestBody<URLSessionRequestStreamBridge>?) {
        self.task = task
        var continuation: AsyncStream<Callback>.Continuation?
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation!
        self.requestBody = body
    }

    // MARK: - Data path

    private static let highWatermark = 256 * 1024

    enum State {
        case awaitingResponse
        case awaitingData(CheckedContinuation<Void, Never>)
        case awaitingConsumption(Data, complete: Bool, error: (any Error)?, suspendedTask: URLSessionTask?)
    }

    let state: Mutex<State> = .init(.awaitingResponse)

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let oldState = self.state.withLock { state in
            defer {
                switch state {
                case .awaitingResponse:
                    state = .awaitingConsumption(Data(), complete: false, error: nil, suspendedTask: nil)
                case .awaitingData, .awaitingConsumption:
                    break
                }
            }
            return state
        }
        switch oldState {
        case .awaitingResponse:
            self.continuation.yield(.response(response))
        case .awaitingData, .awaitingConsumption:
            break
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let oldState = self.state.withLock { state in
            defer {
                switch state {
                case .awaitingData:
                    state = .awaitingConsumption(data, complete: false, error: nil, suspendedTask: nil)
                case .awaitingResponse:
                    // We don't support data before response
                    state = .awaitingConsumption(Data(), complete: true, error: nil, suspendedTask: nil)
                case .awaitingConsumption(let existingData, let complete, let error, var suspendedTask):
                    let newData = existingData + data
                    if newData.count > Self.highWatermark && suspendedTask == nil {
                        dataTask.suspend()
                        suspendedTask = dataTask
                    }
                    state = .awaitingConsumption(
                        newData,
                        complete: complete,
                        error: error,
                        suspendedTask: suspendedTask
                    )
                }
            }
            return state
        }
        switch oldState {
        case .awaitingData(let continuation):
            continuation.resume()
        case .awaitingResponse:
            // We don't support data before response
            self.continuation.yield(.error(URLError(.unknown)))
            dataTask.cancel()
        case .awaitingConsumption:
            break
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let oldState = self.state.withLock { state in
            defer {
                switch state {
                case .awaitingData:
                    state = .awaitingConsumption(Data(), complete: true, error: error, suspendedTask: nil)
                case .awaitingResponse:
                    state = .awaitingConsumption(Data(), complete: true, error: nil, suspendedTask: nil)
                case .awaitingConsumption(let existingData, _, let error, _):
                    state = .awaitingConsumption(existingData, complete: true, error: error, suspendedTask: nil)
                }
            }
            return state
        }
        switch oldState {
        case .awaitingResponse:
            self.continuation.yield(.error(error ?? URLError(.unknown)))
        case .awaitingData(let continuation):
            continuation.resume()
        case .awaitingConsumption:
            break
        }
        self.continuation.finish()
    }

    func data(maximumCount: Int?) async throws -> Data? {
        let needsData: Bool = self.state.withLock { state in
            switch state {
            case .awaitingConsumption(let existingData, let complete, _, _):
                existingData.isEmpty && !complete
            case .awaitingResponse:
                fatalError("Unexpected state")
            case .awaitingData:
                fatalError("Must not read concurrently")
            }
        }
        if needsData {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    self.state.withLock { state in
                        state = .awaitingData(continuation)
                    }
                }
            } onCancel: {
                self.task?.cancel()
            }
        }
        return try self.state.withLock { state in
            switch state {
            case .awaitingConsumption(let existingData, let complete, let error, let suspendedTask):
                if !existingData.isEmpty {
                    let (dataToReturn, remainingData) =
                        if let maximumCount, existingData.count > maximumCount {
                            (existingData.prefix(maximumCount), existingData.dropFirst(maximumCount))
                        } else {
                            (existingData, Data())
                        }
                    let shouldResume = remainingData.count <= Self.highWatermark
                    state = .awaitingConsumption(
                        remainingData,
                        complete: complete,
                        error: existingData.isEmpty ? nil : error,
                        suspendedTask: shouldResume ? nil : suspendedTask
                    )
                    if shouldResume {
                        suspendedTask?.resume()
                    }
                    return dataToReturn
                } else if complete {
                    if let error {
                        throw error
                    }
                    return nil
                } else {
                    fatalError("Unexpected state")
                }
            case .awaitingResponse, .awaitingData:
                fatalError("Unexpected state")
            }
        }
    }

    // MARK: - Request body

    override func responds(to aSelector: Selector) -> Bool {
        if aSelector == #selector(
            (any URLSessionTaskDelegate).urlSession(_:task:needNewBodyStreamFrom:completionHandler:)
        ) {
            return self.requestBody?.isSeekable == true
        }
        return super.responds(to: aSelector)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void
    ) {
        guard let requestBody = self.requestBody else {
            fatalError()
        }
        self.requestBodyTask.withLock {
            let oldTask = $0
            oldTask?.cancel()
            $0 = Task.immediate {
                await oldTask?.value
                let bridge = URLSessionRequestStreamBridge(task: task)
                completionHandler(bridge.inputStream)
                do {
                    try await requestBody.produce(into: bridge)
                } catch {
                    if bridge.writeFailed {
                        // Ignore error
                    } else {
                        self.requestBodyStreamFailed(with: error)
                    }
                }
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        needNewBodyStreamFrom offset: Int64,
        completionHandler: @escaping @Sendable (InputStream?) -> Void
    ) {
        guard let requestBody = self.requestBody else {
            fatalError()
        }
        self.requestBodyTask.withLock {
            let oldTask = $0
            oldTask?.cancel()
            $0 = Task.immediate {
                await oldTask?.value
                let bridge = URLSessionRequestStreamBridge(task: task)
                completionHandler(bridge.inputStream)
                do {
                    try await requestBody.produce(offset: offset, into: bridge)
                } catch {
                    if bridge.writeFailed {
                        // Ignore error
                    } else {
                        self.requestBodyStreamFailed(with: error)
                    }
                }
            }
        }
    }

    // MARK: - Events

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let scheme = request.url?.scheme?.lowercased(),
            scheme == "https" || scheme == "http"
        else {
            completionHandler(nil)
            return
        }
        if case .enqueued = self.continuation.yield(
            .redirection(response: response, newRequest: request, completionHandler: completionHandler)
        ) {
        } else {
            completionHandler(nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if case .enqueued = self.continuation.yield(
            .challenge(challenge: challenge, completionHandler: completionHandler)
        ) {
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func requestBodyStreamFailed(with error: any Error) {
        self.continuation.yield(.error(error))
    }

    func processDelegateCallbacksBeforeResponse(
        _ eventHandler: borrowing some HTTPClientEventHandler & ~Escapable & ~Copyable
    ) async throws -> URLResponse {
        for await callback in self.stream {
            switch callback {
            case .response(let response):
                return response
            case .redirection(let response, let request, let completionHandler):
                do {
                    guard let httpResponse = response.httpResponse,
                        let httpRequest = request.httpRequest
                    else {
                        completionHandler(nil)
                        throw HTTPTypeConversionError.failedToConvertURLTypeToHTTPTypes
                    }
                    switch try await eventHandler.handleRedirection(response: httpResponse, newRequest: httpRequest) {
                    case .follow(let finalRequest):
                        guard let urlRequest = URLRequest(httpRequest: finalRequest) else {
                            completionHandler(nil)
                            throw HTTPTypeConversionError.failedToConvertHTTPTypesToURLType
                        }
                        completionHandler(urlRequest)
                    case .deliverRedirectionResponse:
                        completionHandler(nil)
                    }
                } catch {
                    completionHandler(nil)
                    throw error
                }
            case .challenge(let challenge, let completionHandler):
                do {
                    if let trust = challenge.protectionSpace.serverTrust {
                        switch try await eventHandler.handleServerTrust(trust) {
                        case .default:
                            completionHandler(.performDefaultHandling, nil)
                        case .allow:
                            completionHandler(.useCredential, URLCredential(trust: trust))
                        case .deny:
                            completionHandler(.cancelAuthenticationChallenge, nil)
                        }
                    } else {
                        completionHandler(.performDefaultHandling, nil)
                    }
                } catch {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    throw error
                }
            case .error(let error):
                throw error
            }
        }
        fatalError()
    }

    func processDelegateCallbacksAfterResponse(
        _ eventHandler: borrowing some HTTPClientEventHandler & ~Escapable & ~Copyable
    ) async throws {
        for await callback in self.stream {
            switch callback {
            case .response:
                break
            case .redirection(_, _, let completionHandler):
                completionHandler(nil)
            case .challenge(_, let completionHandler):
                completionHandler(.cancelAuthenticationChallenge, nil)
            case .error(let error):
                await self.requestBodyTask.withLock { $0 }?.value
                throw error
            }
        }
        await self.requestBodyTask.withLock { $0 }?.value
    }
}
#endif
