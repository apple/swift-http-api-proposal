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

import NIOConcurrencyHelpers
import NIOCore
import NIOPosix

enum ListeningAddressError: CustomStringConvertible, Error {
    case addressOrPortNotAvailable
    case unsupportedAddressType
    case serverClosed

    var description: String {
        switch self {
        case .addressOrPortNotAvailable:
            return "Unable to retrieve the bound address or port from the underlying socket"
        case .unsupportedAddressType:
            return "Unsupported address type: only IPv4 and IPv6 are supported"
        case .serverClosed:
            return """
                There is no listening address bound for this server: there may have been an error which caused the server to close, or it may have shut down.
                """
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension NIOHTTPServer {
    func addressBound(_ address: NIOCore.SocketAddress?) throws {
        switch self.listeningAddressState.withLockedValue({ $0.addressBound(address) }) {
        case .succeedPromise(let promise, let boundAddress):
            promise.succeed(boundAddress)
        case .failPromise(let promise, let error):
            promise.fail(error)
        }
    }

    /// The address the server is listening from.
    ///
    /// It is an `async` property because it will only return once the address has been successfully bound.
    ///
    /// - Throws: An error will be thrown if the address could not be bound or is not bound any longer because the
    ///   server isn't listening anymore.
    public var listeningAddress: SocketAddress {
        get async throws {
            try await self.listeningAddressState
                .withLockedValue { try $0.listeningAddressFuture }
                .get()
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension NIOHTTPServer {
    enum State {
        case idle(EventLoopPromise<SocketAddress>)
        case listening(EventLoopFuture<SocketAddress>)
        case closedOrInvalidAddress(ListeningAddressError)

        var listeningAddressFuture: EventLoopFuture<SocketAddress> {
            get throws {
                switch self {
                case .idle(let eventLoopPromise):
                    return eventLoopPromise.futureResult
                case .listening(let eventLoopFuture):
                    return eventLoopFuture
                case .closedOrInvalidAddress(let error):
                    throw error
                }
            }
        }

        enum OnBound {
            case succeedPromise(_ promise: EventLoopPromise<SocketAddress>, address: SocketAddress)
            case failPromise(_ promise: EventLoopPromise<SocketAddress>, error: ListeningAddressError)
        }

        mutating func addressBound(_ address: NIOCore.SocketAddress?) -> OnBound {
            switch self {
            case .idle(let listeningAddressPromise):
                do {
                    let socketAddress = try SocketAddress(address)
                    self = .listening(listeningAddressPromise.futureResult)
                    return .succeedPromise(listeningAddressPromise, address: socketAddress)
                } catch {
                    self = .closedOrInvalidAddress(error)
                    return .failPromise(listeningAddressPromise, error: error)
                }

            case .listening, .closedOrInvalidAddress:
                fatalError("Invalid state: addressBound should only be called once and when in idle state")
            }
        }

        enum OnClose {
            case failPromise(_ promise: EventLoopPromise<SocketAddress>, error: ListeningAddressError)
            case doNothing
        }

        mutating func close() -> OnClose {
            switch self {
            case .idle(let listeningAddressPromise):
                self = .closedOrInvalidAddress(.serverClosed)
                return .failPromise(listeningAddressPromise, error: .serverClosed)

            case .listening:
                self = .closedOrInvalidAddress(.serverClosed)
                return .doNothing

            case .closedOrInvalidAddress:
                return .doNothing
            }
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension NIOHTTPServer.SocketAddress {
    fileprivate init(_ address: NIOCore.SocketAddress?) throws(ListeningAddressError) {
        guard let address, let port = address.port else {
            throw ListeningAddressError.addressOrPortNotAvailable
        }

        switch address {
        case .v4(let ipv4Address):
            self.init(base: .ipv4(.init(host: ipv4Address.host, port: port)))
        case .v6(let ipv6Address):
            self.init(base: .ipv6(.init(host: ipv6Address.host, port: port)))
        case .unixDomainSocket:
            throw ListeningAddressError.unsupportedAddressType
        }
    }
}
