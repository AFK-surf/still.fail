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

///|
test "a style sheet's ^=, $= and *= attribute selectors (mermaid's markers: [id$=\"-extensionStart\"])" {
  // each rule's selector list has one of them first: the whole rule was dropped when it did not read
  let svg = @utf8.encode(
    "<svg xmlns='http://www.w3.org/2000/svg' width='30' height='10'><style>" +
    "rect{fill:#ff0000}" +
    "[id^=\"a-\"],.none{fill:#00ff00}" +
    "[id$=\"-b\"],.none{fill:#0000ff}" +
    "[id*=\"mid\"],.none{fill:#ffffff}" +
    "</style><rect id='a-1' width='10' height='10'/><rect id='x-b' x='10' width='10' height='10'/>" +
    "<rect id='xmidx' x='20' width='10' height='10'/></svg>",
  )
  guard rasterize(svg, 30) is Some((w, _, rgba)) else { fail("not drawn") }
  let at = fn(x) { (rgba[(5 * w + x) * 4].to_int(), rgba[(5 * w + x) * 4 + 1].to_int(), rgba[(5 * w + x) * 4 + 2].to_int()) }
  assert_eq(at(5), (0, 255, 0))
  assert_eq(at(15), (0, 0, 255))
  assert_eq(at(25), (255, 255, 255))
}
