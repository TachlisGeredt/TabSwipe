// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "TabSwipe",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "tabswipe", targets: ["tabswipe"]),
        .library(name: "TabSwipeCore", targets: ["TabSwipeCore"]),
    ],
    targets: [
        .target(
            name: "TabSwipeCore",
            path: "Sources/TabSwipeCore"
        ),
        .executableTarget(
            name: "tabswipe",
            dependencies: ["TabSwipeCore"],
            path: "Sources/tabswipe"
        ),
        .testTarget(
            name: "TabSwipeTests",
            dependencies: ["TabSwipeCore"],
            path: "Tests/TabSwipeTests"
        ),
    ]
)
