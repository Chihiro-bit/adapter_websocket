// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "adapter_websocket",
  platforms: [
    .iOS("12.0"),
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
