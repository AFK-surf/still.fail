///|
test "oklch black, white, alpha and gamut clamping" {
  assert_eq(@ui.oklch(0.0, 0.0, 0.0), 0x000000FFL)
  assert_eq(@ui.oklch(1.0, 0.0, 0.0), 0xFFFFFFFFL)
  assert_eq(@ui.oklch(1.0, 0.0, 0.0, alpha=0.5), 0xFFFFFF80L)
  // High chroma is stepped down into sRGB gamut while preserving lightness and hue
  let vivid = @ui.oklch(0.60, 0.40, 210.0)
  let r = (vivid >> 24) & 0xFFL
  let g = (vivid >> 16) & 0xFFL
  let b = (vivid >> 8) & 0xFFL
  let a = vivid & 0xFFL
  assert_true(r >= 0L && r <= 255L)
  assert_true(g > r && b > g)
  assert_eq(a, 0xFFL)
}
