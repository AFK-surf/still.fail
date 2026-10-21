// What a person does on the device, as a station's screen takes it (ember apps/android app/remote/Input.kt;
// docs/remote-screens.md, `screen.input`): points in 0..1 of the frame, buttons as the DOM's bit mask, keys by the DOM's
// KeyboardEvent names, typed text as it is committed. And the frame's own zoom and the trackpad's pointer, on this
// device only (ScreenViewer.kt ViewZoom, PadPointer).

///|
/// The DOM's mouse buttons (MouseEvent.buttons).
let btn_primary : Int = 1

///|
let btn_secondary : Int = 2

///|
/// The modifier bits as the station takes them.
let mod_alt : Int = 1

///|
let mod_ctrl : Int = 2

///|
let mod_meta : Int = 4

///|
let mod_shift : Int = 8

///|
/// A rect on the stage: left, top, width, height (px).
priv struct SRect {
  x : Double
  y : Double
  w : Double
  h : Double
} derive(Eq, Show, Debug)

///|
// kept across runs: a value (no field of it changes)
let srect_zero : SRect = { x: 0.0, y: 0.0, w: 0.0, h: 0.0 }

///|
/// Where `p` (on the stage) is on the frame drawn at `shown` (on the stage too: letterboxed, zoomed), 0..1 each way.
/// Outside the frame: None, or the nearest edge when `clamp` (a drag that went past it).
fn screen_frame_at(px : Double, py : Double, shown : SRect, clamp : Bool) -> (Double, Double)? {
  if shown.w <= 0.0 || shown.h <= 0.0 {
    return None
  }
  let x = (px - shown.x) / shown.w
  let y = (py - shown.y) / shown.h
  if !clamp && (x < 0.0 || x > 1.0 || y < 0.0 || y > 1.0) {
    return None
  }
  Some((clamp01(x), clamp01(y)))
}

///|
fn clamp01(v : Double) -> Double {
  if v < 0.0 {
    0.0
  } else if v > 1.0 {
    1.0
  } else {
    v
  }
}

///|
fn clamp_to(v : Double, lo : Double, hi : Double) -> Double {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
/// Where a frame of `fw` × `fh` px fits whole in a stage of `bw` × `bh` px, centred (letterboxed).
fn fit_in(bw : Double, bh : Double, fw : Double, fh : Double) -> SRect {
  if fw <= 0.0 || fh <= 0.0 || bw <= 0.0 || bh <= 0.0 {
    return srect_zero
  }
  let k = dmin(bw / fw, bh / fh)
  let w = fw * k
  let h = fh * k
  { x: (bw - w) / 2.0, y: (bh - h) / 2.0, w, h }
}

///|
fn pointer_input(kind : String, at : (Double, Double), buttons : Int) -> Json {
  Json::object({
    "t": Json::string("pointer"),
    "kind": Json::string(kind),
    "x": Json::number(at.0),
    "y": Json::number(at.1),
    "buttons": Json::number(buttons.to_double()),
  })
}

///|
/// A wheel at `at`, `dx`/`dy` in CSS pixels (positive: scrolls right / down).
fn wheel_input(at : (Double, Double), dx : Double, dy : Double) -> Json {
  Json::object({
    "t": Json::string("wheel"),
    "x": Json::number(at.0),
    "y": Json::number(at.1),
    "dx": Json::number(dx),
    "dy": Json::number(dy),
  })
}

///|
fn key_input(kind : String, key : String, code : String, mods : Int) -> Json {
  Json::object({
    "t": Json::string("key"),
    "kind": Json::string(kind),
    "key": Json::string(key),
    "code": Json::string(code),
    "mods": Json::number(mods.to_double()),
  })
}

///|
fn text_input(words : String) -> Json {
  Json::object({ "t": Json::string("text"), "text": Json::string(words) })
}

///|
/// A key pressed and let go.
fn stroke(send : (Json) -> Unit, key : String, code : String, mods : Int) -> Unit {
  send(key_input("down", key, code, mods))
  send(key_input("up", key, code, mods))
}

///|
/// The modifiers tapped on the keys row (⌘ ⌃ ⌥ ⇧, which a phone's keyboard has not): held for the next key or
/// character, then let go, as a phone's own shift is.
priv struct HeldKeys {
  mut mods : Int
}

///|
fn HeldKeys::toggle(self : HeldKeys, bit : Int) -> Unit {
  self.mods = self.mods ^ bit
}

///|
/// What is held, for a key now: let go of after it.
fn HeldKeys::take(self : HeldKeys) -> Int {
  let m = self.mods
  self.mods = 0
  m
}

///|
/// The DOM's `code` of a character typed with a modifier held (⌘ then c: KeyC); "" for one with no key of its own.
fn code_of(ch : Char) -> String {
  let c = if ch >= 'A' && ch <= 'Z' { (ch.to_int() + 32).unsafe_to_char() } else { ch }
  if c >= 'a' && c <= 'z' {
    return "Key" + (c.to_int() - 32).unsafe_to_char().to_string()
  }
  if c >= '0' && c <= '9' {
    return "Digit" + c.to_string()
  }
  match c {
    ' ' => "Space"
    '-' => "Minus"
    '=' => "Equal"
    '[' => "BracketLeft"
    ']' => "BracketRight"
    '\\' => "Backslash"
    ';' => "Semicolon"
    '\'' => "Quote"
    ',' => "Comma"
    '.' => "Period"
    '/' => "Slash"
    '`' => "Backquote"
    _ => ""
  }
}

///|
/// Words typed (committed by the keyboard: KeyCatcher.type): lines as text, Enter between them; with a modifier held
/// on the keys row, each character as its key with it (⌘ then c: ⌘C).
fn type_words(send : (Json) -> Unit, held : HeldKeys, words : String) -> Unit {
  let mods = held.take()
  if mods != 0 {
    for ch in words {
      if ch == '\n' {
        stroke(send, "Enter", "Enter", mods)
      } else {
        stroke(send, ch.to_string(), code_of(ch), mods)
      }
    }
    return
  }
  for i, line in words.split("\n").to_array() {
    if i > 0 {
      stroke(send, "Enter", "Enter", 0)
    }
    if line.length() > 0 {
      send(text_input(line.to_string()))
    }
  }
}

///|
/// The frame's own zoom, on this device only (never sent): `scale` over the fitted size, the frame moved by `x`, `y`
/// (px) from where it sits fitted. Kept within the stage: smaller than it, centred; larger, no gap at its edges.
priv struct ViewZoom {
  mut scale : Double
  mut x : Double
  mut y : Double
}

///|
/// The most a screen is zoomed in, over its fitted size.
let screen_max_zoom : Double = 5.0

///|
fn ViewZoom::zoomed(self : ViewZoom) -> Bool {
  self.scale > 1.01
}

///|
/// Where the frame is drawn on the stage, fitted at `fit`.
fn ViewZoom::shown(self : ViewZoom, fit : SRect) -> SRect {
  { x: fit.x + self.x, y: fit.y + self.y, w: fit.w * self.scale, h: fit.h * self.scale }
}

///|
/// At `next` over `fit`, its top left at `left`, `top` on the stage as near as its edges let it be.
fn ViewZoom::put(
  self : ViewZoom,
  next : Double,
  left : Double,
  top : Double,
  fit : SRect,
  bw : Double,
  bh : Double,
) -> Unit {
  let place = fn(want : Double, size : Double, room : Double) {
    if size <= room {
      (room - size) / 2.0
    } else {
      clamp_to(want, room - size, 0.0)
    }
  }
  self.scale = next
  self.x = place(left, fit.w * next, bw) - fit.x
  self.y = place(top, fit.h * next, bh) - fit.y
}

///|
/// By `factor` around (fx, fy), and moved by (dx, dy) (on the stage, px).
fn ViewZoom::by(
  self : ViewZoom,
  factor : Double,
  fx : Double,
  fy : Double,
  dx : Double,
  dy : Double,
  fit : SRect,
  bw : Double,
  bh : Double,
) -> Unit {
  if fit.w <= 0.0 {
    return
  }
  let before = self.shown(fit)
  let next = clamp_to(self.scale * factor, 1.0, screen_max_zoom)
  let ux = (fx - before.x) / before.w
  let uy = (fy - before.y) / before.h
  self.put(next, fx - ux * fit.w * next + dx, fy - uy * fit.h * next + dy, fit, bw, bh)
}

///|
fn ViewZoom::pan(self : ViewZoom, dx : Double, dy : Double, fit : SRect, bw : Double, bh : Double) -> Unit {
  self.by(1.0, fit.x + fit.w / 2.0, fit.y + fit.h / 2.0, dx, dy, fit, bw, bh)
}

///|
/// `at` (0..1 of the frame) brought `margin` px within the stage's edges, the frame moved as little as it takes.
fn ViewZoom::keep(
  self : ViewZoom,
  at : (Double, Double),
  margin : Double,
  fit : SRect,
  bw : Double,
  bh : Double,
) -> Unit {
  let s = self.shown(fit)
  let px = s.x + at.0 * s.w
  let py = s.y + at.1 * s.h
  let off = fn(v : Double, room : Double) {
    if room < 2.0 * margin {
      room / 2.0 - v
    } else if v < margin {
      margin - v
    } else if v > room - margin {
      room - margin - v
    } else {
      0.0
    }
  }
  let dx = off(px, bw)
  let dy = off(py, bh)
  if dx != 0.0 || dy != 0.0 {
    self.pan(dx, dy, fit, bw, bh)
  }
}

///|
/// The stage resized (the keyboard up or down): the frame drawn as large as it was, so what is typed into stays as
/// legible, `at` (0..1 of the frame; else what was in the middle) where it was on the stage and kept in sight.
fn ViewZoom::refit(
  self : ViewZoom,
  before : SRect,
  after : SRect,
  bw : Double,
  bh : Double,
  at : (Double, Double)?,
  margin : Double,
) -> Unit {
  if before.w <= 0.0 || after.w <= 0.0 {
    self.reset()
    return
  }
  let was = self.shown(before)
  let u = match at {
    Some(a) => a
    None =>
      ((before.x + before.w / 2.0 - was.x) / was.w, (before.y + before.h / 2.0 - was.y) / was.h)
  }
  let next = clamp_to(was.w / after.w, 1.0, screen_max_zoom)
  self.put(
    next,
    was.x + u.0 * was.w - u.0 * after.w * next,
    was.y + u.1 * was.h - u.1 * after.h * next,
    after,
    bw,
    bh,
  )
  self.keep(u, margin, after, bw, bh)
}

///|
fn ViewZoom::reset(self : ViewZoom) -> Unit {
  self.scale = 1.0
  self.x = 0.0
  self.y = 0.0
}

///|
/// How far the pointer goes for a finger's move of 1 px, by how fast it moves (dp per ms): slowly, less than the
/// finger, to land on something small; fast, further, to cross the screen in a stroke.
fn pad_gain(dp_per_ms : Double) -> Double {
  0.55 + 1.6 * clamp01((dp_per_ms - 0.1) / 1.4)
}

///|
/// How long after the finger moved the pointer the station's word on it is taken again (its echo of the moves is
/// behind).
let pad_settle_ms : Double = 600.0

///|
/// Where the pointer is as the trackpad moves it (0..1 of the frame), ahead of the station saying so; where the
/// station says it is once the finger has been still a moment (something else moved it, or the screen's edge held it).
priv struct PadPointer {
  mut x : Double
  mut y : Double
  /// how many times the finger has moved it: the wait for the station's word starts again from each
  mut moves : Int
}

///|
fn PadPointer::at(self : PadPointer) -> (Double, Double) {
  (self.x, self.y)
}

///|
fn PadPointer::by(self : PadPointer, dx : Double, dy : Double) -> Unit {
  self.x = clamp01(self.x + dx)
  self.y = clamp01(self.y + dy)
  self.moves += 1
}

///|
/// The station's word on where the pointer is, taken (once the finger has let it be: the caller says).
fn PadPointer::follow(self : PadPointer, cursor : (Double, Double)?) -> Unit {
  match cursor {
    Some((x, y)) => {
      self.x = clamp01(x)
      self.y = clamp01(y)
    }
    None => ()
  }
}
