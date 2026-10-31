// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PaperclipKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PaperclipKit", targets: ["PaperclipKit"]),
    ],
    targets: [
        .target(name: "PaperclipKit", resources: [.process("Resources")]),
        .testTarget(
            name: "PaperclipKitTests",
            dependencies: ["PaperclipKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
