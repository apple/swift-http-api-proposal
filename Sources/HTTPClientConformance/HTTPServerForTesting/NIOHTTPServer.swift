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

import HTTPTypes
public import Logging
import NIOCertificateReloading
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOHTTP2
import NIOHTTPTypes
import NIOHTTPTypesHTTP1
import NIOHTTPTypesHTTP2
import NIOPosix
import NIOSSL
import SwiftASN1
import Synchronization
import X509

/// A generic HTTP server that can handle incoming HTTP requests.
///
/// The `Server` class provides a high-level interface for creating HTTP servers with support for:
/// - TLS/SSL encryption
/// - Custom request handlers
/// - Configurable binding targets
/// - Async/await request processing
/// - Bi-directional streaming support
/// - Request and response trailers
///
/// ## Usage
///
/// ```swift
/// let configuration = NIOHTTPServerConfiguration(
///     bindTarget: .hostAndPort(host: "localhost", port: 8080),
///     tlsConfiguration: .insecure()
/// )
///
/// try await Server.serve(
///     logger: logger,
///     configuration: configuration
/// ) { request, bodyReader, sendResponse in
///     // Read the entire request body
///     let (bodyData, trailers) = try await bodyReader.consumeAndConclude { reader in
///         var data = [UInt8]()
///         var shouldContinue = true
///         while shouldContinue {
///             try await reader.read { span in
///                 guard let span else {
///                     shouldContinue = false
///                     return
///                 }
///                 data.append(contentsOf: span)
///             }
///         }
///         return data
///     }
///
///     // Create and send response
///     var response = HTTPResponse(status: .ok)
///     response.headerFields[.contentType] = "text/plain"
///     let responseWriter = try await sendResponse(response)
///     try await responseWriter.produceAndConclude { writer in
///         try await writer.write("Hello, World!".utf8CString.dropLast().span)
///         return ((), nil)
///     }
/// }
/// ```
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct NIOHTTPServer: HTTPServer {
    public typealias RequestReader = HTTPRequestConcludingAsyncReader
    public typealias ResponseWriter = HTTPResponseConcludingAsyncWriter

    let logger: Logger
    private let configuration: NIOHTTPServerConfiguration

    var listeningAddressState: NIOLockedValueBox<State>

    /// Task-local storage for connection-specific information accessible from request handlers.
    ///
    /// - SeeAlso: ``ConnectionContext``.
    @TaskLocal public static var connectionContext = ConnectionContext()

    /// Create a new ``HTTPServer`` implemented over `SwiftNIO`.
    /// - Parameters:
    ///   - logger: A logger instance for recording server events and debugging information.
    ///   - configuration: The server configuration including bind target and TLS settings.
    public init(
        logger: Logger,
        configuration: NIOHTTPServerConfiguration,
    ) {
        self.logger = logger
        self.configuration = configuration

        // TODO: If we allow users to pass in an event loop, use that instead of the singleton MTELG.
        let eventLoopGroup: MultiThreadedEventLoopGroup = .singletonMultiThreadedEventLoopGroup
        self.listeningAddressState = .init(.idle(eventLoopGroup.any().makePromise()))
    }

    /// Starts an HTTP server with the specified request handler.
    ///
    /// This method creates and runs an HTTP server that processes incoming requests using the provided
    /// ``HTTPServerRequestHandler`` implementation. The server binds to the specified configuration and
    /// handles each connection concurrently using Swift's structured concurrency.
    ///
    /// - Parameters:
    ///   - logger: A logger instance for recording server events and debugging information.
    ///   - configuration: The server configuration including bind target and TLS settings.
    ///   - handler: A ``HTTPServerRequestHandler`` implementation that processes incoming HTTP requests. The handler
    ///     receives each request along with a body reader and response sender function.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct EchoHandler: HTTPServerRequestHandler {
    ///     func handle(
    ///         request: HTTPRequest,
    ///         requestBodyAndTrailers: HTTPRequestConcludingAsyncReader,
    ///         responseSender: @escaping (HTTPResponse) async throws -> HTTPResponseConcludingAsyncWriter
    ///     ) async throws {
    ///         let response = HTTPResponse(status: .ok)
    ///         let writer = try await sendResponse(response)
    ///         // Handle request and write response...
    ///     }
    /// }
    ///
    /// let configuration = HTTPServerConfiguration(
    ///     bindTarget: .hostAndPort(host: "localhost", port: 8080),
    ///     tlsConfiguration: .insecure()
    /// )
    ///
    /// try await Server.serve(
    ///     logger: logger,
    ///     configuration: configuration,
    ///     handler: EchoHandler()
    /// )
    /// ```
    public func serve(handler: some HTTPServerRequestHandler<RequestReader, ResponseWriter>) async throws {
        defer {
            switch self.listeningAddressState.withLockedValue({ $0.close() }) {
            case .failPromise(let promise, let error):
                promise.fail(error)
            case .doNothing:
                ()
            }
        }

        let asyncChannelConfiguration: NIOAsyncChannel<HTTPRequestPart, HTTPResponsePart>.Configuration
        switch self.configuration.backpressureStrategy.backing {
        case .watermark(let low, let high):
            asyncChannelConfiguration = .init(
                backPressureStrategy: .init(lowWatermark: low, highWatermark: high),
                isOutboundHalfClosureEnabled: true
            )
        }

        switch self.configuration.transportSecurity.backing {
        case .plaintext:
            try await self.serveInsecureHTTP1_1(
                bindTarget: self.configuration.bindTarget,
                handler: handler,
                asyncChannelConfiguration: asyncChannelConfiguration
            )

        case .tls(let certificateChain, let privateKey):
            let http2Config = NIOHTTP2Handler.Configuration(
                httpServerHTTP2Configuration: self.configuration.http2
            )

            let certificateChain = try certificateChain.map { try NIOSSLCertificateSource($0) }
            let privateKey = try NIOSSLPrivateKeySource(privateKey)

            var tlsConfiguration: TLSConfiguration = .makeServerConfiguration(
                certificateChain: certificateChain,
                privateKey: privateKey
            )
            tlsConfiguration.applicationProtocols = ["h2", "http/1.1"]

            try await self.serveSecureUpgrade(
                bindTarget: self.configuration.bindTarget,
                tlsConfiguration: tlsConfiguration,
                handler: handler,
                asyncChannelConfiguration: asyncChannelConfiguration,
                http2Configuration: http2Config
            )

        case .reloadingTLS(let certificateReloader):
            let http2Config = NIOHTTP2Handler.Configuration(
                httpServerHTTP2Configuration: configuration.http2
            )

            var tlsConfiguration: TLSConfiguration = try .makeServerConfiguration(
                certificateReloader: certificateReloader
            )
            tlsConfiguration.applicationProtocols = ["h2", "http/1.1"]

            try await self.serveSecureUpgrade(
                bindTarget: self.configuration.bindTarget,
                tlsConfiguration: tlsConfiguration,
                handler: handler,
                asyncChannelConfiguration: asyncChannelConfiguration,
                http2Configuration: http2Config
            )

        case .mTLS(let certificateChain, let privateKey, let trustRoots, let verificationMode, let verificationCallback):
            let http2Config = NIOHTTP2Handler.Configuration(
                httpServerHTTP2Configuration: configuration.http2
            )

            let certificateChain = try certificateChain.map { try NIOSSLCertificateSource($0) }
            let privateKey = try NIOSSLPrivateKeySource(privateKey)
            let nioTrustRoots = try NIOSSLTrustRoots(treatingNilAsSystemTrustRoots: trustRoots)

            var tlsConfiguration: TLSConfiguration = .makeServerConfigurationWithMTLS(
                certificateChain: certificateChain,
                privateKey: privateKey,
                trustRoots: nioTrustRoots
            )
            tlsConfiguration.certificateVerification = .init(verificationMode)
            tlsConfiguration.applicationProtocols = ["h2", "http/1.1"]

            try await self.serveSecureUpgrade(
                bindTarget: self.configuration.bindTarget,
                tlsConfiguration: tlsConfiguration,
                handler: handler,
                asyncChannelConfiguration: asyncChannelConfiguration,
                http2Configuration: http2Config,
                verificationCallback: verificationCallback
            )

        case .reloadingMTLS(let certificateReloader, let trustRoots, let verificationMode, let verificationCallback):
            let http2Config = NIOHTTP2Handler.Configuration(
                httpServerHTTP2Configuration: configuration.http2
            )

            let nioTrustRoots = try NIOSSLTrustRoots(treatingNilAsSystemTrustRoots: trustRoots)

            var tlsConfiguration: TLSConfiguration = try .makeServerConfigurationWithMTLS(
                certificateReloader: certificateReloader,
                trustRoots: nioTrustRoots
            )
            tlsConfiguration.certificateVerification = .init(verificationMode)
            tlsConfiguration.applicationProtocols = ["h2", "http/1.1"]

            try await self.serveSecureUpgrade(
                bindTarget: self.configuration.bindTarget,
                tlsConfiguration: tlsConfiguration,
                handler: handler,
                asyncChannelConfiguration: asyncChannelConfiguration,
                http2Configuration: http2Config,
                verificationCallback: verificationCallback
            )
        }
    }

    func handleRequestChannel(
        channel: NIOAsyncChannel<HTTPRequestPart, HTTPResponsePart>,
        handler: some HTTPServerRequestHandler<RequestReader, ResponseWriter>
    ) async throws {
        do {
            try await channel
                .executeThenClose { inbound, outbound in
                    var iterator = inbound.makeAsyncIterator()

                    let httpRequest: HTTPRequest
                    switch try await iterator.next() {
                    case .head(let request):
                        httpRequest = request
                    case .body:
                        self.logger.debug("Unexpectedly received body on connection. Closing now")
                        outbound.finish()
                        return
                    case .end:
                        self.logger.debug("Unexpectedly received end on connection. Closing now")
                        outbound.finish()
                        return
                    case .none:
                        self.logger.trace("No more requests parts on connection")
                        return
                    }

                    let readerState = HTTPRequestConcludingAsyncReader.ReaderState()
                    let writerState = HTTPResponseConcludingAsyncWriter.WriterState()

                    do {
                        try await handler.handle(
                            request: httpRequest,
                            requestContext: HTTPRequestContext(),
                            requestBodyAndTrailers: HTTPRequestConcludingAsyncReader(
                                iterator: iterator,
                                readerState: readerState
                            ),
                            responseSender: HTTPResponseSender { response in
                                try await outbound.write(.head(response))
                                return HTTPResponseConcludingAsyncWriter(
                                    writer: outbound,
                                    writerState: writerState
                                )
                            } sendInformational: { response in
                                try await outbound.write(.head(response))
                            }
                        )
                    } catch {
                        logger.error("Error thrown while handling connection: \(error)")
                        if !readerState.wrapped.withLock({ $0.finishedReading }) {
                            logger.error("Did not finish reading but error thrown.")
                            // TODO: if h2 reset stream; if h1 try draining request?
                        }
                        if !writerState.wrapped.withLock({ $0.finishedWriting }) {
                            logger.error("Did not write response but error thrown.")
                            // TODO: we need to do something, possibly just close the connection or
                            // reset the stream with the appropriate error.
                        }
                        throw error
                    }

                    // TODO: handle other state scenarios.
                    // For example, if we're using h2 and we didn't finish reading but we wrote back
                    // a response, we should send a RST_STREAM with NO_ERROR set.
                    // If we finished reading but we didn't write back a response, then RST_STREAM
                    // is also likely appropriate but unclear about the error.
                    // For h1, we should close the connection.

                    // Finish the outbound and wait on the close future to make sure all pending
                    // writes are actually written.
                    outbound.finish()
                    try await channel.channel.closeFuture.get()
                }
        } catch {
            self.logger.debug("Error thrown while handling connection: \(error)")
            // TODO: We need to send a response head here potentially
            throw error
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension NIOHTTP2Handler.Configuration {
    init(httpServerHTTP2Configuration http2Config: NIOHTTPServerConfiguration.HTTP2) {
        let clampedTargetWindowSize = Self.clampTargetWindowSize(http2Config.targetWindowSize)
        let clampedMaxFrameSize = Self.clampMaxFrameSize(http2Config.maxFrameSize)

        var http2HandlerConnectionConfiguration = NIOHTTP2Handler.ConnectionConfiguration()
        var http2HandlerHTTP2Settings = HTTP2Settings([
            HTTP2Setting(parameter: .initialWindowSize, value: clampedTargetWindowSize),
            HTTP2Setting(parameter: .maxFrameSize, value: clampedMaxFrameSize),
        ])
        if let maxConcurrentStreams = http2Config.maxConcurrentStreams {
            http2HandlerHTTP2Settings.append(
                HTTP2Setting(parameter: .maxConcurrentStreams, value: maxConcurrentStreams)
            )
        }
        http2HandlerConnectionConfiguration.initialSettings = http2HandlerHTTP2Settings

        var http2HandlerStreamConfiguration = NIOHTTP2Handler.StreamConfiguration()
        http2HandlerStreamConfiguration.targetWindowSize = clampedTargetWindowSize

        self = NIOHTTP2Handler.Configuration(
            connection: http2HandlerConnectionConfiguration,
            stream: http2HandlerStreamConfiguration
        )
    }

    /// Window size which mustn't exceed `2^31 - 1` (RFC 9113 § 6.5.2).
    private static func clampTargetWindowSize(_ targetWindowSize: Int) -> Int {
        min(targetWindowSize, Int(Int32.max))
    }

    /// Max frame size must be in the range `2^14 ..< 2^24` (RFC 9113 § 4.2).
    private static func clampMaxFrameSize(_ maxFrameSize: Int) -> Int {
        let clampedMaxFrameSize: Int
        if maxFrameSize >= (1 << 24) {
            clampedMaxFrameSize = (1 << 24) - 1
        } else if maxFrameSize < (1 << 14) {
            clampedMaxFrameSize = (1 << 14)
        } else {
            clampedMaxFrameSize = maxFrameSize
        }
        return clampedMaxFrameSize
    }
}
