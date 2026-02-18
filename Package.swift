// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "S2T",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder.git", from: "0.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "S2T",
            dependencies: ["TOMLDecoder"],
            path: "Sources/S2T"
        ),
        .testTarget(
            name: "S2TTests",
            dependencies: ["S2T"],
            path: "Tests/S2TTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
