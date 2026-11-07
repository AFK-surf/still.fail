// swift-tools-version: 6.0
// serve-sim's simulator capture and input (EvanBacon/serve-sim, packages/serve-sim; vendor/README.md): the iOS
// Simulator's framebuffer and its HID, through the private CoreSimulator and SimulatorKit frameworks. still.fail
// Helper's `simulator.view` uses it (docs/remote-screens.md, "Simulators").
import PackageDescription

let package = Package(
  name: "SimNative",
  platforms: [.macOS(.v14)],
  products: [.library(name: "SimNative", targets: ["SimNative"])],
  targets: [
    .target(name: "SimNativeSupport"),
    .target(name: "SimNative", dependencies: ["SimNativeSupport"]),
  ],
  swiftLanguageModes: [.v5]
)
