// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "OdooDashboard",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0")
    ],
    targets: [
        .executableTarget(name: "OdooDashboard", dependencies: ["SwiftSoup"], path: "Sources/OdooDashboard")
    ]
)
