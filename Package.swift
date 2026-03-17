// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "pinentry-rbw-macos",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .executableTarget(
            name: "pinentry-rbw-macos"
        ),
        .testTarget(
            name: "pinentry-rbw-macosTests",
            dependencies: ["pinentry-rbw-macos"],
            swiftSettings: [
                // Testing.framework 在 CLI Tools 的非标准路径下，需要显式指定
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
    ]
)
