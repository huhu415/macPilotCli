// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "macPilotCli",
    platforms: [
        .macOS(.v14), // 添加平台要求为 macOS 14.0
    ],
    dependencies: [
        .package(url: "https://github.com/gsabran/mcp-swift-sdk", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "macPilotCli",
            dependencies: [
                .product(name: "MCPServer", package: "mcp-swift-sdk"),
            ]
        ),
    ]
)
