// A cover: a box laid over one of a row's items (a segmented choice's thumb, a tab's underline), placed in the same
// layout as the items are, where its item is and as big. So it goes with them as they move or change size (a page
// sliding in, a window resized, words of another size), in the frame they do, and that is no motion of its own. Only
// another item covered is: said once as it starts (what it set out from, the item it goes to, when, on a spring of
// its own: motion_data.mbt), its place in a frame is the blend of those items' places as laid out in that frame, so
// it keeps to them even while they move.

///|
struct CoverState {
  /// what it set out from: items (by their place among the items) and their shares, summing to 1
  mut from : Array[(Int, Double)]
  mut to : Int
  /// from 0 (at `from`) to 1 (at `to`)
  path : SpringPath
  mut seen : Int
}

///|
/// A cover asked for this frame, built over its items once they are laid out.
struct CoverAsk {
  holder : Int
  items : Array[Int]
  from : Array[(Int, Double)]
  to : Int
  p : Double
  look : (Ctx, Double, Double) -> Unit
  // the theme and the direction where it was asked for: it is built after layout, theirs ended (as a list's rows)
  theme : Theme
  direction : Direction
}

///|
/// A cover's spring (Ctx::spring's: 420 stiff, 32 damped), from 0 (where it set out) to 1 (the item it goes to): at
/// rest within 1/2000 of the way.
let cover_k : Double = 420.0

///|
let cover_c : Double = 32.0

///|
let cover_rest : Double = 0.0005

///|
fn cover_spring() -> SpringPath {
  SpringPath::new(1.0, k=cover_k, c=cover_c, rest=cover_rest)
}

///|
/// A cover's spring's way (cover_spring's, for what moves a cover otherwise: a node's, @motion.cover_spring): `t` ms
/// after it set out `d` from its rest at `v` a second, how far from it and how fast (a second).
pub fn cover_spring_at(d : Double, v : Double, t : Double) -> (Double, Double) {
  spring_at(d, v, cover_k, cover_c, t / 1000.0)
}

///|
/// When (ms after it set out `d` from its rest at `v` a second) a cover's spring is at rest: cover_spring's end.
pub fn cover_spring_end(d : Double, v : Double) -> Double {
  1000.0 * spring_end(d, v, cover_k, cover_c, cover_rest)
}

///|
/// How long a cover takes from one item to another (ms): the same however far, its way being from 0 to 1.
pub let cover_slide_ms : Double = cover_spring_end(-1.0, 0.0)

///|
/// Where a cover sets out from as it is sent to another item: where it is (`p` of the way from `from`, the items it
/// set out from by their shares, to `to`) as a blend of items by their shares, summing to 1.
pub fn cover_set_out(from : Array[(Int, Double)], to : Int, p : Double) -> Array[(Int, Double)] {
  let out : Array[(Int, Double)] = []
  let mut put_to = false
  for e in from {
    if e.0 == to {
      out.push((e.0, e.1 * (1.0 - p) + p))
      put_to = true
    } else {
      out.push((e.0, e.1 * (1.0 - p)))
    }
  }
  if !put_to {
    out.push((to, p))
  }
  out
}

///|
/// Where a cover is, `p` of its way from `from` (items by their shares) to `to`: the blend of the items' boxes (x, y,
/// width, height) as `rect` has them where they are now (None: an item gone, left out of what it set out from; the
/// one it goes to gone, None).
pub fn cover_rect(
  from : Array[(Int, Double)],
  to : Int,
  p : Double,
  rect : (Int) -> (Double, Double, Double, Double)?,
) -> (Double, Double, Double, Double)? {
  guard rect(to) is Some(t) else { return None }
  let mut x = 0.0
  let mut y = 0.0
  let mut w = 0.0
  let mut h = 0.0
  let mut share = 0.0
  for e in from {
    match rect(e.0) {
      Some(r) => {
        x = x + r.0 * e.1
        y = y + r.1 * e.1
        w = w + r.2 * e.1
        h = h + r.3 * e.1
        share = share + e.1
      }
      None => ()
    }
  }
  let (fx, fy, fw, fh) = if share.abs() < 1.0e-9 {
    t
  } else {
    (x / share, y / share, w / share, h / share)
  }
  Some((fx + (t.0 - fx) * p, fy + (t.1 - fy) * p, dmax(0.0, fw + (t.2 - fw) * p), dmax(0.0, fh + (t.3 - fh) * p)))
}

///|
/// A box over item `at` of `items` (the items' nodes, built this frame), built by `look` (given its width and height)
/// in `holder` (a node built before the items, drawn behind them: a layer over their ground). Placed once they are
/// laid out, in this frame, where the item is; to another item on its spring when `at` is
/// another than it was. One not shown last frame is where it is at once.
pub fn Ctx::cover(
  self : Ctx,
  key : String,
  holder : Int,
  items : Array[Int],
  at : Int,
  look : (Ctx, Double, Double) -> Unit,
) -> Unit {
  let id = self.id(key)
  let s = match self.covers.get(id) {
    Some(s) if s.seen >= self.frame_no - 1 => s
    _ => {
      let s = {
        from: [(at, 1.0)],
        to: at,
        path: cover_spring(),
        seen: self.frame_no,
      }
      self.covers[id] = s
      s
    }
  }
  s.seen = self.frame_no
  if at != s.to {
    // where it is now, as a blend: what it set out from by 1 - p, the item it went to by p; from there to `at`
    let p = s.path.value(self.now_before(s.path.end()))
    s.from = cover_set_out(s.from, s.to, p)
    s.to = at
    s.path.put(0.0)
    s.path.go(self.clock, 1.0)
  }
  if self.still() {
    s.path.put(1.0)
  }
  self.cover_asks.push({
    holder,
    items,
    from: s.from,
    to: s.to,
    p: s.path.value(self.now_before(s.path.end())),
    look,
    theme: self.theme,
    direction: self.direction,
  })
}

///|
/// Once laid out: each cover asked for this frame built and laid out over its items (where they are now, blended).
fn Ctx::covers_after_layout(self : Ctx) -> Unit {
  if self.cover_asks.is_empty() {
    return
  }
  for a in self.cover_asks {
    let rect = fn(k : Int) -> (Double, Double, Double, Double)? {
      if k >= 0 && k < a.items.length() {
        let n = self.nodes[a.items[k]]
        Some((n.x, n.y, n.fw, n.fh))
      } else {
        None
      }
    }
    guard cover_rect(a.from, a.to, a.p, rect) is Some((bx, by, bw, bh)) else { continue }
    let saved = self.cur
    let (saved_theme, saved_dir) = (self.theme, self.direction)
    self.theme = a.theme
    self.direction = a.direction
    self.cur = a.holder
    let i = self.alloc(kind_box)
    self.nodes[i].w = Px(bw)
    self.nodes[i].h = Px(bh)
    self.with_parent(i, fn() { (a.look)(self, bw, bh) })
    self.cur = saved
    self.theme = saved_theme
    self.direction = saved_dir
    self.layout(i, bx, by, bw, bh) |> ignore
  }
  self.cover_asks.clear()
}
