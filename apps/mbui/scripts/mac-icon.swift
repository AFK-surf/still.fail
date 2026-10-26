// still.fail's macOS, iOS, Windows and Linux icons (the Android app's launcher icon, android/app/src/main/res:
// still.fail's mark, s. in Inter Bold, on its app's colour; design/brand): drawn into the shape of a macOS app icon and
// made an .icns, the iPhone's square (the system rounds it) as the 1024-pixel PNG of an asset catalog's app icon
// (scripts/ios.sh), Windows' .ico, or Linux's 512-pixel PNG (its desktop entry's icon, in Windows' shape). Which app's:
// VARIANT, as mac-app.sh's MBUI_VARIANT (mbui by default: still.fail mbui's violet; stable still.fail's paper, beta
// youdid.wtf's night).
//   swift apps/mbui/scripts/mac-icon.swift [VARIANT] OUT.icns
//   swift apps/mbui/scripts/mac-icon.swift --ios OUT.png
//   swift apps/mbui/scripts/mac-icon.swift --ico OUT.ico
//   swift apps/mbui/scripts/mac-icon.swift --png OUT.png
// The Android drawable's 108-unit viewport, of which a launcher shows the middle 72 (18 to 90), is laid on the icon's
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
let variant = rest.count > 1 ? rest[0] : "mbui"
// where the square is on the 1024 grid, and its corners' radius
let (edge, side, radius): (CGFloat, CGFloat, CGFloat) = ios ? (0, 1024, 0) : ico ? (32, 960, 192) : (100, 824, 185)

func rgb(_ hex: Int) -> NSColor {
  NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
// the app's tile, its s and its dot (android/app/src/<variant>/res/values/launcher.xml's)
let colours: [String: (NSColor, NSColor, NSColor)] = [
  "mbui": (rgb(0x5B4FD6), rgb(0xFFFFFF), rgb(0xFFD66B)),
  "stable": (rgb(0xFAFAF9), rgb(0x18181B), rgb(0xE5704A)),
  "beta": (rgb(0x111114), rgb(0xFAFAFA), rgb(0xE5704A)),
]
guard let palette = colours[variant] else {
  FileHandle.standardError.write("mac-icon.swift: VARIANT is mbui, stable or beta, not \(variant)\n".data(using: .utf8)!)
  exit(1)
}
let (ground, ink, dotColour) = palette

// brand: made by design/brand/make.py
let sPath = "M47.41 69.84C44.94 69.84 42.76 69.49 40.85 68.78C38.94 68.07 37.39 67.05 36.19 65.71C34.98 64.36 34.2 62.75 33.84 60.85L41.52 59.53C41.92 60.96 42.62 62.03 43.62 62.74C44.63 63.46 45.97 63.81 47.66 63.81C49.22 63.81 50.46 63.51 51.37 62.91C52.29 62.31 52.74 61.56 52.74 60.64C52.74 59.83 52.42 59.18 51.77 58.66C51.12 58.15 50.12 57.76 48.77 57.48L43.49 56.39C40.53 55.78 38.32 54.75 36.85 53.3C35.39 51.85 34.66 49.97 34.66 47.67C34.66 45.71 35.19 44.02 36.27 42.6C37.34 41.18 38.84 40.08 40.77 39.31C42.7 38.54 44.95 38.16 47.54 38.16C49.97 38.16 52.07 38.5 53.85 39.17C55.62 39.84 57.05 40.78 58.15 42C59.24 43.23 59.98 44.67 60.35 46.35L53.05 47.63C52.72 46.58 52.12 45.73 51.24 45.06C50.35 44.4 49.16 44.07 47.67 44.07C46.31 44.07 45.18 44.35 44.26 44.92C43.35 45.49 42.89 46.24 42.89 47.18C42.89 47.95 43.18 48.6 43.77 49.13C44.37 49.67 45.39 50.08 46.83 50.39L52.35 51.48C55.32 52.08 57.53 53.07 58.98 54.43C60.43 55.8 61.15 57.58 61.15 59.78C61.15 61.79 60.57 63.55 59.39 65.06C58.22 66.57 56.6 67.74 54.54 68.58C52.47 69.42 50.1 69.84 47.41 69.84Z"
let dot = (x: 70.9 as CGFloat, y: 65.05 as CGFloat, r: 4.76 as CGFloat)
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
  // the viewport's (x, y), y down, to the icon's points, y up
  func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: (edge + (x - 18) * side / 72) * k, y: (1024 - (edge + (y - 18) * side / 72)) * k) }
  func len(_ v: CGFloat) -> CGFloat { v * side / 72 * k }
  // the square, its corners as macOS's (about 22.5% of its side)
  let square = NSBezierPath(roundedRect: NSRect(x: edge * k, y: edge * k, width: side * k, height: side * k),
                            xRadius: radius * k, yRadius: radius * k)
  // on macOS's grid its shadow under it (Apple's template's: 28% black, 10 down, 12 soft); the paper's tile edged
  // faintly, as it would be lost on a light Dock or taskbar
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
  if variant == "stable" && !ios {
    NSColor(white: 0, alpha: 0.06).setStroke()
    square.lineWidth = k
    square.stroke()
  }
  // the s, and its dot
  ink.setFill()
  shape(sPath, p).fill()
  let c = p(dot.x, dot.y)
  dotColour.setFill()
  NSBezierPath(ovalIn: NSRect(x: c.x - len(dot.r), y: c.y - len(dot.r), width: 2 * len(dot.r), height: 2 * len(dot.r))).fill()
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
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
