// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Keysmith",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Keysmith", targets: ["Keysmith"]),
    ],
    targets: [
        .executableTarget(
            name: "Keysmith",
            path: "Sources/Keysmith"
        ),
    ]
)
