// swift-tools-version: 6.2
// The desktop's dock (README.md): a SwiftUI helper the app starts and feeds (apps/desktop/src/dock.mts).
import PackageDescription

let package = Package(
  name: "StillfailDock",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(name: "StillfailDock", swiftSettings: [.swiftLanguageMode(.v5)]),
  ]
)
