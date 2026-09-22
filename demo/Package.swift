// swift-tools-version: 6.0
import PackageDescription

// A separate package so the library's consumers never resolve a demo product.
let package = Package(
  name: "SwiftTreeDemo",
  platforms: [.macOS(.v14)],
  dependencies: [.package(path: "..")],
  targets: [
    .executableTarget(
      name: "SwiftTreeDemo",
      dependencies: [.product(name: "SwiftTree", package: "swift-tree")])
  ]
)
