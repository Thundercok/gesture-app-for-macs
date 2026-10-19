// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GestureFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GestureFlow", targets: ["GestureFlow"])
    ],
    targets: [
        .executableTarget(
            name: "GestureFlow",
            path: "Sources/GestureFlow"
        ),
        .testTarget(
            name: "GestureFlowTests",
            dependencies: ["GestureFlow"],
            path: "Tests/GestureFlowTests"
        )
    ]
)
