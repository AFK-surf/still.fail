// What a person does on the device, as a station's screen takes it (ember apps/android app/remote/Input.kt;
// docs/remote-screens.md, `screen.input`): points in 0..1 of the frame, buttons as the DOM's bit mask, keys by the DOM's
// KeyboardEvent names, typed text as it is committed. And the frame's own zoom and the trackpad's pointer, on this
// device only (ScreenViewer.kt ViewZoom: mbui's @kit.Zoom; PadPointer).

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
/// A mouse button pressed and let go at `at`, the keys of `mods` held round it (⌘-click, ⇧-click).
fn click(send : (Json) -> Unit, at : (Double, Double), button : Int, mods : Int) -> Unit {
  mods_round(send, mods, "down")
  send(pointer_input("down", at, button))
  send(pointer_input("up", at, button))
  mods_round(send, mods, "up")
}

///|
/// The keys held on this device (@ui.mods_held: mod_shift_key, mod_ctrl, mod_alt, mod_cmd) as the station takes them.
fn mods_of_held(held : Int) -> Int {
  (if (held & @ui.mod_alt) != 0 { mod_alt } else { 0 }) |
  (if (held & @ui.mod_ctrl) != 0 { mod_ctrl } else { 0 }) |
  (if (held & @ui.mod_cmd) != 0 { mod_meta } else { 0 }) |
  (if (held & @ui.mod_shift_key) != 0 { mod_shift } else { 0 })
}

///|
/// The modifier keys of `mods`, each its key going `kind` ("down" before a press, "up" after it), so a click with ⇧ or
/// ⌘ held is one there too (a key held alone never comes to a key catcher).
fn mods_round(send : (Json) -> Unit, mods : Int, kind : String) -> Unit {
  for k in [
    (mod_meta, "Meta", "MetaLeft"),
    (mod_ctrl, "Control", "ControlLeft"),
    (mod_alt, "Alt", "AltLeft"),
    (mod_shift, "Shift", "ShiftLeft"),
  ] {
    if (mods & k.0) != 0 {
      send(key_input(kind, k.1, k.2, mods))
    }
  }
}

///|
/// The station's pointer's shape (a CSS cursor's name: docs/remote-screens.md `cursor`) as this device draws its own.
fn cursor_of_shape(shape : String) -> @ui.Cursor {
  match shape {
    "pointer" => Hand
    "text" | "vertical-text" => IBeam
    "ew-resize" | "col-resize" | "e-resize" | "w-resize" => ResizeX
    "ns-resize" | "row-resize" | "n-resize" | "s-resize" => ResizeY
    "grab" | "move" | "all-scroll" => Grab
    "grabbing" => Grabbing
    "crosshair" => Crosshair
    "not-allowed" | "no-drop" => NotAllowed
    _ => Arrow
  }
}

///|
/// The modifiers tapped on the keys row (⌘ ⌃ ⌥ ⇧, which a phone's keyboard has not): held for the next key or
/// character, then let go, as a phone's own shift is.
priv struct HeldKeys {
  mods : @signals.Signal[Int]
}

///|
fn HeldKeys::toggle(self : HeldKeys, bit : Int) -> Unit {
  self.mods.set(self.mods.get() ^ bit)
}

///|
/// What is held, for a key now: let go of after it.
fn HeldKeys::take(self : HeldKeys) -> Int {
  let m = self.mods.get()
  self.mods.set(0)
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
/// The frame's own zoom, on this device only (never sent): mbui's @kit.Zoom, the frame fitted edge to edge (larger
/// than its pixels where the stage has room), zoomed from the fitted size to `screen_max_zoom` times it. Kept within
/// the stage: smaller than it, centred; larger, no gap at its edges.
fn screen_zoom() -> @kit.Zoom {
  @kit.Zoom::new(margin=fn(_) { 0.0 }, enlarge=true, min_scale=fn(fit) { fit }, max_scale=fn(fit) {
    fit * screen_max_zoom
  })
}

///|
/// The most a screen is zoomed in, over its fitted size.
let screen_max_zoom : Double = 5.0

///|
/// Where the frame is drawn on the stage now (zoomed), nothing before its size is known.
fn ScreenUi::shown(self : ScreenUi) -> SRect {
  match self.zoom.rect() {
    Some((x, y, w, h)) => { x, y, w, h }
    None => srect_zero
  }
}

///|
/// The part of the frame in sight while it is zoomed in (0..1 of it each way); None while it is not (all of it is).
fn ScreenUi::in_sight(self : ScreenUi) -> Part? {
  let s = self.shown()
  if !self.zoom.zoomed() || s.w <= 0.0 || s.h <= 0.0 || self.box_w.get() <= 0.0 || self.box_h.get() <= 0.0 {
    return None
  }
  let x0 = dmax(0.0, -s.x / s.w)
  let y0 = dmax(0.0, -s.y / s.h)
  let x1 = dmin(1.0, (self.box_w.get() - s.x) / s.w)
  let y1 = dmin(1.0, (self.box_h.get() - s.y) / s.h)
  if x1 <= x0 || y1 <= y0 {
    None
  } else {
    Some(({ x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : Part))
  }
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
  x : @signals.Signal[Double]
  y : @signals.Signal[Double]
  /// how many times the finger has moved it: the wait for the station's word starts again from each
  moves : @signals.Signal[Int]
}

///|
fn PadPointer::at(self : PadPointer) -> (Double, Double) {
  (self.x.get(), self.y.get())
}

///|
fn PadPointer::by(self : PadPointer, dx : Double, dy : Double) -> Unit {
  self.x.set(clamp01(self.x.get() + dx))
  self.y.set(clamp01(self.y.get() + dy))
  self.moves.set(self.moves.get() + 1)
}

///|
/// The station's word on where the pointer is, taken (once the finger has let it be: the caller says).
fn PadPointer::follow(self : PadPointer, cursor : (Double, Double)?) -> Unit {
  match cursor {
    Some((x, y)) => {
      self.x.set(clamp01(x))
      self.y.set(clamp01(y))
    }
    None => ()
  }
}
