// swift-tools-version: 5.9

// Runs the math engine's unit tests on macOS (GitHub Actions).
// CI copies MathNotes.swiftpm/App/Engine/*.swift into Sources/MathEngine before `swift test`.

import PackageDescription

let package = Package(
    name: "MathEngine",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(name: "MathEngine"),
        .testTarget(name: "MathEngineTests", dependencies: ["MathEngine"]),
    ]
)
