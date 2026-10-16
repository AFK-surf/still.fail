// swift-tools-version: 6.2
// The station's desktop as a screen source (docs/remote-screens.md, station/src/screens/desktop.ts): a helper the
// station starts per view, capturing the main display with ScreenCaptureKit, encoding H.264 with VideoToolbox and
// posting a person's input with CGEvent.
import PackageDescription

let package = Package(
  name: "StillfailScreen",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "stillfail-screen", targets: ["StillfailScreen"])],
  targets: [
    .executableTarget(name: "StillfailScreen", swiftSettings: [.swiftLanguageMode(.v5)]),
  ]
)
