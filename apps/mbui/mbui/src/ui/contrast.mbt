// Contrast, measured: what a frame draws to be seen stands off what it is drawn on far enough to be seen (still.fail's
// docs/ui-panels.md「对比度」). Words as WCAG 2's AA asks: 4.5:1, 3:1 where they are large (24 and up, or 18.66 and up
// in bold); an icon (Ctx::shapes) 3:1, as its non-text contrast asks of what is understood by its shape. What is drawn
// with nothing in it, its ground or (where that does not show) its edge alone saying what it is: a gauge's cell, a
// bar's track, a line (Ctx::lines too), a sheet's grip, each bar and shape of a page's bones (bones.mbt): at least
// `contrast_mark_least`, WCAG 2's ratio. A ground under words, a picture or an icon is not asked: what is in it
// carries it (and under bones, as under the words they stand for). Each is measured where
// it is drawn, against what the frame drew under it there (its instances before it, as the renderers lay them: fills,
// and glass's tint over what it frosts); what lies on a picture, a video or another app's view, or is covered by what
// is drawn after it (a dialog's scrim, a bar's glass over a list), is not asked, nor a picture drawn of something else
// (Role Image: another system's screen, a code to scan), nor what is in a widget said disabled (WCAG asks nothing of
// what cannot be used).

///|
/// Which node drew each instance of a frame, kept only while a test asks (Tester::contrast_faults): `owner[k]`
/// instance k's (-1 none known), `painting` the node being painted; `own_colours` the nodes said to draw in their own
/// colours (Ctx::own_colours). `track`: the owners kept on every frame a Tester draws, and nothing else of `on`'s (its
/// frame drawn as measured, each loop at its start, no row kept): what words lie over whose (words_over.mbt).
priv struct InstOwners {
  mut on : Bool
  mut track : Bool
  mut painting : Int
  owner : Array[Int]
  /// a glyph's cell across (where its advance starts and ends), as shares of its picture's width (0, 1: the picture's
  /// own), kept beside its owner: what of its picture is its own room, not the room its picture spills into
  /// (words_over.mbt)
  cell : Array[(Double, Double)]
  own_colours : Set[Int]
}

///|
let inst_owners : InstOwners = { on: false, track: false, painting: -1, owner: [], cell: [], own_colours: Set::new() }

///|
/// The frame's contrast asked again from nothing: no instance's owner known, no node said in its own colours.
fn inst_owners_clear() -> Unit {
  inst_owners.painting = -1
  inst_owners.owner.clear()
  inst_owners.cell.clear()
  inst_owners.own_colours.clear()
  bone_insts.clear()
}

///|
/// Node `node` (as Ctx::box or Ctx::shapes returns it) draws a picture in its own colours, a maker's mark, a logo, an
/// illustration: its colours are its owner's, as a picture's are, and the contrast rule asks nothing of them (WCAG asks
/// nothing of a logo).
pub fn Ctx::own_colours(self : Ctx, node : Int) -> Unit {
  ignore(self)
  if inst_owners.on {
    inst_owners.own_colours.add(node)
  }
}

///|
/// Whether each instance's owner is kept (`on` or `track`).
fn inst_owners_kept() -> Bool {
  inst_owners.on || inst_owners.track
}

///|
/// Instance `k` drawn by the node being painted.
fn inst_owned(k : Int) -> Unit {
  let o = inst_owners.owner
  let cl = inst_owners.cell
  while o.length() <= k {
    o.push(-1)
  }
  while cl.length() <= k {
    cl.push((0.0, 1.0))
  }
  o[k] = inst_owners.painting
  cl[k] = (0.0, 1.0)
}

///|
/// Glyph `k`'s cell across, from `x0` to `x1` where its picture is `gx` across `gw` wide (inst_owners' `cell`).
fn inst_cell(k : Int, gx : Double, gw : Double, x0 : Double, x1 : Double) -> Unit {
  if k < inst_owners.cell.length() && gw > 0.0 {
    inst_owners.cell[k] = ((x0 - gx) / gw, (x1 - gx) / gw)
  }
}

///|
/// Instance `k`'s cell (inst_owners' `cell`).
fn inst_cell_of(k : Int) -> (Double, Double) {
  if k < inst_owners.cell.length() {
    inst_owners.cell[k]
  } else {
    (0.0, 1.0)
  }
}

///|
/// The node that drew instance `k`, -1 none known.
fn inst_owner(k : Int) -> Int {
  if k < inst_owners.owner.length() {
    inst_owners.owner[k]
  } else {
    -1
  }
}

///|
/// The owners moved as Ctx::raise_tops moves the instances, `tops` (from, to) after the rest of the `count` painted.
fn inst_owners_raised(tops : Array[(Int, Int)], count : Int) -> Unit {
  let raised : Array[(Int, (Double, Double))] = []
  for r in tops {
    for q in r.0..<r.1 {
      raised.push((inst_owner(q), inst_cell_of(q)))
    }
  }
  let moved : Array[(Int, (Double, Double))] = []
  for k, r in tops {
    let end = if k + 1 < tops.length() { tops[k + 1].0 } else { count }
    for q in r.1..<end {
      moved.push((inst_owner(q), inst_cell_of(q)))
    }
  }
  let was = inst_owners.painting
  let mut to = tops[0].0
  for o in moved + raised {
    inst_owners.painting = o.0
    inst_owned(to)
    inst_owners.cell[to] = o.1
    to = to + 1
  }
  inst_owners.painting = was
}

///|
/// The least what is drawn with nothing in it stands off what it lies on (see the head): WCAG 2's contrast ratio. A
/// line (the theme's `line` on its page) is the faintest the design draws on purpose, about 1.2; a block the size of
/// a gauge's cell below that is not seen in a lit room (1.03: a station's cells in dark on its card, 2026-10-26).
pub let contrast_mark_least : Double = 1.25

///|
/// The least words stand off their ground: WCAG 2's AA, 3:1 large (24 and up, 18.66 and up bold), 4.5:1 else.
pub fn contrast_words_least(size : Double, weight : Int) -> Double {
  if size >= 24.0 || (size >= 18.66 && weight >= 700) {
    3.0
  } else {
    4.5
  }
}

///|
/// The least an icon stands off its ground: WCAG 2's non-text contrast.
pub let contrast_icon_least : Double = 3.0

///|
/// The most an icon is across: a shape drawn larger is a drawing or an outline (a card's dashed edge), held as a line.
let icon_most : Double = 48.0

///|
/// A colour's red, green and blue, 0 to 1.
priv struct Rgb {
  r : Double
  g : Double
  b : Double
}

///|
/// `top` laid over `under` at opacity `a` (as the renderers blend: in the colours as they are written).
fn Rgb::laid(under : Rgb, top : Rgb, a : Double) -> Rgb {
  { r: under.r + (top.r - under.r) * a, g: under.g + (top.g - under.g) * a, b: under.b + (top.b - under.b) * a }
}

///|
/// WCAG 2's relative luminance.
fn Rgb::luminance(self : Rgb) -> Double {
  let lin = fn(v : Double) {
    if v <= 0.04045 {
      v / 12.92
    } else {
      @dmath.pow((v + 0.055) / 1.055, 2.4)
    }
  }
  0.2126 * lin(self.r) + 0.7152 * lin(self.g) + 0.0722 * lin(self.b)
}

///|
/// WCAG 2's contrast ratio of two colours (1 to 21).
fn contrast_of(a : Rgb, b : Rgb) -> Double {
  let la = a.luminance()
  let lb = b.luminance()
  (dmax(la, lb) + 0.05) / (dmin(la, lb) + 0.05)
}

///|
/// A colour as the theme writes it (0xRRGGBBAA), its red, green and blue.
fn rgb_of(v : Int64) -> Rgb {
  {
    r: ((v >> 24) & 0xFFL).to_double() / 255.0,
    g: ((v >> 16) & 0xFFL).to_double() / 255.0,
    b: ((v >> 8) & 0xFFL).to_double() / 255.0,
  }
}

///|
/// WCAG 2's contrast ratio of two opaque colours as the theme writes them (0xRRGGBBAA), 1 to 21.
pub fn contrast_ratio(a : Int64, b : Int64) -> Double {
  contrast_of(rgb_of(a), rgb_of(b))
}

///|
/// `ink` laid over `ground` (opaque, 0xRRGGBBAA) as faintly as it is still seen on it: the least opacity, in steps of
/// 8 bits, at which it stands contrast_mark_least off, as an opaque colour. A mark that only parts what is around it (a
/// table's rules between its rows) and needs to be no more than seen.
pub fn faintest_mark(ink : Int64, ground : Int64) -> Int64 {
  let under = rgb_of(ground)
  let top = rgb_of(ink)
  let byte = fn(v : Double) { (v * 255.0).round().to_int64() }
  for step = 1; step <= 255; step = step + 1 {
    let c = under.laid(top, step.to_double() / 255.0)
    let v = (byte(c.r) << 24) | (byte(c.g) << 16) | (byte(c.b) << 8) | 0xFFL
    if contrast_ratio(v, ground) >= contrast_mark_least {
      return v
    }
  }
  ink | 0xFFL
}

///|
/// Of `inks`, the one that stands furthest off `ground` (opaque, 0xRRGGBBAA): what is said on a colour a person chose
/// (an app's picture's ground) reads on whatever they chose.
pub fn ink_on(ground : Int64, inks : Array[Int64]) -> Int64 {
  let mut best = inks[0]
  for i in inks {
    if contrast_ratio(i, ground) > contrast_ratio(best, ground) {
      best = i
    }
  }
  best
}

///|
/// Whether two colours are the same as drawn (within a step of 8 bits).
fn same_rgb(a : Rgb, b : Rgb) -> Bool {
  (a.r - b.r).abs() < 0.5 / 255.0 && (a.g - b.g).abs() < 0.5 / 255.0 && (a.b - b.b).abs() < 0.5 / 255.0
}

///|
/// `#rrggbb`.
fn Rgb::hex(self : Rgb) -> String {
  let two = fn(v : Double) {
    let n = (dmin(dmax(v, 0.0), 1.0) * 255.0).round().to_int()
    let s = n.to_string(radix=16)
    if s.length() < 2 {
      "0" + s
    } else {
      s
    }
  }
  "#" + two(self.r) + two(self.g) + two(self.b)
}

///|
/// A ratio as said: two decimals.
fn ratio_said(r : Double) -> String {
  let h = (r * 100.0).round().to_int()
  let f = h % 100
  "\{h / 100}.\{if f < 10 { "0" } else { "" }}\{f}"
}

///|
/// Instance `b`'s colour (8-10) and its opacity (11).
fn inst_rgb(a : FixedArray[Double], b : Int) -> Rgb {
  { r: a[b + 8], g: a[b + 9], b: a[b + 10] }
}

///|
/// Whether (`px`, `py`) is inside what cuts instance `b` (its clip's rect).
fn in_inst_clip(a : FixedArray[Double], b : Int, px : Double, py : Double) -> Bool {
  px >= a[b + 16] && px <= a[b + 18] && py >= a[b + 17] && py <= a[b + 19]
}

///|
/// Whether (`px`, `py`) is inside instance `b`'s rect, its corners each as round as it draws them (36-39), and inside
/// what cuts it.
fn in_inst(a : FixedArray[Double], b : Int, px : Double, py : Double) -> Bool {
  let x = a[b]
  let y = a[b + 1]
  let w = a[b + 2]
  let h = a[b + 3]
  if px < x || py < y || px > x + w || py > y + h || !in_inst_clip(a, b, px, py) {
    return false
  }
  let most = dmin(w, h) / 2.0
  let inside = fn(r : Double, cx : Double, cy : Double, left : Bool, top : Bool) {
    let r = dmin(r, most)
    let dx = if left { cx + r - px } else { px - (cx - r) }
    let dy = if top { cy + r - py } else { py - (cy - r) }
    dx <= 0.0 || dy <= 0.0 || dx * dx + dy * dy <= r * r
  }
  inside(a[b + 36], x, y, true, true) &&
  inside(a[b + 37], x + w, y, false, true) &&
  inside(a[b + 38], x + w, y + h, false, false) &&
  inside(a[b + 39], x, y + h, true, false)
}

///|
/// How instance `j` lies over (`px`, `py`) as a ground: 0 not, 1 a colour (its fill, glass's tint, a shape's filled
/// band: a badge's disc under its glyph, not `own`'s own) at an opacity, 2 a picture, a video or another app's view, its
/// colours not known here.
fn ground_kind(a : FixedArray[Double], j : Int, px : Double, py : Double, own? : Int = -1) -> (Int, Double) {
  let b = j * inst_size
  let kind = a[b + 5]
  if kind == 11.0 {
    if a[b + 4] == 0.0 && a[b + 11] > 0.002 && in_inst(a, b, px, py) && inst_owner(j) != own {
      (1, a[b + 11])
    } else {
      (0, 0.0)
    }
  } else if kind == 0.0 {
    let o = a[b + 11]
    if o > 0.002 && in_inst(a, b, px, py) {
      (1, o)
    } else {
      (0, 0.0)
    }
  } else if kind == 5.0 || kind == 6.0 {
    if in_inst(a, b, px, py) {
      (1, a[b + 11] * a[b + 15])
    } else {
      (0, 0.0)
    }
  } else if kind == 4.0 || kind == 9.0 {
    if in_inst(a, b, px, py) {
      (2, 1.0)
    } else {
      (0, 0.0)
    }
  } else {
    (0, 0.0)
  }
}

///|
/// What the frame drew at (`px`, `py`) before instance `k`: the colour there, and each colour it was on the way up
/// (the last whole one first: a sidebar's, a row's on it); None where that is a picture's, a video's or another app's
/// (or on one, with nothing whole over it).
fn Ctx::ground_under(self : Ctx, k : Int, px : Double, py : Double) -> (Rgb, Array[Rgb])? {
  let a = self.inst
  let own = inst_owner(k)
  // the last whole colour under it there, then what is laid over that
  let mut from = -1
  let mut j = k - 1
  while j >= 0 {
    let (kind, o) = ground_kind(a, j, px, py, own~)
    if kind == 2 {
      return None
    }
    if kind == 1 && o >= 0.999 {
      from = j
      break
    }
    j = j - 1
  }
  let t = if self.narrow { self.theme_narrow.unwrap_or(self.theme_wide) } else { self.theme_wide }
  let mut out = if from >= 0 {
    inst_rgb(a, from * inst_size)
  } else {
    let v = t.bg
    {
      r: ((v >> 24) & 0xFFL).to_double() / 255.0,
      g: ((v >> 16) & 0xFFL).to_double() / 255.0,
      b: ((v >> 8) & 0xFFL).to_double() / 255.0,
    }
  }
  let beneath = [out]
  for q in (from + 1)..<k {
    let (kind, o) = ground_kind(a, q, px, py, own~)
    if kind == 1 {
      out = Rgb::laid(out, inst_rgb(a, q * inst_size), o)
      beneath.push(out)
    }
  }
  Some((out, beneath))
}

///|
/// Whether instance `k` (a filled shape) is in the colour of a ground drawn whole by a node holding something (words, a
/// picture), touching it: a piece of that ground (a popover's arrow, a bubble's tail), not a mark of its own.
fn Ctx::ground_piece(self : Ctx, k : Int, holding : Array[Bool]) -> Bool {
  let a = self.inst
  let b = k * inst_size
  let ink = inst_rgb(a, b)
  for j in 0..<self.ninst {
    let q = j * inst_size
    let o = inst_owner(j)
    if j == k || a[q + 5] != 0.0 || a[q + 11] < 0.999 || o < 0 || o >= self.count || !holding[o] {
      continue
    }
    if !same_rgb(inst_rgb(a, q), ink) {
      continue
    }
    // (their rects within a pixel of each other)
    if a[b] <= a[q] + a[q + 2] + 1.0 &&
      a[q] <= a[b] + a[b + 2] + 1.0 &&
      a[b + 1] <= a[q + 1] + a[q + 3] + 1.0 &&
      a[q + 1] <= a[b + 1] + a[b + 3] + 1.0 {
      return true
    }
  }
  false
}

///|
/// Whether node `i` is `own` or in it.
fn Ctx::node_in(self : Ctx, i : Int, own : Int) -> Bool {
  let mut q = i
  while q >= 0 {
    if q == own {
      return true
    }
    q = self.nodes[q].parent
  }
  false
}

///|
/// Whether something drawn after instance `k`, not by `own` nor what is in it, lies over (`px`, `py`): what `k`
/// draws there is covered (a dialog's scrim over the page, a bar's glass over a list).
fn Ctx::covered_after(self : Ctx, k : Int, px : Double, py : Double, own : Int) -> Bool {
  let a = self.inst
  for j in (k + 1)..<self.ninst {
    let (kind, _) = ground_kind(a, j, px, py)
    if kind != 0 && !self.node_in(inst_owner(j), own) {
      return true
    }
  }
  false
}

///|
/// For each node, whether it draws words, a picture, an icon or another app's view, or holds something that does: a
/// ground with something in it, which carries it.
fn Ctx::holding(self : Ctx) -> Array[Bool] {
  let out = Array::make(self.count, false)
  for i in 0..<self.count {
    let n = self.nodes[i]
    let shows = n.kind == kind_text ||
      n.kind == kind_rich ||
      n.kind == kind_editor ||
      n.kind == kind_image ||
      n.kind == kind_native ||
      n.kind == kind_page ||
      n.shapes.length() > 0
    if shows {
      let mut q = i
      while q >= 0 && !out[q] {
        out[q] = true
        q = self.nodes[q].parent
      }
    }
  }
  out
}

///|
/// Whether instance `k` (node `own`'s) is a ground for what is drawn over it after it: words, an icon, a picture or
/// another app's view with its middle inside it (a choice's thumb under its words), or a ground or a line of what is in
/// `own` over its own middle (`px`, `py`: a ring round a dot, cut out of what lies under it; a spinner in a place kept).
fn Ctx::drawn_over(self : Ctx, k : Int, own : Int, px : Double, py : Double) -> Bool {
  let a = self.inst
  let b = k * inst_size
  for j in (k + 1)..<self.ninst {
    let q = j * inst_size
    let kind = a[q + 5]
    if kind == 1.0 || kind == 3.0 || kind == 7.0 || kind == 4.0 || kind == 9.0 || kind == 11.0 {
      let cx = a[q] + a[q + 2] / 2.0
      let cy = a[q + 1] + a[q + 3] / 2.0
      if cx >= a[b] && cx <= a[b] + a[b + 2] && cy >= a[b + 1] && cy <= a[b + 1] + a[b + 3] {
        return true
      }
    } else if kind == 0.0 && a[q + 11] > 0.002 {
      let o = inst_owner(j)
      if o != own && self.node_in(o, own) && in_inst(a, q, px, py) {
        return true
      }
    } else if kind == 10.0 {
      // (a line of what is in it over its middle: a spinner turning in a placeholder)
      let o = inst_owner(j)
      if o != own && self.node_in(o, own) && in_inst(a, q, px, py) {
        return true
      }
    }
  }
  false
}

///|
/// Where node `i` is, and the words nearest it (its own, or the first of what holds it), to find it by: ` at x,y w×h
/// by "…"`.
fn Ctx::contrast_where(self : Ctx, i : Int) -> String {
  let n = self.nodes[i]
  let at = " at \{n.x.round()},\{n.y.round()} \{n.fw.round()}×\{n.fh.round()}"
  // (the first words in it, depth first, or in what holds it, up to four boxes out)
  let words_in = fn(r : Int) -> String {
    let todo = [r]
    while todo.pop() is Some(q) {
      let m = self.nodes[q]
      if m.text != "" && (m.kind == kind_text || m.kind == kind_rich || m.kind == kind_editor) {
        return m.text
      }
      if m.label != "" {
        return m.label
      }
      let kids = []
      let mut ch = m.first
      while ch >= 0 {
        kids.push(ch)
        ch = self.nodes[ch].next
      }
      for x = kids.length() - 1; x >= 0; x = x - 1 {
        todo.push(kids[x])
      }
    }
    ""
  }
  let mut q = i
  for _ in 0..<5 {
    if q < 0 {
      break
    }
    let w = words_in(q)
    if w != "" {
      let w = if w.length() > 16 { w.unsafe_substring(start=0, end=16) + "…" } else { w }
      return at + " by \"" + w.replace_all(old="\n", new=" ") + "\""
    }
    q = self.nodes[q].parent
  }
  at
}

///|
/// Where the frame Tester::contrast_faults drew stands too faint off what it lies on (see the file's head), each once:
/// what it is and where, its colour as drawn on its ground, the ratio and the least. `marks`: the least for what has
/// nothing in it. Words are measured at their faintest letter; a line (Ctx::lines) or an icon at its strongest piece,
/// as it is seen by that (a spinner's spokes fading behind the one it is at). What is drawn in the colour of a ground
/// under it, deeper than the one it lies on, is a cut through to that ground (round a dot over a picture, in the
/// sidebar's colour), not a mark of its own.
fn Ctx::contrast_faults_drawn(self : Ctx, marks : Double) -> Array[String] {
  let a = self.inst
  let pictures = self.pictures()
  for n in inst_owners.own_colours {
    pictures.add(n)
  }
  let disabled : Set[Int] = Set::new()
  for s in self.sems {
    if s.disabled {
      disabled.add(s.node)
    }
  }
  let holding = self.holding()
  // each node's words at their faintest letter, a line's or an icon's pieces at their strongest: (ratio, what is said
  // where it is under the least)
  let lines : Map[Int, (Double, String)] = Map::new()
  let order : Array[Int] = []
  let out : Array[String] = []
  let seen : Set[String] = Set::new()
  let say = fn(s : String) {
    if !seen.contains(s) {
      seen.add(s)
      out.push(s)
    }
  }
  for k in 0..<self.ninst {
    let o = inst_owner(k)
    if o < 0 || o >= self.count {
      continue
    }
    let n = self.nodes[o]
    let b = k * inst_size
    let kind = a[b + 5]
    let is_words = kind == 1.0 &&
      (n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor)
    let is_line = kind == 10.0 || kind == 11.0 || is_words
    // (a page's bones: each is what has nothing in it, whatever drew it, bones.mbt)
    let bone = bone_insts.contains(k)
    if !(is_line || bone || (kind == 0.0 && n.kind == kind_box && !n.blocks)) {
      continue
    }
    let px = a[b] + a[b + 2] / 2.0
    let py = a[b + 1] + a[b + 3] / 2.0
    if px < 0.0 ||
      py < 0.0 ||
      px > self.window_w ||
      py > self.window_h ||
      !in_inst_clip(a, b, px, py) ||
      self.in_picture(o, pictures) ||
      (kind != 0.0 && self.in_picture(o, disabled)) {
      continue
    }
    // (a filled shape in the colour of a ground with words in it, touching it: that ground's piece, as a popover's arrow
    // is the popover's)
    if kind == 11.0 && a[b + 4] == 0.0 && self.ground_piece(k, holding) {
      continue
    }
    if is_line {
      let (ground, beneath) = match self.ground_under(k, px, py) {
        Some(g) => g
        None => continue
      }
      if self.covered_after(k, px, py, o) {
        continue
      }
      let ink = inst_rgb(a, b)
      let shown = Rgb::laid(ground, ink, a[b + 11])
      // (a cut through to a ground under it, or that ground's own colour; words are never that)
      if !is_words &&
        (same_rgb(shown, ground) || (a[b + 11] >= 0.999 && beneath.iter().any(fn(u) { same_rgb(u, ink) }))) {
        continue
      }
      let r = contrast_of(shown, ground)
      let (what, least) = if is_words {
        let text = if n.text.length() > 24 { n.text.unsafe_substring(start=0, end=24) + "…" } else { n.text }
        (
          "words \"\{text.replace_all(old="\n", new=" ")}\" \{n.font_size}/\{n.weight}",
          contrast_words_least(n.font_size, n.weight),
        )
      } else if kind == 11.0 && n.fw <= icon_most && n.fh <= icon_most {
        ("icon", contrast_icon_least)
      } else {
        ("line", marks)
      }
      let said = if r < least - 0.005 {
        "\{what}\{self.contrast_where(o)}: \{shown.hex()} on \{ground.hex()} \{ratio_said(r)}:1, under \{least}"
      } else {
        ""
      }
      match lines.get(o) {
        Some((had, _)) if (is_words && had <= r) || (!is_words && had >= r) => ()
        Some(_) => lines[o] = (r, said)
        None => {
          lines[o] = (r, said)
          order.push(o)
        }
      }
      continue
    }
    // a box with nothing in it (nothing drawn in it, nor over it after: a choice's thumb under its words holds them; a
    // ring round a dot is the dot's ground), seen by its ground or by its edge (a box to tick, white with a line round
    // it): the one that stands further off what it lies on
    if !bone && (holding[o] || self.drawn_over(k, o, px, py)) {
      continue
    }
    // (what fades out over all of itself is no mark but a ground going off: a bar's going on under it, scene.mbt 52-59)
    let over_all = fn(soft : Double, side : Double) { soft > 0.0 && soft >= side - 0.5 }
    if over_all(a[b + 53], a[b + 3]) ||
      over_all(a[b + 55], a[b + 3]) ||
      over_all(a[b + 57], a[b + 2]) ||
      over_all(a[b + 59], a[b + 2]) {
      continue
    }
    // (ratio, what is said): its ground's, its edge's (at the middle of its left side), each that shows and is not cut
    // through to a ground under it
    let mut seen : (Double, String)? = None
    let look = fn(what : String, x : Double, ink : Rgb, o2 : Double) {
      match self.ground_under(k, x, py) {
        Some((ground, beneath)) if !self.covered_after(k, x, py, o) => {
          let shown = Rgb::laid(ground, ink, o2)
          let cut = o2 >= 0.999 && beneath.iter().any(fn(u) { same_rgb(u, ink) })
          if !cut && !same_rgb(shown, ground) {
            let r = contrast_of(shown, ground)
            match seen {
              Some((had, _)) if had >= r => ()
              _ =>
                seen = Some(
                  (r, "\{what}\{self.contrast_where(o)}: \{shown.hex()} on \{ground.hex()} \{ratio_said(r)}:1, under \{marks}"),
                )
            }
          }
        }
        _ => ()
      }
    }
    if a[b + 11] > 0.002 {
      look("mark", px, inst_rgb(a, b), a[b + 11])
    }
    let ex = a[b] + a[b + 6] / 2.0
    if a[b + 6] > 0.0 && a[b + 15] > 0.002 && ex >= 0.0 && in_inst_clip(a, b, ex, py) {
      look("edge", ex, { r: a[b + 12], g: a[b + 13], b: a[b + 14] }, a[b + 15])
    }
    match seen {
      Some((r, said)) if r < marks - 0.005 => say(said)
      _ => ()
    }
  }
  for o in order {
    match lines.get(o) {
      Some((_, said)) if said != "" => say(said)
      _ => ()
    }
  }
  out
}

///|
/// Where the screen as it is now draws something too faint to be seen on what it lies on (see the file's head): a
/// frame drawn, each fault once. `marks`: the least for what has nothing in it (contrast_mark_least).
pub fn Tester::contrast_faults(self : Tester, marks? : Double = contrast_mark_least) -> Array[String] {
  let c = g()
  inst_owners.on = true
  inst_owners_clear()
  self.frame()
  inst_owners.on = false
  // (drawn as before from the next frame on, built whole: frame_watch.mbt)
  test_stepped()
  c.contrast_faults_drawn(marks)
}
