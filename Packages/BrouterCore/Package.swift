// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrouterCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BrouterCore", targets: ["BrouterCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "BrouterCore",
            dependencies: [.product(name: "TOMLDecoder", package: "TOMLDecoder")]
        ),
    ]
)
