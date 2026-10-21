// The pictures the photos app and the image tests use, all drawn here from
// shapes (no photographs, no fonts), so they can be published freely: what it
// writes is dedicated to the public domain (CC0 1.0), the script itself is MIT
// as the rest of mbui.
//   swift scripts/test_images.swift test/images      the committed ones: one picture stored turned for each of a
//                                                    few EXIF orientations (exif<n>.jpg; a host that ignores or
//                                                    misreads the tag shows the "F" turned or mirrored) and two
//                                                    made-up landscapes (scene0.jpg, scene1.jpg)
//   swift scripts/test_images.swift --gallery DIR    the photos app's others, made at build time, never committed:
//                                                    twelve landscapes as JPEG and HEIC (0…11.jpg, 0…11.heic, 800
//                                                    px at most) and big ones, 6016 × 6016 (big.jpg, big.heic,
//                                                    big0…4.heic)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

var args = Array(CommandLine.arguments.dropFirst())
let gallery = args.first == "--gallery"
if gallery { args.removeFirst() }
let out = args.first ?? (gallery ? "out/pictures" : "test/images")
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let info = CGImageAlphaInfo.premultipliedLast.rawValue

func write(_ img: CGImage, _ name: String, orientation: Int = 1, quality: Double = 0.8) {
  let url = URL(fileURLWithPath: "\(out)/\(name)")
  let type = name.hasSuffix(".heic") ? UTType.heic : UTType.jpeg
  let dst = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
  let props: [CFString: Any] = [
    kCGImagePropertyOrientation: orientation,
    kCGImageDestinationLossyCompressionQuality: quality,
  ]
  CGImageDestinationAddImage(dst, img, props as CFDictionary)
  if !CGImageDestinationFinalize(dst) { fatalError("could not write \(name)") }
}

func context(_ w: Int, _ h: Int) -> CGContext {
  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: srgb, bitmapInfo: info)!
  ctx.translateBy(x: 0, y: CGFloat(h))
  ctx.scaleBy(x: 1, y: -1)  // y down
  return ctx
}

func rgb(_ v: UInt32) -> CGColor {
  CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
          blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

// A digit of seven segments in the rect (x, y, w, h), strokes t thick.
func digit(_ ctx: CGContext, _ d: Int, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ t: CGFloat) {
  //            a     b     c     d     e     f     g
  let on: [[Bool]] = [
    [true, true, true, true, true, true, false], [false, true, true, false, false, false, false],
    [true, true, false, true, true, false, true], [true, true, true, true, false, false, true],
    [false, true, true, false, false, true, true], [true, false, true, true, false, true, true],
    [true, false, true, true, true, true, true], [true, true, true, false, false, false, false],
    [true, true, true, true, true, true, true], [true, true, true, true, false, true, true],
  ]
  let m = y + (h - t) / 2
  let segs = [
    CGRect(x: x, y: y, width: w, height: t), CGRect(x: x + w - t, y: y, width: t, height: h / 2 + t / 2),
    CGRect(x: x + w - t, y: m, width: t, height: h - (m - y)), CGRect(x: x, y: y + h - t, width: w, height: t),
    CGRect(x: x, y: m, width: t, height: h - (m - y)), CGRect(x: x, y: y, width: t, height: h / 2 + t / 2),
    CGRect(x: x, y: m, width: w, height: t),
  ]
  for (i, r) in segs.enumerated() where on[d][i] { ctx.fill(r) }
}

// What every orientation picture should look like: an "F" at the top left, a red band along the top, the number of
// its orientation.
let W = 480, H = 320
func upright(_ o: Int) -> [UInt32] {
  let ctx = context(W, H)
  ctx.setFillColor(rgb(0x8CBFF2))
  ctx.fill(CGRect(x: 0, y: 0, width: W, height: H / 2))
  ctx.setFillColor(rgb(0x73B366))
  ctx.fill(CGRect(x: 0, y: H / 2, width: W, height: H / 2))
  ctx.setFillColor(rgb(0xD92626))
  ctx.fill(CGRect(x: 0, y: 0, width: W, height: 16))
  ctx.setFillColor(rgb(0x1A1A26))
  ctx.fill(CGRect(x: 40, y: 50, width: 30, height: 200))  // F
  ctx.fill(CGRect(x: 40, y: 50, width: 130, height: 30))
  ctx.fill(CGRect(x: 40, y: 130, width: 90, height: 30))
  ctx.setFillColor(rgb(0xFFFFFF))
  digit(ctx, o, 260, 150, 60, 110, 16)
  let p = ctx.data!.bindMemory(to: UInt32.self, capacity: W * H)
  return Array(UnsafeBufferPointer(start: p, count: W * H))
}

// stored pixel (x, y) shows at upright (X, Y), from the EXIF definitions
func stored(_ u: [UInt32], _ o: Int) -> CGImage {
  let turned = o >= 5
  let sw = turned ? H : W, sh = turned ? W : H
  var s = [UInt32](repeating: 0, count: sw * sh)
  for y in 0..<sh {
    for x in 0..<sw {
      let (X, Y): (Int, Int)
      switch o {
      case 2: (X, Y) = (W - 1 - x, y)
      case 3: (X, Y) = (W - 1 - x, H - 1 - y)
      case 4: (X, Y) = (x, H - 1 - y)
      case 5: (X, Y) = (y, x)
      case 6: (X, Y) = (W - 1 - y, x)
      case 7: (X, Y) = (W - 1 - y, H - 1 - x)
      case 8: (X, Y) = (y, H - 1 - x)
      default: (X, Y) = (x, y)
      }
      s[y * sw + x] = u[Y * W + X]
    }
  }
  return s.withUnsafeMutableBytes { b in
    CGContext(data: b.baseAddress, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: sw * 4,
              space: srgb, bitmapInfo: info)!.makeImage()!
  }
}

// A made-up landscape: a sky, a sun, ridges one behind the other, water or a field; `seed` picks its colours and
// shapes, the same every time.
let palettes: [[UInt32]] = [
  // sky top, sky low, sun, far ridge, near ridge, ground
  [0x2E5FA8, 0xF2B07A, 0xFFE3A3, 0x7A6A9C, 0x3F3D63, 0x2A4F6E],
  [0x87C3EB, 0xDCEFF7, 0xFFFFFF, 0x8FB3A0, 0x4D7F5C, 0x6E9E4F],
  [0x1B1B3A, 0x6A3E7C, 0xF6C177, 0x3A2E58, 0x221C3A, 0x14122A],
  [0xF59E6B, 0xFCE3B0, 0xFFF6D5, 0xC27C5A, 0x8C4A3B, 0xD9A066],
  [0x5AA7C8, 0xBFE3E8, 0xFFF9E8, 0x9CB8C9, 0x5E7F96, 0x2F6F8F],
  [0x0F2A44, 0x2F6C8F, 0xE8F1F5, 0x1E4660, 0x123147, 0x0B1E30],
]

func scene(_ seed: Int, _ w: Int, _ h: Int) -> CGImage {
  let ctx = context(w, h)
  let p = palettes[seed % palettes.count]
  let fw = CGFloat(w), fh = CGFloat(h)
  let horizon = fh * (0.55 + 0.1 * CGFloat(seed % 3) / 2)
  let sky = CGGradient(colorsSpace: srgb, colors: [rgb(p[0]), rgb(p[1])] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: horizon), options: [.drawsAfterEndLocation])
  // the sun, with a glow
  let sx = fw * (0.2 + 0.6 * CGFloat((seed * 37) % 100) / 100), sy = horizon * (0.35 + 0.3 * CGFloat(seed % 4) / 3)
  let r = min(fw, fh) * 0.08
  let glow = CGGradient(colorsSpace: srgb, colors: [rgb(p[2]).copy(alpha: 0.6)!, rgb(p[2]).copy(alpha: 0)!] as CFArray,
                        locations: [0, 1])!
  ctx.drawRadialGradient(glow, startCenter: CGPoint(x: sx, y: sy), startRadius: r, endCenter: CGPoint(x: sx, y: sy),
                         endRadius: r * 4, options: [])
  ctx.setFillColor(rgb(p[2]))
  ctx.fillEllipse(in: CGRect(x: sx - r, y: sy - r, width: 2 * r, height: 2 * r))
  // ridges: sums of sines, the far one paler
  for (k, colour) in [p[3], p[4]].enumerated() {
    let base = horizon - fh * (k == 0 ? 0.12 : 0.03)
    let amp = fh * (k == 0 ? 0.1 : 0.07)
    let a = Double(seed * 3 + k * 7), b = Double(seed * 5 + k * 11)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 0, y: fh))
    for i in 0...200 {
      let t = Double(i) / 200
      let v = sin(t * 7.0 + a) * 0.5 + sin(t * 17.0 + b) * 0.3 + sin(t * 41.0 + a + b) * 0.12
      ctx.addLine(to: CGPoint(x: fw * CGFloat(t), y: base - amp * CGFloat(v + 0.6)))
    }
    ctx.addLine(to: CGPoint(x: fw, y: fh))
    ctx.closePath()
    ctx.setFillColor(rgb(colour))
    ctx.fillPath()
  }
  // the ground, and on water the sun's light in bands
  ctx.setFillColor(rgb(p[5]))
  ctx.fill(CGRect(x: 0, y: horizon, width: fw, height: fh - horizon))
  if seed % 2 == 0 {
    ctx.setFillColor(rgb(p[2]).copy(alpha: 0.35)!)
    var y = horizon + fh * 0.02
    var i = 0
    while y < fh {
      let half = r * (1.4 - CGFloat(i) * 0.05) + CGFloat((i * 13) % 7)
      ctx.fill(CGRect(x: sx - half, y: y, width: 2 * half, height: max(1, fh * 0.006)))
      y += fh * 0.025 + CGFloat(i) * fh * 0.002
      i += 1
    }
  } else {
    ctx.setStrokeColor(rgb(p[4]).copy(alpha: 0.5)!)
    ctx.setLineWidth(max(1, fh * 0.004))
    for i in 0..<12 {
      let y = horizon + (fh - horizon) * CGFloat(i * i) / 121
      ctx.move(to: CGPoint(x: 0, y: y))
      ctx.addLine(to: CGPoint(x: fw, y: y))
    }
    ctx.strokePath()
  }
  return ctx.makeImage()!
}

if gallery {
  let sizes = [(800, 533), (533, 800), (800, 800), (800, 450), (600, 800), (800, 600)]
  for i in 0..<12 {
    let (w, h) = sizes[i % sizes.count]
    let img = scene(i + 2, w, h)
    write(img, "\(i).jpg", quality: 0.8)
    write(img, "\(i).heic", quality: 0.7)
  }
  let big = scene(1, 6016, 6016)
  write(big, "big.jpg", quality: 0.85)
  write(big, "big.heic")
  for i in 0..<5 { write(i == 0 ? big : scene(20 + i, 6016, 6016), "big\(i).heic") }
} else {
  for o in [1, 3, 6, 8, 5, 7] {
    write(stored(upright(o), o), "exif\(o).jpg", orientation: o)
  }
  write(scene(0, 354, 354), "scene0.jpg", quality: 0.8)
  write(scene(1, 356, 356), "scene1.jpg", quality: 0.8)
}
