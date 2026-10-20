// swift-tools-version: 6.2
// EYHN/PermissionFlow at 9b02967a8b47133204c2456c56a1bfb393d4bd95 (MIT, LICENSE), its SystemSettingsKit and
// PermissionFlow only, changed for still.fail (vendor/README.md; `ember:` in the source).
import PackageDescription

let package = Package(
  name: "PermissionFlow",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "SystemSettingsKit", targets: ["SystemSettingsKit"]),
    .library(name: "PermissionFlow", targets: ["PermissionFlow"]),
  ],
  targets: [
    .target(name: "SystemSettingsKit"),
    .target(name: "PermissionFlow", dependencies: ["SystemSettingsKit"]),
  ]
)
