// still.fail mbui's macOS, iOS and Windows icons (the Android app's launcher icon, android/app/src/main/res: still.fail's
// face under a crescent, on violet): drawn into the shape of a macOS app icon and made an .icns, the iPhone's square
// (the system rounds it) as the 1024-pixel PNG of an asset catalog's app icon (scripts/ios.sh), or Windows' .ico.
//   swift apps/mbui/scripts/mac-icon.swift OUT.icns
//   swift apps/mbui/scripts/mac-icon.swift --ios OUT.png
//   swift apps/mbui/scripts/mac-icon.swift --ico OUT.ico
// The Android drawable's 108-unit viewport, of which a launcher shows the middle 72 (18 to 90), is laid on the icon's
// 824-point rounded square (100 to 924 of 1024, Apple's grid), on the whole of the iPhone's, or on Windows' square
// (32 to 992: its icons fill their cell, a sliver of it left for the rounded corners' edge to be seen).
// Windows' is not made where it is built (no AppKit there): its .ico is kept in the repository, named by this
// script's hash (apps/mbui/windows/AppIcon-<hash>.ico, which scripts/win.sh asks for): this script changed, it is
// made again here (on a Mac) and the one before removed.
import AppKit
import Foundation

let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[1] : ""
let ios = mode == "--ios", ico = mode == "--ico"
let out = mode != "" ? CommandLine.arguments[2] : CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
// where the square is on the 1024 grid, and its corners' radius
let (edge, side, radius): (CGFloat, CGFloat, CGFloat) = ios ? (0, 1024, 0) : ico ? (32, 960, 192) : (100, 824, 185)
let violet = NSColor(srgbRed: 0x5B / 255.0, green: 0x4F / 255.0, blue: 0xD6 / 255.0, alpha: 1)
let moon = NSColor(srgbRed: 0xFF / 255.0, green: 0xD6 / 255.0, blue: 0x6B / 255.0, alpha: 1)
let cheeks = NSColor(srgbRed: 0xB7 / 255.0, green: 0xB0 / 255.0, blue: 0xF2 / 255.0, alpha: 1)

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
  func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> NSBezierPath {
    let c = p(x, y)
    return NSBezierPath(ovalIn: NSRect(x: c.x - len(r), y: c.y - len(r), width: 2 * len(r), height: 2 * len(r)))
  }
  // the square, its corners as macOS's (about 22.5% of its side)
  let square = NSBezierPath(roundedRect: NSRect(x: edge * k, y: edge * k, width: side * k, height: side * k),
                            xRadius: radius * k, yRadius: radius * k)
  violet.setFill()
  square.fill()
  // the crescent: the circle (54, 31) r 8.5 less the circle (58.5, 27.5) r 7.5
  NSGraphicsContext.saveGraphicsState()
  circle(54, 31, 8.5).addClip()
  moon.setFill()
  circle(54, 31, 8.5).fill()
  violet.setFill()
  circle(58.5, 27.5, 7.5).fill()
  NSGraphicsContext.restoreGraphicsState()
  // the eyes
  NSColor.white.setFill()
  circle(40.8, 52.2, 4.51).fill()
  circle(67.2, 52.2, 4.51).fill()
  // the cheeks: capsules 5.87 high
  cheeks.setFill()
  for x0 in [26.99, 70.19] as [CGFloat] {
    let a = p(x0, 73.19)
    NSBezierPath(roundedRect: NSRect(x: a.x, y: a.y, width: len(10.82), height: len(5.87)),
                 xRadius: len(2.93), yRadius: len(2.93)).fill()
  }
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

if ios {
  try render(1024).write(to: URL(fileURLWithPath: out))
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
