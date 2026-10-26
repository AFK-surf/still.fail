// Bones (a skeleton): what is waited on, drawn as it will be. A page draws what it will show, made of made-up words
// (its rows, its cards, its messages: by the same parts it draws them with when they come) inside Ctx::bones, and it
// is drawn as its bones: its words a bar on each of their lines, as long as the line, in its middle, `bone_share` of
// their size high, round; its pictures, icons and drawings a shape where they are (a dot where they are an icon's
// size, else their box a little round), in the bones' one colour; its grounds and edges (a card, a bubble, a field)
// as they are, so the outline is the page's own wherever its parts change, but a ground that says something by its
// colour (an accent, a state's tint, someone's colour, an ink: bone_ground) in the bones' colour too. What says it is one
// piece (Ctx::bone_whole: a picture of someone, a chip, a button) is a shape of its own box, in its own corners,
// nothing in it drawn. Nothing in them is pressed, pointed at, read out or found by a test's words: none of it is
// there yet.

///|
/// How high a line's bar is, of its words' size: about as high as a line of them is inked (a Chinese line's, a Latin
/// line's capitals).
pub let bone_share : Double = 0.8

///|
/// `body` built in its bones (see the head), in `color` (what has nothing in it is drawn in: a theme's line).
pub fn Ctx::bones(self : Ctx, color : Int64, body : () -> Unit) -> Unit {
  let was = self.bones
  self.bones = color
  self.hidden_from_semantics(body)
  self.bones = was
}

///|
/// Whether what is built now is built in its bones (Ctx::bones): what it does is not done (nothing is asked of the
/// core for it, nothing is opened, nothing moves on its own).
pub fn Ctx::in_bones(self : Ctx) -> Bool {
  self.bones != 0L
}

///|
/// Node `node` (as Ctx::box returns it), built in bones, drawn as one piece: its own box in its corners, nothing in
/// it drawn (a picture of someone with their initial on it, a chip, a button). Elsewhere nothing.
pub fn Ctx::bone_whole(self : Ctx, node : Int) -> Unit {
  if node >= 0 && node < self.count && self.nodes[node].bones != 0L {
    self.nodes[node].bone_whole = true
  }
}

///|
/// The instances drawn as bones, while a test asks (contrast.mbt: each is measured as what has nothing in it).
// kept across runs: emptied each time a test asks again (inst_owners_clear)
let bone_insts : Set[Int] = Set::new()

///|
/// A bone drawn: (`x`, `y`) `w` × `h`, `r` round, in `color`.
fn Ctx::emit_bone(
  self : Ctx,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  r : Double,
  color : Int64,
  alpha : Double,
) -> Unit {
  if w <= 0.0 || h <= 0.0 {
    return
  }
  self.emit_rect(x, y, w, h, r, color, 0.0, 0L, alpha)
  if inst_owners.on {
    bone_insts.add(self.ninst - 1)
  }
}

///|
/// A line of words' bar: from `x0` to `x1`, in the middle of the line from `top`, `line_h` high, its words `size`.
fn Ctx::emit_bone_line(
  self : Ctx,
  x0 : Double,
  x1 : Double,
  top : Double,
  line_h : Double,
  size : Double,
  color : Int64,
  alpha : Double,
) -> Unit {
  let h = dmin((size * bone_share).round(), line_h)
  self.emit_bone(x0, top + (line_h - h) / 2.0, x1 - x0, h, h / 2.0, color, alpha)
}

///|
/// Node `n`'s words (`tl`, as laid out at `ox`, `oy`, each line moved right by `dx(line)`) as their bones: a bar on
/// each line from its first letter to its last, inside the clip [cy0, cy1].
fn Ctx::paint_bone_text(
  self : Ctx,
  n : Node,
  tl : TextLayout,
  ox : Double,
  oy : Double,
  dx : (Int) -> Double,
  alpha : Double,
) -> Unit {
  let s = tl.shaped
  let k = clip_top()
  let cy0 = clip_stack[k + 1]
  let cy1 = clip_stack[k + 3]
  for l in 0..<tl.line_start.length() {
    let top = oy + l.to_double() * tl.line_h
    if top > cy1 || top + tl.line_h < cy0 {
      continue
    }
    let mut first = -1
    let mut last = -1
    for c in tl.line_start[l]..<tl.line_end[l] {
      if c < s.cu.length() && !run_space(s.cu[c]) {
        if first < 0 {
          first = c
        }
        last = c
      }
    }
    if first < 0 {
      continue
    }
    let x = ox + dx(l) + s.pad
    self.emit_bone_line(
      x + tl.xs[first],
      x + tl.xs[last] + s.adv[last] - 2.0 * s.pad,
      top,
      tl.line_h,
      n.font_size,
      n.bones,
      alpha,
    )
  }
}

///|
/// Rich words (`lay`, as laid out at `ox`, `oy`) as their bones: a bar on each line, its words' size its first run's.
fn Ctx::paint_bone_rich(self : Ctx, n : Node, lay : RichLayout, ox : Double, oy : Double, alpha : Double) -> Unit {
  let k = clip_top()
  let cy0 = clip_stack[k + 1]
  let cy1 = clip_stack[k + 3]
  for l in 0..<lay.line_start.length() {
    let top = oy + lay.line_y[l]
    if top > cy1 || top + lay.line_h[l] < cy0 {
      continue
    }
    let mut first = -1
    let mut last = -1
    for c in lay.line_start[l]..<lay.line_end[l] {
      if c < lay.cu.length() && !run_space(lay.cu[c]) {
        if first < 0 {
          first = c
        }
        last = c
      }
    }
    if first < 0 {
      continue
    }
    let (x0, x1) = lay.span_x(first, last + 1)
    let run = lay.run_of[first]
    let size = if run >= 0 && run < lay.run_size.length() { lay.run_size[run] } else { n.font_size }
    self.emit_bone_line(ox + x0 + lay.pre[first], ox + x1, top, lay.line_h[l], size, n.bones, alpha)
  }
}

///|
/// The most an icon is across as a bone: a shape that big or smaller is a dot of it; a larger one (a drawing, a chart)
/// keeps its box with corners `bone_drawing_r` round.
let bone_icon_most : Double = 24.0

///|
let bone_drawing_r : Double = 8.0

///|
/// A picture, an icon or a drawing (node `n`) as its bone: its box in its own corners where it has them, else a dot (an
/// icon) or a box with its corners a little round (a drawing).
fn Ctx::paint_bone_shape(self : Ctx, n : Node, alpha : Double) -> Unit {
  let short = dmin(n.fw, n.fh)
  let r = if n.radius > 0.0 {
    dmin(n.radius, short / 2.0)
  } else if dmax(n.fw, n.fh) <= bone_icon_most {
    short / 2.0
  } else {
    dmin(bone_drawing_r, short / 2.0)
  }
  self.emit_bone(n.x, n.y, n.fw, n.fh, r, n.bones, alpha)
  self.corners_last(n)
}

///|
/// What node `i` (`n`, built in a page's bones) holds of its own drawn as its bones: its words a bar on each line, a
/// picture or another app's view its shape. A box's, nothing (what is in it is drawn in turn).
fn Ctx::paint_bones_of(self : Ctx, i : Int, n : Node, alpha : Double) -> Unit {
  ignore(i)
  if n.kind == kind_text {
    match n.tl {
      Some(tl) => {
        let room = dmax(n.fw - n.pad_l - n.pad_r, 0.0)
        self.paint_bone_text(n, tl, n.x + n.pad_l, n.y + n.pad_t, fn(line) {
          if n.center && line < tl.line_w.length() {
            dmax((room - tl.line_w[line]) / 2.0, 0.0)
          } else {
            0.0
          }
        }, alpha)
      }
      None => ()
    }
  } else if n.kind == kind_rich {
    match n.rich_layout(dmax(n.fw - n.pad_l - n.pad_r, 0.0)) {
      Some(lay) => self.paint_bone_rich(n, lay, n.x + n.pad_l, n.y + n.pad_t, alpha)
      None => ()
    }
  } else if n.kind == kind_image || n.kind == kind_native || n.kind == kind_page {
    self.paint_bone_shape(n, alpha)
  }
}

///|
/// How saturated a ground may be and still be the page's outline in its bones (a card's, a bubble's, a field's, of the
/// greys a page is made of: the warmest, a row picked, about 0.22); and how far off the page it may stand (its surfaces
/// a step off it, about 1.2). One more so says something of what is in it (an accent, a state's tint, someone's colour,
/// the ink of a button or of a share's bar) and is drawn in the bones' colour, as what it says is not there yet.
let bone_grey_most : Double = 0.3

///|
let bone_off_page_most : Double = 1.5

///|
/// A ground or an edge of colour `c` as a page's bones draw it (`bones` their colour): its own where it is one of the
/// surfaces a page is made of (bone_grey_most, bone_off_page_most), else theirs.
fn Ctx::bone_ground(self : Ctx, c : Int64, bones : Int64) -> Int64 {
  if (c & 0xFFL) == 0L {
    return c
  }
  let r = ((c >> 24) & 0xFFL).to_double()
  let g = ((c >> 16) & 0xFFL).to_double()
  let b = ((c >> 8) & 0xFFL).to_double()
  let most = dmax(r, dmax(g, b))
  let least = dmin(r, dmin(g, b))
  // (HSL's saturation)
  let sum = most + least
  let saturation = if most == least {
    0.0
  } else if sum <= 255.0 {
    (most - least) / sum
  } else {
    (most - least) / (510.0 - sum)
  }
  // (as it shows on the page)
  let t = if self.narrow { self.theme_narrow.unwrap_or(self.theme_wide) } else { self.theme_wide }
  let page = rgb_of(t.bg)
  let shown = Rgb::laid(page, rgb_of(c), (c & 0xFFL).to_double() / 255.0)
  if saturation > bone_grey_most || contrast_of(shown, page) > bone_off_page_most {
    bones
  } else {
    c
  }
}
