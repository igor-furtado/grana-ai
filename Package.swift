// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GranaAI",
    products: [
        .library(
            name: "GranaAICore",
            targets: ["GranaAICore"]
        ),
        .executable(
            name: "grana-ai",
            targets: ["GranaAICommand"]
        ),
    ],
    targets: [
        .target(
            name: "GranaAICore"
        ),
        .executableTarget(
            name: "GranaAICommand",
            dependencies: ["GranaAICore"]
        ),
        .testTarget(
            name: "GranaAICoreTests",
            dependencies: ["GranaAICore"]
        ),
        .testTarget(
            name: "GranaAICommandTests",
            dependencies: ["GranaAICore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
