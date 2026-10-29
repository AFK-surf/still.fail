// Painting: the laid-out tree becomes a flat list of instances (60 floats
// each) that every renderer draws with one shader:
//   0-3 rect x y w h · 4 radius (a box's: the roundest of its corners,
//   36-39) · 5 kind · 6 border width · 7 blur
//   8-11 color rgba · 12-15 border color, or the glyph's atlas rect
//   16-19 clip x0 y0 x1 y1 · 20 image id · 21-23 a notch in its top edge
//   (kinds 0 and 5: its circle's middle below the top, its radius, its
//   fillets'; 0 none: Ctx::box notch_r) · 24-27 the clip's corners' radii
//   (top left, top right, bottom right, bottom left: 16-19 is a rounded rect)
//   · 28-31 how smooth those corners are (smooth.mbt: 0 round, 1 wholly
//   smooth; as the box whose corner it is had room for). A shape's own
//   corner is as smooth as its rect has room for: the renderers say.
//   · 32-35 how it is turned (a look's `rot`: draw.mbt): by 32 radians,
//   clockwise on the screen, about the point 33, 34; everything else above
//   (its rect, its clip) as before it is turned, the renderers turning
//   where it is drawn and nothing of how; 35 1: its clip is not turned
//   (one from outside what turned: where it is drawn). · 36-39 a box's
//   corners' radii (kinds 0, 2, 4, 5, 9: top left, top right, bottom right,
//   bottom left, each as smooth as its rect has room for; all 4 where they
//   are one). · 40-51 the rounded clip outside its own that its own cuts
//   through (clip_stack: a pane round an image's rounded frame scrolled into
//   its corner): its rect x0 y0 x1 y1 (40-43), its corners' radii (44-47)
//   and how smooth each is (48-51), as 16-19 and 24-31; none where 44-47 are
//   all 0. What it covers is both clips' cover. · 52-55 where it fades out
//   towards a cut softly (draw.mbt, Ctx::cut_to_top/bottom `soft`), each
//   pixel by where it is, not the whole of what is drawn: from its top, 0 at
//   52 and whole 53 below it; from its foot, 0 at 54 and whole 55 above it
//   (none where 53, 55 are 0); 56-59 the same across: from its left, 0 at 56
//   and whole 57 right of it; from its right, 0 at 58 and whole 59 left of it.
// kinds: 0 rounded rect, 1 glyph (alpha mask), 2 shadow (12 > 0: only
// outside its box, which is 13 above it), 3 color glyph, 4 image (12-15 its
// uv rect, 0-1), 5 frosted glass, 6 liquid glass, 7 a glyph in liquid glass
// inked by what is under it (glass.mbt), 9 a hole where a native view shows
// (written transparent, without blending: native.mbt), 10 a piece of a line
// (line.mbt: 4 half its width; 12-15 its ends, x0 y0 x1 y1 as shares of its
// rect, so that what moves or scales the rect takes its ends along; its ends
// round), 11 a band of a shape (shape.mbt: 4 half its stroke's width, 0 a
// fill; 6 1 a fill by the even-odd rule; 12 its first piece, 13 how many), 12
// the pieces of the frame's shapes, after every instance drawn (shape.mbt:
// six to an instance, none drawn).

///|
let inst_size = 60

///|
fn Ctx::grow(self : Ctx) -> Unit {
  let old = self.inst
  let bigger = FixedArray::make(old.length() * 2, 0.0)
  old.blit_to(bigger, len=self.ninst * inst_size)
  self.inst = bigger
}

///|
/// What cuts what is painted now, a level per clipping node: 12 numbers each, its rect (x0 y0 x1 y1), its corners'
/// radii (top left, top right, bottom right, bottom left) and how smooth each is (smooth.mbt: as the box whose corner it
/// is has room for, kept as the corner is, so a list cut by a card's corners is cut as the card's ground is drawn), what
/// each instance carries (16-19, 24-31). A box with
/// `clip` and a `radius` cuts to its rounded rect (Compose's clip(RoundedCornerShape)), what it holds covered at the
/// edge as its own ground is (the renderers: 0.5 - d · scale of the rounded rect's distance; a clip with no rounded
/// corner cuts hard, at pixel centres, as before), and presses in what it cut away miss (Ctx::hit_clips).
/// Within other clips, the rule for where they meet: their rects' intersection, each of its corners as round as the
/// clips whose corner it is (both's: the rounder), square where it is no clip's corner. So a rect inside a rounded
/// clip (a list in a card, down to its foot) keeps the card's corners where they are its own, and a rounded clip in
/// a rounded clip is right wherever the inner lies within the outer or shares its corners with room for them. Where
/// one clip's edge cuts through another's rounded corner, not at its corner (an image's rounded frame scrolled into a
/// pane's corner, its edge across the pane's curve), or shares the corner with too little room to draw it as long (a
/// band across the frame's top, flatter there), the intersection's corner there is not its own: so the level keeps
/// that other clip too, whole (its outer: 12 numbers more, instances' 40-51), and what is painted in it is cut by
/// both, exactly. One outer a level: the outermost such clip (a level whose clip has an outer passes it on, whatever it
/// cuts itself),
/// so what is drawn never leaves a pane or a window's rounded corners; a clip between the two (a card in the pane,
/// round the frame) keeps the old error where the frame cuts through its corner (a square corner there, at most
/// (1 - π/4) r² of it); no stencil is kept.
// kept across runs: every clip a paint pushes it pops in the same paint, so between frames only its base level is
// left, the same in every run
let clip_stack : Array[Double] = [
  0.0, 0.0, 1.0e9, 1.0e9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
  0.0,
]

///|
/// Whether each level of `clip_stack` is the window's own edges (its base; a look's copy of them where what it moves
/// is laid out, draw.mbt): what cuts nothing drawn, past which nothing is. A level not said (one pushed whole, a part's
/// band: kept_part.mbt) is not.
// kept across runs: pushed and popped with `clip_stack`'s levels, its base the only one left between frames
let clip_window : Array[Bool] = [true]

///|
/// Whether the clip at `k` (in `clip_stack`) is the window's own edges (clip_window).
fn clip_is_window(k : Int) -> Bool {
  let level = k / clip_n
  level < clip_window.length() && clip_window[level]
}

///|
/// The level just pushed said to be the window's own edges, or not (clip_window).
fn clip_say_window(window : Bool) -> Unit {
  let levels = clip_stack.length() / clip_n
  while clip_window.length() > levels {
    clip_window.pop() |> ignore
  }
  while clip_window.length() < levels - 1 {
    clip_window.push(false)
  }
  if clip_window.length() < levels {
    clip_window.push(window)
  } else {
    clip_window[levels - 1] = window
  }
}

///|
/// The numbers a level of `clip_stack` has: its own clip's 12, then its outer's (none: its radii 0).
let clip_n = 24

///|
/// Where the clip painted in now starts in `clip_stack`.
fn clip_top() -> Int {
  clip_stack.length() - clip_n
}

///|
/// The corner of the clip `k` (in `clip_stack`) at its corner `corner` (0 top left, then clockwise) where (`x`, `y`) is
/// that corner (as laid out: within a millionth, what the same place worked out two ways may differ by, a capsule's
/// place in a smooth corner being no whole number, smooth.mbt round_like): its radius and how smooth it is, else
/// square (0, 0).
fn clip_corner_r(k : Int, corner : Int, x : Double, y : Double) -> (Double, Double) {
  let s = clip_stack
  let cx = if corner == 0 || corner == 3 { s[k] } else { s[k + 2] }
  let cy = if corner < 2 { s[k + 1] } else { s[k + 3] }
  if (x - cx).abs() < 1.0e-6 && (y - cy).abs() < 1.0e-6 {
    (s[k + 4 + corner], s[k + 8 + corner])
  } else {
    (0.0, 0.0)
  }
}

///|
/// A clip of its own rect (x0 y0 x1 y1, as given) pushed: its corners round where they are the clip it is in's.
fn push_clip(x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Unit {
  let k = clip_top()
  let (tl, stl) = clip_corner_r(k, 0, x0, y0)
  let (tr, s_tr) = clip_corner_r(k, 1, x1, y0)
  let (br, sbr) = clip_corner_r(k, 2, x1, y1)
  let (bl, sbl) = clip_corner_r(k, 3, x0, y1)
  push_clip_r(x0, y0, x1, y1, (tl, tr, br, bl), (stl, s_tr, sbr, sbl))
}

///|
/// A clip pushed: its rect (x0 y0 x1 y1), its corners' radii and how smooth each is (top left, then clockwise); its
/// outer the clip it is in's where that has one, else the clip it is in where it cuts through a rounded corner of it
/// (clip_cuts), else none. `outer_kept`: the clip it is in's outer, whatever it cuts (a clip pushed where what it
/// holds is laid out, not where it is drawn: a look's, draw.mbt). `outer_whole`: the clip it is in, whole, its outer
/// (a circle reaching past it: push_circle_clip).
fn push_clip_r(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  r : (Double, Double, Double, Double),
  sm : (Double, Double, Double, Double),
  outer_kept? : Bool = false,
  outer_whole? : Bool = false,
) -> Unit {
  let k = clip_top()
  let has_outer = clip_has_outer(k)
  let from = if outer_whole {
    k
  } else if has_outer || outer_kept || !clip_cuts(k, x0, y0, x1, y1, r) {
    // (its outer's numbers, or none)
    k + 12
  } else {
    // (the clip it is in, whole)
    k
  }
  clip_stack.push(x0)
  clip_stack.push(y0)
  clip_stack.push(x1)
  clip_stack.push(y1)
  clip_stack.push(r.0)
  clip_stack.push(r.1)
  clip_stack.push(r.2)
  clip_stack.push(r.3)
  clip_stack.push(sm.0)
  clip_stack.push(sm.1)
  clip_stack.push(sm.2)
  clip_stack.push(sm.3)
  for j in 0..<12 {
    clip_stack.push(clip_stack[from + j])
  }
  // (a square clip holding all of the window's edges it is in, a frame's whole, is those edges still)
  let s = clip_stack
  clip_say_window(
    clip_is_window(k) &&
    x0 <= s[k] &&
    y0 <= s[k + 1] &&
    x1 >= s[k + 2] &&
    y1 >= s[k + 3] &&
    r.0 <= 0.0 &&
    r.1 <= 0.0 &&
    r.2 <= 0.0 &&
    r.3 <= 0.0 &&
    !has_outer,
  )
}

///|
/// No clip pushed, nor any outer: what is painted till it is popped is cut by nothing (an editor's handles, which are
/// also put after everything else painted: Ctx::paint_top).
fn push_unclipped() -> Unit {
  for v in [-1.0e9, -1.0e9, 1.0e9, 1.0e9] {
    clip_stack.push(v)
  }
  for _ in 0..<20 {
    clip_stack.push(0.0)
  }
}

///|
/// Whether the level at `k` has an outer clip (its radii not all 0).
fn clip_has_outer(k : Int) -> Bool {
  let s = clip_stack
  s[k + 16] > 0.0 || s[k + 17] > 0.0 || s[k + 18] > 0.0 || s[k + 19] > 0.0
}

///|
/// Whether a clip of rect (x0 y0 x1 y1), its corners `r`, pushed in the clip at `k` cuts through one of that clip's
/// rounded corners: reaches into the square that corner's curve lies in (as far as a smooth corner's curve goes in,
/// smooth.mbt) other than by being that corner as round or rounder, its own corner there, with room for it (the
/// renderers draw a corner no longer than half its rect's shorter side: one sharing that corner with less room, a band
/// across a frame's top as a picture is brushed in, is flatter than the corner and would show past it).
fn clip_cuts(k : Int, x0 : Double, y0 : Double, x1 : Double, y1 : Double, r : (Double, Double, Double, Double)) -> Bool {
  let s = clip_stack
  let own = [r.0, r.1, r.2, r.3]
  for j in 0..<4 {
    let rr = s[k + 4 + j]
    if rr <= 0.0 {
      continue
    }
    let reach = rr * (1.0 + (smooth_scale - 1.0) * s[k + 8 + j])
    let left = j == 0 || j == 3
    let top = j < 2
    let cx = if left { s[k] } else { s[k + 2] }
    let cy = if top { s[k + 1] } else { s[k + 3] }
    // the square from the corner `reach` in
    let (zx0, zx1) = if left { (cx, cx + reach) } else { (cx - reach, cx) }
    let (zy0, zy1) = if top { (cy, cy + reach) } else { (cy - reach, cy) }
    if x1 <= zx0 || x0 >= zx1 || y1 <= zy0 || y0 >= zy1 {
      continue
    }
    // its own corner there, the same corner, as round and as long: the clip's curve within its own
    let ox = if left { x0 } else { x1 }
    let oy = if top { y0 } else { y1 }
    if (ox - cx).abs() < 1.0e-6 && (oy - cy).abs() < 1.0e-6 && own[j] >= rr && dmin(x1 - x0, y1 - y0) / 2.0 >= reach {
      continue
    }
    return true
  }
  false
}

///|
/// A clip of a circle about (`cx`, `cy`), `r` across (a look's: draw.mbt), within the clip it is in: that clip its
/// outer, so that it is cut round where it reaches past that clip's edges too (cut to that clip's rect, its curve
/// would be lost there); where that clip has an outer of its own, cut to the clip's rect.
fn push_circle_clip(cx : Double, cy : Double, r : Double) -> Unit {
  let k = clip_top()
  let s = clip_stack
  if clip_has_outer(k) {
    push_clip_r(
      dmax(cx - r, s[k]),
      dmax(cy - r, s[k + 1]),
      dmin(cx + r, s[k + 2]),
      dmin(cy + r, s[k + 3]),
      (r, r, r, r),
      (0.0, 0.0, 0.0, 0.0),
    )
  } else {
    push_clip_r(cx - r, cy - r, cx + r, cy + r, (r, r, r, r), (0.0, 0.0, 0.0, 0.0), outer_whole=true)
  }
}

///|
/// Node `n`'s clip pushed: its rect, its corners rounded as it draws them (radius_at), within the clip it is in.
fn push_round_clip(n : Node) -> Unit {
  // (a box whose border is drawn over what it holds (paint's border_over) cuts it at the border's inside, as CSS's
  // overflow cuts at the padding box: what it holds never shows under its line, which is the box's edge (a list's row
  // under a card's see-through line read as the line through it), its corners concentric with the box's there)
  let bw = if n.border_w > 0.0 && n.first >= 0 && (n.kind == kind_box || n.kind == kind_list || n.kind == kind_scroll) {
    dmin(n.border_w, dmin(n.fw, n.fh) / 2.0)
  } else {
    0.0
  }
  let x = n.x + bw
  let y = n.y + bw
  let w = n.fw - 2.0 * bw
  let h = n.fh - 2.0 * bw
  let k = clip_top()
  let s = clip_stack
  let x0 = dmax(x, s[k])
  let y0 = dmax(y, s[k + 1])
  let x1 = dmin(x + w, s[k + 2])
  let y1 = dmin(y + h, s[k + 3])
  // as round, and as smooth, as its ground's corners are (the renderers cap a radius at half the shorter side, and
  // smooth it as far as the box has room for)
  let room = dmin(w, h) / 2.0
  // (cut by the window's edges alone, which cut nothing drawn (past them nothing is), no less of its own rect kept than
  // its corners take: a box mostly past one keeps its far corners as round as it draws them, the renderers drawing a
  // corner no longer than half the clip's room (an iPhone Duo's card 56 of its 240 shown: its 46 corner 28, flatter
  // than its line, what it holds showing past it))
  let edges = clip_is_window(k)
  let most = dmin(
    concentric(dmax(dmax(n.radius_at(0), n.radius_at(1)), dmax(n.radius_at(2), n.radius_at(3))), bw),
    room,
  )
  let (x0, x1) = if edges && x1 - x0 < 2.0 * most {
    (if x0 > x { dmax(x, x1 - 2.0 * most) } else { x0 }, if x1 < x + w { dmin(x + w, x0 + 2.0 * most) } else { x1 })
  } else {
    (x0, x1)
  }
  let (y0, y1) = if edges && y1 - y0 < 2.0 * most {
    (if y0 > y { dmax(y, y1 - 2.0 * most) } else { y0 }, if y1 < y + h { dmin(y + h, y0 + 2.0 * most) } else { y1 })
  } else {
    (y0, y1)
  }
  // where a corner is both's, the rounder
  let corner = fn(j : Int, cx : Double, cy : Double, ox : Double, oy : Double) {
    let (pr, ps) = clip_corner_r(k, j, cx, cy)
    let r = dmax(dmin(concentric(n.radius_at(j), bw), room), 0.0)
    if r > 0.0 && cx == ox && cy == oy && r >= pr {
      (r, smoothness(r, room))
    } else {
      (pr, ps)
    }
  }
  let (tl, stl) = corner(0, x0, y0, x, y)
  let (tr, s_tr) = corner(1, x1, y0, x + w, y)
  let (br, sbr) = corner(2, x1, y1, x + w, y + h)
  let (bl, sbl) = corner(3, x0, y1, x, y + h)
  push_clip_r(x0, y0, x1, y1, (tl, tr, br, bl), (stl, s_tr, sbr, sbl))
}

///|
fn pop_clip() -> Unit {
  for _ in 0..<clip_n {
    clip_stack.pop() |> ignore
  }
  while clip_window.length() > clip_stack.length() / clip_n {
    clip_window.pop() |> ignore
  }
}

///|
/// The clip `k` (in `clip_stack`): its rect, its corners' radii and how smooth they are.
fn clip_at(
  k : Int,
) -> ((Double, Double, Double, Double), (Double, Double, Double, Double), (Double, Double, Double, Double)) {
  let s = clip_stack
  (
    (s[k], s[k + 1], s[k + 2], s[k + 3]),
    (s[k + 4], s[k + 5], s[k + 6], s[k + 7]),
    (s[k + 8], s[k + 9], s[k + 10], s[k + 11]),
  )
}

///|
/// Instance `b`'s clip moved to (`m0` `m1` `m2` `m3`), then cut to the clip `c` (rounded by `r`, as smooth as `sm`):
/// where that moves a corner, the corner is `c`'s (its radius, its smoothness) or square.
fn clamp_inst_clip(
  a : FixedArray[Double],
  b : Int,
  m0 : Double,
  m1 : Double,
  m2 : Double,
  m3 : Double,
  c : (Double, Double, Double, Double),
  r : (Double, Double, Double, Double),
  sm : (Double, Double, Double, Double),
) -> Unit {
  let (c0, c1, c2, c3) = c
  a[b + 16] = dmax(m0, c0)
  a[b + 17] = dmax(m1, c1)
  a[b + 18] = dmin(m2, c2)
  a[b + 19] = dmin(m3, c3)
  let corner = fn(
    j : Int,
    xi : Int,
    yi : Int,
    mx : Double,
    my : Double,
    cx : Double,
    cy : Double,
    cr : Double,
    cs : Double,
  ) {
    if a[b + xi] != mx || a[b + yi] != my {
      let theirs = a[b + xi] == cx && a[b + yi] == cy
      a[b + 24 + j] = if theirs { cr } else { 0.0 }
      a[b + 28 + j] = if theirs { cs } else { 0.0 }
    }
  }
  corner(0, 16, 17, m0, m1, c0, c1, r.0, sm.0)
  corner(1, 18, 17, m2, m1, c2, c1, r.1, sm.1)
  corner(2, 18, 19, m2, m3, c2, c3, r.2, sm.2)
  corner(3, 16, 19, m0, m3, c0, c3, r.3, sm.3)
}

///|
/// `v` set on the device's pixels (`sc` of them a point): the nearest (half way, away from 0, as runs kept from a
/// device's frames have it: their frames are told apart by hash).
fn on_pixels(v : Double, sc : Double) -> Double {
  (v * sc).round() / sc
}

///|
/// Where a glyph's picture goes down the screen: its line's baseline `base` set on the pixels first, then the glyph's
/// own offset `oy` from it. A host draws each picture with the baseline on a pixel row (win_text.cpp), so every glyph
/// of a line lands on the same row; rounded as one sum, a baseline half way between two rows went up for one glyph
/// and down for the next, by how its offset's float rounded (at 150%, a flat-topped "u" a pixel above its "p" and "s").
fn on_glyph_row(base : Double, oy : Double, sc : Double) -> Double {
  on_pixels(on_pixels(base, sc) + oy, sc)
}

///|
/// How much fainter the words painted now are than what holds them (the looks being painted: Look's `words`).
// kept across runs: 1 between frames, each look that changes it putting it back as it is painted (draw.mbt)
let words_alpha : Ref[Double] = Ref(1.0)

///|
fn Ctx::push_inst(
  self : Ctx,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  radius : Double,
  kind : Double,
  bw : Double,
  blur : Double,
  color : Int64,
  alpha : Double,
  c2a : Double,
  c2b : Double,
  c2c : Double,
  c2d : Double,
) -> Unit {
  if (self.ninst + 1) * inst_size > self.inst.length() {
    self.grow()
  }
  let b = self.ninst * inst_size
  let a = self.inst
  a[b] = x
  a[b + 1] = y
  a[b + 2] = w
  a[b + 3] = h
  a[b + 4] = radius
  a[b + 5] = kind
  a[b + 6] = bw
  a[b + 7] = blur
  a[b + 8] = ((color >> 24) & 0xFFL).to_double() / 255.0
  a[b + 9] = ((color >> 16) & 0xFFL).to_double() / 255.0
  a[b + 10] = ((color >> 8) & 0xFFL).to_double() / 255.0
  // (words fainter by the looks they are in: words_alpha)
  let alpha = if kind == 1.0 || kind == 3.0 || kind == 7.0 { alpha * words_alpha.val } else { alpha }
  a[b + 11] = (color & 0xFFL).to_double() / 255.0 * alpha
  a[b + 12] = c2a
  a[b + 13] = c2b
  a[b + 14] = c2c
  a[b + 15] = c2d
  let k = clip_top()
  a[b + 16] = clip_stack[k]
  a[b + 17] = clip_stack[k + 1]
  a[b + 18] = clip_stack[k + 2]
  a[b + 19] = clip_stack[k + 3]
  a[b + 24] = clip_stack[k + 4]
  a[b + 25] = clip_stack[k + 5]
  a[b + 26] = clip_stack[k + 6]
  a[b + 27] = clip_stack[k + 7]
  a[b + 28] = clip_stack[k + 8]
  a[b + 29] = clip_stack[k + 9]
  a[b + 30] = clip_stack[k + 10]
  a[b + 31] = clip_stack[k + 11]
  // the clip outside it its own cuts through, if any (40-51)
  for j in 0..<12 {
    a[b + 40 + j] = clip_stack[k + 12 + j]
  }
  a[b + 20] = 0.0 // the image it shows, if any
  // a rect's or frosted glass's notch (none); liquid glass and glyphs in it set theirs after
  a[b + 21] = 0.0
  a[b + 22] = 0.0
  a[b + 23] = 0.0
  // not turned
  a[b + 32] = 0.0
  a[b + 33] = 0.0
  a[b + 34] = 0.0
  a[b + 35] = 0.0
  // its corners all `radius` (a box's each its own: corners_last)
  a[b + 36] = radius
  a[b + 37] = radius
  a[b + 38] = radius
  a[b + 39] = radius
  // fading towards no cut
  a[b + 52] = 0.0
  a[b + 53] = 0.0
  a[b + 54] = 0.0
  a[b + 55] = 0.0
  a[b + 56] = 0.0
  a[b + 57] = 0.0
  a[b + 58] = 0.0
  a[b + 59] = 0.0
  if inst_owners_kept() {
    inst_owned(self.ninst)
  }
  self.ninst = self.ninst + 1
}

///|
/// The corners of node `n` (radius_at's) on the instance just emitted for it (its ground, its border, its shadow, its
/// glass, its picture), where they are each their own: 36-39, and 4 the roundest.
fn Ctx::corners_last(self : Ctx, n : Node) -> Unit {
  self.corners_on(self.ninst - 1, n)
}

///|
/// The same on instance `k`.
fn Ctx::corners_on(self : Ctx, k : Int, n : Node) -> Unit {
  match n.radii {
    Some(r) => self.corners_each(k, r[0], r[1], r[2], r[3])
    None => ()
  }
}

///|
/// The same with corners `r0` to `r3` (top left, then round it), the roundest its corner (4).
fn Ctx::corners_last_each(self : Ctx, r0 : Double, r1 : Double, r2 : Double, r3 : Double) -> Unit {
  self.corners_each(self.ninst - 1, r0, r1, r2, r3)
}

///|
fn Ctx::corners_each(self : Ctx, k : Int, r0 : Double, r1 : Double, r2 : Double, r3 : Double) -> Unit {
  let b = k * inst_size
  let a = self.inst
  a[b + 4] = dmax(dmax(r0, r1), dmax(r2, r3))
  a[b + 36] = r0
  a[b + 37] = r1
  a[b + 38] = r2
  a[b + 39] = r3
}

///|
/// The notch of node `n` (Ctx::box `notch_r`) on the instance just emitted for it (its ground or its glass): where
/// its circle's middle is below the top (21), its radius (22), its fillets' (23).
fn Ctx::notch_last(self : Ctx, n : Node) -> Unit {
  if n.notch_r <= 0.0 {
    return
  }
  let b = (self.ninst - 1) * inst_size
  self.inst[b + 21] = n.notch_y
  self.inst[b + 22] = n.notch_r
  self.inst[b + 23] = n.notch_f
}

///|
fn Ctx::emit_rect(
  self : Ctx,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  radius : Double,
  color : Int64,
  bw : Double,
  bc : Int64,
  alpha : Double,
) -> Unit {
  let ba = (bc & 0xFFL).to_double() / 255.0 * alpha
  self.push_inst(
    x,
    y,
    w,
    h,
    radius,
    0.0,
    bw,
    0.0,
    color,
    if alpha == 0.0 { 1.0 } else { alpha },
    ((bc >> 24) & 0xFFL).to_double() / 255.0,
    ((bc >> 16) & 0xFFL).to_double() / 255.0,
    ((bc >> 8) & 0xFFL).to_double() / 255.0,
    ba,
  )
}

///|
fn Ctx::emit_text(
  self : Ctx,
  tl : TextLayout,
  ox : Double,
  oy : Double,
  color : Int64,
  alpha : Double,
  center_in? : Double = -1.0,
  spans? : Array[(Int, Int, Int64)] = [],
  font? : (Double, Int, Int, Double),
) -> Unit {
  let s = tl.shaped
  let n = s.starts.length()
  let k = clip_top()
  let cy0 = clip_stack[k + 1]
  let cy1 = clip_stack[k + 3]
  let sc = self.scale
  // in a shot drawn at more pixels a point than the host's glyphs are made at (words_zoom): its words' glyphs made
  // that much larger, as crisp, drawn that much smaller, where its font is said (`font`: size, weight, style, spacing)
  let zoom = words_zoom.val
  let zoomed = match font {
    Some((size, weight, style, spacing)) => zoomed_keys(tl.text, s, size, weight, style, spacing)
    None => None
  }
  let (keys, z) = match zoomed {
    Some(big) => (big, zoom)
    None => (s.keys, 1.0)
  }
  keep_text_runs(
    tl,
    ox,
    oy,
    fn(line) {
      if center_in >= 0.0 && line < tl.line_w.length() {
        dmax((center_in - tl.line_w[line]) / 2.0, 0.0)
      } else {
        0.0
      }
    },
    cy0,
    cy1,
  )
  for c in 0..<n {
    let key = keys[c]
    if key < 0 {
      continue
    }
    let line = tl.line_of[c]
    let top = oy + line.to_double() * tl.line_h
    if top > cy1 || top + tl.line_h < cy0 {
      continue
    }
    // (made at the host's pixels a point)
    let g = glyph(key, sc / zoom)
    if g.gw <= 0.0 {
      continue
    }
    let (gw, gh) = (g.gw / z, g.gh / z)
    // centred: each line by half of what it leaves of the box
    let dx = if center_in >= 0.0 && line < tl.line_w.length() {
      dmax((center_in - tl.line_w[line]) / 2.0, 0.0)
    } else {
      0.0
    }
    let gx = on_pixels(ox + dx + tl.xs[c] + s.pad + g.ox / z, sc)
    let gy = on_glyph_row(top + tl.ascent, g.oy / z, sc)
    let adaptive = glass_paint.ink_r > 0.0 && !g.color
    self.push_inst(
      gx,
      gy,
      gw,
      gh,
      0.0,
      if g.color { 3.0 } else if adaptive { 7.0 } else { 1.0 },
      0.0,
      0.0,
      if g.color {
        0xFFFFFFFFL
      } else if spans.is_empty() {
        color
      } else {
        span_color(spans, s.starts[c], color)
      },
      alpha,
      g.u,
      g.v,
      // (its pixels in the atlas: as many as the host made)
      g.gw * (sc / zoom),
      g.gh * (sc / zoom),
    )
    if inst_owners_kept() {
      let x0 = ox + dx + tl.xs[c] + s.pad
      inst_cell(self.ninst - 1, gx, gw, x0, x0 + s.adv[c] - 2.0 * s.pad)
    }
    if adaptive {
      let b = (self.ninst - 1) * inst_size
      self.inst[b + 21] = glass_paint.ink_x
      self.inst[b + 22] = glass_paint.ink_y
      self.inst[b + 23] = glass_paint.ink_r
    }
  }
}

///|
/// The colour of the words at `off`: the last of `spans` (from, to, colour) over it, else `color`.
fn span_color(spans : Array[(Int, Int, Int64)], off : Int, color : Int64) -> Int64 {
  let mut out = color
  for sp in spans {
    if sp.0 <= off && off < sp.1 {
      out = sp.2
    }
  }
  out
}

///|
/// What node `n` holds, painted in turn (what goes over its siblings after them).
fn Ctx::paint_held(self : Ctx, n : Node, alpha : Double) -> Unit {
  let mut c = n.first
  let mut over = false
  while c >= 0 {
    if dr.any && self.drawn_z(c) == 1 {
      over = true
    } else {
      self.paint(c, alpha)
    }
    c = self.nodes[c].next
  }
  if over {
    // what goes over its siblings, after them
    c = n.first
    while c >= 0 {
      if self.drawn_z(c) == 1 {
        self.paint(c, alpha)
      }
      c = self.nodes[c].next
    }
  }
}

///|
/// Node `i` drawn, and what it holds: a hit target of its own holds the targets drawn in it (Ctx::hit_ends: what
/// holds the one under the pointer is pointed at too, Ctx::hovered).
fn Ctx::paint(self : Ctx, i : Int, alpha_in : Double) -> Unit {
  // a shot's layer: never on the screen, painted apart (Ctx::paint_shots)
  if self.nodes[i].shot && !shooting.val {
    return
  }
  // a layer (overlay.mbt): what is over everything under it (Ctx::paint_top) stays under it, and what is so in it is
  // put over the rest of it
  let layer = self.nodes[i].portal
  // a stratum over what flies (strata.mbt): what flies put off under it, painted now
  if layer || self.nodes[i].mark != 0 {
    self.land_flying()
  }
  if layer {
    self.raise_tops()
  }
  let h0 = self.next_hit_ids.length()
  // (whose each instance is, where a test asks: contrast.mbt)
  let was = inst_owners.painting
  if inst_owners_kept() {
    inst_owners.painting = i
  }
  let passes = self.nodes[i].passes
  if passes {
    self.passing += 1
  }
  self.paint_node(i, alpha_in)
  if passes {
    self.passing -= 1
  }
  // a scrim: what is put over it (Stratum's OverScrim) over it, under the rest of its layer
  if !dr.raised.is_empty() && dr.mode != mode_hits && dr.scrims.contains(i) {
    self.paint_raised()
  }
  // the page's cover: what is over it (strata.mbt's OverCover) over it
  if !dr.over_cover.is_empty() && dr.mode != mode_hits && dr.covers.contains(i) {
    self.paint_over_cover()
  }
  if inst_owners_kept() {
    inst_owners.painting = was
  }
  if layer {
    self.raise_tops()
  }
  let id = self.nodes[i].id
  // (its own target the first it drew, if it took presses: none drawn before it)
  if id != 0 && self.next_hit_ids.length() > h0 + 1 && self.next_hit_ids[h0] == id {
    self.next_hit_ends[h0] = self.next_hit_ids.length()
  }
}

///|
fn Ctx::paint_node(self : Ctx, i : Int, alpha_in : Double) -> Unit {
  // drawn by its look, tapped as laid out (draw.mbt), when it has one
  if dr.any && self.drawn_paint(i, alpha_in) {
    return
  }
  let n = self.nodes[i]
  let alpha = alpha_in * n.opacity
  if alpha <= 0.002 {
    return
  }
  let k = clip_top()
  let cx0 = clip_stack[k]
  let cy0 = clip_stack[k + 1]
  let cx1 = clip_stack[k + 2]
  let cy1 = clip_stack[k + 3]
  // cull what is outside the clip: nothing of its own shows there, and nothing it cuts; what a box that does not cut
  // holds may lie past the box (a row squeezed to the room it has, wider than that, moved sideways: ＋'s recent
  // photos), each part of it culled where it is
  if (n.x > cx1 || n.y > cy1 || n.x + n.fw < cx0 || n.y + n.fh < cy0) &&
    !(dr.any && dr.mode != mode_hits && self.draw_carries(i)) {
    if !n.clip && (n.kind == kind_box || n.kind == kind_scroll) {
      self.paint_held(n, alpha)
    }
    return
  }
  // built in a page's bones and drawn whole: one piece of its own box, nothing in it (bones.mbt)
  if n.bones != 0L && n.bone_whole {
    // (in its own corners; with none, round at its ends: a control's)
    let r = if n.radius > 0.0 { n.radius } else { dmin(n.fw, n.fh) / 2.0 }
    self.emit_bone(n.x, n.y, n.fw, n.fh, r, n.bones, alpha)
    self.corners_last(n)
    return
  }
  // its own ground drawn in another box (a shape on its way: draw_ground), what it holds where it is laid out
  let laid = (n.x, n.y, n.fw, n.fh, n.radius, n.radii)
  let ground = self.ground_of(i)
  match ground {
    Some((gx, gy, gw, gh, (r0, r1, r2, r3))) => {
      n.x = gx
      n.y = gy
      n.fw = gw
      n.fh = gh
      n.set_radii(FixedArray::from_array([r0, r1, r2, r3]))
    }
    None => ()
  }
  match n.glass {
    Some(gl) => self.paint_glass(n, gl, alpha)
    None => ()
  }
  if n.shadow > 0.0 && n.glass is None {
    let dy = if n.shadow_y >= 0.0 { n.shadow_y } else { n.shadow * 0.35 }
    self.push_inst(
      n.x,
      n.y + dy,
      n.fw,
      n.fh,
      n.radius,
      2.0,
      0.0,
      n.shadow,
      n.shadow_c,
      alpha,
      // (only outside the box, which is `dy` above its shadow: kinds above)
      if n.shadow_out { 1.0 } else { 0.0 },
      if n.shadow_out { dy } else { 0.0 },
      0.0,
      0.0,
    )
    self.corners_last(n)
  }
  // its border over what it holds (drawn after it, below): the box's own edge, never covered by what is in it, as
  // CSS's border is outside what a box holds (here it takes no room); with nothing in it, with its ground
  let border_over = n.border_w > 0.0 &&
    n.first >= 0 &&
    (n.kind == kind_box || n.kind == kind_list || n.kind == kind_scroll)
  // (a picture's is what shows until it is in, drawn with it: paint_image)
  let bg = if n.kind == kind_image {
    0L
  } else {
    match self.ground_bg_of(i) {
      Some(b) if ground is Some(_) => b
      _ => n.bg
    }
  }
  // (in a page's bones, a ground or an edge that says something by its colour in theirs: bones.mbt)
  let bg = if n.bones != 0L { self.bone_ground(bg, n.bones) } else { bg }
  let border_c = if n.bones != 0L { self.bone_ground(n.border_c, n.bones) } else { n.border_c }
  if (bg & 0xFFL) != 0L || (n.border_w > 0.0 && !border_over) {
    // (where its border is drawn over what it holds, its ground stops at the border's inside, the border's band left
    // clear: a border seen through is over what is behind the box, as one drawn with its ground is, never over the
    // box's own ground: a panel's line over its white was a pale ring round it on a dimmed page)
    self.emit_rect(
      n.x,
      n.y,
      n.fw,
      n.fh,
      n.radius,
      bg,
      if n.dashed { 0.0 } else { n.border_w },
      if border_over { 0L } else { border_c },
      alpha,
    )
    self.notch_last(n)
    self.corners_last(n)
    if n.dashed && n.border_w > 0.0 && !border_over {
      self.emit_dashes(n.x, n.y, n.fw, n.fh, n.radius, n.border_w, border_c, alpha)
    }
  }
  if ground is Some(_) {
    n.x = laid.0
    n.y = laid.1
    n.fw = laid.2
    n.fh = laid.3
    n.radius = laid.4
    n.radii = laid.5
  }
  // (nothing in a page's bones is pressed or pointed at: it is not there yet)
  if (n.hit || n.points) && n.id != 0 && n.bones == 0L {
    if self.push_hit(n.id, dmax(n.x, cx0), dmax(n.y, cy0), dmin(n.x + n.fw, cx1), dmin(n.y + n.fh, cy1)) &&
      n.points {
      self.point_said(n.id)
    }
  }
  // a modal's ground: the wheel stops at it too (overlay.mbt); and what says it stops it (Ctx::stop_wheel), what
  // scrolls in it (laid in it, later) still taking it first
  if (n.blocks || n.stops_wheel) && n.id != 0 && n.bones == 0L {
    self.next_scroll_ids.push(n.id)
    self.next_scroll_rects.push(dmax(n.x, cx0))
    self.next_scroll_rects.push(dmax(n.y, cy0))
    self.next_scroll_rects.push(dmin(n.x + n.fw, cx1))
    self.next_scroll_rects.push(dmin(n.y + n.fh, cy1))
  }
  if n.bones != 0L && (n.shapes.length() > 0 || n.lines.length() > 0) {
    // an icon, a drawing, in a page's bones: its shape
    self.paint_bone_shape(n, alpha)
  } else {
    if n.shapes.length() > 0 {
      self.paint_shapes(n, alpha)
    }
    if n.lines.length() > 0 {
      self.paint_lines(n, alpha)
    }
  }
  if n.bones != 0L {
    self.paint_bones_of(i, n, alpha)
    if n.kind != kind_box && n.kind != kind_scroll && n.kind != kind_list {
      return
    }
  }
  if n.kind == kind_text {
    match n.tl {
      Some(tl) =>
        self.emit_text(
          tl,
          n.x + n.pad_l,
          n.y + n.pad_t,
          n.color,
          alpha,
          center_in=if n.center {
            dmax(n.fw - n.pad_l - n.pad_r, 0.0)
          } else {
            -1.0
          },
          font=(n.font_size, n.weight, n.words_style(), n.spacing),
        )
      None => ()
    }
    return
  }
  if n.kind == kind_rich {
    self.paint_rich(i, n, alpha)
    return
  }
  if n.kind == kind_editor {
    // its words more than it shows: what the wheel and a finger scroll there, as a box kept to a height (sideways.mbt)
    match sideways.get(n.id) {
      Some(sw) if sw.max > 0.0 => {
        self.next_scroll_ids.push(n.id)
        self.next_scroll_rects.push(dmax(n.x, cx0))
        self.next_scroll_rects.push(dmax(n.y, cy0))
        self.next_scroll_rects.push(dmin(n.x + n.fw, cx1))
        self.next_scroll_rects.push(dmin(n.y + n.fh, cy1))
      }
      _ => ()
    }
    self.paint_editor(n, alpha)
    return
  }
  if n.kind == kind_image {
    self.paint_image(i, n, alpha)
    return
  }
  if n.kind == kind_native {
    self.paint_native(i, n)
    return
  }
  if n.kind == kind_page {
    self.paint_page(n, alpha)
    return
  }
  if n.kind == kind_list ||
    (
      n.id != 0 &&
      (pagers.contains(n.id) ||
      drags.contains(n.id) ||
      captures.contains(n.id) ||
      sideways.contains(n.id))
    ) {
    self.next_scroll_ids.push(n.id)
    self.next_scroll_rects.push(dmax(n.x, cx0))
    self.next_scroll_rects.push(dmax(n.y, cy0))
    self.next_scroll_rects.push(dmin(n.x + n.fw, cx1))
    self.next_scroll_rects.push(dmin(n.y + n.fh, cy1))
  }
  let clipped = n.clip
  if clipped {
    push_round_clip(n)
  }
  // its scroll bar, where what it holds scrolls past it (scroll_bar.mbt): drawn over what it holds, in its clip;
  // the bars of the boxes in its rows scrolled as one, along its foot
  let bar = if n.kind == kind_list || (n.sideways && n.id != 0) { self.bar_at(n) } else { None }
  let across_from = self.across_seen.length()
  let first_inst = self.ninst
  // liquid glass in a group: all of it first, so it merges; text in
  // adaptive liquid glass inked by what is under it
  let group = n.glass_group && !glass_paint.solid
  if group {
    // (a run of its own: what is before it and after it merges with none of it)
    glass_run_break()
    self.emit_group_glass(i, alpha)
    glass_run_break()
    glass_paint.in_group = glass_paint.in_group + 1
  }
  let ink = (glass_paint.ink_x, glass_paint.ink_y, glass_paint.ink_r)
  match n.glass {
    Some(gl) if gl.liquid && gl.adaptive && !glass_paint.solid => {
      glass_paint.ink_x = n.x + n.fw / 2.0
      glass_paint.ink_y = n.y + n.fh / 2.0
      glass_paint.ink_r = dmax(dmin(n.fw, n.fh) / 2.0, 1.0)
    }
    _ => ()
  }
  if n.kind == kind_list {
    // under its rows: what the motion package draws there (its rows gone, leaving)
    self.paint_underlay(i)
  }
  match n.paints {
    Some(f) => f(n, alpha)
    None => ()
  }
  self.paint_held(n, alpha)
  glass_paint.ink_x = ink.0
  glass_paint.ink_y = ink.1
  glass_paint.ink_r = ink.2
  if group {
    glass_paint.in_group = glass_paint.in_group - 1
  }
  if n.kind == kind_list {
    // Android's stretch past an end (scroll.mbt)
    match self.lists.get(n.id) {
      Some(st) if st.over > 0.0 => {
        let k = clip_top()
        self.stretch_rows(
          st,
          first_inst,
          n.y,
          n.fh,
          clip_stack[k + 1],
          clip_stack[k + 3],
        )
      }
      _ => ()
    }
  }
  match bar {
    Some(b) => self.paint_bar(b, alpha)
    None => ()
  }
  if n.kind == kind_list {
    self.across_bars(n, across_from, alpha)
  }
  if clipped {
    pop_clip()
  }
  if border_over && n.dashed {
    match ground {
      Some((bx, by, bw, bh, (r0, r1, r2, r3))) =>
        self.emit_dashes(bx, by, bw, bh, dmax(dmax(r0, r1), dmax(r2, r3)), n.border_w, border_c, alpha)
      None => self.emit_dashes(n.x, n.y, n.fw, n.fh, n.radius, n.border_w, border_c, alpha)
    }
  } else if border_over {
    match ground {
      // (round its ground drawn in another box: that box's corners, each its own)
      Some((bx, by, bw, bh, (r0, r1, r2, r3))) => {
        self.emit_rect(bx, by, bw, bh, dmax(dmax(r0, r1), dmax(r2, r3)), 0L, n.border_w, border_c, alpha)
        self.notch_last(n)
        self.corners_last_each(r0, r1, r2, r3)
      }
      None => {
        self.emit_rect(n.x, n.y, n.fw, n.fh, n.radius, 0L, n.border_w, border_c, alpha)
        self.notch_last(n)
        self.corners_last(n)
      }
    }
  }
}

///|
/// Instance `b` (in `a`) fading out towards a cut softly (52-55): from its top, 0 at `top` and whole `top_soft` below
/// it; from its foot, 0 at `foot` and whole `foot_soft` above it (a soft of 0: none that way). Where it fades that way
/// already (a cut inside this one), what fades it more there: the one reaching further in.
fn inst_fade(a : FixedArray[Double], b : Int, top : Double, top_soft : Double, foot : Double, foot_soft : Double) -> Unit {
  if top_soft > 0.0 && (a[b + 53] <= 0.0 || top + top_soft > a[b + 52] + a[b + 53]) {
    a[b + 52] = top
    a[b + 53] = top_soft
  }
  if foot_soft > 0.0 && (a[b + 55] <= 0.0 || foot - foot_soft < a[b + 54] - a[b + 55]) {
    a[b + 54] = foot
    a[b + 55] = foot_soft
  }
}

///|
/// Instance `b`'s fading (52-55) moved as its rect is down the screen: about `oy` by `sy`, then by `dy`.
fn inst_fade_moved(a : FixedArray[Double], b : Int, oy : Double, sy : Double, dy : Double) -> Unit {
  if a[b + 53] > 0.0 {
    a[b + 52] = oy + (a[b + 52] - oy) * sy + dy
    a[b + 53] = a[b + 53] * sy
  }
  if a[b + 55] > 0.0 {
    a[b + 54] = oy + (a[b + 54] - oy) * sy + dy
    a[b + 55] = a[b + 55] * sy
  }
}

///|
/// How much of instance `b` shows at (`x`, `y`) as it fades out towards a cut (52-59): 1 where it does not.
fn inst_fade_at(a : FixedArray[Double], b : Int, x : Double, y : Double) -> Double {
  let top = if a[b + 53] > 0.0 { dclamp((y - a[b + 52]) / a[b + 53], 0.0, 1.0) } else { 1.0 }
  let foot = if a[b + 55] > 0.0 { dclamp((a[b + 54] - y) / a[b + 55], 0.0, 1.0) } else { 1.0 }
  let start = if a[b + 57] > 0.0 { dclamp((x - a[b + 56]) / a[b + 57], 0.0, 1.0) } else { 1.0 }
  let end = if a[b + 59] > 0.0 { dclamp((a[b + 58] - x) / a[b + 59], 0.0, 1.0) } else { 1.0 }
  top * foot * start * end
}

///|
/// Instance `b` fading out towards a cut across (56-59), as inst_fade does down: from its left, 0 at `start` and whole
/// `start_soft` right of it; from its right, 0 at `end` and whole `end_soft` left of it.
fn inst_fade_across(
  a : FixedArray[Double],
  b : Int,
  start : Double,
  start_soft : Double,
  end : Double,
  end_soft : Double,
) -> Unit {
  if start_soft > 0.0 && (a[b + 57] <= 0.0 || start + start_soft > a[b + 56] + a[b + 57]) {
    a[b + 56] = start
    a[b + 57] = start_soft
  }
  if end_soft > 0.0 && (a[b + 59] <= 0.0 || end - end_soft < a[b + 58] - a[b + 59]) {
    a[b + 58] = end
    a[b + 59] = end_soft
  }
}

///|
/// Instance `b`'s fading across (56-59) moved as its rect is: about `ox` by `sx`, then by `dx`.
fn inst_fade_moved_across(a : FixedArray[Double], b : Int, ox : Double, sx : Double, dx : Double) -> Unit {
  if a[b + 57] > 0.0 {
    a[b + 56] = ox + (a[b + 56] - ox) * sx + dx
    a[b + 57] = a[b + 57] * sx
  }
  if a[b + 59] > 0.0 {
    a[b + 58] = ox + (a[b + 58] - ox) * sx + dx
    a[b + 59] = a[b + 59] * sx
  }
}
