// One sheet from the bottom at a time (ember apps/android shared/ui/Sheet.kt SheetHost): it rises on a spring over a
// scrim (black at 28%), takes its share of the screen (or fits what it shows), and its top (the grabber and the head,
// 64 high) drags it: a draggable sheet between half (55%) and nearly all (94%) of the screen, or down to close (under
// 30%); any other only down, closing past 80. Let go, it goes on at the finger's speed to where it settles; a tap on
// a draggable sheet's grabber switches it between half and full. A tap on the scrim, back, or the sheet dragged down
// closes it; it sinks away on the same spring. What it shows is its kind's (SheetKind), drawn anew each frame.

///|
/// Which sheet: what it shows and how it sits.
priv enum SheetKind {
  NoSheet
  /// the workspaces (Workspaces.kt WorkspacesSheet): 70%, draggable
  Workspaces
  /// where a new chat runs (NewChat.kt pickStation): half the screen
  PickStation(String)
  /// what a new chat runs on (NewChat.kt openRunPicker): 66%; its accounts' list in place of it while `accounts`
  RunPicker(String)
} derive(Eq)

///|
/// How a sheet sits: its share of the screen at first, whether its top drags it between half and full.
fn sheet_spec(kind : SheetKind) -> (Double, Bool) {
  match kind {
    Workspaces => (0.7, true)
    PickStation(_) => (0.5, false)
    RunPicker(_) => (0.66, false)
    NoSheet => (0.5, false)
  }
}

///|
/// A number on a spring (Motion.kt SheetSpring: motionSpring(0.32), critically damped; stiffness (2π / 1.2·0.32)²),
/// stepped a frame at a time; `v` per second.
priv struct Sp {
  mut x : Double
  mut v : Double
  mut to : Double
}

///|
let sheet_k : Double = {
  let w = 2.0 * 3.141592653589793 / (1.2 * 0.32)
  w * w
}

///|
fn Sp::step(self : Sp, dt_ms : Double) -> Bool {
  let k = sheet_k
  let damp = 2.0 * k.sqrt()
  let mut left = dmin(dt_ms, 64.0) / 1000.0
  while left > 0.0 {
    let h = dmin(left, 0.004)
    left = left - h
    self.v = self.v + (-k * (self.x - self.to) - damp * self.v) * h
    self.x = self.x + self.v * h
  }
  if (self.x - self.to).abs() < 0.5 && self.v.abs() < 5.0 {
    self.x = self.to
    self.v = 0.0
    false
  } else {
    true
  }
}

///|
priv struct SheetHost {
  /// asked open (NoSheet: closed), and what is drawn (until it has sunk away)
  mut kind : SheetKind
  mut shown : SheetKind
  /// how tall it is, and how far below its place (both on the spring)
  h : Sp
  off : Sp
  /// where a finger has its height while dragging (-1: none)
  mut held : Double
  /// the scrim: how much, from where, since when (300 ms, CSS's ease)
  mut scrim : Double
  mut scrim_from : Double
  mut scrim_at : Double
  /// just asked: placed at its first frame (from below, or changing height from the one before)
  mut fresh : Bool
  /// the run picker showing its accounts' list
  mut accounts : Bool
}

///|
let sheet_host : SheetHost = {
  kind: NoSheet,
  shown: NoSheet,
  h: { x: 0.0, v: 0.0, to: 0.0 },
  off: { x: 0.0, v: 0.0, to: 0.0 },
  held: -1.0,
  scrim: 0.0,
  scrim_from: 0.0,
  scrim_at: -1.0,
  fresh: false,
  accounts: false,
}

///|
/// Opens `kind` (in place of one open). What was typed lets go of the keyboard first.
fn raise_sheet(kind : SheetKind) -> Unit {
  let s = sheet_host
  if s.kind == NoSheet {
    s.scrim_from = s.scrim
    s.scrim_at = -1.0
  }
  s.kind = kind
  s.fresh = true
  s.accounts = false
  run_picker_opened.val = false
}

///|
/// Closes the sheet open: it sinks away.
fn lower_sheet() -> Unit {
  let s = sheet_host
  if s.kind == NoSheet {
    return
  }
  s.kind = NoSheet
  s.held = -1.0
  s.scrim_from = s.scrim
  s.scrim_at = -1.0
  s.off.to = s.h.x
}

///|
/// Whether a sheet is open.
fn sheet_open() -> Bool {
  sheet_host.kind != NoSheet
}

///|
/// How tall `kind` is at first (its share of `total`).
fn sheet_tall(kind : SheetKind, total : Double) -> Double {
  let (share, _) = sheet_spec(kind)
  share * total
}

///|
/// The sheet's own ground: frosted glass over the pages on the phone (Sheet.kt: the paper, the scrim's black, then the
/// surface at 80%, blurred 28). Here its look with nothing blurred, the one place the glass is chosen for a sheet.
fn sheet_ground(scrim : Double) -> Int64 {
  let t = @sf.theme()
  @sf.over(@sf.over(t.p.bg, @sf.alpha(0x000000FFL, 0.28 * scrim)), @sf.alpha(t.p.card, 0.8))
}

///|
/// The sheet, over everything (call last); `content` draws a kind's content in the room it is given.
fn sheet_layer(c : @ui.Ctx, content : (SheetKind) -> Unit) -> Unit {
  let s = sheet_host
  let total = c.height
  let dt = c.frame_dt()
  if s.fresh {
    s.fresh = false
    let target = sheet_tall(s.kind, total)
    if s.shown == NoSheet || s.off.x > 1.0 {
      // from below: its height at once, coming up
      s.h.x = target
      s.h.v = 0.0
      s.h.to = target
      s.off.x = target
      s.off.v = 0.0
      s.off.to = 0.0
    } else {
      s.h.to = target
      s.off.to = 0.0
    }
    s.shown = s.kind
  }
  if s.shown == NoSheet {
    return
  }
  // the scrim: 300 ms on CSS's ease toward 1 open, 0 closed
  let want = if s.kind == NoSheet { 0.0 } else { 1.0 }
  if s.scrim_at < 0.0 {
    s.scrim_at = c.now()
  }
  let p = if c.stable() { 1.0 } else { dmin((c.now() - s.scrim_at) / 300.0, 1.0) }
  s.scrim = s.scrim_from + (want - s.scrim_from) * @ui.bezier(0.25, 0.1, 0.25, 1.0, p)
  if c.stable() {
    s.h.x = s.h.to
    s.off.x = s.off.to
    s.h.v = 0.0
    s.off.v = 0.0
  } else {
    let moving_h = if s.held >= 0.0 { false } else { s.h.step(dt) }
    let moving_o = s.off.step(dt)
    if moving_h || moving_o || p < 1.0 {
      c.request_frame()
    }
  }
  if s.kind == NoSheet && s.off.x >= s.h.x - 0.5 && p >= 1.0 {
    // sunk away
    s.shown = NoSheet
    s.scrim = 0.0
    return
  }
  if s.kind != NoSheet {
    c.on_back(fn() { lower_sheet() })
  }
  let kind = s.shown
  let (_, draggable) = sheet_spec(kind)
  let base = sheet_tall(kind, total)
  let lowest = 120.0
  // the scrim, which a tap closes and nothing drags through
  let scrim_id = c.id("sheet/scrim")
  match c.drag_of(scrim_id) {
    Some(d) => if d.take_tap() { lower_sheet() }
    None => ()
  }
  // closed and sinking away, it takes nothing: what is under it is the finger's again
  let live = s.kind != NoSheet
  c.layer(fn() {
    let ground = fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=@sf.alpha(0x000000FFL, 0.28 * s.scrim), fn() {  })
      |> ignore
    }
    if live {
      c.drag_area(scrim_id, axis=Hold, w=Fill(1.0), h=Fill(1.0), ground) |> ignore
    } else {
      ground()
    }
  })
  |> ignore
  // its top drags it
  let top_id = c.id("sheet/top")
  match c.drag_of(top_id) {
    Some(d) => {
      let (_, dy) = d.take_move()
      if dy != 0.0 {
        let from = if s.held >= 0.0 { s.held } else { s.h.x }
        let to = dclamp(from - dy, lowest, if draggable { total * 0.94 } else { base })
        s.held = to
        s.h.x = to
        s.h.v = 0.0
        s.h.to = to
        c.request_frame()
      }
      if d.take_end() {
        let at = if s.held >= 0.0 { s.held } else { s.h.x }
        s.held = -1.0
        // up is more, per second
        let v = -d.vy * 1000.0
        let f = at / total
        // what it comes to, for scripted runs (e2e: a sheet opened and closed by dragging)
        if !draggable {
          if base - at > 80.0 {
            @host.log("SHEET dragged closed")
            lower_sheet()
          } else {
            @host.log("SHEET dragged back")
            settle(base, v)
          }
        } else if f < 0.3 {
          @host.log("SHEET dragged closed")
          lower_sheet()
        } else {
          @host.log(if f > 0.72 { "SHEET dragged to 94%" } else { "SHEET dragged to 55%" })
          settle(if f > 0.72 { total * 0.94 } else { total * 0.55 }, v)
        }
        c.request_frame()
      }
      // a tap on a draggable sheet's grabber: half or full
      if d.take_tap() && draggable && d.y - (total - s.h.x + s.off.x) < 30.0 {
        settle(if s.h.x > total * 0.9 { total * 0.55 } else { total * 0.94 }, 0.0)
        c.request_frame()
      }
    }
    None => ()
  }
  let t = @sf.theme()
  let h = s.h.x
  let body_id = c.id("sheet/body")
  c.layer(fn() {
    c.spacer()
    // 26 more under the screen's foot: its rounded corners are only the top's
    c.drag_area(body_id, axis=Hold, w=Fill(1.0), h=Px(h + 26.0), ty=s.off.x + 26.0, fn() {
      c.box(
        w=Fill(1.0),
        h=Fill(1.0),
        radius=26.0,
        bg=sheet_ground(s.scrim),
        shadow=24.0,
        clip=true,
        pb=26.0,
        fn() {
          // behind what it shows, so its buttons take their taps; over the body, so it takes the drags
          c.layer(fn() {
            c.drag_area(top_id, axis=Vertical, w=Fill(1.0), h=Px(64.0), fn() {  }) |> ignore
          })
          |> ignore
          content(kind)
        },
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
  ignore(t)
  // what it shows may have closed it or asked another (a row tapped): drawn again at once
  if s.kind != s.shown || s.fresh || s.off.x != s.off.to || s.h.x != s.h.to {
    c.request_frame()
  }
}

///|
/// Let go: on to `to` from where it is, at the finger's speed (per second, up is more).
fn settle(to : Double, v : Double) -> Unit {
  let s = sheet_host
  s.h.to = to
  s.h.v = v
}

// The grabber and a sheet's head (Sheet.kt SheetGrab, SheetHead) are decide.mbt's `sheet_grab`, `sheet_head`.

///|
fn dclamp(v : Double, lo : Double, hi : Double) -> Double {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}
