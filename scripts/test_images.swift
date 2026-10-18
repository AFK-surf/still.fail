// Makes test/images: two photos (from macOS's desktop picture thumbnails)
// and one picture stored turned for each of a few EXIF orientations, so a
// host that ignores or misreads the tag shows the "F" turned or mirrored.
//   swift scripts/test_images.swift test/images
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "test/images"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let info = CGImageAlphaInfo.premultipliedLast.rawValue

func write(_ img: CGImage, _ name: String, orientation: Int = 1, quality: Double = 0.8) {
  let url = URL(fileURLWithPath: "\(out)/\(name)")
  let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
  let props: [CFString: Any] = [
    kCGImagePropertyOrientation: orientation,
    kCGImageDestinationLossyCompressionQuality: quality,
  ]
  CGImageDestinationAddImage(dst, img, props as CFDictionary)
  CGImageDestinationFinalize(dst)
}

// what every orientation picture should look like: an "F" at the top left,
// a red band along the top, the number of its orientation
let W = 480, H = 320
func upright(_ label: String) -> [UInt32] {
  let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                      space: srgb, bitmapInfo: info)!
  ctx.translateBy(x: 0, y: CGFloat(H))
  ctx.scaleBy(x: 1, y: -1)  // y down
  ctx.setFillColor(CGColor(srgbRed: 0.55, green: 0.75, blue: 0.95, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 0, width: W, height: H / 2))
  ctx.setFillColor(CGColor(srgbRed: 0.45, green: 0.7, blue: 0.4, alpha: 1))
  ctx.fill(CGRect(x: 0, y: H / 2, width: W, height: H / 2))
  ctx.setFillColor(CGColor(srgbRed: 0.85, green: 0.15, blue: 0.15, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 0, width: W, height: 16))
  ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.15, alpha: 1))
  ctx.fill(CGRect(x: 40, y: 50, width: 30, height: 200))  // F
  ctx.fill(CGRect(x: 40, y: 50, width: 130, height: 30))
  ctx.fill(CGRect(x: 40, y: 130, width: 90, height: 30))
  let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 64, nil)
  let s = NSAttributedString(string: label, attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
  ])
  ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
  ctx.textPosition = CGPoint(x: 220, y: 230)
  CTLineDraw(CTLineCreateWithAttributedString(s), ctx)
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

for o in [1, 3, 6, 8, 5, 7] {
  write(stored(upright("EXIF \(o)"), o), "exif\(o).jpg", orientation: o)
}

let thumbs = "/System/Library/Desktop Pictures/.thumbnails/"
for (i, name) in ["Catalina Coast.heic", "Big Sur Road.heic"].enumerated() {
  let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: thumbs + name) as CFURL, nil)!
  let opt: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: 800,
  ]
  write(CGImageSourceCreateThumbnailAtIndex(src, 0, opt as CFDictionary)!, "photo\(i).jpg", quality: 0.7)
}
