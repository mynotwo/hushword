// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FlowType",
    platforms: [
        .macOS("13.3"),
    ],
    products: [
        .library(name: "FlowTypeCore", targets: ["FlowTypeCore"]),
        .executable(name: "FlowType", targets: ["FlowType"]),
        .executable(name: "FlowTypeCoreTests", targets: ["FlowTypeCoreTests"]),
        .executable(name: "FlowTypeAppKitTests", targets: ["FlowTypeAppKitTests"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.5"
        ),
    ],
    targets: [
        .target(name: "FlowTypeCore"),
        .target(
            name: "FlowTypeAppKit",
            dependencies: [
                "FlowTypeCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/FlowType",
            exclude: ["main.swift"]
        ),
        .executableTarget(
            name: "FlowType",
            dependencies: ["FlowTypeAppKit"],
            path: "Sources/FlowTypeExecutable",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .executableTarget(
            name: "FlowTypeCoreTests",
            dependencies: ["FlowTypeCore"]
        ),
        .executableTarget(
            name: "FlowTypeAppKitTests",
            dependencies: ["FlowTypeAppKit", "FlowTypeCore"],
            path: "Tests/FlowTypeAppKitTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
