// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "macstatus",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "macstatus",
            path: "Sources/macstatus"
        )
    ]
)
