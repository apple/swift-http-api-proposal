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

public import NIOCertificateReloading
import NIOCore
import NIOSSL
public import X509

/// Configuration settings for ``NIOHTTPServer``.
///
/// This structure contains all the necessary configuration options for setting up
/// and running ``NIOHTTPServer``, including network binding and TLS settings.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct NIOHTTPServerConfiguration: Sendable {
    /// Specifies where the server should bind and listen for incoming connections.
    ///
    /// Currently supports binding to a specific host and port combination.
    /// Additional binding targets may be added in the future.
    public struct BindTarget: Sendable {
        enum Backing {
            case hostAndPort(host: String, port: Int)
        }

        let backing: Backing

        /// Creates a bind target for a specific host and port.
        ///
        /// - Parameters:
        ///   - host: The hostname or IP address to bind to (e.g., "localhost", "0.0.0.0")
        ///   - port: The port number to listen on (e.g., 8080, 443)
        /// - Returns: A configured `BindTarget` instance
        ///
        /// ## Example
        /// ```swift
        /// let target = BindTarget.hostAndPort(host: "localhost", port: 8080)
        /// ```
        public static func hostAndPort(host: String, port: Int) -> Self {
            Self(backing: .hostAndPort(host: host, port: port))
        }
    }

    /// Configuration for transport security settings.
    ///
    /// Provides options for running the server with or without TLS encryption.
    /// When using TLS, you must either provide a certificate chain and private key, or a `CertificateReloader`.
    public struct TransportSecurity: Sendable {
        enum Backing {
            case plaintext
            case tls(
                certificateChain: [Certificate],
                privateKey: Certificate.PrivateKey
            )
            case reloadingTLS(certificateReloader: any CertificateReloader)
            case mTLS(
                certificateChain: [Certificate],
                privateKey: Certificate.PrivateKey,
                trustRoots: [Certificate]?,
                certificateVerification: CertificateVerificationMode = .noHostnameVerification,
                customCertificateVerificationCallback: (
                    @Sendable ([X509.Certificate]) async throws -> CertificateVerificationResult
                )? = nil
            )
            case reloadingMTLS(
                certificateReloader: any CertificateReloader,
                trustRoots: [Certificate]?,
                certificateVerification: CertificateVerificationMode = .noHostnameVerification,
                customCertificateVerificationCallback: (
                    @Sendable ([X509.Certificate]) async throws -> CertificateVerificationResult
                )? = nil
            )
        }

        let backing: Backing

        /// Configures the server for plaintext HTTP without TLS encryption.
        public static let plaintext: Self = Self(backing: .plaintext)

        /// Configures the server for TLS with the provided certificate chain and private key.
        /// - Parameters:
        ///   - certificateChain: The certificate chain to present during negotiation.
        ///   - privateKey: The private key corresponding to the leaf certificate in `certificateChain`.
        public static func tls(
            certificateChain: [Certificate],
            privateKey: Certificate.PrivateKey
        ) -> Self {
            Self(
                backing: .tls(
                    certificateChain: certificateChain,
                    privateKey: privateKey
                )
            )
        }

        /// Configures the server for TLS with automatic certificate reloading.
        /// - Parameters:
        ///   - certificateReloader: The certificate reloader instance.
        public static func tls(certificateReloader: any CertificateReloader) throws -> Self {
            Self(backing: .reloadingTLS(certificateReloader: certificateReloader))
        }

        /// Configures the server for mTLS with support for customizing client certificate verification logic.
        ///
        /// - Parameters:
        ///   - certificateChain: The certificate chain to present during negotiation.
        ///   - privateKey: The private key corresponding to the leaf certificate in `certificateChain`.
        ///   - trustRoots: The root certificates to trust when verifying client certificates.
        ///   - certificateVerification: Configures the client certificate validation behaviour. Defaults to
        ///      ``CertificateVerificationMode/noHostnameVerification``.
        ///   - customCertificateVerificationCallback: If specified, this callback *overrides* the default NIOSSL client
        ///     certificate verification logic. The callback receives the certificates presented by the peer. Within the
        ///     callback, you must validate these certificates against your trust roots and derive a validated chain of
        ///     trust per [RFC 4158](https://datatracker.ietf.org/doc/html/rfc4158). Return
        ///     ``CertificateVerificationResult/certificateVerified(_:)`` from the callback if verification succeeds,
        ///     optionally including the validated certificate chain you derived. Returning the validated certificate
        ///     chain allows ``NIOHTTPServer`` to provide access to it in the request handler through
        ///     ``NIOHTTPServer/ConnectionContext/peerCertificateChain``, accessed via the task-local
        ///     ``NIOHTTPServer/connectionContext`` property. Otherwise, return
        ///     ``CertificateVerificationResult/failed(_:)`` if verification fails.
        ///
        /// - Warning: If `customCertificateVerificationCallback` is set, it will **override** NIOSSL's default
        ///   certificate verification logic.
        public static func mTLS(
            certificateChain: [Certificate],
            privateKey: Certificate.PrivateKey,
            trustRoots: [Certificate]?,
            certificateVerification: CertificateVerificationMode = .noHostnameVerification,
            customCertificateVerificationCallback: (
                @Sendable ([X509.Certificate]) async throws -> CertificateVerificationResult
            )? = nil
        ) -> Self {
            Self(
                backing: .mTLS(
                    certificateChain: certificateChain,
                    privateKey: privateKey,
                    trustRoots: trustRoots,
                    certificateVerification: certificateVerification,
                    customCertificateVerificationCallback: customCertificateVerificationCallback
                )
            )
        }

        /// Configures the server for mTLS with automatic certificate reloading and support for customizing client
        /// certificate verification logic.
        ///
        /// - Parameters:
        ///   - certificateReloader: The certificate reloader instance.
        ///   - trustRoots: The root certificates to trust when verifying client certificates.
        ///   - certificateVerification: Configures the client certificate validation behaviour. Defaults to
        ///     ``CertificateVerification/noHostnameVerification``.
        ///   - customCertificateVerificationCallback: If specified, this callback *overrides* the default NIOSSL client
        ///     certificate verification logic. The callback receives the certificates presented by the peer. Within the
        ///     callback, you must validate these certificates against your trust roots and derive a validated chain of
        ///     trust per [RFC 4158](https://datatracker.ietf.org/doc/html/rfc4158). Return
        ///     ``CertificateVerificationResult/certificateVerified(_:)`` from the callback if verification succeeds,
        ///     optionally including the validated certificate chain you derived. Returning the validated certificate
        ///     chain allows ``NIOHTTPServer`` to provide access to it in the request handler through
        ///     ``NIOHTTPServer/ConnectionContext/peerCertificateChain``, accessed via the task-local
        ///     ``NIOHTTPServer/connectionContext`` property. Otherwise, return
        ///     ``CertificateVerificationResult/failed(_:)`` if verification fails.
        ///
        /// - Warning: If `customCertificateVerificationCallback` is set, it will **override** NIOSSL's default
        ///   certificate verification logic.
        public static func mTLS(
            certificateReloader: any CertificateReloader,
            trustRoots: [Certificate]?,
            certificateVerification: CertificateVerificationMode = .noHostnameVerification,
            customCertificateVerificationCallback: (
                @Sendable ([X509.Certificate]) async throws -> CertificateVerificationResult
            )? = nil
        ) throws -> Self {
            Self(
                backing: .reloadingMTLS(
                    certificateReloader: certificateReloader,
                    trustRoots: trustRoots,
                    certificateVerification: certificateVerification,
                    customCertificateVerificationCallback: customCertificateVerificationCallback
                )
            )
        }
    }

    /// HTTP/2 specific configuration.
    public struct HTTP2: Sendable, Hashable {
        /// The maximum frame size to be used in an HTTP/2 connection.
        public var maxFrameSize: Int

        /// The target window size for this connection.
        ///
        /// - Note: This will also be set as the initial window size for the connection.
        public var targetWindowSize: Int

        /// The number of concurrent streams on the HTTP/2 connection.
        public var maxConcurrentStreams: Int?

        public init(
            maxFrameSize: Int,
            targetWindowSize: Int,
            maxConcurrentStreams: Int?
        ) {
            self.maxFrameSize = maxFrameSize
            self.targetWindowSize = targetWindowSize
            self.maxConcurrentStreams = maxConcurrentStreams
        }

        @inlinable
        static var defaultMaxFrameSize: Int { 1 << 14 }

        @inlinable
        static var defaultTargetWindowSize: Int { (1 << 16) - 1 }

        @inlinable
        static var defaultMaxConcurrentStreams: Int? { nil }

        /// Default values.
        ///
        /// The max frame size defaults to 2^14, the target window size defaults to 2^16-1, and
        /// the max concurrent streams default to infinite.
        public static var defaults: Self {
            Self(
                maxFrameSize: Self.defaultMaxFrameSize,
                targetWindowSize: Self.defaultTargetWindowSize,
                maxConcurrentStreams: Self.defaultMaxConcurrentStreams
            )
        }
    }

    /// Configuration for the backpressure strategy to use when reading requests and writing back responses.
    public struct BackPressureStrategy: Sendable {
        enum Backing {
            case watermark(low: Int, high: Int)
        }

        internal let backing: Backing

        init(backing: Backing) {
            self.backing = backing
        }

        /// A low/high watermark will be applied when reading requests and writing responses.
        /// - Parameters:
        ///   - low: The threshold below which the consumer will ask the producer to produce more elements.
        ///   - high: The threshold above which the producer will stop producing elements.
        /// - Returns: A low/high watermark strategy with the configured thresholds.
        public static func watermark(low: Int, high: Int) -> Self {
            .init(backing: .watermark(low: low, high: high))
        }

        @inlinable
        static var defaultWatermarkLow: Int { 2 }

        @inlinable
        static var defaultWatermarkHigh: Int { 10 }

        /// Default values.
        ///
        /// The watermark low value defaults to 2, and the watermark high value default to 10.
        public static var defaults: Self {
            Self.init(
                backing: .watermark(
                    low: Self.defaultWatermarkLow,
                    high: Self.defaultWatermarkHigh
                )
            )
        }
    }

    /// Network binding configuration.
    public var bindTarget: BindTarget

    /// TLS configuration for the server.
    public var transportSecurity: TransportSecurity

    /// Backpressure strategy to use in the server.
    public var backpressureStrategy: BackPressureStrategy

    /// Backpressure strategy to use in the server.
    public var http2: HTTP2

    /// Create a new configuration.
    /// - Parameters:
    ///   - bindTarget: A ``BindTarget``.
    ///   - transportSecurity: A ``TransportSecurity``. Defaults to ``TransportSecurity/plaintext``.
    ///   - backpressureStrategy: A ``BackPressureStrategy``.
    ///   Defaults to ``BackPressureStrategy/watermark(low:high:)`` with a low watermark of 2 and a high of 10.
    ///   - http2: A ``HTTP2``. Defaults to ``HTTP2/defaults``.
    public init(
        bindTarget: BindTarget,
        transportSecurity: TransportSecurity = .plaintext,
        backpressureStrategy: BackPressureStrategy = .defaults,
        http2: HTTP2 = .defaults
    ) {
        self.bindTarget = bindTarget
        self.transportSecurity = transportSecurity
        self.backpressureStrategy = backpressureStrategy
        self.http2 = http2
    }
}

/// Represents the outcome of certificate verification.
///
/// Indicates whether certificate verification succeeded or failed, and provides associated metadata when verification
/// is successful.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public enum CertificateVerificationResult: Sendable, Hashable {
    /// Metadata resulting from successful certificate verification.
    public struct VerificationMetadata: Sendable, Hashable {
        /// A container for the validated certificate chain: an array of certificates forming a verified and ordered
        /// chain of trust, starting from the peer's leaf certificate to a trusted root certificate.
        public var validatedCertificateChain: X509.ValidatedCertificateChain?

        /// Creates an instance with the peer's *validated* certificate chain.
        ///
        /// - Parameter validatedCertificateChain: An optional *validated* certificate chain. If provided, it must
        ///   **only** contain the **validated** chain of trust that was built and verified from the certificates
        ///   presented by the peer.
        public init(_ validatedCertificateChain: X509.ValidatedCertificateChain?) {
            self.validatedCertificateChain = validatedCertificateChain
        }
    }

    /// An error representing certificate verification failure.
    public struct VerificationError: Swift.Error, Hashable {
        public let reason: String

        /// Creates a verification error with the reason why verification failed.
        /// - Parameter reason: The reason of why certificate verification failed.
        public init(reason: String) {
            self.reason = reason
        }
    }

    /// Certificate verification succeeded.
    ///
    /// The associated metadata contains information captured during verification.
    case certificateVerified(VerificationMetadata)

    /// Certificate verification failed.
    case failed(VerificationError)
}

/// Represents the certificate verification behaviour.
public struct CertificateVerificationMode: Sendable {
    enum VerificationMode {
        case optionalVerification
        case noHostnameVerification
    }

    let mode: VerificationMode

    /// Allows peers to connect without presenting any certificates.
    ///
    /// However, if the peer *does* present
    /// certificates, they are validated like normal (exactly like with ``noHostnameVerification``), and the TLS
    /// handshake will fail if verification fails.
    ///
    /// - Warning: With this mode, a peer can successfully connect even without presenting any certificates. As such,
    ///   this mode must be used with great caution.
    public static var optionalVerification: Self {
        Self(mode: .optionalVerification)
    }

    /// Validates the certificates presented by the peer but skips hostname verification as it cannot succeed in
    /// a server context.
    public static var noHostnameVerification: Self {
        Self(mode: .noHostnameVerification)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension NIOSSL.CertificateVerification {
    /// Maps ``CertificateVerificationMode`` to the NIOSSL representation.
    init(_ verificationMode: CertificateVerificationMode) {
        switch verificationMode.mode {
        case .noHostnameVerification:
            self = .noHostnameVerification
        case .optionalVerification:
            self = .optionalVerification
        }
    }
}
