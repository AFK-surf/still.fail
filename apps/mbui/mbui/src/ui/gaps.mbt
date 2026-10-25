// still.fail's spacing rules, measured on the frame just built (Tester::gap_faults), as the corner rule is (corners.mbt):
// where things stand apart from each other and from the edges of what holds them. Each fault a line saying its rule,
// the boxes (Ctx::named) and by how much:
//
// 1. What lights up under the hand (a box whose look asks Ctx::lit, or is drawn selected) stands apart from the next
//    one that does, by the theme's `lit_apart` at least (the web's sidebar rows, `& + &` 2): two lit grounds side by
//    side read as one block. Measured between their boxes, in the same layer, where they share a column or a row;
//    what holds others that light up as wide or as tall as it (a list, a rail) is where they are, not one of them.
//    Not held to it: the parts of one control (in a ground of their own that hugs them: a segmented choice's
//    options), and rows across the whole window (a list there keeps nothing lit: one lights at a time).
// 3. Two blocks with grounds of their own beside each other in one box never meet (0 between them) or run over each
//    other: they stand apart, or are one block. Lines (thinner than `gap_line`) are what parts things, not a block.
// 4. What a box with a ground or an edge holds (words, a drawing) stands in from its edges, never touching one; and
//    where it spans the box (in from both sides by less than a quarter of it), as far in from the left as from the
//    right (its children's boxes) where they stand in one line (a row, a button, a chip: what a box with lines under lines holds stands as
//    its column says).
//
// Rules 2 (siblings of a kind equally spaced), 5 (one column's things aligned) and 6 (gaps on the scale) are still.fail's
// too, not measured yet.

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
/// What a box laid out `n` says it lights up as: it asked whether the hand is on it (Ctx::lit), or is drawn selected.
fn Ctx::gap_lights(self : Ctx, i : Int) -> Bool {
  let b = self.nodes[i]
  b.kind == kind_box && b.id != 0 && self.lit_asked.contains(b.id)
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
/// Whether node `i` draws words or a drawing of its own (an icon), what rule 4 holds in from its box's edges.
fn Node::gap_content(self : Node) -> Bool {
  if self.fw <= 0.0 || self.fh <= 0.0 {
    return false
  }
  if self.kind == kind_text || self.kind == kind_rich {
    self.text != "" || self.rich is Some(_)
  } else {
    self.kind == kind_box && !self.grounded() && (self.shapes.length() > 0 || self.lines.length() > 0)
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
    // (rows across the whole window: a list there opens what is pressed over itself, so nothing in it stays lit; one
    // lights at a time, pressed or pointed at, and never reads as one block with another: the app's lists across the
    // whole screen, ListAt's Whole)
    let across = fn(i : Int) {
      let b = self.nodes[i]
      b.x <= gap_slack && b.x + b.fw >= self.width - gap_slack
    }
    for x in 0..<lit.length() {
      for y in (x + 1)..<lit.length() {
        let (a, b) = (lit[x], lit[y])
        if layer[a] != layer[b] || one_control(a, b) || (across(a) && across(b)) {
          continue
        }
        match gap_between(rect(a), rect(b)) {
          Some((d, _)) if d < self.lit_apart - gap_slack =>
            out.push(
              "rule 1: \{self.named(a)} and \{self.named(b)} light up \{d} apart (\{self.lit_apart} at least)",
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
    let mut k = gb.first
    while k >= 0 {
      let ch = self.nodes[k]
      if whole[k] && layer[k] == layer[gi] && ch.fw > 0.0 && ch.fh > 0.0 {
        bx0 = dmin(bx0, ch.x)
        bx1 = dmax(bx1, ch.x + ch.fw)
      }
      k = ch.next
    }
    let l = bx0 - gb.x
    let r = gb.x + gb.fw - bx1
    let one_line = y1 - y0 <= tallest + gap_slack
    if bx0 < bx1 && one_line && l < gb.fw / 4.0 && r < gb.fw / 4.0 && (l - r).abs() > 2.0 * gap_slack {
      out.push("rule 4: what \{self.named(gi)} holds stands \{l} in from its left, \{r} from its right")
    }
  }
  out
}
