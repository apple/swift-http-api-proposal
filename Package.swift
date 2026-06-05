// swift-tools-version: 6.4

import PackageDescription

let extraSettings: [SwiftSetting] = [
    .strictMemorySafety(),
    .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
    .enableExperimentalFeature("LifetimeDependence"),
    .enableExperimentalFeature("Lifetimes"),
    .enableExperimentalFeature("Extern"),
    .enableUpcomingFeature("LifetimeDependence"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "HTTPAPIProposal",
    platforms: [  // TODO: Needed until https://github.com/swiftlang/swift/issues/89028 is fixed
        .macOS(.v27),
        .iOS(.v27),
        .watchOS(.v27),
        .tvOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "HTTPAPIs", targets: ["HTTPAPIs"]),
        .library(name: "HTTPClient", targets: ["HTTPClient"]),
        .library(name: "URLSessionHTTPClient", targets: ["URLSessionHTTPClient"]),
        .library(name: "AHCHTTPClient", targets: ["AHCHTTPClient"]),
        .library(name: "NetworkTypes", targets: ["NetworkTypes"]),
        .library(name: "Middleware", targets: ["Middleware"]),
        .library(name: "HTTPClientConformance", targets: ["HTTPClientConformance"]),
    ],
    traits: [
        .trait(name: "Configuration"),
        .default(enabledTraits: ["Configuration"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.5.0"),
        .package(
            url: "https://github.com/FranzBusch/swift-async-algorithms.git",
            revision: "e1a6dff375ca9fc079d02276f489663ad9204e01",
            traits: ["UnstableAsyncStreaming"]
        ),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.5.1"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.16.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.92.2"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.36.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.30.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.0.0"),
        .package(url: "https://github.com/guoye-zhang/async-http-client.git", revision: "ce50e695f16c10a97bec2731c652eaedcf823fcf"),
    ],
    targets: [
        // MARK: Libraries
        .target(
            name: "HTTPAPIs",
            dependencies: [
                .product(name: "AsyncStreaming", package: "swift-async-algorithms"),
                "NetworkTypes",
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
            swiftSettings: extraSettings
        ),
        .target(
            name: "HTTPClient",
            dependencies: [
                "AHCHTTPClient",
                "URLSessionHTTPClient",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ],
            swiftSettings: extraSettings
        ),
        .target(
            name: "NetworkTypes",
            swiftSettings: extraSettings
        ),
        .target(
            name: "Middleware",
            swiftSettings: extraSettings
        ),
        .target(
            name: "AHCHTTPClient",
            dependencies: [
                "HTTPAPIs",
                .product(name: "AsyncStreaming", package: "swift-async-algorithms"),
                "NetworkTypes",
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            swiftSettings: extraSettings
        ),
        .target(
            name: "URLSessionHTTPClient",
            dependencies: [
                "HTTPAPIs",
                .product(name: "AsyncStreaming", package: "swift-async-algorithms"),
                "NetworkTypes",
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
            ],
            swiftSettings: extraSettings
        ),

        // MARK: Conformance Testing

        .target(
            name: "HTTPClientConformance",
            dependencies: [
                "HTTPClient",
                // These dependencies are needed by the `swift-http-server` that
                // we borrowed.
                .product(name: "AsyncStreaming", package: "swift-async-algorithms"),
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
                    condition: .when(traits: ["Configuration"])
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
            name: "HTTPAPIsTests",
            dependencies: [
                "HTTPAPIs",
                .product(name: "AsyncStreaming", package: "swift-async-algorithms"),
                "NetworkTypes",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            swiftSettings: extraSettings
        ),
        .testTarget(
            name: "AsyncHTTPClientConformanceTests",
            dependencies: [
                "AHCHTTPClient",
                "HTTPClientConformance",
            ]
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
                "HTTPAPIs",
                "HTTPClient",
            ],
            path: "Examples/EchoServer",
            swiftSettings: extraSettings
        ),
        .executableTarget(
            name: "ProxyServer",
            dependencies: [
                "HTTPAPIs",
                "HTTPClient",
            ],
            path: "Examples/ProxyServer",
            swiftSettings: extraSettings
        ),
        .executableTarget(
            name: "MiddlewareClient",
            dependencies: [
                "HTTPAPIs",
                "HTTPClient",
                "Middleware",
                "ExampleMiddleware",
            ],
            path: "Examples/MiddlewareClient",
            swiftSettings: extraSettings
        ),
        .executableTarget(
            name: "MiddlewareServer",
            dependencies: [
                "HTTPAPIs",
                "Middleware",
                "ExampleMiddleware",
            ],
            path: "Examples/MiddlewareServer",
            swiftSettings: extraSettings
        ),
        .target(
            name: "ExampleMiddleware",
            dependencies: [
                "HTTPAPIs",
                "Middleware",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Examples/ExampleMiddleware",
            swiftSettings: extraSettings
        ),
    ]
)

// ------- WASM specific targets --------

// This environment variable is needed to allow WASM to compile only
// when the WASM SDK is available and being used. Attempting to compile
// WASM targets using non-WASM SDKs causes build failures.
let enableWASM = Context.environment["HTTP_API_ENABLE_WASM"] != nil

if enableWASM {
    // BridgeJS generated code doesn't work well with `NonisolatedNonsendingByDefault`
    let wasmExtraSettings: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("Extern"),
        .enableUpcomingFeature("LifetimeDependence"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]

    package.dependencies.append(
        .package(url: "https://github.com/swiftwasm/JavaScriptKit", from: "0.53.0")
    )
    package.products.append(
        .library(name: "FetchHTTPClient", targets: ["FetchHTTPClient"])
    )
    package.targets.append(
        .target(
            name: "FetchHTTPClient",
            dependencies: [
                "HTTPAPIs",
                .product(name: "AsyncStreaming", package: "swift-async-algorithms"),
                .product(name: "BasicContainers", package: "swift-collections"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ],
            swiftSettings: wasmExtraSettings,
            plugins: [
                .plugin(name: "BridgeJS", package: "JavaScriptKit")
            ],
        )
    )
    package.targets.append(
        .executableTarget(
            name: "WASMClient",
            dependencies: [
                "FetchHTTPClient",
                .product(name: "BasicContainers", package: "swift-collections"),
                .product(name: "ContainersPreview", package: "swift-collections"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ],
            path: "Examples/WASMClient",
            swiftSettings: wasmExtraSettings,
            plugins: [
                .plugin(name: "BridgeJS", package: "JavaScriptKit")
            ],
        )
    )
}
