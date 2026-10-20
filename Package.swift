// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Hushword",
    platforms: [
        .macOS("13.3"),
    ],
    products: [
        .library(name: "HushwordCore", targets: ["HushwordCore"]),
        .executable(name: "Hushword", targets: ["Hushword"]),
        .executable(name: "HushwordCoreTests", targets: ["HushwordCoreTests"]),
        .executable(name: "HushwordAppKitTests", targets: ["HushwordAppKitTests"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.5"
        ),
    ],
    targets: [
        .target(name: "HushwordCore"),
        .target(
            name: "HushwordAppKit",
            dependencies: [
                "HushwordCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Hushword",
            exclude: ["main.swift"]
        ),
        .executableTarget(
            name: "Hushword",
            dependencies: ["HushwordAppKit"],
            path: "Sources/HushwordExecutable",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .executableTarget(
            name: "HushwordCoreTests",
            dependencies: ["HushwordCore"]
        ),
        .executableTarget(
            name: "HushwordAppKitTests",
            dependencies: ["HushwordAppKit", "HushwordCore"],
            path: "Tests/HushwordAppKitTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
