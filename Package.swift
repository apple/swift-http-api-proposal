// swift-tools-version: 6.2

import PackageDescription

let extraSettings: [SwiftSetting] = [
    .strictMemorySafety(),
    .enableExperimentalFeature("SuppressedAssociatedTypes"),
    .enableExperimentalFeature("LifetimeDependence"),
    .enableExperimentalFeature("Lifetimes"),
    .enableUpcomingFeature("LifetimeDependence"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]
let package = Package(
    name: "HTTPAPIProposal",
    products: [
        .library(name: "HTTPAPIs", targets: ["HTTPAPIs"]),
        .library(name: "HTTPClient", targets: ["HTTPClient"]),
        .library(name: "HTTPServer", targets: ["HTTPServer"]),
        .library(name: "AsyncStreaming", targets: ["AsyncStreaming"]),
        .library(name: "NetworkTypes", targets: ["NetworkTypes"]),
    ],
    traits: [
        .trait(name: "SwiftConfiguration"),
        .default(enabledTraits: ["SwiftConfiguration"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/FranzBusch/swift-collections.git",
            branch: "fb-async"
        ),
        .package(
            url: "https://github.com/FranzBusch/swift-async-algorithms.git",
            branch: "fb-nonisolated-nonsending"
        ),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.5.1"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.16.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.92.2"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.36.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.30.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.0.0"),
    ],
    targets: [
        // MARK: Libraries
        .target(
            name: "HTTPAPIs",
            dependencies: [
                "AsyncStreaming",
                "NetworkTypes",
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
            swiftSettings: extraSettings
        ),
        .target(
            name: "HTTPClient",
            dependencies: [
                "HTTPAPIs",
                "AsyncStreaming",
                "NetworkTypes",
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
            ],
            swiftSettings: extraSettings
        ),
        .target(
            name: "HTTPServer",
            dependencies: [
                "HTTPAPIs",
                "AsyncStreaming",
                "NetworkTypes",
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
            swiftSettings: extraSettings
        ),
        .target(
            name: "NetworkTypes",
            swiftSettings: extraSettings
        ),
        .target(
            name: "AsyncStreaming",
            dependencies: [
                .product(
                    name: "BasicContainers",
                    package: "swift-collections"
                )
            ],
            swiftSettings: extraSettings
        ),
        .target(
            name: "Middleware",
            swiftSettings: extraSettings
        ),

        // MARK: Conformance Testing

        .target(
            name: "HTTPClientConformance",
            dependencies: [
                "HTTPClient",
                .product(name: "HTTPTypes", package: "swift-http-types"),

                // These dependencies are needed by the `swift-http-server` that
                // we borrowed.
                "AsyncStreaming",
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "BasicContainers", package: "swift-collections"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOHTTP2", package: "swift-nio-http2"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOHTTPTypesHTTP1", package: "swift-nio-extras"),
                .product(name: "NIOHTTPTypesHTTP2", package: "swift-nio-extras"),
                .product(name: "NIOCertificateReloading", package: "swift-nio-extras"),
                .product(
                    name: "Configuration",
                    package: "swift-configuration",
                    condition: .when(traits: ["SwiftConfiguration"])
                ),
            ],
            swiftSettings: extraSettings
        ),

        // MARK: Tests

        .testTarget(
            name: "NetworkTypesTests",
            dependencies: [
                "NetworkTypes"
            ],
            swiftSettings: extraSettings
        ),
        .testTarget(
            name: "AsyncStreamingTests",
            dependencies: [
                "AsyncStreaming"
            ],
            swiftSettings: extraSettings
        ),
        .testTarget(
            name: "HTTPAPIsTests",
            dependencies: [
                "HTTPAPIs",
                "AsyncStreaming",
                "NetworkTypes",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            swiftSettings: extraSettings
        ),
        .testTarget(
            name: "HTTPClientTests",
            dependencies: [
                "HTTPClient",
                "HTTPClientConformance",
            ],
            swiftSettings: extraSettings
        ),
        .testTarget(
            name: "MiddlewareTests",
            dependencies: [
                "Middleware"
            ],
            swiftSettings: extraSettings
        ),

        // MARK: Examples
        .executableTarget(
            name: "EchoServer",
            dependencies: [
                "HTTPAPIs"
            ],
            path: "Examples/EchoServer",
            swiftSettings: extraSettings
        ),
        .executableTarget(
            name: "ProxyServer",
            dependencies: [
                "HTTPAPIs"
            ],
            path: "Examples/ProxyServer",
            swiftSettings: extraSettings
        ),
    ]
)
