// swift-tools-version: 6.0
import PackageDescription

// No dependencies outside Apple frameworks, on purpose: embedding the tree must
// not pull anything else into a host app's package graph.
let package = Package(
  name: "SwiftTree",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "SwiftTree", targets: ["SwiftTree"])
  ],
  targets: [
    .target(name: "SwiftTree")
  ]
)
