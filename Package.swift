// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Amid",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Amid", targets: ["AmidApp"]),
        .executable(name: "amid-probe", targets: ["AmidProbe"]),
        .library(name: "AmidCore", targets: ["AmidCore"])
    ],
    targets: [
        .target(name: "CAmid", publicHeadersPath: "include"),
        .target(name: "AmidCore", dependencies: ["CAmid"]),
        .executableTarget(name: "AmidApp", dependencies: ["AmidCore"]),
        .executableTarget(name: "AmidProbe", dependencies: ["AmidCore"]),
        .testTarget(name: "AmidCoreTests", dependencies: ["AmidCore"]),
        .testTarget(name: "AmidAppTests", dependencies: ["AmidApp", "AmidCore"])
    ]
)
