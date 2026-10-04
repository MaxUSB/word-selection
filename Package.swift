// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WordSelection",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WordSelection", targets: ["WordSelection"])],
    targets: [.executableTarget(name: "WordSelection", path: "Sources")]
)
