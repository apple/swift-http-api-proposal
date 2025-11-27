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
        .library(name: "AsyncStreaming", targets: ["AsyncStreaming"]),
        .library(name: "NetworkTypes", targets: ["NetworkTypes"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/FranzBusch/swift-collections.git",
            branch: "fb-async"
        ),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.5.1"),
    ],
    targets: [
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
            name: "NetworkTypes",
            swiftSettings: extraSettings
        ),
        .target(
            name: "AsyncStreaming",
            dependencies: [
                .product(name: "BasicContainers", package: "swift-collections")
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
            name: "HTTPClientTests",
            dependencies: [
                "HTTPClient"
            ],
            swiftSettings: extraSettings
        ),
    ]
)
