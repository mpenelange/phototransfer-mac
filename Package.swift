// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PhotoTransfer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PhotoTransfer", targets: ["PhotoTransfer"])
    ],
    targets: [
        .executableTarget(
            name: "PhotoTransfer",
            path: "Sources/PhotoTransfer",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "PhotoTransferTests",
            dependencies: ["PhotoTransfer"],
            path: "Tests/PhotoTransferTests"
        )
    ]
)
