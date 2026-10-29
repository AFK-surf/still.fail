///|
/// A host whose glyphs are 100 pixels square, its atlas 1024 a side (four plots of 25 of them): each UTF-16 unit a
/// cluster, keyed by its code. What it is asked to draw noted, and which glyph it was told to put where last.
priv struct SquareHost {
  drawn : Array[Int]
  put : Map[(Int, Int), Int]
}

///|
impl @hostapi.Host for SquareHost with font_metrics(_, size, _, _, out) {
  out[0] = size * 0.75
  out[1] = size * 0.25
  out[2] = size * 1.25
}

///|
impl @hostapi.Host for SquareHost with shape(_, text, _, _, _, out) {
  let n = text.length()
  for i in 0..<n {
    out[i * 4] = i.to_double()
    out[i * 4 + 1] = 1.0
    out[i * 4 + 2] = 7.0
    out[i * 4 + 3] = text.at(i).to_int().to_double()
  }
  n
}

///|
impl @hostapi.Host for SquareHost with text_key(_, text, _, _, _) {
  text.at(0).to_int()
}

///|
impl @hostapi.Host for SquareHost with glyph(self, key, out) {
  self.drawn.push(key)
  out[0] = 0.0
  out[1] = 0.0
  out[2] = square_glyph
  out[3] = square_glyph
  out[4] = 0.0
  out[5] = -square_glyph
  out[6] = 0.0
}

///|
impl @hostapi.Host for SquareHost with glyph_put(self, key, x, y) {
  self.put[(x, y)] = key
}

///|
impl @hostapi.Host for SquareHost with atlas_size(_, colour) {
  if colour {
    0
  } else {
    1024
  }
}

///|
/// A glyph's side in points: 100 pixels at the Tester's scale (1).
let square_glyph : Double = 100.0

///|
test "words scrolled through, more than the atlas holds: what stays on the screen is drawn once, every glyph from where it was put" {
  let host = SquareHost::{ drawn: [], put: {} }
  let words = Ref::new("")
  let t = @ui.Tester::new(
    fn(c) { c.text(words.val, wrap=false) |> ignore },
    w=4000.0,
    scale=1.0,
    live={ host, turn: fn() {  } },
  )
  // "AB" on the screen all along, 30 words of its own beside it on each page: 360 glyphs in all, the atlas 100
  for page in 0..<12 {
    let codes = ['A'.to_int(), 'B'.to_int()]
    codes.append(Array::makei(30, fn(i) { 0x4E00 + page * 30 + i }))
    let line = StringBuilder()
    for code in codes {
      line.write_char(Int::unsafe_to_char(code))
    }
    words.val = line.to_string()
    t.draw()
    // every glyph drawn from the place the host last put that glyph in, none from another's
    let (inst, n, _) = t.presented()
    let from : Array[Int] = []
    for k in 0..<n {
      if inst[k * glyphs_inst + 5] == 1.0 {
        let at = (inst[k * glyphs_inst + 12].to_int(), inst[k * glyphs_inst + 13].to_int())
        from.push(host.put.get(at).unwrap_or(-1))
      }
    }
    from.sort()
    codes.sort()
    assert_eq(from, codes)
  }
  // what stayed was drawn once, the first time it showed
  assert_eq(host.drawn.filter(fn(k) { k == 'A'.to_int() || k == 'B'.to_int() }).length(), 2)
}

///|
/// The numbers of an instance (scene.mbt).
let glyphs_inst = 60
