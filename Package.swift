// swift-tools-version:6.0
// This file helps SourceKit-LSP understand the project for IDE features.
// Build with Xcode project, not this package.

import PackageDescription

let package = Package(
    name: "Todo",
    platforms: [.macOS(.v15), .iOS(.v18)],
    targets: [
        .executableTarget(
            name: "Todo",
            path: "Todo",
            exclude: ["Assets.xcassets", "Todo.entitlements"]
        ),
    ]
)
