// swift-tools-version: 6.2
// still.fail Helper (docs/station-ts-native.md §4): the station's macOS app for what macOS grants an app, not a
// process the station starts (a grant then needs only this app restarted, never the station): this Mac's screen
// first (docs/remote-screens.md). scripts/native.ts builds it and puts it in its bundle with Info.plist.
import PackageDescription

let package = Package(
  name: "StillfailHelper",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "stillfail-helper", targets: ["StillfailHelper"])],
  dependencies: [.package(path: "../../../vendor/PermissionFlow")],
  targets: [
    .executableTarget(
      name: "StillfailHelper",
      dependencies: [
        .product(name: "PermissionFlow", package: "PermissionFlow"),
        .product(name: "SystemSettingsKit", package: "PermissionFlow"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v5),
        // As Cue's Computer Use: Swift 6 dependencies' ObjC async continuation ABI (swiftlang/swift#81846).
        .unsafeFlags(["-Xfrontend", "-checked-async-objc-bridging=on"]),
      ]
    ),
  ]
)
