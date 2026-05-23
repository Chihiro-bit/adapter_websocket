// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "adapter_websocket",
  platforms: [
    .macOS("10.14"),
  ],
  products: [
    .library(name: "adapter_websocket", targets: ["adapter_websocket"])
  ],
  targets: [
    .target(
      name: "adapter_websocket",
      path: "../Classes"
    )
  ]
)
