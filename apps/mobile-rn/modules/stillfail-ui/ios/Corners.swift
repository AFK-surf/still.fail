// still.fail's corners (apps/android/shared/.../ui/Corners.kt, as modules/stillfail-ui/android's Corners.kt, the same
// curves): a rounded rectangle's corner is a superellipse(1.5) one over a radius a quarter longer than the one it is
// given; circles and capsules are untouched, and between the two it goes over evenly.
import CoreGraphics
import Foundation

let SMOOTH_SCALE: CGFloat = 1.25
private let SMOOTH_EXPONENT = 2.8284271
private let CUTS = 12

private func smoothness(_ radius: CGFloat, _ room: CGFloat) -> CGFloat {
  radius <= 0 ? 0 : min(max((room - radius) / ((SMOOTH_SCALE - 1) * radius), 0), 1)
}

private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }

/// The outline as a path for a box of `box`; radii in points (top left, top right, bottom right, bottom left).
func smoothPath(_ box: CGRect, _ topLeft: CGFloat, _ topRight: CGFloat, _ bottomRight: CGFloat, _ bottomLeft: CGFloat, amount: CGFloat = 1) -> CGPath {
  let path = CGMutablePath()
  let room = max(min(box.width, box.height) / 2, 0)
  let tl = clamp(topLeft, 0, room), tr = clamp(topRight, 0, room), br = clamp(bottomRight, 0, room), bl = clamp(bottomLeft, 0, room)
  let a = clamp(amount, 0, 1)
  let stl = smoothness(tl, room) * a, str = smoothness(tr, room) * a, sbr = smoothness(br, room) * a, sbl = smoothness(bl, room) * a
  let rtl = tl * (1 + (SMOOTH_SCALE - 1) * stl), rtr = tr * (1 + (SMOOTH_SCALE - 1) * str)
  let rbr = br * (1 + (SMOOTH_SCALE - 1) * sbr), rbl = bl * (1 + (SMOOTH_SCALE - 1) * sbl)
  path.move(to: CGPoint(x: box.minX + rtl, y: box.minY))
  path.addLine(to: CGPoint(x: box.maxX - rtr, y: box.minY))
  corner(path, box.maxX - rtr, box.minY + rtr, rtr, 0, -1, 1, 0, str)
  path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - rbr))
  corner(path, box.maxX - rbr, box.maxY - rbr, rbr, 1, 0, 0, 1, sbr)
  path.addLine(to: CGPoint(x: box.minX + rbl, y: box.maxY))
  corner(path, box.minX + rbl, box.maxY - rbl, rbl, 0, 1, -1, 0, sbl)
  path.addLine(to: CGPoint(x: box.minX, y: box.minY + rtl))
  corner(path, box.minX + rtl, box.minY + rtl, rtl, -1, 0, 0, -1, stl)
  path.closeSubpath()
  return path
}

private func corner(_ path: CGMutablePath, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat, _ smooth: CGFloat) {
  if r <= 0 { return }
  let k = smooth == 1 ? full : smoothCorner(smooth)
  var i = 0
  while i < k.count {
    path.addCurve(
      to: CGPoint(x: cx + r * (k[i + 4] * ux + k[i + 5] * vx), y: cy + r * (k[i + 4] * uy + k[i + 5] * vy)),
      control1: CGPoint(x: cx + r * (k[i] * ux + k[i + 1] * vx), y: cy + r * (k[i] * uy + k[i + 1] * vy)),
      control2: CGPoint(x: cx + r * (k[i + 2] * ux + k[i + 3] * vx), y: cy + r * (k[i + 2] * uy + k[i + 3] * vy)))
    i += 6
  }
}

private let full = smoothCorner(1)

/// A quarter of the superellipse between the corner's two edges as CUTS cubics (Hermite to Bézier): their control
/// points and ends, in the corner's own axes, for a radius of 1.
private func smoothCorner(_ smooth: CGFloat) -> [CGFloat] {
  let n = 2.0 + (SMOOTH_EXPONENT - 2.0) * Double(smooth)
  let h = Double.pi / 2 / Double(CUTS)
  var out = [CGFloat](repeating: 0, count: CUTS * 6)
  func at(_ i: Int) -> [Double] {
    let c = i == CUTS ? 0.0 : cos(Double(i) * h), s = i == 0 ? 0.0 : sin(Double(i) * h)
    let sum = pow(c, n) + pow(s, n)
    let rho = pow(sum, -1 / n)
    let turn = rho * (pow(c, n - 1) * s - pow(s, n - 1) * c) / sum
    return [rho * c, rho * s, turn * c - rho * s, turn * s + rho * c]
  }
  var p = at(0)
  for i in 0..<CUTS {
    let q = at(i + 1)
    out[i * 6] = CGFloat(p[0] + p[2] * h / 3); out[i * 6 + 1] = CGFloat(p[1] + p[3] * h / 3)
    out[i * 6 + 2] = CGFloat(q[0] - q[2] * h / 3); out[i * 6 + 3] = CGFloat(q[1] - q[3] * h / 3)
    out[i * 6 + 4] = CGFloat(q[0]); out[i * 6 + 5] = CGFloat(q[1])
    p = q
  }
  return out
}
