// still.fail's spacing rules, measured on the frame just built (Tester::gap_faults), as the corner rule is (corners.mbt):
// where things stand apart from each other and from the edges of what holds them. Each fault a line saying its rule,
// the boxes (Ctx::named) and by how much:
//
// 1. What lights up under the hand (a box whose look asks Ctx::lit, or is drawn selected, a shape a ground shows in)
//    stands apart from the next one that does, by the theme's `lit_apart` at least (the web's sidebar rows, `& + &`
//    2): two lit grounds side by side read as one block. Measured between their boxes, in the same layer, where they
//    share a column or a row; what holds others that light up as wide or as tall as it (a list, a rail) is where they
//    are, not one of them.
//    Not held to it: the parts of one control (in a ground of their own that hugs them: a segmented choice's
//    options), and things where nothing stays lit (no ground shown with no hand on them in what holds them: one
//    lights at a time; a list across the whole screen, a card of options).
// 3. Two blocks with grounds of their own beside each other in one box never meet (0 between them) or run over each
//    other: they stand apart, or are one block. Lines (thinner than `gap_line`) are what parts things, not a block.
// 4. What a box with a ground or an edge holds (words, a drawing, a block with a ground: a chip) stands in from its
//    edges, never touching one; and where it spans the box (in from both sides by less than a quarter of it), as far
//    in from the left as from the right where it stands in one line (a row, a button, a chip: what a box with lines
//    under lines holds stands as its column says): each end by its box, a drawing larger than an icon by its ink (a
//    file's sheet in its tile), in a capsule what stands at its ends concentric with them by their middles (a dot, a
//    tab's ×; a capsule button by its end's).
//
// 5. The blocks that show their edges (a ground, an edge, what lights up), half as wide as what they stand on at least,
//    the outermost on it, stand on the edges most of them do, whatever boxes lay them out: one off them by less than
//    a step of the scale (`gap_align_step`) juts out or falls short (a sheet's row past its others, a card short of
//    the segmented choice over it).
//
// Rules 2 (siblings of a kind equally spaced) and 6 (gaps on the scale) are still.fail's too, not measured yet.

///|
/// How thin a box is a line (a rule between rows, a progress bar's track), not a block with a ground.
let gap_line : Double = 3.0

///|
/// How small a thing that lights up may be and still be pressed by itself (an icon's button, 20; a handle to drag
/// between panes, 6, is not).
let gap_lit_least : Double = 16.0

///|
/// How far in round the parts of one control its ground may stand (a segmented choice's track, 2 round its options).
let gap_part_in : Double = 4.0

///|
/// How much of what holds it a thing that lights up spans, across or down, for that to be where such things stand (a
/// list's rows its width), not one of them (a row's buttons).
let gap_spans : Double = 0.8

///|
/// How far measured places may differ and be the same: the layout's rounding, and words' widths measured.
let gap_slack : Double = 0.5

///|
/// Where the last frame breaks the spacing rules (see the file's head): one line for each fault, its rule first.
pub fn Tester::gap_faults(self : Tester) -> Array[String] {
  ignore(self)
  g().gap_faults()
}

///|
/// Whether box `i` lights up as a ground: it asked whether the hand is on it (Ctx::lit), or is drawn selected, and it is
/// a shape a ground shows in, a ground now or its corners said while it has none (a row's, a button's). What the hand
/// changes otherwise (a timeline's track grown under the pointer, an icon's ink) lights no block.
fn Ctx::gap_lights(self : Ctx, i : Int) -> Bool {
  let b = self.nodes[i]
  b.kind == kind_box && b.id != 0 && self.lit_asked.contains(b.id) && (b.grounded() || b.radius > 0.0)
}

///|
/// Where node `i` shows, its words as wide as they are drawn (a line of words in a wider box drawn from its start, or
/// in its middle where centred): (x0, y0, x1, y1).
fn Ctx::gap_drawn(self : Ctx, i : Int) -> (Double, Double, Double, Double) {
  let b = self.nodes[i]
  match b.tl {
    Some(tl) if b.kind == kind_text && tl.w < b.fw => {
      let off = if b.center { (b.fw - tl.w) / 2.0 } else if b.rtl { b.fw - tl.w } else { 0.0 }
      (b.x + off, b.y, b.x + off + tl.w, b.y + b.fh)
    }
    _ => (b.x, b.y, b.x + b.fw, b.y + b.fh)
  }
}

///|
/// How large an icon's box is at most (one 16 or 20 in its room): its box its ink, drawn on its grid.
let gap_icon_most : Double = 24.0

///|
/// Where node `i` draws across where it is a drawing larger than an icon (gap_ink), None otherwise.
fn Ctx::gap_ink_large(self : Ctx, i : Int) -> (Double, Double)? {
  if i < 0 || dmax(self.nodes[i].fw, self.nodes[i].fh) <= gap_icon_most {
    return None
  }
  self.gap_ink(i)
}

///|
/// Where what node `i` holds draws across (x0, x1): its drawings' ink (their outlines' points, a stroke's half width
/// round them), its grounds, its pictures; None where it holds words (their room the layout's, not their ink's) or
/// draws nothing.
fn Ctx::gap_ink(self : Ctx, i : Int) -> (Double, Double)? {
  if i < 0 {
    return None
  }
  let mut x0 = 1.0e9
  let mut x1 = -1.0e9
  let todo = [i]
  while todo.pop() is Some(k) {
    let n = self.nodes[k]
    if n.opacity <= 0.01 || n.layer {
      continue
    }
    if (n.kind == kind_text || n.kind == kind_rich) && (n.text != "" || n.rich is Some(_)) {
      return None
    }
    if n.grounded() || n.kind == kind_image {
      x0 = dmin(x0, n.x)
      x1 = dmax(x1, n.x + n.fw)
    }
    for sh in n.shapes {
      let half = if sh.stroke != 0L { sh.width / 2.0 } else { 0.0 }
      for o in sh.outlines {
        let pts = o.0
        let mut j = 0
        while j + 1 < pts.length() {
          x0 = dmin(x0, n.x + pts[j] - half)
          x1 = dmax(x1, n.x + pts[j] + half)
          j += 2
        }
      }
    }
    for ln in n.lines {
      for pt in ln.points {
        x0 = dmin(x0, n.x + pt.0 - ln.width / 2.0)
        x1 = dmax(x1, n.x + pt.0 + ln.width / 2.0)
      }
    }
    let mut ch = n.first
    while ch >= 0 {
      todo.push(ch)
      ch = self.nodes[ch].next
    }
  }
  if x0 < x1 {
    Some((x0, x1))
  } else {
    None
  }
}

///|
/// Whether node `i` draws words, a drawing of its own (an icon) or a block with a ground (a chip, a tag): what rule 4
/// holds in from the edges of the box with a ground round it.
fn Node::gap_content(self : Node) -> Bool {
  if self.fw <= 0.0 || self.fh <= 0.0 {
    return false
  }
  if self.kind == kind_text || self.kind == kind_rich {
    self.text != "" || self.rich is Some(_)
  } else if self.kind == kind_box && self.grounded() {
    // a block with a ground of its own in it (a chip, a tag), not a line parting things
    dmin(self.fw, self.fh) >= gap_line
  } else {
    self.kind == kind_box && (self.shapes.length() > 0 || self.lines.length() > 0)
  }
}

///|
/// How far apart two boxes stand where they share a column or a row (below 0: over each other), and which way:
/// None where they share neither (one off the other's corner) or one holds the other.
fn gap_between(
  a : (Double, Double, Double, Double),
  b : (Double, Double, Double, Double),
) -> (Double, Bool)? {
  let (ax0, ay0, ax1, ay1) = a
  let (bx0, by0, bx1, by1) = b
  let holds = fn(o : (Double, Double, Double, Double), n : (Double, Double, Double, Double)) {
    n.0 >= o.0 - gap_slack && n.1 >= o.1 - gap_slack && n.2 <= o.2 + gap_slack && n.3 <= o.3 + gap_slack
  }
  if holds(a, b) || holds(b, a) {
    return None
  }
  let ox = dmin(ax1, bx1) - dmax(ax0, bx0)
  let oy = dmin(ay1, by1) - dmax(ay0, by0)
  if ox > gap_slack && oy > gap_slack {
    // over each other: by the lesser
    Some((-dmin(ox, oy), oy < ox))
  } else if ox > gap_slack {
    Some((-oy, true))
  } else if oy > gap_slack {
    Some((-ox, false))
  } else {
    None
  }
}

///|
fn Ctx::gap_faults(self : Ctx) -> Array[String] {
  let out : Array[String] = []
  let n = self.count
  let pictures = self.pictures()
  // (a node's parent comes before it in the pool) whether each shows whole: drawn, not moved off its place, in the
  // window and in what cuts it (a row scrolled half under a list's edge is measured nowhere); the layer it is in (a
  // layer, a page of a pager, one put where it is said, over the whole window: what lies over another on purpose)
  let whole = Array::make(n, false)
  let layer = Array::make(n, -1)
  for i in 0..<n {
    let b = self.nodes[i]
    let p = b.parent
    let inside = b.x >= -gap_slack &&
      b.y >= -gap_slack &&
      b.x + b.fw <= self.width + gap_slack &&
      b.y + b.fh <= self.height + gap_slack
    let aside = b.layer || b.portal || b.pager != 0 || b.placed_at()
    let moved = b.tx != 0.0 || b.ty != 0.0 || b.slide != 0.0
    if p < 0 || p >= n {
      whole[i] = b.opacity > 0.01 && inside && !moved
      layer[i] = i
    } else {
      let a = self.nodes[p]
      let cut_in = !a.squeeze_cuts() ||
        (
          b.x >= a.x - gap_slack &&
          b.y >= a.y - gap_slack &&
          b.x + b.fw <= a.x + a.fw + gap_slack &&
          b.y + b.fh <= a.y + a.fh + gap_slack
        )
      whole[i] = whole[p] && b.opacity > 0.01 && inside && !moved && cut_in && !a.sideways
      layer[i] = if aside { i } else { layer[p] }
    }
  }
  let rect = fn(i : Int) {
    let b = self.nodes[i]
    (b.x, b.y, b.x + b.fw, b.y + b.fh)
  }
  // 1. what lights up, apart
  if self.lit_apart > 0.0 {
    let lit : Array[Int] = []
    for i in 0..<n {
      if whole[i] && self.gap_lights(i) && self.nodes[i].fw > 0.0 && self.nodes[i].fh > 0.0 {
        lit.push(i)
      }
    }
    // (what holds others that light up as wide as it or as tall is where they stand, a list, a rail, a pane, not one
    // of them: a row holding its small buttons is a row; nor what is too small to be pressed by itself, a handle to
    // drag between panes)
    let holds = fn(o : Int, i : Int) {
      let a = self.nodes[o]
      let b = self.nodes[i]
      b.x >= a.x - gap_slack &&
      b.y >= a.y - gap_slack &&
      b.x + b.fw <= a.x + a.fw + gap_slack &&
      b.y + b.fh <= a.y + a.fh + gap_slack &&
      (b.fw >= a.fw * gap_spans || b.fh >= a.fh * gap_spans)
    }
    let lit = lit.filter(fn(o) {
      dmin(self.nodes[o].fw, self.nodes[o].fh) >= gap_lit_least &&
      !lit.iter().any(fn(i) { i != o && layer[i] == layer[o] && holds(o, i) })
    })
    // (the parts of one control: what lights up in a ground that is theirs alone, as large as they are with its few in
    // round them, a segmented choice's options in its track: one thing, its parts edge to edge on purpose, what is
    // chosen shown by its thumb)
    let ground_of : Map[Int, Int] = {}
    let parts : Map[Int, (Double, Double, Double, Double)] = {}
    for i in lit {
      let mut q = self.nodes[i].parent
      while q >= 0 && layer[q] == layer[i] && !self.nodes[q].grounded() {
        q = self.nodes[q].parent
      }
      if q >= 0 && layer[q] == layer[i] {
        ground_of[i] = q
        let b = self.nodes[i]
        parts[q] = match parts.get(q) {
          Some((x0, y0, x1, y1)) => (dmin(x0, b.x), dmin(y0, b.y), dmax(x1, b.x + b.fw), dmax(y1, b.y + b.fh))
          None => (b.x, b.y, b.x + b.fw, b.y + b.fh)
        }
      }
    }
    let one_control = fn(a : Int, b : Int) {
      match (ground_of.get(a), ground_of.get(b)) {
        (Some(ga), Some(gb)) if ga == gb =>
          match parts.get(ga) {
            Some((x0, y0, x1, y1)) => {
              let g = self.nodes[ga]
              x0 - g.x <= gap_part_in &&
              y0 - g.y <= gap_part_in &&
              g.x + g.fw - x1 <= gap_part_in &&
              g.y + g.fh - y1 <= gap_part_in
            }
            None => false
          }
        _ => false
      }
    }
    // (where nothing stays lit, one lights at a time, pressed or pointed at, and never reads as one block with
    // another: two count where one of them, or another of theirs that lights up (parting from them where they part),
    // shows its ground with
    // no hand on it (the frame is drawn with none): kept lit, the page in view's row, the one chosen. A list across
    // the whole screen opens what is pressed over itself and keeps none (the app's ListAt's Whole: a phone's chats); a
    // card of options shows the one chosen otherwise)
    let within = fn(i : Int, o : Int) {
      let mut q = i
      while q >= 0 && q != o {
        q = self.nodes[q].parent
      }
      q == o
    }
    // (kept: its ground with no hand on it, and not where the hand moves the choice, the one chosen following the
    // pointer: one lit at a time)
    let kept = lit.filter(fn(i) { self.nodes[i].grounded() && !self.hand_chooses.contains(self.nodes[i].id) })
    // (what holds both, the nearest; one kept lit is of theirs where it parts from them there and is of their kind, in
    // their column as wide or in their line as high: a row of their list, not a tool or a filter kept on over it)
    let holder = fn(a : Int, b : Int) {
      let mut o = self.nodes[a].parent
      while o >= 0 && !within(b, o) {
        o = self.nodes[o].parent
      }
      o
    }
    let kept_by = fn(a : Int, b : Int) -> Int? {
      let o = holder(a, b)
      if o < 0 {
        return None
      }
      // (of their kind: in their column as wide, or in their line as high, as one of them is)
      let like = fn(k : Int, i : Int) {
        let kn = self.nodes[k]
        let n = self.nodes[i]
        ((kn.x - n.x).abs() <= gap_slack && (kn.fw - n.fw).abs() <= gap_slack) ||
        ((kn.y - n.y).abs() <= gap_slack && (kn.fh - n.fh).abs() <= gap_slack)
      }
      kept
      .iter()
      .find_first(fn(k) {
        k == a || k == b || (within(k, o) && holder(a, k) == o && (like(k, a) || like(k, b)))
      })
    }
    for x in 0..<lit.length() {
      for y in (x + 1)..<lit.length() {
        let (a, b) = (lit[x], lit[y])
        let by = match kept_by(a, b) {
          Some(k) => k
          None => continue
        }
        if layer[a] != layer[b] || one_control(a, b) {
          continue
        }
        match gap_between(rect(a), rect(b)) {
          Some((d, _)) if d < self.lit_apart - gap_slack =>
            out.push(
              "rule 1: \{self.named(a)} and \{self.named(b)} light up \{d} apart (\{self.lit_apart} at least; kept lit: \{self.named(by)})",
            )
          _ => ()
        }
      }
    }
  }
  // 3. blocks beside each other in a box, apart
  for i in 0..<n {
    let p = self.nodes[i]
    if p.kind != kind_box || p.first < 0 || !whole[i] {
      continue
    }
    let blocks : Array[Int] = []
    let mut k = p.first
    while k >= 0 {
      let ch = self.nodes[k]
      if whole[k] &&
        layer[k] == layer[i] &&
        ch.grounded() &&
        dmin(ch.fw, ch.fh) >= gap_line &&
        ch.mar_l >= 0.0 &&
        ch.mar_t >= 0.0 &&
        !self.in_picture(k, pictures) {
        blocks.push(k)
      }
      k = ch.next
    }
    for x in 0..<blocks.length() {
      for y in (x + 1)..<blocks.length() {
        let (a, b) = (blocks[x], blocks[y])
        match gap_between(rect(a), rect(b)) {
          Some((d, _)) if d < gap_slack => {
            let how = if d < -gap_slack { "run \{-d} over each other" } else { "meet" }
            out.push("rule 3: \{self.named(a)} and \{self.named(b)} \{how}, in \{self.named(i)}")
          }
          _ => ()
        }
      }
    }
  }
  // 4. what a box with a ground holds, in from its edges and as far from both sides: each content's box, the nearest
  // grounded one round it
  let held : Map[Int, Array[Int]] = Map::new()
  for i in 0..<n {
    let c = self.nodes[i]
    if !whole[i] || !c.gap_content() || self.in_picture(i, pictures) {
      continue
    }
    let mut q = c.parent
    while q >= 0 {
      let a = self.nodes[q]
      if layer[q] != layer[i] {
        break
      }
      if a.grounded() && dmin(a.fw, a.fh) >= 2.0 * gap_line {
        // (a block of its own is held in it only as a part of what it holds, a chip, a tag: not a band across it, a
        // pane, a card of a page's, what lies along its edges by what it is)
        if c.kind == kind_box && c.grounded() && (c.fw >= a.fw * gap_spans || c.fh >= a.fh * gap_spans) {
          break
        }
        match held.get(q) {
          Some(list) => list.push(i)
          None => held[q] = [i]
        }
        break
      }
      q = a.parent
    }
  }
  for entry in held {
    let (gi, kids) = entry
    let gb = self.nodes[gi]
    if !whole[gi] {
      continue
    }
    let mut y0 = 1.0e9
    let mut y1 = -1.0e9
    let mut tallest = 0.0
    let touched : Array[String] = []
    for k in kids {
      let (cx0, cy0, cx1, cy1) = self.gap_drawn(k)
      // (a drawing as large as the ground it is on is drawn on it, a mark's ring or tick, not held in it)
      let kn = self.nodes[k]
      if (kn.x - gb.x).abs() <= gap_slack &&
        (kn.y - gb.y).abs() <= gap_slack &&
        (kn.fw - gb.fw).abs() <= gap_slack &&
        (kn.fh - gb.fh).abs() <= gap_slack {
        continue
      }
      y0 = dmin(y0, cy0)
      y1 = dmax(y1, cy1)
      tallest = dmax(tallest, cy1 - cy0)
      let words = self.nodes[k].kind != kind_box
      let l = cx0 - gb.x
      let r = gb.x + gb.fw - cx1
      let t = cy0 - gb.y
      let d = gb.y + gb.fh - cy1
      // (words' boxes are their lines', whose height has room over and under the letters: only their sides)
      let sides = if words {
        [("left", l), ("right", r)]
      } else {
        [("left", l), ("right", r), ("top", t), ("foot", d)]
      }
      for s in sides {
        if s.1 < gap_slack {
          touched.push("\{self.named(k)} \{s.1} from its \{s.0}")
        }
      }
    }
    if touched.length() > 0 {
      out.push("rule 4: in \{self.named(gi)}, " + touched.join("; "))
      continue
    }
    // (as far in from both sides: what it lays out in its line, its children's boxes, each holding its own as it
    // says, words in the middle of a segment, an icon in its button's room)
    let mut bx0 = 1.0e9
    let mut bx1 = -1.0e9
    let mut first = -1
    let mut last = -1
    let mut k = gb.first
    while k >= 0 {
      let ch = self.nodes[k]
      if whole[k] && layer[k] == layer[gi] && ch.fw > 0.0 && ch.fh > 0.0 {
        if ch.x < bx0 {
          first = k
        }
        if ch.x + ch.fw > bx1 {
          last = k
        }
        bx0 = dmin(bx0, ch.x)
        bx1 = dmax(bx1, ch.x + ch.fw)
      }
      k = ch.next
    }
    // (in a capsule what stands at its ends stands concentric with them, each its own size: one no wider than the
    // capsule is high by its middle (a tab's mark and its ×, a dot), a capsule of its own by its end's (a button 6 in
    // from the end of a 44 bar, 32 high: 22, as a dot's 18 + 4); as far from both by those)
    let capsule = gb.corner() >= gb.fh / 2.0 - gap_slack
    let end_mid = fn(i : Int, left : Bool) -> Double? {
      if i < 0 {
        return None
      }
      let n = self.nodes[i]
      let inset = if left { n.x - gb.x } else { gb.x + gb.fw - (n.x + n.fw) }
      if n.fw <= gb.fh + gap_slack {
        Some(inset + n.fw / 2.0)
      } else if n.corner() >= n.fh / 2.0 - gap_slack {
        Some(inset + n.fh / 2.0)
      } else {
        None
      }
    }
    // (else each end where its box is; a drawing larger than an icon where it draws, not the room round it (a file's
    // sheet drawn 2.75 in its tile): an icon's box is its ink, drawn on its grid)
    let (l, r) = if capsule && end_mid(first, true) is Some(a) && end_mid(last, false) is Some(b) {
      (a, b)
    } else {
      let x0 = match self.gap_ink_large(first) {
        Some((ix0, _)) => ix0
        None => bx0
      }
      let x1 = match self.gap_ink_large(last) {
        Some((_, ix1)) => ix1
        None => bx1
      }
      (x0 - gb.x, gb.x + gb.fw - x1)
    }
    let one_line = y1 - y0 <= tallest + gap_slack
    if bx0 < bx1 && one_line && l < gb.fw / 4.0 && r < gb.fw / 4.0 && (l - r).abs() > 2.0 * gap_slack {
      out.push("rule 4: what \{self.named(gi)} holds stands \{l} in from its left, \{r} from its right")
    }
  }
  // 5. one column's blocks aligned: the blocks that show their edges (a ground, an edge, what lights up) half as wide
  // as what they stand on at least (its ground, the nearest; the layer's where none), whatever boxes lay them out (a
  // page's head and its cards, a sheet's rows), stand on the same left and right edges as the most of them (no two
  // alike: the widest's); one a little off them (more than the layout's rounding, less than a step of the scale) juts
  // out or falls short
  let groups : Map[Int, Array[Int]] = {}
  // (a box grounded by a layer of its size under it, a card drawn so, is grounded as one with its own: by that ground)
  let laid = self.layer_grounds()
  let ground_of = fn(k : Int) -> Int? {
    if self.nodes[k].grounded() {
      Some(k)
    } else {
      laid.get(k)
    }
  }
  for k in 0..<n {
    let b = self.nodes[k]
    if !whole[k] || b.kind != kind_box || b.squeeze_aside() || !(ground_of(k) is Some(_) || self.gap_lights(k)) {
      continue
    }
    let mut q = b.parent
    while q >= 0 && layer[q] == layer[k] && ground_of(q) is None {
      q = self.nodes[q].parent
    }
    let on = if q >= 0 && layer[q] == layer[k] { q } else { layer[k] }
    let w = if on >= 0 { self.nodes[on].fw } else { self.width }
    if b.fw < w / 2.0 || dmin(b.fw, b.fh) < gap_line {
      continue
    }
    // (a ground the colour of what it stands on, no edge round it, shows no edges: a head on the page's ground)
    match (ground_of(k), if on >= 0 { ground_of(on) } else { None }) {
      (Some(gk), Some(go)) if !self.gap_lights(k) => {
        let a = self.nodes[gk]
        if a.bg == self.nodes[go].bg && !(a.border_w > 0.0 && (a.border_c & 0xFFL) != 0L) {
          continue
        }
      }
      _ => ()
    }
    match groups.get(on) {
      Some(list) => list.push(k)
      None => groups[on] = [k]
    }
  }
  for entry in groups {
    let (on, all) = entry
    // (what one of them holds is laid by it, not beside it: only the outermost)
    let within = fn(i : Int, o : Int) {
      let mut q = self.nodes[i].parent
      while q >= 0 && q != o {
        q = self.nodes[q].parent
      }
      q == o
    }
    let outer = all.filter(fn(k) { !all.iter().any(fn(o) { o != k && within(k, o) }) })
    // (a band across all of it, edge to edge, a bar, is not in its column; nor one as wide as what it holds, far
    // narrower than the column's widest (a bubble, a card hugging its words): only what the column lays out across)
    let g = self.nodes[on]
    let band = fn(k : Int) {
      let b = self.nodes[k]
      (b.x - g.x).abs() <= gap_slack && (b.x + b.fw - g.x - g.fw).abs() <= gap_slack
    }
    let mut widest = 0.0
    for k in outer {
      if !band(k) {
        widest = dmax(widest, self.nodes[k].fw)
      }
    }
    let blocks = outer.filter(fn(k) { !band(k) && self.nodes[k].fw >= widest - 2.0 * gap_align_step })
    if blocks.length() < 2 {
      continue
    }
    for side in [0, 1] {
      let at = fn(k : Int) {
        let b = self.nodes[k]
        if side == 0 { b.x } else { b.x + b.fw }
      }
      let mut best = at(blocks[0])
      let mut most = 0
      for k in blocks {
        let here = blocks.filter(fn(o) { (at(o) - at(k)).abs() <= gap_slack }).length()
        if here > most {
          most = here
          best = at(k)
        }
      }
      // (no two on one edge: the widest's, the one what is in the column is laid by)
      if most < 2 {
        let mut wide = blocks[0]
        for k in blocks {
          if self.nodes[k].fw > self.nodes[wide].fw {
            wide = k
          }
        }
        best = at(wide)
      }
      for k in blocks {
        let d = at(k) - best
        if d.abs() > gap_slack && d.abs() < gap_align_step {
          let how = if (side == 0) == (d < 0.0) { "juts out" } else { "falls short" }
          let which = if side == 0 { "left" } else { "right" }
          out.push("rule 5: \{self.named(k)} \{how} \{d.abs()} at its \{which} of the others' edge, on \{self.named(on)}")
        }
      }
    }
  }
  out
}

///|
/// How far apart two edges of a column are on purpose at least (an indent, a step of the scale): nearer, they were
/// meant to be one.
let gap_align_step : Double = 16.0


