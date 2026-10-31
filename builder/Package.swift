// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NFSU2Builder",
    platforms: [.macOS(.v11)],
    targets: [
        .target(name: "BuilderCore"),
        .executableTarget(name: "NFSU2Builder", dependencies: ["BuilderCore"]),
        .testTarget(name: "BuilderCoreTests", dependencies: ["BuilderCore"]),
    ]
)
