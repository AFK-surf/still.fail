// What a frame drew, said one line for each thing drawn in the order it is drawn, the same however the frame was put
// together (built whole, painted, drawn by the window's tree alone, of its looks): for a frame of one build to be
// compared with the same frame of another (a pinned commit's against this one's, step by step, frame by frame).
// Places to the half point, colour and opacity apart, the clip in force, who drew it (the window's tree's node or the
// old frame's), a run of glyphs one line with the words of what drew them.

///|
/// From now on, who drew each thing is kept as each frame is drawn (what Tester::frame_export says it was drawn by).
pub fn Tester::export_frames(self : Tester) -> Unit {
  ignore(self)
  inst_owners.track = true
}

///|
/// The last frame drawn, a line for each thing in it as it was drawn: its kind, where it is and how big (x y w h), its
/// colour (#rrggbb) and opacity apart, its corners, the clip it is cut by, who drew it, and for a run of glyphs the
/// words of what drew them. Tester::export_frames first, for who drew what to be known.
pub fn Tester::frame_export(self : Tester) -> Array[String] {
  ignore(self)
  let c = g()
  let a = c.inst
  let half = fn(v : Double) -> String {
    let r = (v * 2.0).round() / 2.0
    if r == r.floor() {
      "\{r.to_int()}"
    } else {
      "\{r.floor().to_int()}.5"
    }
  }
  let hex = fn(v : Double) -> String {
    let n = (v * 255.0).round().to_int()
    let n = if n < 0 { 0 } else if n > 255 { 255 } else { n }
    let d = "0123456789abcdef"
    d[n / 16:n / 16 + 1].to_string() + d[n % 16:n % 16 + 1].to_string()
  }
  let kind_of = fn(k : Double) -> String {
    match k.to_int() {
      0 => "rect"
      1 => "glyph"
      2 => "shadow"
      3 => "image"
      11 => "shape"
      12 => "pieces"
      n => "kind\{n}"
    }
  }
  let by_of = fn(k : Int) -> (String, String) {
    match inst_tree_owner(k) {
      Some(id) => ("tree:\{id.at}", inst_owners.tree_words.get(id).unwrap_or(""))
      None =>
        if k < inst_owners.owner.length() && inst_owners.owner[k] >= 0 && inst_owners.owner[k] < c.count {
          let o = inst_owners.owner[k]
          ("old:\{o}", c.nodes[o].text)
        } else {
          ("none", "")
        }
    }
  }
  let line = fn(kind : String, x0 : Double, y0 : Double, x1 : Double, y1 : Double, b : Int, by : String, words : String) {
    "\{kind} \{half(x0)} \{half(y0)} \{half(x1 - x0)} \{half(y1 - y0)} #\{hex(a[b + 8])}\{hex(a[b + 9])}\{hex(a[b + 10])} a=\{hex(a[b + 11])} r=\{half(a[b + 36])},\{half(a[b + 37])},\{half(a[b + 38])},\{half(a[b + 39])} clip=\{half(a[b + 16])},\{half(a[b + 17])},\{half(a[b + 18])},\{half(a[b + 19])} by=\{by}" +
    (if words != "" { " \"" + words + "\"" } else { "" })
  }
  let out : Array[String] = []
  let mut k = 0
  while k < c.ninst {
    let b = k * inst_size
    let kind = a[b + 5]
    // (a frame's shapes' pieces: what its shapes are drawn of, said by the shapes)
    if kind == 12.0 {
      k = k + 1
      continue
    }
    let (by, words) = by_of(k)
    if kind == 1.0 {
      // (a run of glyphs, of one that drew them, in one colour and one clip: one line, its box all of theirs)
      let mut x0 = a[b]
      let mut y0 = a[b + 1]
      let mut x1 = a[b] + a[b + 2]
      let mut y1 = a[b + 1] + a[b + 3]
      let mut j = k + 1
      while j < c.ninst {
        let q = j * inst_size
        if a[q + 5] != 1.0 || by_of(j).0 != by {
          break
        }
        let mut same = true
        for s in [8, 9, 10, 11, 16, 17, 18, 19] {
          if a[q + s] != a[b + s] {
            same = false
          }
        }
        if !same {
          break
        }
        x0 = if a[q] < x0 { a[q] } else { x0 }
        y0 = if a[q + 1] < y0 { a[q + 1] } else { y0 }
        x1 = if a[q] + a[q + 2] > x1 { a[q] + a[q + 2] } else { x1 }
        y1 = if a[q + 1] + a[q + 3] > y1 { a[q + 1] + a[q + 3] } else { y1 }
        j = j + 1
      }
      out.push(line("glyphs", x0, y0, x1, y1, b, by, words))
      k = j
    } else {
      out.push(line(kind_of(kind), a[b], a[b + 1], a[b] + a[b + 2], a[b + 1] + a[b + 3], b, by, ""))
      k = k + 1
    }
  }
  out
}
