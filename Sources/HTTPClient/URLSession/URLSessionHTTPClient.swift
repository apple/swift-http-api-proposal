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
final class URLSessionHTTPClient: HTTPClient, Sendable {
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

    // TODO: Do we need to remove sessions again to avoid holding onto the memory forever
    let sessions: Mutex<[SessionConfiguration: URLSession]> = .init([:])

    func session(for options: HTTPRequestOptions) -> URLSession {
        let sessionConfiguration = SessionConfiguration(options, poolConfiguration: self.poolConfiguration)
        return self.sessions.withLock {
            if let session = $0[sessionConfiguration] {
                return session
            }
            let session = URLSession(configuration: sessionConfiguration.configuration)
            $0[sessionConfiguration] = session
            return session
        }
    }

    func request(for request: HTTPRequest, options: HTTPRequestOptions) throws -> URLRequest {
        guard var request = URLRequest(httpRequest: request) else {
            throw HTTPTypeConversionError.failedToConvertHTTPTypesToURLType
        }
        request.allowsExpensiveNetworkAccess = options.allowsExpensiveNetworkAccess
        request.allowsConstrainedNetworkAccess = options.allowsConstrainedNetworkAccess
        return request
    }

    func perform<Return>(
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
            task = session.uploadTask(withStreamedRequest: request)
            delegateBridge = URLSessionTaskDelegateBridge(task: task, body: body)
        } else {
            task = session.dataTask(with: request)
            delegateBridge = URLSessionTaskDelegateBridge(task: task, body: nil)
        }
        task.delegate = delegateBridge
        task.resume()
        return try await withTaskCancellationHandler {
            let result: Result<Return, any Error>
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
            return try result.get()
        } onCancel: {
            task.cancel()
        }
    }
}
#endif
