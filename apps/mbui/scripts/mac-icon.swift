// still.fail's macOS, iOS, Windows and Linux icons (the Android app's launcher icon, android/app/src/main/res:
// still.fail's face, its eyes and cheeks, on its app's colour; design/brand): drawn into the shape of a macOS app icon and
// made an .icns, macOS 26's Icon Composer document (OUT.icon: the face's layers, each appearance's colours, for actool;
// scripts/mac-app.sh), the iPhone's square (the system rounds it) as the 1024-pixel PNG of an asset catalog's app icon
// (scripts/ios.sh), Windows' .ico, or Linux's 512-pixel PNG (its desktop entry's icon, in Windows' shape). Which app's:
// VARIANT, as mac-app.sh's MBUI_VARIANT (stable by default, still.fail's black face, as mbui's app is still.fail's now;
// beta youdid.wtf's, the orange tape across its corner; stable-dark and beta-dark their white faces, for a dark system).
//   swift apps/mbui/scripts/mac-icon.swift [VARIANT] OUT.icns
//   swift apps/mbui/scripts/mac-icon.swift --icon [VARIANT] OUT.icon
//   swift apps/mbui/scripts/mac-icon.swift --ios OUT.png
//   swift apps/mbui/scripts/mac-icon.swift --ico OUT.ico
//   swift apps/mbui/scripts/mac-icon.swift --png OUT.png
// The face's 100-unit tile (design/brand/make.py's, the middle 72 of the Android drawable's 108) is laid on the icon's
// 824-point rounded square (100 to 924 of 1024, Apple's grid), on the whole of the iPhone's, or on Windows' square
// (32 to 992: its icons fill their cell, a sliver of it left for the rounded corners' edge to be seen).
// Windows' and Linux's are not made where they are built (no AppKit there): kept in the repository, named by this
// script's hash (apps/mbui/windows/AppIcon-<hash>.ico, which scripts/win.sh asks for; apps/mbui/linux/AppIcon-<hash>.png,
// scripts/beta.sh linux's): this script changed, they are made again here (on a Mac) and the ones before removed.
import AppKit
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
let ios = args.contains("--ios"), png = args.contains("--png"), ico = args.contains("--ico") || png
let rest = args.filter { !$0.hasPrefix("--") }
let out = rest.last ?? "AppIcon.icns"
let variant = rest.count > 1 ? (rest[0] == "mbui" ? "stable" : rest[0]) : "stable"
// where the square is on the 1024 grid, and its corners' radius
let (edge, side, radius): (CGFloat, CGFloat, CGFloat) = ios ? (0, 1024, 0) : ico ? (32, 960, 192) : (100, 824, 185)

func rgb(_ hex: Int) -> NSColor {
  NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
// the app's tile, its eyes and its cheeks (android/app/src/<variant>/res/values/launcher.xml's), and whether the tape is
// across its corner
let colours: [String: (NSColor, NSColor, NSColor, Bool)] = [
  "stable": (rgb(0x1C1D20), rgb(0xFFFFFF), rgb(0xF6BC9F), false),
  "stable-dark": (rgb(0xF4F4F5), rgb(0x1C1D20), rgb(0xF6BC9F), false),
  "beta": (rgb(0x1C1D20), rgb(0xFFFFFF), rgb(0xF6BC9F), true),
  "beta-dark": (rgb(0xF4F4F5), rgb(0x1C1D20), rgb(0xF6BC9F), true),
]
guard let palette = colours[variant] else {
  FileHandle.standardError.write("mac-icon.swift: VARIANT is stable, stable-dark, beta or beta-dark (mbui: stable), not \(variant)\n".data(using: .utf8)!)
  exit(1)
}
let (ground, ink, cheekColour, taped) = palette
let tapeColour = rgb(0xE5704A)

// brand: made by design/brand/make.py
let eyePaths = ["M39 47.6C39 51.25 36.05 54.2 32.4 54.2C28.75 54.2 25.8 51.25 25.8 47.6C25.8 43.95 28.75 41 32.4 41C36.05 41 39 43.95 39 47.6Z", "M74.2 47.6C74.2 51.25 71.25 54.2 67.6 54.2C63.95 54.2 61 51.25 61 47.6C61 43.95 63.95 41 67.6 41C71.25 41 74.2 43.95 74.2 47.6Z"]
let cheekPaths = ["M17.9 67.8L24.5 67.8C26.65 67.8 28.4 69.55 28.4 71.7C28.4 73.85 26.65 75.6 24.5 75.6L17.9 75.6C15.75 75.6 14 73.85 14 71.7C14 69.55 15.75 67.8 17.9 67.8Z", "M75.5 67.8L82.1 67.8C84.25 67.8 86 69.55 86 71.7C86 73.85 84.25 75.6 82.1 75.6L75.5 75.6C73.35 75.6 71.6 73.85 71.6 71.7C71.6 69.55 73.35 67.8 75.5 67.8Z"]
let tapePath = "M42 0L62 0L100 38L100 58Z"
let tapeWords = "M65.7 18.23L70.23 13.7L72.03 15.5C72.36 15.83 72.58 16.16 72.71 16.48C72.83 16.8 72.86 17.11 72.79 17.39C72.73 17.68 72.58 17.93 72.36 18.16C72.18 18.34 71.99 18.46 71.78 18.52C71.58 18.58 71.38 18.59 71.17 18.55C70.96 18.51 70.76 18.44 70.57 18.32L70.53 18.36C70.69 18.54 70.8 18.75 70.86 18.99C70.92 19.23 70.92 19.48 70.85 19.73C70.79 19.99 70.64 20.23 70.42 20.45C70.18 20.69 69.91 20.84 69.6 20.91C69.3 20.98 68.98 20.96 68.64 20.84C68.3 20.72 67.96 20.48 67.62 20.14ZM67.4 18.4L68.2 19.2C68.47 19.47 68.72 19.61 68.95 19.63C69.18 19.65 69.38 19.58 69.55 19.41C69.68 19.28 69.76 19.14 69.8 18.97C69.84 18.81 69.83 18.65 69.77 18.48C69.71 18.31 69.6 18.15 69.45 17.99L68.62 17.17ZM69.26 16.53L69.99 17.26C70.12 17.4 70.26 17.49 70.41 17.55C70.57 17.61 70.72 17.62 70.87 17.59C71.01 17.57 71.15 17.49 71.27 17.37C71.44 17.21 71.51 17.01 71.5 16.79C71.48 16.57 71.37 16.35 71.15 16.14L70.4 15.39ZM70.07 22.59L74.59 18.07L77.62 21.1L76.85 21.87L74.75 19.77L73.66 20.86L75.6 22.8L74.85 23.56L72.9 21.61L71.77 22.75L73.87 24.86L73.1 25.63ZM77.67 22.69L78.44 21.92L82.14 25.61L81.37 26.38L79.99 25L76.23 28.75L75.3 27.83L79.06 24.07ZM77.68 30.21L83.76 27.23L84.97 28.44L82.03 34.56L81 33.53L82.46 30.62C82.65 30.25 82.87 29.85 83.12 29.43C83.36 29 83.64 28.54 83.93 28.05L84.13 28.25C83.64 28.55 83.18 28.83 82.76 29.08C82.34 29.33 81.95 29.56 81.59 29.75L78.71 31.23ZM79.7 30.13L80.43 29.4L82.84 31.81L82.11 32.54Z"
// brand end

/// An SVG path of M, L, C and Z (absolute, as make.py writes them), its points through `p`.
func shape(_ d: String, _ p: (CGFloat, CGFloat) -> NSPoint) -> NSBezierPath {
  let path = NSBezierPath()
  var op: Character = " ", nums: [CGFloat] = [], number = ""
  func take() {
    if let v = Double(number) { nums.append(CGFloat(v)) }
    number = ""
  }
  func draw() {
    switch op {
    case "M": path.move(to: p(nums[0], nums[1]))
    case "L": path.line(to: p(nums[0], nums[1]))
    case "C": path.curve(to: p(nums[4], nums[5]), controlPoint1: p(nums[0], nums[1]), controlPoint2: p(nums[2], nums[3]))
    case "Z": path.close()
    default: break
    }
    nums = []
  }
  for ch in d {
    if ch.isLetter {
      take(); draw(); op = ch
    } else if ch == " " || ch == "," {
      take()
    } else if ch == "-" && !number.isEmpty {
      take(); number = "-"
    } else {
      number.append(ch)
    }
  }
  take(); draw()
  return path
}

func render(_ size: Int) -> Data {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let k = CGFloat(size) / 1024
  // the tile's (x, y), y down, to the icon's points, y up
  func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: (edge + x * side / 100) * k, y: (1024 - (edge + y * side / 100)) * k) }
  // the square, its corners as macOS's (about 22.5% of its side)
  let square = NSBezierPath(roundedRect: NSRect(x: edge * k, y: edge * k, width: side * k, height: side * k),
                            xRadius: radius * k, yRadius: radius * k)
  // on macOS's grid its shadow under it (Apple's template's: 28% black, 10 down, 12 soft); the white face's tile
  // edged faintly, as it would be lost on a light Dock or taskbar
  NSGraphicsContext.saveGraphicsState()
  if !ios && !ico {
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
    shadow.shadowBlurRadius = 24 * k
    shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    shadow.set()
  }
  ground.setFill()
  square.fill()
  NSGraphicsContext.restoreGraphicsState()
  if variant.hasSuffix("-dark") && !ios {
    NSColor(white: 0, alpha: 0.06).setStroke()
    square.lineWidth = k
    square.stroke()
  }
  // the eyes, the cheeks, and the tape inside the square
  ink.setFill()
  for d in eyePaths { shape(d, p).fill() }
  cheekColour.setFill()
  for d in cheekPaths { shape(d, p).fill() }
  if taped {
    NSGraphicsContext.saveGraphicsState()
    square.addClip()
    tapeColour.setFill()
    shape(tapePath, p).fill()
    NSColor.white.setFill()
    shape(tapeWords, p).fill()
    NSGraphicsContext.restoreGraphicsState()
  }
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

// macOS 26's: an Icon Composer document (OUT.icon, which actool compiles into the app's Assets.car), its tile and face
// each appearance's own (the variant's, and its -dark's for a dark system), the system giving it its shape and glass
if args.contains("--icon") {
  let dark = colours[variant + "-dark"]!
  func colour(_ c: NSColor) -> String {
    let s = c.usingColorSpace(.sRGB)!
    return "srgb:" + [s.redComponent, s.greenComponent, s.blueComponent, 1].map { String(format: "%.5f", $0) }.joined(separator: ",")
  }
  func fill(_ light: NSColor, _ dark: NSColor) -> [String: Any] {
    ["fill-specializations": [["value": ["solid": colour(light)]], ["appearance": "dark", "value": ["solid": colour(dark)]]]]
  }
  // a layer: its shapes on the tile's 100, the whole of the document's 1024
  func svg(_ paths: [(String, String)]) -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 100 100\">"
      + paths.map { "<path d=\"\($0.0)\" fill=\"\($0.1)\"/>" }.joined() + "</svg>"
  }
  var layers: [[String: Any]] = []
  var files: [String: String] = [:]
  if taped {
    files["tape.svg"] = svg([(tapePath, "#E5704A"), (tapeWords, "#FFFFFF")])
    layers.append(["name": "tape", "image-name": "tape.svg", "glass": false])
  }
  files["eyes.svg"] = svg(eyePaths.map { ($0, "#FFFFFF") })
  files["cheeks.svg"] = svg(cheekPaths.map { ($0, "#F6BC9F") })
  layers.append(["name": "eyes", "image-name": "eyes.svg", "glass": false].merging(fill(ink, dark.1)) { a, _ in a })
  layers.append(["name": "cheeks", "image-name": "cheeks.svg", "glass": false].merging(fill(cheekColour, dark.2)) { a, _ in a })
  let doc: [String: Any] = fill(ground, dark.0).merging([
    "groups": [["layers": layers, "shadow": ["kind": "neutral", "opacity": 0.5], "translucency": ["enabled": false, "value": 0.5]]],
    "supported-platforms": ["squares": ["macOS"]],
  ]) { a, _ in a }
  let dir = URL(fileURLWithPath: out)
  try? FileManager.default.removeItem(at: dir)
  try FileManager.default.createDirectory(at: dir.appendingPathComponent("Assets"), withIntermediateDirectories: true)
  for (name, body) in files { try body.write(to: dir.appendingPathComponent("Assets/" + name), atomically: true, encoding: .utf8) }
  try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]).write(to: dir.appendingPathComponent("icon.json"))
  exit(0)
}
if ios {
  try render(1024).write(to: URL(fileURLWithPath: out))
  exit(0)
}
if png {
  try render(512).write(to: URL(fileURLWithPath: out))
  exit(0)
}
// Windows': each size the shell asks for at 100-200 % scaling a PNG of its own (an .ico holds PNGs since Vista), the
// largest 256 (said as 0 in its entry)
if ico {
  let sizes = [16, 20, 24, 32, 40, 48, 64, 96, 256]
  let pngs = sizes.map { render($0) }
  var file = Data()
  func u16(_ v: Int) { file.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
  func u32(_ v: Int) { u16(v & 0xFFFF); u16((v >> 16) & 0xFFFF) }
  u16(0); u16(1); u16(sizes.count)
  var at = 6 + 16 * sizes.count
  for (s, png) in zip(sizes, pngs) {
    file.append(contentsOf: [UInt8(s >= 256 ? 0 : s), UInt8(s >= 256 ? 0 : s), 0, 0])
    u16(1); u16(32); u32(png.count); u32(at)
    at += png.count
  }
  for png in pngs { file.append(png) }
  try file.write(to: URL(fileURLWithPath: out))
  exit(0)
}
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mbui-\(getpid()).iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
  try render(s).write(to: set.appendingPathComponent("icon_\(s)x\(s).png"))
  try render(s * 2).write(to: set.appendingPathComponent("icon_\(s)x\(s)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set.path, "-o", out]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: set)
exit(iconutil.terminationStatus)
