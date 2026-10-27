// A change of theme shown spreading from where it was asked (Telegram's): the window as it was drawn, read back as a
// picture as the change is asked (Ctx::reveal_from: its last frame, as the host draws it), stays under; the window as
// it is now comes over it in a circle growing from that point till it covers it all (reveal_ms, easing out). Asked by
// what changes the theme (a person's pick of it, at the point they picked it), it sets out in the first frame whose view
// is drawn in another theme (the pick goes through the app's settings first): told by the view's build itself, so that
// frame is already in the circle; let go when none is in reveal_wait_most. Where the host reads no frame back, or its
// picture is not decoded by then, nothing: the theme changes at once. While it spreads the window's presses go to what
// shows in the circle; what lies over the page (overlay.mbt's layers) is over both, as it is.

///|
/// The reveal asked: the picture of the window as it was ("" none), where it spreads from, the theme it was drawn in
/// and how to tell the one it is drawn in now, when it was asked and when it set out (-1: not yet), a number of its own
/// for its picture, what moves it.
priv struct Reveal {
  mut key : String
  mut x : Double
  mut y : Double
  mut dark : Bool
  mut dark_now : () -> Bool
  mut asked : Double
  mut start : Double
  mut serial : Int
  mover : Mover
}

///|
// kept across runs: said by the app asking it and the frames drawing it; reveal_reset puts it back
let reveal : Reveal = {
  key: "",
  x: 0.0,
  y: 0.0,
  dark: false,
  dark_now: fn() { false },
  asked: 0.0, start: -1.0, serial: 0, mover: Mover::new() }

///|
fn reveal_reset() -> Unit {
  reveal_drop()
  reveal.serial = 0
}

///|
fn reveal_drop() -> Unit {
  if reveal.key != "" {
    image_data.remove(reveal.key)
  }
  reveal.key = ""
  reveal.start = -1.0
  reveal.dark_now = fn() { false }
}

///|
/// The view's box over the picture: the window's.
// kept across runs: a value (no field of it changes)
let reveal_view : Style = css("w=Full h=Full")

///|
/// How long the circle takes to cover the window, and how long a reveal asked waits for the theme to change.
pub let reveal_ms : Double = 620.0

///|
let reveal_wait_most : Double = 3000.0

///|
/// The circle's way: its end, for the frames to go on till then (Ctx::moving).
priv struct RevealRun {
  end : Double
}

///|
impl Moving for RevealRun with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  self.end
}

///|
/// The theme is about to change (a person picked another), shown spreading from (`x`, `y`) in the window: the window as
/// it is drawn now kept as a picture, the next one coming over it from there once the theme it is drawn in changes.
/// `dark` says whether the view is drawn dark, read as its build ends (the Ctx's theme's by default; an app that themes
/// its view itself, `with_theme` in it, says its own).
pub fn Ctx::reveal_from(self : Ctx, x : Double, y : Double, dark? : () -> Bool) -> Unit {
  let dark_now = match dark {
    Some(f) => f
    None => fn() { self.theme.dark }
  }
  let cols = (self.width * self.scale).round().to_int()
  let rows = (self.height * self.scale).round().to_int()
  let n = self.ninst
  if cols <= 0 || rows <= 0 || n == 0 {
    return
  }
  // (the last frame's instances, as it was painted: this frame is not painted yet)
  let inst = FixedArray::make(n * inst_size, 0.0)
  self.inst.blit_to(inst, len=n * inst_size)
  let out = FixedArray::make(cols * rows * 4, b'\x00')
  if !h_drawn_pixels_of(inst, n, self.scale, cols, rows, out) {
    return
  }
  let png = @pixels.PngRows::new(cols, rows)
  png.add(out, rows)
  reveal_drop()
  reveal.serial += 1
  reveal.key = "mem:reveal/\{reveal.serial}"
  add_image(reveal.key, png.end())
  // (its decoding started now, so that it is ready by the time the theme changes)
  self.image_ready(reveal.key, (if cols > rows { cols } else { rows }).to_double()) |> ignore
  reveal.x = x
  reveal.y = y
  reveal.dark = dark_now()
  reveal.dark_now = dark_now
  reveal.asked = self.now
}

///|
/// The view (`view`, the window `w` by `h`), under a reveal while one spreads (see the file's head): while one is asked,
/// the view built in a box over the picture, drawn cut to the circle (a look: pressed as laid out, the whole window)
/// once it is built and has said its theme.
fn Ctx::revealed(self : Ctx, w : Double, h : Double, view : () -> Unit) -> Unit {
  if reveal.key == "" {
    view()
    return
  }
  // the window as it was, under; the window as it is, over it
  let key = reveal.key
  let mut picture = -1
  self.layer(fn() { picture = self.image(key, w=Px(w), h=Px(h), fit=FitFill, bg=0L, fade=false) }) |> ignore
  let now = self.layer(fn() { self.box(style=reveal_view, fn() { view() }) |> ignore })
  if reveal.start < 0.0 && (reveal.dark_now)() != reveal.dark {
    // (its picture not decoded yet: the theme changes at once, as where none is read back, never over nothing)
    if !self.image_ready(key, dmax(w, h) * self.scale) {
      self.look(picture, look(alpha=0.0))
      reveal_drop()
      return
    }
    reveal.start = self.now
    let run : RevealRun = { end: self.now + reveal_ms }
    self.moving(reveal.mover, run as &Moving, what="the theme's reveal")
  }
  let p = if reveal.start < 0.0 { 1.0 } else { (self.now - reveal.start) / reveal_ms }
  if p >= 1.0 {
    // not set out (or done): the view as it is, the picture hidden
    self.look(picture, look(alpha=0.0))
    if reveal.start >= 0.0 || self.now - reveal.asked > reveal_wait_most {
      reveal_drop()
    }
    return
  }
  let e = 1.0 - (1.0 - p) * (1.0 - p) * (1.0 - p)
  // as far as the window's furthest corner from where it spreads
  let fx = dmax(reveal.x, w - reveal.x)
  let fy = dmax(reveal.y, h - reveal.y)
  let r = dmax(0.5, (fx * fx + fy * fy).sqrt() * e)
  self.look(now, look(ox=reveal.x / w, oy=reveal.y / h, circle=r))
}
