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
    dependencies: [
        .package(
            url: "https://github.com/FranzBusch/swift-collections.git",
            branch: "fb-async"
        )
    ],
    targets: [
        .target(
            name: "AsyncStreaming",
            dependencies: [
                .product(name: "BasicContainers", package: "swift-collections")
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
    ]
)
