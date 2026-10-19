// What the default looks share: the focus ring, the tints of what is pointed at and pressed, the look of what is
// disabled. A component's look is a function of its state (docs/components.md, rule 1): an app passes its own.

///|
/// The ring round what has the keyboard's focus (when `shown`), `radius` the corner of what it rings, as wide and as
/// far out as the theme says. Built last in the box it rings (laid over it, its size the box's last frame: `rect`).
pub fn focus_ring(c : @ui.Ctx, shown : Bool, rect : (Double, Double, Double, Double), radius : Double) -> Unit {
  let (_, _, w, h) = rect
  if !shown || w <= 0.0 {
    return
  }
  let t = c.theme()
  let out = t.focus_gap + t.focus_w
  c.layer(fn() {
    c.box(
      w=Px(w + 2.0 * out),
      h=Px(h + 2.0 * out),
      tx=-out,
      ty=-out,
      radius=radius + out,
      border=t.focus_w,
      border_color=t.focus,
      fn() {  },
    )
    |> ignore
  })
  |> ignore
}

///|
/// `ground` as it shows pointed at (`hovered`) or held (`pressed`): the theme's tint over it, twice when held.
pub fn tinted(c : @ui.Ctx, ground : Int64, hovered : Bool, pressed : Bool) -> Int64 {
  let t = c.theme()
  if pressed {
    @ui.over(@ui.over(ground, t.hover), t.hover)
  } else if hovered {
    @ui.over(ground, t.hover)
  } else {
    ground
  }
}

///|
/// How opaque what is disabled is drawn.
pub let disabled_alpha : Double = 0.4

///|
/// A tint twice as strong (its alpha doubled, at most opaque): what is held, over nothing.
pub fn doubled(tint : Int64) -> Int64 {
  let a = (tint & 0xFFL) * 2L
  (tint & 0xFFFFFF00L) | (if a > 255L { 255L } else { a })
}

///|
/// `a` going to `b` as `t` goes from 0 to 1, channel by channel (alpha too).
pub fn blend(a : Int64, b : Int64, t : Double) -> Int64 {
  let k = if t < 0.0 { 0.0 } else if t > 1.0 { 1.0 } else { t }
  let ch = fn(sh : Int) -> Int64 {
    let x = ((a >> sh) & 0xFFL).to_double()
    let y = ((b >> sh) & 0xFFL).to_double()
    (x + (y - x) * k).round().to_int64() << sh
  }
  ch(24) | ch(16) | ch(8) | ch(0)
}

///|
/// Of two values by `on`.
fn[T] pick(on : Bool, yes : T, no : T) -> T {
  if on {
    yes
  } else {
    no
  }
}

///|
/// The id of part `k` of the widget `id` (a group's item, a slider's thumb).
pub fn part_id(id : Int, k : Int) -> Int {
  let mut h = id ^ ((k + 1) * 0x5bd1e995)
  h = h ^ (h >> 15)
  h = h * 0x27d4eb2d
  h = h ^ (h >> 13)
  if h == 0 {
    1
  } else {
    h
  }
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// `yes` (a widget's value changed as it was built): a frame again, so that what the view builds from the value it
/// keeps shows it.
fn told(c : @ui.Ctx, yes : Bool) -> Bool {
  if yes {
    c.request_frame()
  }
  yes
}

///|
/// A chevron down (or, `up`, up) in `color`, on the middle of the words beside it (the glyphs sit low and high).
fn chevron(c : @ui.Ctx, up : Bool, color : Int64) -> Unit {
  let t = c.theme()
  c.box(ty=if up { 3.0 } else { -3.0 }, fn() {
    c.text(if up { "⌃" } else { "⌄" }, size=t.font + 1.0, color~, wrap=false) |> ignore
  })
  |> ignore
}
