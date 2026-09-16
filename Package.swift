// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Suiji",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Suiji", targets: ["Suiji"])
    ],
    targets: [
        .executableTarget(
            name: "Suiji",
            path: "Sources/Suiji"
        ),
        .testTarget(
            name: "SuijiTests",
            dependencies: ["Suiji"],
            path: "Tests/SuijiTests"
        )
    ]
)
