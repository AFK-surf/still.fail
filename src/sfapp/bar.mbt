// The phone's bottom bar (ember apps/android shared/ui/Bar.kt BottomBar, shared/Places.kt PlaceBar): a floating capsule
// of the places of one bar, 22 in from the screen's sides and its foot (the system's bars are the host's: the view is
// laid out inside them); a ball over the place shown that travels on a spring stretched by its speed and goes where a
// finger takes it; the page's primary action in a notch cut out of the bar's top (令, a new chat, on the chats'
// pages); with more than one bar, the glass grows upward into a panel of the other bars, one row each, open once a
// finger on the bar is drawn 24 over it and closed once back under 16, and a bar chosen there is the bar. Every
// motion is a number on a spring (or a timed glide) stepped a frame at a time. Shown on a place's top page with
// nothing over it; gone down out of the way (300 ms) under a page pushed, back up (380 ms) as it comes back.
//
// The glass is frosted on the phone (the pages blurred under it); here it is its tint over the page's paper, the look
// the app has where nothing blurs (Glass.kt `floating` ground: --raised at 72% over the paper): `bar_ground` is where
// that is chosen, for the glass work to switch.

// ── geometry (Bar.kt, dp) ──────────────────────────────────────────────

///|
let bar_track : Double = 56.0

///|
let bar_inset : Double = 6.0

///|
let ball_rest : Double = bar_track - bar_inset * 2.0

///|
let ball_size : Double = bar_track + 12.0

///|
let c0 : Double = bar_inset + ball_rest / 2.0

///|
let drop : Double = 56.0

///|
let notch_gap : Double = 6.0

///|
let lift : Double = 4.0

///|
let fillet : Double = 8.0

///|
let bar_row : Double = 56.0

///|
let over : Double = 20.0

///|
let rad : Double = bar_track / 2.0

///|
let slot_px : Double = 90.0

///|
let lean : Double = 0.25

///|
let max_stretch : Double = 36.0

///|
let opens : Double = 24.0

///|
let closes : Double = 16.0

///|
/// What a place's top page keeps clear at its foot for the bar (Places.kt BAR_ROOM: the bar, its 22 from the foot, a
/// little air, and the action standing 32 over it).
let bar_room : Double = 56.0 + 22.0 + 16.0 + 32.0

///|
/// Every place a bar can hold (the core's BAR_PLACES); the chats' family, whose pages have 令 in the notch.
let places : Array[String] = [
  "chats", "decisions", "files", "stations", "profiles", "connects", "usage", "archive",
]

///|
let chat_family : Array[String] = ["chats", "decisions", "archive"]

///|
/// The bars before the core has said (BARS_DEFAULT).
fn default_bars() -> (Array[Array[String]], Int) {
  ([["chats", "files", "profiles", "stations"], ["decisions", "usage", "connects", "archive"]], 0)
}

///|
/// The bars whole, as the core keeps them (prefs.ts barsOf): each one to four known places, none twice; empty ones
/// dropped; none left, the default ones; the one in view one of them.
fn bars_of(v : Json?) -> (Array[Array[String]], Int) {
  let sets : Array[Array[String]] = []
  for s in items(v, "sets") {
    let kept : Array[String] = []
    match s {
      Array(a) =>
        for p in a {
          match p {
            String(k) if places.contains(k) && !kept.contains(k) && kept.length() < 4 =>
              kept.push(k)
            _ => ()
          }
        }
      _ => ()
    }
    if kept.length() > 0 {
      sets.push(kept)
    }
  }
  if sets.length() == 0 {
    return default_bars()
  }
  let cur = number(v, "current").to_int()
  (sets, if cur < 0 { 0 } else if cur >= sets.length() { sets.length() - 1 } else { cur })
}

///|
/// The places' middles on a bar `w` wide holding `n` with the notch `k` open (Bar.kt barCentres).
fn bar_centres(w : Double, k : Double, n : Int) -> Array[Double] {
  let closed = (w - 2.0 * c0) / 3.0
  let open = w / 2.0 - (drop / 2.0 + notch_gap) - 6.0 - ball_rest / 2.0 - c0
  let sp = closed + (open - closed) * k
  if n >= 4 {
    [c0, c0 + sp, w - c0 - sp, w - c0]
  } else if n == 3 {
    let mid = w / 2.0 - c0 - (w / 2.0 - c0 - sp) * k
    [c0, c0 + mid, w - c0, w - c0]
  } else if n == 2 {
    [c0, w - c0, w - c0, w - c0]
  } else {
    [c0, c0, c0, c0]
  }
}

///|
fn nearest(cs : Array[Double], n : Int, x : Double) -> Int {
  let mut best = 0
  for j in 0..<imin(n, cs.length()) {
    if (cs[j] - x).abs() < (cs[best] - x).abs() {
      best = j
    }
  }
  best
}

///|
fn imin(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

// ── motion ─────────────────────────────────────────────────────────────

///|
/// One number on a spring (react-spring's tension and friction, mass 1), stepped a frame at a time (Bar.kt BarSpring).
priv struct Spr {
  mut x : Double
  mut v : Double
  mut to : Double
  mut tension : Double
  mut friction : Double
}

///|
fn spr(start : Double, tension : Double, friction : Double) -> Spr {
  { x: start, v: 0.0, to: start, tension, friction }
}

///|
fn Spr::moving(self : Spr) -> Bool {
  self.v != 0.0 || self.x != self.to
}

///|
fn Spr::go(self : Spr, to : Double, tension : Double, friction : Double) -> Unit {
  self.to = to
  self.tension = tension
  self.friction = friction
}

///|
fn Spr::step(self : Spr, dt : Double) -> Unit {
  let mut x = self.x
  let mut v = self.v
  let mut left = dt
  while left > 0.0 {
    let h = dmin(left, 0.004)
    left = left - h
    v = v + (-self.tension * (x - self.to) - self.friction * v) * h
    x = x + v * h
  }
  if (x - self.to).abs() < 0.001 && v.abs() < 0.01 {
    x = self.to
    v = 0.0
  }
  self.x = x
  self.v = v
}

///|
/// One number gliding to where it is sent over a time on a curve (Bar.kt Glide).
priv struct Glide {
  mut value : Double
  mut target : Double
  mut from : Double
  mut t : Double
  mut span : Double
  mut curve : Int
}

///|
fn glide(start : Double) -> Glide {
  { value: start, target: start, from: start, t: 0.0, span: 0.0, curve: 0 }
}

///|
/// Sent to `target` over `ms` on `curve` (0 CSS's ease, 1 Arrive, 2 linear); nothing new when it is going there.
fn Glide::go(self : Glide, target : Double, ms : Double, curve : Int) -> Unit {
  if target == self.target {
    return
  }
  self.from = self.value
  self.target = target
  self.t = 0.0
  self.span = ms / 1000.0
  self.curve = curve
}

///|
fn Glide::step(self : Glide, dt : Double) -> Unit {
  if self.value == self.target {
    return
  }
  self.t = self.t + dt
  let p = if self.span <= 0.0 { 1.0 } else { dmin(1.0, self.t / self.span) }
  let e = match self.curve {
    0 => @ui.bezier(0.25, 0.1, 0.25, 1.0, p)
    1 => @ui.bezier(0.2, 0.8, 0.2, 1.0, p)
    _ => p
  }
  self.value = if p >= 1.0 {
    self.target
  } else {
    self.from + (self.target - self.from) * e
  }
}

///|
/// What the bar keeps between frames (Bar.kt BarModel, BallMotion).
priv struct BarModel {
  /// the panel of the other bars open (or opening, or the finger's)
  mut mode : Bool
  /// how open the panel is (0 the bar, 1 the panel); the notch (1 open); the ball held
  o : Spr
  k : Spr
  held : Spr
  /// the bar shown, the ball shown and its size
  vis : Glide
  ball_alpha : Glide
  ball_scale : Glide
  /// each place drawn ("bar:<place>", "row:<place>"): how lit
  tints : Map[String, Glide]
  /// the ball: where, how fast (per second), where it is sent, how stiff across
  mut bx : Double
  mut by : Double
  mut bvx : Double
  mut bvy : Double
  mut gx : Double
  mut gy : Double
  mut tension : Double
  /// how far the ball went to the place shown last (its spring as stiff as the way is short)
  mut trip : Double
  mut active_was : String
  /// a finger: where it has the ball (-1 none), its height once the panel is its own
  mut drag : Double
  mut drag_y : Double
  mut holds : Bool
  mut from_open : Bool
  mut open : Bool
  mut y0 : Double
  mut o0 : Double
  mut was_down : Bool
  /// first drawn: everything where it goes at once
  mut placed : Bool
  mut width : Double
}

///|
let bar : BarModel = {
  mode: false,
  o: spr(0.0, 260.0, 17.0),
  k: spr(1.0, 300.0, 30.0),
  held: spr(0.0, 420.0, 16.0),
  vis: glide(0.0),
  ball_alpha: glide(1.0),
  ball_scale: glide(1.0),
  tints: {},
  bx: 0.0,
  by: 0.0,
  bvx: 0.0,
  bvy: 0.0,
  gx: 0.0,
  gy: 0.0,
  tension: 300.0,
  trip: slot_px,
  active_was: "",
  drag: -1.0,
  drag_y: -1.0,
  holds: false,
  from_open: false,
  open: false,
  y0: 0.0,
  o0: 0.0,
  was_down: false,
  placed: false,
  width: 0.0,
}

///|
/// As at the start (tests).
fn bar_reset() -> Unit {
  bar.mode = false
  bar.o.x = 0.0
  bar.o.to = 0.0
  bar.o.v = 0.0
  bar.vis.value = 0.0
  bar.vis.target = 0.0
  bar.tints.clear()
  bar.drag = -1.0
  bar.drag_y = -1.0
  bar.holds = false
  bar.placed = false
  bar.was_down = false
  bars_picked.val = None
}

///|
fn BarModel::open_panel(self : BarModel, open : Bool) -> Unit {
  self.mode = open
  if open {
    self.o.go(1.0, 260.0, 17.0)
  } else {
    self.o.go(0.0, 320.0, 26.0)
  }
}

///|
/// The notch as drawn: as its place has it, closed as far as the panel is drawn up (fully by half open).
fn BarModel::k_now(self : BarModel) -> Double {
  self.k.x * (1.0 - dclamp(2.0 * self.o.x, 0.0, 1.0))
}

///|
fn BarModel::moving(self : BarModel) -> Bool {
  self.o.moving() ||
  self.k.moving() ||
  self.held.moving() ||
  self.vis.value != self.vis.target ||
  self.ball_alpha.value != self.ball_alpha.target ||
  self.ball_scale.value != self.ball_scale.target ||
  self.bvx != 0.0 ||
  self.bvy != 0.0 ||
  self.bx != self.gx ||
  self.by != self.gy ||
  self.tints.values().any(fn(g) { g.value != g.target })
}

///|
fn BarModel::step(self : BarModel, dt : Double) -> Unit {
  for s in [self.o, self.k, self.held] {
    if s.moving() {
      s.step(dt)
    }
  }
  for g in [self.vis, self.ball_alpha, self.ball_scale] {
    g.step(dt)
  }
  for _, g in self.tints {
    g.step(dt)
  }
  // the ball: across as stiff as the way is short, down and up 300; damped as the web's (ZETA 0.635)
  let cx = 2.0 * 0.635 * self.tension.sqrt()
  let cy = 2.0 * 0.635 * 300.0.sqrt()
  let mut nx = self.bx
  let mut ny = self.by
  let mut left = dt
  while left > 0.0 {
    let h = dmin(left, 0.004)
    left = left - h
    self.bvx = self.bvx + (-self.tension * (nx - self.gx) - cx * self.bvx) * h
    nx = nx + self.bvx * h
    self.bvy = self.bvy + (-300.0 * (ny - self.gy) - cy * self.bvy) * h
    ny = ny + self.bvy * h
  }
  if (self.gx - nx).abs() < 0.01 && self.bvx.abs() < 0.01 {
    nx = self.gx
    self.bvx = 0.0
  }
  if (self.gy - ny).abs() < 0.01 && self.bvy.abs() < 0.01 {
    ny = self.gy
    self.bvy = 0.0
  }
  self.bx = nx
  self.by = ny
}

///|
/// Everything where it is going, at once (screenshots, the first frame).
fn BarModel::jump(self : BarModel) -> Unit {
  for s in [self.o, self.k, self.held] {
    s.x = s.to
    s.v = 0.0
  }
  for g in [self.vis, self.ball_alpha, self.ball_scale] {
    g.value = g.target
  }
  for _, g in self.tints {
    g.value = g.target
  }
  self.bx = self.gx
  self.by = self.gy
  self.bvx = 0.0
  self.bvy = 0.0
}

// ── what the bar is told ───────────────────────────────────────────────

///|
/// The notch's action's icon, as last shown (kept as it closes).
let m_face : Ref[String] = { val: "ling" }

///|
/// The bars as switched here, before the prefs say it.
let bars_picked : Ref[(Array[Array[String]], Int)?] = { val: None }

///|
/// The bars of workspace `ws`: switched here, else its own as the prefs keep them (`barsBy`), else everyone's (`bars`).
fn bars_in(src : Source, ws : String) -> (Array[Array[String]], Int) {
  match bars_picked.val {
    Some(b) => b
    None => {
      let prefs = (src.topic)("prefs", {}).value
      match field(field(prefs, "barsBy"), ws) {
        Some(Object(_)) as b => bars_of(b)
        _ =>
          match field(prefs, "bars") {
            Some(Object(_)) as b => bars_of(b)
            _ => default_bars()
          }
      }
    }
  }
}

///|
/// Another bar in view (AppState.setBars): shown at once, kept whole as the workspace's (`prefs.set {barsBy}`).
fn set_bars(src : Source, ws : String, sets : Array[Array[String]], cur : Int) -> Unit {
  bars_picked.val = Some((sets, cur))
  let whole = Json::object({
    "sets": Json::array(sets.map(fn(s) { Json::array(s.map(fn(p) { Json::string(p) })) })),
    "current": Json::number(cur.to_double()),
  })
  let by : Map[String, Json] = Map::new()
  by[ws] = whole
  (src.call)("prefs.set", Json::object({ "barsBy": Json::object(by) }), fn(_) {  })
}

///|
/// A place's name (the bar's words for what a screen reader says, the place's page's title).
fn place_label(place : String) -> String {
  tr("android-misc.bar.place." + place)
}

///|
/// A place's icon (Places.kt placeIcon; the stations' glyph of their state is the server's mark here).
fn place_icon(place : String) -> String {
  match place {
    "chats" => "chats"
    "decisions" => "zou"
    "files" => "folder"
    "profiles" => "quota"
    "connects" => "im"
    "usage" => "chart"
    "archive" => "archive"
    _ => "server"
  }
}

///|
/// The place a page is the top of (none: it is not a place's).
fn place_of(page : Page) -> String? {
  match page {
    Home => Some("chats")
    Files => Some("files")
    Decisions => Some("decisions")
    Place(p) => Some(p)
    _ => None
  }
}

// ── drawing ────────────────────────────────────────────────────────────

///|
/// The glass's own colour where nothing blurs (Glass.kt: --raised at 72% over the paper), the one place it is chosen.
fn bar_ground() -> Int64 {
  let t = @sf.theme()
  @sf.over(t.p.bg, @sf.alpha(t.p.raised, 0.72))
}

///|
/// A box at (x, y) in its parent, `w` × `h`, laid over what is there.
fn at(
  c : @ui.Ctx,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  clip? : Bool = false,
  bg? : Int64 = 0L,
  radius? : Double = 0.0,
  border? : Double = 0.0,
  border_color? : Int64 = 0L,
  opacity? : Double = 1.0,
  id? : Int = 0,
  body? : () -> Unit = fn() {  },
) -> Unit {
  c.layer(fn() {
    c.box(
      w=Px(w),
      h=Px(h),
      tx=x,
      ty=y,
      clip~,
      bg~,
      radius~,
      border~,
      border_color~,
      opacity~,
      id~,
      body,
    )
    |> ignore
  })
  |> ignore
}

///|
/// The glass `w` wide from `top` to `bottom` (in the panel's frame) with the notch cut into its top: a circle of
/// radius `r` about (w/2, top + cy), met by the edge through fillets (Bar.kt outline, notch). Drawn from rounded
/// rectangles and rings in clips: the ends whole, the middle as a ring about the notch (what is outside it), the lips'
/// fillets as their discs.
fn bar_glass(c : @ui.Ctx, w : Double, top : Double, bottom : Double, cy : Double, r : Double) -> Unit {
  let t = @sf.theme()
  let ground = bar_ground()
  let h = bottom - top
  let corner = dmin(rad, h / 2.0)
  // the lit rim inside its edge (the web's inset shadows), as one hairline here
  let rim = @sf.alpha(0xFFFFFFFFL, if t.dark { 0.14 } else { 0.35 })
  let cx = w / 2.0
  let dy = fillet - cy
  let reach = (r + fillet) * (r + fillet) - dy * dy
  if r <= 0.5 || cy + r <= 0.5 || reach <= 0.0 {
    at(c, 0.0, top, w, h, bg=ground, radius=corner, border=0.5, border_color=rim)
    return
  }
  let xf = reach.sqrt()
  let l = cx - xf
  let rr = cx + xf
  // where each fillet meets the circle
  let k = fillet / (r + fillet)
  let tx = l + (cx - l) * k
  let ty = fillet + (cy - fillet) * k
  // the ends, whole, each in its clip
  at(c, 0.0, top, l, h, clip=true, body=fn() {
    at(c, 0.0, 0.0, w, h, bg=ground, radius=corner, border=0.5, border_color=rim)
  })
  at(c, rr, top, w - rr, h, clip=true, body=fn() {
    at(c, -rr, 0.0, w, h, bg=ground, radius=corner, border=0.5, border_color=rim)
  })
  // the middle under the lips: what is outside the circle
  let big = r + h + xf + 40.0
  at(c, l, top + ty, rr - l, h - ty, clip=true, body=fn() {
    at(
      c,
      cx - big - l,
      cy - big - ty,
      big * 2.0,
      big * 2.0,
      radius=big,
      border=big - r,
      border_color=ground,
    )
    // the notch's edge, lit as the rim
    at(
      c,
      cx - r - 1.0 - l,
      cy - r - 1.0 - ty,
      (r + 1.0) * 2.0,
      (r + 1.0) * 2.0,
      radius=r + 1.0,
      border=1.0,
      border_color=@sf.alpha(0xFFFFFFFFL, if t.dark { 0.22 } else { 0.7 }),
    )
  })
  // the bottom's hairline under the middle
  at(c, l, bottom - 0.5, rr - l, 0.5, bg=rim)
  // the lips: the fillets' discs
  at(c, l, top, tx - l, ty, clip=true, body=fn() {
    at(c, -fillet, 0.0, fillet * 2.0, fillet * 2.0, bg=ground, radius=fillet)
  })
  at(c, 2.0 * cx - tx, top, rr - (2.0 * cx - tx), ty, clip=true, body=fn() {
    at(c, rr - (2.0 * cx - tx) - fillet, 0.0, fillet * 2.0, fillet * 2.0, bg=ground, radius=fillet)
  })
}

///|
/// The bar's shadow (Bar.kt: below the glass and to its sides only, none above its top or under it): a blurred
/// rounded rectangle 4 lower, seen only outside the glass.
fn bar_shadow(c : @ui.Ctx, w : Double, top : Double, bottom : Double) -> Unit {
  let t = @sf.theme()
  let h = bottom - top
  let color = @sf.alpha(0x000000FFL, if t.dark { 0.45 } else { 0.16 })
  let cast = fn() {
    c.box(
      w=Px(w),
      h=Px(h),
      ty=4.0,
      radius=dmin(rad, h / 2.0),
      shadow=10.0,
      shadow_color=color,
      shadow_y=0.0,
      fn() {  },
    )
    |> ignore
  }
  // left, right, under
  at(c, -40.0, top, 40.0, h + 40.0, clip=true, body=fn() { at(c, 40.0, 0.0, w, h, body=cast) })
  at(c, w, top, 40.0, h + 40.0, clip=true, body=fn() { at(c, -w, 0.0, w, h, body=cast) })
  at(c, 0.0, bottom, w, 40.0, clip=true, body=fn() { at(c, 0.0, -h, w, h, body=cast) })
}

///|
/// A place's look: its icon (28) in `idle`, `lit` over it as far as it is lit (`v`: two pictures, one each colour,
/// rather than one more of each colour on its way between them), its dot at the icon's top right.
fn place_face(c : @ui.Ctx, place : String, idle : Int64, lit : Int64, v : Double, dot : Int64) -> Unit {
  let name = place_icon(place)
  if v < 0.999 {
    @sf.icon(c, name, size=28.0, color=idle) |> ignore
  }
  if v > 0.001 {
    c.layer(align=ACenter, fn() {
      c.box(h=Fill(1.0), justify=JCenter, opacity=v, fn() {
        @sf.icon(c, name, size=28.0, color=lit) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  if dot != 0L {
    c.layer(align=ACenter, fn() {
      c.box(h=Fill(1.0), justify=JCenter, fn() {
        c.box(w=Px(7.0), h=Px(7.0), radius=3.5, bg=dot, tx=13.5, ty=-12.5, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// How lit place `id` is now, sent toward `on` (300 ms, CSS's ease); it is as it is when it comes.
fn tint_of(id : String, on : Bool) -> Double {
  let g = match bar.tints.get(id) {
    Some(g) => g
    None => {
      let g = glide(if on { 1.0 } else { 0.0 })
      bar.tints[id] = g
      g
    }
  }
  g.go(if on { 1.0 } else { 0.0 }, 300.0, 0)
  g.value
}

///|
/// The bottom bar over the pages of `w` (Places.kt PlaceBar, Bar.kt BottomBar). `shown`: on a place's top page with
/// nothing over it; `active`: the place shown (its top page's).
fn bottom_bar(c : @ui.Ctx, src : Source, ws : Workspace, active : String?, shown : Bool) -> Unit {
  let t = @sf.theme()
  let (sets, cur) = bars_in(src, ws.id)
  let items = sets[cur]
  let others : Array[Int] = []
  for i in 0..<sets.length() {
    if i != cur {
      others.push(i)
    }
  }
  let rows = if others.length() > 1 { others.length() } else { 1 }
  let panel = bar_track + rows.to_double() * bar_row + over
  let row_top = panel - bar_track
  let reach = row_top - over
  let bar_mid = row_top + bar_track / 2.0
  let w = c.width - 44.0
  let slot = (w - 2.0 * c0) / 3.0
  // the page's primary action in the notch (Places.kt PlaceBar): 令 on the chats' pages, 文件's ＋ while it can lend
  // a folder (Files.kt), none on the others yet
  let action = match active {
    Some(a) if chat_family.contains(a) => "ling"
    Some("files") if files_can_lend(src, ws) => "plus"
    _ => ""
  }
  let notched = action != ""
  if action != "" {
    m_face.val = action
  }
  // the dots: 奏 waiting (the accent), a station in trouble (red)
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(ws.id) })
  let decisions = count(field(field(marks.value, "workspaces"), ws.id), "decisions")
  let chats = (src.topic)("chats", { "scope": Json::string(ws.id), "mine": Json::boolean(false) })
  let dots : Map[String, Int64] = Map::new()
  if decisions > 0 {
    dots["decisions"] = t.p.accent
  }
  match field(chats.value, "trouble") {
    Some(Object(_)) => dots["stations"] = t.p.red
    _ => ()
  }
  let m = bar
  // told each frame: shown or not, the notch as the place has it
  m.vis.go(if shown { 1.0 } else { 0.0 }, if shown { 380.0 } else { 300.0 }, 1)
  if !shown {
    if m.mode {
      m.open_panel(false)
    }
    m.drag = -1.0
    m.drag_y = -1.0
    m.holds = false
  }
  m.k.to = if notched { 1.0 } else { 0.0 }
  let ai = match active {
    Some(a) => items.search(a).unwrap_or(-1)
    None => -1
  }
  let final_cs = bar_centres(w, if notched && !m.mode { 1.0 } else { 0.0 }, items.length())
  // the finger's place, and the place a let-go would choose: the ball keeps to it, leaning toward the finger
  let cand : (Double, Double, Int, String)? = if m.drag >= 0.0 {
    let x = m.drag
    if m.drag_y >= 0.0 && m.drag_y < row_top - 4.0 && others.length() > 0 {
      let n = dclamp(((m.drag_y - over) / bar_row).floor(), 0.0, (others.length() - 1).to_double()).to_int()
      let set = sets[others[n]]
      let cs = bar_centres(w, 0.0, set.length())
      let j = nearest(cs, set.length(), x)
      Some((cs[j], over + n.to_double() * bar_row + bar_row / 2.0, others[n], set[j]))
    } else if items.length() > 0 {
      let j = imin(items.length() - 1, nearest(final_cs, 4, x))
      Some((final_cs[j], bar_mid, cur, items[j]))
    } else {
      None
    }
  } else {
    None
  }
  let (goal_x, goal_y) = match cand {
    Some((cx, cy, _, _)) =>
      (cx + (m.drag - cx) * lean, cy + ((if m.drag_y >= 0.0 { m.drag_y } else { bar_mid }) - cy) * lean)
    None => (final_cs[if ai < 0 { 0 } else { ai }], bar_mid)
  }
  let sliding = m.drag >= 0.0
  let active_key = active.unwrap_or("")
  if !sliding && active_key != m.active_was {
    m.active_was = active_key
    m.trip = dmax(8.0, (goal_x - m.bx).abs())
  }
  m.gx = goal_x
  m.gy = goal_y
  m.tension = if sliding { 300.0 } else { dclamp(300.0 * slot_px / m.trip, 90.0, 700.0) }
  if m.width != w {
    // a new width (turned): there at once
    m.width = w
    m.bx = goal_x
    m.bvx = 0.0
  }
  m.held.to = if sliding { 1.0 } else { 0.0 }
  let ball_shown = ai >= 0 || sliding
  m.ball_alpha.go(if ball_shown { 1.0 } else { 0.0 }, 200.0, 0)
  m.ball_scale.go(if ball_shown { 1.0 } else { 0.6 }, 250.0, 0)
  // the frame's motion
  if !m.placed || c.stable() {
    m.placed = true
    m.jump()
  } else {
    m.step(c.frame_dt() / 1000.0)
  }
  if m.moving() {
    c.request_frame()
  }
  if m.vis.value <= 0.0 && !shown {
    return
  }
  let under = match cand {
    Some((_, _, set, key)) => if set == cur { key } else { "" }
    None => active_key
  }
  let k_now = m.k_now()
  let clip_top = dmax(0.0, over + reach * (1.0 - m.o.x))
  let notch_r = (drop / 2.0 + notch_gap) * k_now
  let notch_y = -lift * k_now
  let idle = if t.dark { 0xD1D5DBFFL } else { 0x6B7280FFL }
  let lit = if t.dark { 0xFFFFFFFFL } else { 0x111827FFL }
  // the panel's frame in the window
  let fx = 22.0
  let fy = c.height - 22.0 - panel
  // the panel open: a press anywhere else closes it (and does nothing else)
  if shown && m.mode {
    let catcher = c.id("bar/catch")
    match c.drag_of(catcher) {
      Some(d) => if d.down || d.take_tap() { m.open_panel(false) }
      None => ()
    }
    c.layer(fn() {
      c.drag_area(catcher, axis=Hold, w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
    })
    |> ignore
    c.on_back(fn() { m.open_panel(false) })
  }
  // the gestures on the glass
  let glass_id = c.id("bar/glass")
  if shown {
    match c.drag_of(glass_id) {
      Some(d) => bar_gesture(c, src, ws, d, sets, cur, others, active, fx, fy, w, panel, final_cs)
      None => ()
    }
  }
  let action_id = c.id("bar/action")
  if c.clicked(action_id) && shown && k_now > 0.9 {
    match action {
      "ling" => new_chat(c)
      "plus" => files_lend(c, src, ws)
      _ => ()
    }
  }
  c.layer(fn() {
    c.spacer()
    c.box(
      w=Px(w),
      h=Px(panel),
      tx=22.0,
      ty=-22.0 + (1.0 - m.vis.value) * 120.0,
      opacity=m.vis.value,
      fn() {
        bar_shadow(c, w, clip_top, panel)
        bar_glass(c, w, clip_top, panel, notch_y, notch_r)
        // the glass takes the gestures (its places' taps are read where they land)
        at(c, 0.0, clip_top, w, panel - clip_top, body=fn() {
          c.drag_area(glass_id, axis=Free, w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
        })
        // 令 in the notch: accent glass, growing out of the bar as the notch opens
        // (closing, the action keeps its icon as it shrinks)
        if k_now > 0.001 {
          let s = dmax(0.001, k_now)
          let size = drop * s
          let cy = row_top + notch_y
          at(
            c,
            w / 2.0 - size / 2.0,
            cy - size / 2.0,
            size,
            size,
            bg=@sf.over(t.p.bg, @sf.alpha(t.p.accent, 0.86)),
            radius=size / 2.0,
            border=0.5,
            border_color=@sf.alpha(0xFFFFFFFFL, 0.4),
            opacity=dmin(1.0, k_now * 3.0),
            id=if k_now > 0.9 { action_id } else { 0 },
            body=fn() {
              c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
                // its icon in eight sizes on the way (a picture each, kept), not one each frame
                // (closing, the last action's icon as it shrinks; 令 40, any other 30)
                let q = (s * 8.0).round() / 8.0
                let face = m_face.val
                if q > 0.1 {
                  @sf.icon(c, face, size=(if face == "ling" { 40.0 } else { 30.0 }) * q, color=0xFFFFFFFFL)
                  |> ignore
                }
              })
              |> ignore
            },
          )
        }
        // the ball, under the places, stretched by its speed toward where it goes
        let scale = (1.0 + 0.06 * m.held.x) * m.ball_scale.value
        let v = if (goal_x - m.bx).abs() < 0.5 { 0.0 } else { m.bvx / 60.0 }
        let stretch = dmin(max_stretch, v.abs() * 1.6)
        let bw = ball_size + stretch
        let bh = ball_size - dmin(6.0, stretch * 0.2)
        let left = m.bx - ball_size / 2.0 - (if v < 0.0 { stretch } else { 0.0 })
        let bcx = left + bw / 2.0
        let sw = bw * scale
        let sh = bh * scale
        if m.ball_alpha.value > 0.0 {
          let ball_bg = @sf.over(bar_ground(), @sf.alpha(0xFFFFFFFFL, if t.dark { 0.12 } else { 0.42 }))
          at(
            c,
            bcx - sw / 2.0,
            m.by - sh / 2.0,
            sw,
            sh,
            opacity=m.ball_alpha.value,
            body=fn() {
              c.box(
                w=Fill(1.0),
                h=Fill(1.0),
                radius=dmin(sw, sh) / 2.0,
                bg=ball_bg,
                border=0.5,
                border_color=@sf.alpha(0xFFFFFFFFL, if t.dark { 0.22 } else { 0.5 }),
                shadow=4.0,
                shadow_y=1.0,
                shadow_color=if t.dark { 0x00000059L } else { 0x37352D33L },
                fn() {  },
              )
              |> ignore
            },
          )
        }
        // the other bars, above this one, as the panel opens
        if m.mode || m.o.x > 0.001 {
          let rows_alpha = dclamp((m.o.x - 0.35) / 0.65, 0.0, 1.0)
          let shift = (1.0 - dmin(1.0, m.o.x)) * 14.0 - dmax(0.0, m.o.x - 1.0) * reach
          for n, i in others {
            let set = sets[i]
            let cs = bar_centres(w, 0.0, set.length())
            for j, key in set {
              let on = match cand {
                Some((_, _, cs_set, ck)) => cs_set == i && ck == key
                None => active_key == key
              }
              let tint = tint_of("row:" + key, on)
              at(
                c,
                cs[j] - slot / 2.0,
                over + n.to_double() * bar_row + 4.0 + shift,
                slot,
                48.0,
                opacity=rows_alpha,
                body=fn() {
                  c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
                    place_face(c, key, idle, lit, tint, dots.get(key).unwrap_or(0L))
                  })
                  |> ignore
                },
              )
            }
          }
        }
        // the bar's places, over the ball
        let now_cs = bar_centres(w, k_now, items.length())
        for j, key in items {
          let tint = tint_of("bar:" + key, under == key)
          at(c, now_cs[j] - slot / 2.0, row_top + 4.0, slot, 48.0, body=fn() {
            c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
              place_face(c, key, idle, lit, tint, dots.get(key).unwrap_or(0L))
            })
            |> ignore
          })
        }
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// What a finger does on the glass (Bar.kt BarModel down, move, up, letGo, tap): a stroke any way takes the ball; up,
/// with more than one bar, the panel; a tap picks a place (on the bar), or a bar and its place (in the open panel).
fn bar_gesture(
  c : @ui.Ctx,
  src : Source,
  ws : Workspace,
  d : @ui.Drag,
  sets : Array[Array[String]],
  cur : Int,
  others : Array[Int],
  active : String?,
  fx : Double,
  fy : Double,
  w : Double,
  panel : Double,
  final_cs : Array[Double],
) -> Unit {
  let m = bar
  let items = sets[cur]
  let multi = sets.length() > 1
  let row_top = panel - bar_track
  let reach = row_top - over
  let px = d.x - fx
  let py = d.y - fy
  let on_tab = fn(place : String) {
    if Some(place) != active {
      go_place(c, place, sets, cur)
    }
  }
  let pick = fn(i : Int, key : String?) {
    m.mode = false
    m.o.go(0.0, 200.0, 28.0)
    set_bars(src, ws.id, sets, i)
    match key {
      Some(k) => go_place(c, k, sets, i)
      None => ()
    }
  }
  if d.down && !m.was_down {
    // pressed: the panel open, opening or closing, the finger has it from here
    m.was_down = true
    m.y0 = py
    m.o0 = m.o.x
    m.holds = multi && (m.o0 > 0.02 || (m.o.moving() && m.o.to > 0.0))
    m.from_open = m.holds
    m.open = m.o.to > 0.5
    if m.holds {
      m.mode = true
    }
  }
  if d.down && d.moving {
    if multi {
      let raw = m.o0 + (m.y0 - py - (if m.from_open { 0.0 } else { 8.0 })) / reach
      if !m.holds && raw > 0.0 {
        m.holds = true
        m.mode = true
      }
      if m.holds {
        let over_bar = row_top - py
        if !m.open && over_bar > opens {
          m.open = true
        } else if m.open && over_bar < closes {
          m.open = false
        }
        let snap = if m.open { 1.0 } else { 0.0 }
        let goal = dclamp(snap + lean * (raw - snap), 0.0, 1.1)
        if m.open {
          m.o.go(goal, 260.0, 17.0)
        } else {
          m.o.go(goal, 320.0, 26.0)
        }
      }
    }
    m.drag = px
    m.drag_y = if multi && m.holds && m.open {
      dclamp(py, over + bar_row / 2.0, row_top + bar_track / 2.0)
    } else {
      -1.0
    }
    c.request_frame()
  }
  if d.take_end() {
    m.was_down = false
    let had = m.holds
    m.holds = false
    m.drag = -1.0
    m.drag_y = -1.0
    if had {
      // let go on a row (the panel open): that bar and that place; else as the finger left it
      let in_rows = py < row_top - 4.0 && others.length() > 0
      if in_rows && m.o.x >= 0.85 {
        let n = dclamp(((py - over) / bar_row).floor(), 0.0, (others.length() - 1).to_double()).to_int()
        let set = sets[others[n]]
        pick(others[n], Some(set[nearest(bar_centres(w, 0.0, set.length()), set.length(), px)]))
      } else {
        let j = if py >= row_top - 4.0 && items.length() > 0 {
          imin(items.length() - 1, nearest(final_cs, 4, px))
        } else {
          -1
        }
        m.open_panel(m.open)
        if !m.open && j >= 0 {
          on_tab(items[j])
        }
      }
    } else if items.length() > 0 {
      let j = imin(items.length() - 1, nearest(final_cs, 4, px))
      if m.mode {
        m.open_panel(false)
      }
      on_tab(items[j])
    }
    c.request_frame()
  }
  if d.take_tap() {
    m.was_down = false
    m.holds = false
    // a tap: a place on the bar; with the panel open, a row (that bar) or a place in it
    if m.mode && py < row_top {
      if m.o.x > 0.6 && others.length() > 0 {
        let shift = (1.0 - dmin(1.0, m.o.x)) * 14.0 - dmax(0.0, m.o.x - 1.0) * reach
        let n = ((py - over - shift) / bar_row).floor().to_int()
        if n >= 0 && n < others.length() {
          let set = sets[others[n]]
          let cs = bar_centres(w, 0.0, set.length())
          let j = nearest(cs, set.length(), px)
          let slot = (w - 2.0 * c0) / 3.0
          pick(others[n], if (cs[j] - px).abs() <= slot / 2.0 { Some(set[j]) } else { None })
        }
      }
    } else if items.length() > 0 && py >= row_top - 4.0 {
      let now = bar_centres(w, m.k_now(), items.length())
      let j = nearest(now, items.length(), px)
      let slot = (w - 2.0 * c0) / 3.0
      if (now[j] - px).abs() <= slot / 2.0 {
        if m.mode {
          m.open_panel(false)
        }
        on_tab(items[j])
      }
    }
    c.request_frame()
  }
  if !d.down {
    m.was_down = false
  }
}

///|
/// A place's top page other than the chats (PlacePage.kt, with the bar under it): Home's top bar over it (settings,
/// the place's name), what it shows a later slice's.
fn place_page(c : @ui.Ctx, place : String) -> Unit {
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    place_top_bar(c, place)
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A place's top bar at the stack's root (PlacePage.kt TopGlassBar): settings, the place's name, a hairline under.
fn place_top_bar(c : @ui.Ctx, place : String) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), bg=@sf.alpha(t.p.bg, 0.94), fn() {
    c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=16.0, pt=8.0, pb=8.0, gap=10.0, align=ACenter, fn() {
      if nav_button(c, "settings", 22.0, key="place-settings") {
        app.nav.push(Settings)
      }
      c.box(w=Fill(1.0), h=Px(34.0), justify=JCenter, fn() {
        c.text(place_label(place), size=24.0, weight=700, color=t.p.text, wrap=false, line=30.0)
        |> ignore
      })
      |> ignore
    })
    |> ignore
    c.box(w=Fill(1.0), h=Px(0.5), bg=t.p.line, fn() {  }) |> ignore
  })
  |> ignore
}
