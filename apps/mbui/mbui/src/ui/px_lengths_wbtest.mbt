// Lengths on whole device pixels where the host sets things on them (Ctx::on_px): Compose's Dp.roundToPx, each length
// on its own, at a Pixel's 2.625.

///|
test "a length in points on the device's whole pixels, as Compose rounds each: half up" {
  let c = g()
  let saved = c.scale
  c.scale = 2.625
  let px = fn(v : Double) { (c.on_px(v, true) * 2.625 + 0.5).floor() }
  // 4 → 10.5 → 11, 8 → 21, 12 → 31.5 → 32, 5 → 13.125 → 13, 20 → 52.5 → 53, 16 → 42
  assert_eq([px(4.0), px(8.0), px(12.0), px(5.0), px(20.0), px(16.0)], [11.0, 21.0, 32.0, 13.0, 53.0, 42.0])
  // a host that does not set things on whole pixels: as said
  assert_eq(c.on_px(4.0, false), 4.0)
  assert_eq(c.on_px(0.0, true), 0.0)
  c.scale = saved
}
