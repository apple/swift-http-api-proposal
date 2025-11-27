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

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
final class HTTPClientURLSession: HTTPClient, Sendable {
    static let shared = HTTPClientURLSession()

    typealias RequestWriter = URLSessionRequestStreamBridge
    typealias ResponseReader = URLSessionTaskDelegateBridge

    struct SessionConfiguration: Hashable {
        var minimumTLSVersion: TLSVersion
        var maximumTLSVersion: TLSVersion

        init(_ configuration: HTTPClientConfiguration) {
            self.minimumTLSVersion = configuration.security.minimumTLSVersion
            self.maximumTLSVersion = configuration.security.maximumTLSVersion
        }

        var configuration: URLSessionConfiguration {
            let configuration = URLSessionConfiguration.default
            configuration.usesClassicLoadingMode = false
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

    func session(for configuration: HTTPClientConfiguration) -> URLSession {
        let sessionConfiguration = SessionConfiguration(configuration)
        return self.sessions.withLock {
            if let session = $0[sessionConfiguration] {
                return session
            }
            let session = URLSession(configuration: sessionConfiguration.configuration)
            $0[sessionConfiguration] = session
            return session
        }
    }

    func request(for request: HTTPRequest, configuration: HTTPClientConfiguration) throws -> URLRequest {
        guard var request = URLRequest(httpRequest: request) else {
            throw HTTPTypeConversionError.failedToConvertHTTPTypesToURLType
        }
        request.allowsExpensiveNetworkAccess = configuration.path.allowsExpensiveNetworkAccess
        request.allowsConstrainedNetworkAccess = configuration.path.allowsConstrainedNetworkAccess
        return request
    }

    func perform<Return>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestWriter>?,
        configuration: HTTPClientConfiguration,
        eventHandler: borrowing some HTTPClientEventHandler & ~Escapable & ~Copyable,
        responseHandler: (HTTPResponse, consuming ResponseReader) async throws -> Return
    ) async throws -> Return {
        let request = try self.request(for: request, configuration: configuration)
        let session = self.session(for: configuration)
        let task: URLSessionTask
        let delegateBridge: URLSessionTaskDelegateBridge
        if let body {
            task = session.uploadTask(withStreamedRequest: request)
            delegateBridge = URLSessionTaskDelegateBridge(body: body)
        } else {
            task = session.dataTask(with: request)
            delegateBridge = URLSessionTaskDelegateBridge(body: nil)
        }
        task.delegate = delegateBridge
        task.resume()
        return try await withTaskCancellationHandler {
            let result: Result<Return, any Error>
            do {
                let response = try await delegateBridge.processDelegateCallbacksBeforeResponse(eventHandler)
                guard let response = (response as? HTTPURLResponse)?.httpResponse else {
                    throw HTTPTypeConversionError.failedToConvertURLTypeToHTTPTypes
                }
                result = .success(try await responseHandler(response, delegateBridge))
            } catch {
                result = .failure(error)
            }
            try await delegateBridge.processDelegateCallbacksAfterResponse(eventHandler)
            return try result.get()
        } onCancel: {
            task.cancel()
        }
    }
}
#endif
