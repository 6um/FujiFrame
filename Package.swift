// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FujiFrame", platforms: [.macOS(.v14)], products: [
    .library(name: "FujiFrameCore", targets: ["FujiFrameCore"]),
    .executable(name: "FujiFrame", targets: ["FujiFrame"])
], targets: [
    .target(name: "FujiFrameCore", linkerSettings: [.linkedLibrary("sqlite3")]),
    .executableTarget(name: "FujiFrame", dependencies: ["FujiFrameCore"]),
    .target(name: "FujiFrameTestSupport", path: "Tests/TestSupport"),
    .testTarget(name: "FujiFrameCoreTests", dependencies: ["FujiFrameCore", "FujiFrameTestSupport"]),
    .testTarget(name: "FujiFrameAppTests", dependencies: ["FujiFrame", "FujiFrameCore", "FujiFrameTestSupport"])
])
