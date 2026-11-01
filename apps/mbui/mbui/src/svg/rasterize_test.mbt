///|
test "an SVG's bytes drawn at the size asked, its longer side that many pixels" {
  let svg = @utf8.encode(
    "<svg xmlns='http://www.w3.org/2000/svg' width='40' height='20'><rect width='20' height='20' fill='#ff0000'/></svg>",
  )
  guard rasterize(svg, 80) is Some((w, h, rgba)) else { fail("not drawn") }
  assert_eq(w, 80)
  assert_eq(h, 40)
  // the left half red, straight alpha
  assert_eq((rgba[0].to_int(), rgba[1].to_int(), rgba[2].to_int(), rgba[3].to_int()), (255, 0, 0, 255))
  // the right half clear
  let i = (10 * w + 70) * 4
  assert_eq(rgba[i + 3].to_int(), 0)
  // a tall one: its height the longer side
  let tall = @utf8.encode("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='30'/>")
  guard rasterize(tall, 90) is Some((tw, th, _)) else { fail("not drawn") }
  assert_eq((tw, th), (30, 90))
  assert_true(rasterize(@utf8.encode("not svg"), 50) is None)
}
