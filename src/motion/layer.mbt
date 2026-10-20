// Motion over layout: how nodes move without the layout knowing. All of it only changes how things are drawn (a
// look, @ui.Ctx::set_look; copies drawn under a list's rows): nothing here is laid out differently, nothing takes a
// tap, a focus or words, and nothing waits for it. A node is tapped where it is laid out, at once, whatever it looks
// like meanwhile. Over that:
//
// - layout animation by key (Motion's `layout`, FLIP, Compose's animateItem placement): a node with a key whose
//   laid-out place changed since the last frame is drawn from where it was and goes to its new place on a spring (or
//   a tween, or a progress the app drives), carrying on from where it had got to. In a list a place is the row's
//   place in the list's content, not on the screen, so scrolling moves nothing;
// - a list's rows by key (list_keys, ListMotion.kt): rows new to the list come in (an enter transition), rows gone
//   leave by a copy of how they were last drawn, shrinking and fading where they were, rows that went ahead of others
//   pass over them, the rest close over what left, a little late;
// - enter and exit transitions for what the app shows and hides (presence, Motion's AnimatePresence, Compose's
//   AnimatedVisibility: fade, slide, scale); what goes is only drawn while it goes (leaving: no tap is its);
// - a node flown from a rect to where it is laid out (fly: a shared element, Motion's `layoutId`; the words sent
//   flying from the composer into their bubble).
//
// Nothing of it runs while nothing moves: at rest every look is the identity and painting is as it was (screenshots
// stay the same).

///|
/// How something comes or goes (Compose's EnterTransition / ExitTransition): at its far end its opacity is `fade`, its
/// scale `scale` (about `ox`, `oy`), it is `dx`, `dy` off its place; the opacity goes by `fade_spec`, the rest by
/// `spec`.
pub(all) struct Trans {
  fade : Double
  scale : Double
  ox : Double
  oy : Double
  dx : Double
  dy : Double
  fade_spec : Spec
  spec : Spec
} derive(Show, Eq)

///|
/// A transition: fadeIn/Out to `fade`, scaleIn/Out to `scale`, slideIn/Out by `dx`, `dy`; all by `spec` unless the
/// fade has its own.
pub fn trans(
  fade? : Double = 1.0,
  scale? : Double = 1.0,
  ox? : Double = 0.5,
  oy? : Double = 0.5,
  dx? : Double = 0.0,
  dy? : Double = 0.0,
  spec? : Spec = tween(300.0),
  fade_spec? : Spec,
) -> Trans {
  {
    fade,
    scale,
    ox,
    oy,
    dx,
    dy,
    fade_spec: match fade_spec {
      Some(s) => s
      None => spec
    },
    spec,
  }
}

///|
/// How it looks `pf` of the way in by its opacity and `pm` by the rest (1: all the way in, as laid out).
pub fn Trans::at(self : Trans, pf : Double, pm : Double) -> @ui.Look {
  let s = self.scale + (1.0 - self.scale) * pm
  {
    alpha: self.fade + (1.0 - self.fade) * pf,
    dx: self.dx * (1.0 - pm),
    dy: self.dy * (1.0 - pm),
    sx: s,
    sy: s,
    ox: self.ox,
    oy: self.oy,
  }
}

// ── what this frame asks ────────────────────────────────────────────────

///|
/// A node of this frame with motion: its motion key and what the layer does with it.
priv struct Moving {
  node : Int
  mut key : Int
  /// layout animation: by `spec`; `gate` 1 only while its list's rows changed lately; `drive` ≥ 0: the move goes by
  /// that progress the app gives (0 → 1)
  mut flip : Bool
  mut spec : Spec
  mut gate : Int
  mut drive : Double
  /// in a list, by where it shows in the list's view rather than in its content (what the list's scrolling moves too)
  mut screen : Bool
  /// its key in words: what its motions are said as (Tester::moving: "layout KEY"), and the motion log's
  /// (MBUI_MOTION_LOG=1)
  mut name : String
  mut enter : Trans?
  mut exit : Trans?
  /// `enter` asked by the app (entering): it comes in the first frame it is built, whatever its list says
  mut fresh : Bool
  /// a height to keep (reveal's content, measure)
  mut measure : Bool
  /// a frame its keyed nodes' places are taken in (scope): 1 from its top left, 2 from its bottom left
  mut scope : Int
  /// flown from (x, y, scale), how far across, down and grown
  mut fly : (Double, Double, Double, Double, Double, Double)?
}

///|
/// What a keyed node was, kept from frame to frame: where it was laid out (in its list's content, or the window),
/// when, its offset on the way to its place, its entrance, and how it was last drawn (for its copy when it leaves).
priv struct Rec {
  mut x : Double
  mut y : Double
  mut w : Double
  mut h : Double
  mut ref : Int
  mut seen : Int
  /// where it showed in its list's view
  mut vy : Double
  ox : Anim
  oy : Anim
  /// what the app drives a move by: where the move started from
  mut fx : Double
  mut fy : Double
  mut driven : Bool
  mut enter : Trans?
  ef : Anim
  em : Anim
  /// how it was last drawn, relative to its list's corner
  drawing : @ui.Drawing
  mut exit : Trans?
  mut list : Int
}

///|
fn Rec::new() -> Rec {
  {
    x: 0.0,
    y: 0.0,
    w: 0.0,
    h: 0.0,
    ref: 0,
    seen: -10,
    vy: 0.0,
    ox: Anim::new(0.0),
    oy: Anim::new(0.0),
    fx: 0.0,
    fy: 0.0,
    driven: false,
    enter: None,
    ef: Anim::new(1.0),
    em: Anim::new(1.0),
    drawing: @ui.Drawing::new(),
    exit: None,
    list: 0,
  }
}

///|
/// A list's rows by key, as last told (list_keys): when they last changed, which came in, which went ahead of others,
/// until when the rest wait to close over what left.
priv struct ListMo {
  mut keys : Array[Int]
  /// the same, as given (what a row's copy is named by as it leaves)
  mut names : Array[String]
  mut changed_at : Double
  mut close_until : Double
  arrived : Map[Int, Double]
  lifted : Map[Int, Double]
  /// rows let go without a copy left behind (swiped away: list_unghost)
  unghost : Map[Int, Bool]
  mut seen : Int
}

///|
/// A row gone from its list (the list's id), drawn as it was last drawn while it leaves: its key's (layout_rest), its
/// two Anims named by it ("<key> leaving": Tester::moving, rest_of).
priv struct Ghost {
  list : Int
  key : Int
  drawing : @ui.Drawing
  trans : Trans
  pf : Anim
  pm : Anim
}

///|
priv struct MotionState {
  entries : Array[Moving]
  /// by node: its entry this frame (when `stamp` is this frame)
  at : Array[Int]
  stamp : Array[Int]
  /// the frame `entries` are of
  mut frame : Int
  recs : Map[Int, Rec]
  lists : Map[Int, ListMo]
  ghosts : Array[Ghost]
}

///|
let mo : MotionState = {
  entries: [],
  at: [],
  stamp: [],
  frame: -1,
  recs: {},
  lists: {},
  ghosts: [],
}

///|
// kept across runs: the hooks it guards are kept too (installed once in the process, by the packages over ui)
let installed : Ref[Bool] = { val: false }

///|
/// The layer plugged into ui's frame (once): its looks worked out after layout, its copies drawn under lists' rows,
/// its state forgotten when a Tester starts anew.
fn install() -> Unit {
  if installed.val {
    return
  }
  installed.val = true
  @ui.on_after_layout(after_layout)
  // fx.mbt's layout animations (after the layer's looks)
  @ui.on_after_layout(layouts_after)
  @ui.on_list_underlay(draw_ghosts)
  @ui.on_reset(reset)
}

///|
fn reset() -> Unit {
  mo.entries.clear()
  mo.at.clear()
  mo.stamp.clear()
  mo.frame = -1
  mo.recs.clear()
  mo.lists.clear()
  mo.ghosts.clear()
  anims.clear()
  reset_fx()
  motion_log.val = -1
}

///|
fn hash_mix(a : Int, b : Int) -> Int {
  let mut h = a ^ (b * 0x5bd1e995)
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
/// A motion key: the same string is the same thing wherever it is built (a row moving from one index of its list to
/// another keeps its key).
fn motion_key(key : String) -> Int {
  hash_mix(0x6d6f7469, @ui.stable_hash(key).to_int())
}

///|
/// Whether each frame's motion is logged (MBUI_MOTION_LOG=1: `MOTION <ms> <key> …`, scripts/motionplot.py).
fn logging() -> Bool {
  if motion_log.val < 0 {
    motion_log.val = if @ui.env("MBUI_MOTION_LOG") == "1" { 1 } else { 0 }
  }
  motion_log.val == 1
}

///|
/// A frame of a motion the app steps itself (a number on a spring of its own) into the motion log, as this package's
/// are: `MOTION <ms> <key> <fields>` (`name=value` …), when MBUI_MOTION_LOG=1.
pub fn log_frame(c : @ui.Ctx, key : String, fields : String) -> Unit {
  if logging() {
    @ui.log("MOTION \{c.now()} \{key} \{fields}")
  }
}

///|
let motion_log : Ref[Int] = { val: -1 }

///|
/// The entry of node `i` this frame, made when it has none.
fn moving_of(c : @ui.Ctx, i : Int) -> Moving {
  install()
  let frame = c.frame_number()
  if mo.frame != frame {
    mo.entries.clear()
    mo.frame = frame
  }
  while mo.at.length() <= i {
    mo.at.push(-1)
    mo.stamp.push(-1)
  }
  if mo.stamp[i] == frame && mo.at[i] >= 0 {
    return mo.entries[mo.at[i]]
  }
  let e : Moving = {
    node: i,
    key: 0,
    flip: false,
    spec: row_spring,
    gate: 0,
    drive: -1.0,
    screen: false,
    name: "",
    enter: None,
    exit: None,
    fresh: false,
    measure: false,
    scope: 0,
    fly: None,
  }
  mo.stamp[i] = frame
  mo.at[i] = mo.entries.length()
  mo.entries.push(e)
  e
}

///|
/// Node `i`'s entry this frame, if it has one.
fn entry_of(c : @ui.Ctx, i : Int) -> Moving? {
  let frame = c.frame_number()
  if mo.frame == frame && i >= 0 && i < mo.stamp.length() && mo.stamp[i] == frame && mo.at[i] >= 0 {
    Some(mo.entries[mo.at[i]])
  } else {
    None
  }
}

///|
/// Node `i` keyed `key` moves to its place when its place changes (Motion's `layout`, FLIP): drawn where it was, it
/// goes by `spec` to where it is now, carrying on from wherever it had got to. In a list told its rows (list_keys),
/// only as they change (`listed`: the list's own layout, a width or an item over the rows growing, is taken at once),
/// and `enter` is how a row new to it comes in, `exit` how one gone leaves (a copy of it where it was). `drive` (0 →
/// 1, from the frame it moved): the move goes by that progress instead of `spec`. `screen`: in a list, by where it
/// shows in the list's view.
pub fn layout(
  c : @ui.Ctx,
  i : Int,
  key : String,
  spec? : Spec = row_spring,
  listed? : Bool = true,
  enter? : Trans,
  exit? : Trans,
  drive? : Double = -1.0,
  screen? : Bool = false,
) -> Unit {
  let e = moving_of(c, i)
  e.name = key
  e.key = motion_key(key)
  e.flip = true
  e.screen = screen
  e.spec = spec
  e.gate = if listed { 1 } else { 0 }
  if enter is Some(_) {
    e.enter = enter
  }
  if exit is Some(_) {
    e.exit = exit
  }
  e.drive = drive
}

///|
/// Node `i` keyed `key`, kept from frame to frame (what it came in by goes on; in a list told its rows, one gone
/// leaves by `exit`, a copy of it).
pub fn keyed(c : @ui.Ctx, i : Int, key : String, exit? : Trans) -> Unit {
  let e = moving_of(c, i)
  e.name = key
  e.key = motion_key(key)
  if exit is Some(_) {
    e.exit = exit
  }
}

///|
/// Node `i` keyed `key` comes in by `enter` the first frame it is built (not when its key was built the frame
/// before): what is new as the app says (a message said while the chat shows).
pub fn entering(c : @ui.Ctx, i : Int, key : String, enter : Trans) -> Unit {
  let e = moving_of(c, i)
  e.name = key
  e.key = motion_key(key)
  e.enter = Some(enter)
  e.fresh = true
}

///|
/// Node `i` flown from (`x`, `y`, at `scale`) to where it is laid out (a shared element: Motion's `layoutId`): its
/// top left `px` of the way across, `py` of the way down and `ps` of the way grown (the words sent from the composer
/// to their bubble), drawn over everything (`z` 2) or over its siblings (1). Only drawn so: it is where it is laid
/// out for anything else.
pub fn fly(
  c : @ui.Ctx,
  i : Int,
  x : Double,
  y : Double,
  scale? : Double = 1.0,
  px~ : Double,
  py~ : Double,
  ps? : Double = 1.0,
  z? : Int = 2,
) -> Unit {
  let e = moving_of(c, i)
  if e.name == "" {
    e.name = "fly"
  }
  e.fly = Some((x, y, scale, px, py, ps))
  c.put_over(i, z~)
}

///|
/// The keyed nodes in node `i` take their places from its top left, or with `bottom` from its bottom left (what
/// stands on a bottom edge: the composer's parts), so that it moving (a keyboard coming up) moves none of them.
pub fn scope(c : @ui.Ctx, i : Int, bottom? : Bool = false) -> Unit {
  let e = moving_of(c, i)
  e.scope = if bottom { 2 } else { 1 }
}

///|
/// Node `i`'s height is kept as `key`'s (measured reads it).
pub fn measure(c : @ui.Ctx, i : Int, key : String) -> Unit {
  let e = moving_of(c, i)
  e.key = motion_key("measure\u{1}" + key)
  e.measure = true
}

///|
/// How tall the node kept as `key` was when last laid out (measure).
pub fn measured(c : @ui.Ctx, key : String) -> Double? {
  ignore(c)
  match mo.recs.get(motion_key("measure\u{1}" + key)) {
    Some(r) => Some(r.h)
    None => None
  }
}

///|
/// Where the node kept as `key` (measure) was last laid out, in the window: x, y, w, h (None before it was, or once it
/// has not been for a frame).
pub fn measured_rect(c : @ui.Ctx, key : String) -> (Double, Double, Double, Double)? {
  match mo.recs.get(motion_key("measure\u{1}" + key)) {
    Some(r) if r.seen >= c.frame_number() - 1 => Some((r.x, r.y, r.w, r.h))
    _ => None
  }
}

///|
/// The motion scope node `i` is in, if any (its entry).
fn scope_above(c : @ui.Ctx, i : Int) -> Moving? {
  let mut p = c.node_parent(i)
  while p >= 0 {
    if c.node_is_list(p) {
      return None
    }
    match entry_of(c, p) {
      Some(e) if e.scope != 0 => return Some(e)
      _ => ()
    }
    p = c.node_parent(p)
  }
  None
}

///|
/// When the node keyed `key` (layout, entering) is at its place and in (whole ms, the frames' clock): the latest of
/// its move's ends and its entrance's (Anim::ends_at); a row gone from its list, when its copy has left (its fade's
/// and its move's ends); before now (-1) when it is at rest or the key is not known; +inf when told to move in the
/// frame just drawn (it starts at the next: the frame owed, Tester::draw). Only read.
pub fn layout_rest(key : String) -> Double {
  let k = motion_key(key)
  let mut e = -1.0
  let at = fn(a : Anim) {
    let x = a.ends_at()
    if x > e {
      e = x
    }
  }
  match mo.recs.get(k) {
    Some(r) => [r.ox, r.oy, r.ef, r.em].each(at)
    None => ()
  }
  for gh in mo.ghosts {
    if gh.key == k {
      at(gh.pf)
      at(gh.pm)
    }
  }
  e
}

// ── a list's rows by key ────────────────────────────────────────────────

///|
/// What changes a list shows by its rows' keys (ListMotion.kt update): call while building, each frame, with the keys
/// of the rows of list `list` (as given to Ctx::list in the same scope) in order. The first time nothing moves. As
/// they change: rows new to it come in (layout's `enter`), rows gone that showed leave by a copy (its `exit`), rows
/// that went ahead of others pass over them (lifted), the rest close over what left 100 ms late, and for 150 ms the
/// rows' moves are the list's change (moved to on their springs); otherwise rows are put in their places at once.
/// `liftable`: which keys can go over others (not a day's heading). Its answer is the list's id (for lifted, from its
/// rows).
pub fn list_keys(
  c : @ui.Ctx,
  list : String,
  keys : Array[String],
  liftable? : (String) -> Bool = fn(_) { true },
) -> Int {
  install()
  let id = c.id(list)
  let now = c.now()
  let frame = c.frame_number()
  let ks = keys.map(motion_key)
  let lm = match mo.lists.get(id) {
    Some(l) => l
    None => {
      let l = {
        keys: ks,
        names: keys,
        changed_at: -1.0e9,
        close_until: -1.0e9,
        arrived: {},
        lifted: {},
        unghost: {},
        seen: frame,
      }
      mo.lists[id] = l
      return id
    }
  }
  lm.seen = frame
  if lm.keys == ks {
    return id
  }
  let before = lm.keys
  let before_names = lm.names
  lm.keys = ks
  lm.names = keys
  // nothing to move from: only where they are is kept
  if before.is_empty() || c.still() {
    return id
  }
  lm.changed_at = now
  let old : Map[Int, Int] = {}
  for i, k in before {
    old[k] = i
  }
  let fresh : Map[Int, Int] = {}
  for i, k in ks {
    fresh[k] = i
  }
  for k in ks {
    if !old.contains(k) {
      lm.arrived[k] = now
    }
  }
  // which of the rows there before and now went ahead of others
  let mut kept_i = 0
  let kept_before : Map[Int, Int] = {}
  let mut j = 0
  for k in before {
    if fresh.contains(k) {
      kept_before[k] = j
      j = j + 1
    }
  }
  for i, k in ks {
    if old.contains(k) {
      match kept_before.get(k) {
        Some(r) if r > kept_i && liftable(keys[i]) => {
          lm.lifted[k] = now
          // frames while it passes over the others (lift_ms from now)
          c.moving(@ui.Mover::new(), (Lift::{ at: now }) as &@ui.Moving, what="a row lifted")
        }
        _ => ()
      }
      kept_i = kept_i + 1
    }
  }
  // the rows gone that showed leave by a copy of them
  let mut gone = false
  for i, k in before {
    if fresh.contains(k) {
      continue
    }
    gone = true
    if lm.unghost.contains(k) {
      continue
    }
    match mo.recs.get(k) {
      Some(r) if r.seen >= frame - 2 && r.list == id && !r.drawing.is_empty() =>
        match r.exit {
          Some(t) => {
            let pf = Anim::new(0.0)
            let pm = Anim::new(0.0)
            pf.name = before_names[i] + " leaving"
            pm.name = pf.name
            pf.animate(1.0, t.fade_spec)
            pm.animate(1.0, t.spec)
            mo.ghosts.push({ list: id, key: k, drawing: r.drawing.copy(), trans: t, pf, pm })
          }
          None => ()
        }
      _ => ()
    }
  }
  if gone {
    lm.close_until = now + 50.0
  }
  lm.unghost.clear()
  let stale : Array[Int] = []
  lm.arrived.each(fn(k, at) { if now - at >= 500.0 { stale.push(k) } })
  for k in stale {
    lm.arrived.remove(k)
  }
  id
}

///|
/// Row `key` of list `list` leaves without a copy (it went out of sight already: swiped away).
pub fn list_unghost(c : @ui.Ctx, list : Int, key : String) -> Unit {
  ignore(c)
  match mo.lists.get(list) {
    Some(lm) => lm.unghost[motion_key(key)] = true
    None => ()
  }
}

///|
/// How long a row that went ahead of others takes to pass over them (ListMotion.kt liftedAt).
pub let lift_ms : Double = 480.0

///|
/// A row going ahead of others: it moves until lift_ms after `at`.
priv struct Lift {
  at : Double
}

///|
impl @ui.Moving for Lift with rest_at(self, now, frame) {
  ignore(now)
  ignore(frame)
  self.at + lift_ms
}

///|
/// How long ago row `key` of list `list` (its id, as list_keys answers) went ahead of others (ms), while it passes
/// over them (480 ms: ListMotion.kt liftedAt); -1 otherwise.
pub fn lifted(c : @ui.Ctx, list : Int, key : String) -> Double {
  match mo.lists.get(list) {
    Some(lm) =>
      match lm.lifted.get(motion_key(key)) {
        Some(at) if c.now() - at < lift_ms => c.now() - at
        Some(_) => {
          lm.lifted.remove(motion_key(key))
          -1.0
        }
        None => -1.0
      }
    None => -1.0
  }
}

// ── shown and hidden ────────────────────────────────────────────────────

///|
/// Something shown or hidden as `shown` says (Motion's AnimatePresence, Compose's AnimatedVisibility): coming by
/// `enter`, going by `exit` (by default the way it came), turned back mid-way from where it is. Its look while it
/// shows (for @ui.Ctx::look), None once it has gone (then it need not be built). The first time it is as it is,
/// without motion. While it goes it is only drawn: build it under `leaving`.
pub fn presence(
  c : @ui.Ctx,
  key : String,
  shown : Bool,
  enter? : Trans = trans(fade=0.0),
  exit? : Trans,
) -> @ui.Look? {
  let out = match exit {
    Some(t) => t
    None => enter
  }
  let to = if shown { 1.0 } else { 0.0 }
  let f = anim(c, key + "\u{1}fade", to)
  let m = anim(c, key + "\u{1}move", to)
  let t = if shown { enter } else { out }
  f.follow(to, t.fade_spec)
  m.follow(to, t.spec)
  if !shown && f.value <= 0.0 && m.value <= 0.0 {
    return None
  }
  let l = t.at(f.value, m.value)
  if logging() && (f.running || m.running) {
    @ui.log("MOTION \{c.now()} \{key} alpha=\{l.alpha} dx=\{l.dx} dy=\{l.dy} scale=\{l.sx}")
  }
  Some(l)
}

///|
/// Node `i`, built while it leaves (`shown` false: `presence`, or a value the app animates, still drawing it as it
/// goes), is only drawn (@ui.Ctx::draw_only): drawn, never tapped nor found on screen, so what is tapped
/// meanwhile is what is under it, at once. Shown, it is tapped as anything.
pub fn leaving(c : @ui.Ctx, i : Int, shown : Bool) -> Unit {
  if !shown {
    c.draw_only(i)
  }
}

///|
/// What `body` builds, as tall as `share` (0 → 1) of its own height (expandVertically / shrinkVertically, from its top
/// or with its foot kept), cut there when `clip`; all of it at 1. `align` places what it builds across, as its parent
/// would. Its own height is the one it was last laid out with (none the first frame, when it is nothing tall). The one
/// helper here that lays out: a height the app animates (what is in it is tapped where it is laid out, as anything).
pub fn reveal(
  c : @ui.Ctx,
  key : String,
  share : Double,
  from_top? : Bool = true,
  clip? : Bool = false,
  align? : @ui.Align = AStretch,
  body : () -> Unit,
) -> Unit {
  let k = motion_key("reveal\u{1}" + key)
  let natural = match mo.recs.get(k) {
    Some(r) => r.h
    None => 0.0
  }
  let whole = share >= 1.0
  let outer = c.box(
    w=Fill(1.0),
    h=if whole { Auto } else { Px(natural * dmax(share, 0.0)) },
    clip=clip && !whole,
    align~,
    justify=if from_top { JStart } else { JEnd },
    fn() {
      let inner = c.box(w=Fill(1.0), align~, body)
      let e = moving_of(c, inner)
      e.key = k
      e.measure = true
    },
  )
  ignore(outer)
}

// ── after layout ────────────────────────────────────────────────────────

///|
/// What moves this frame, worked out once its layout is done: each keyed node's place against the last frame's, its
/// entrance, where it is flown to; their looks then are what painting draws (the app's own look first).
fn after_layout(c : @ui.Ctx) -> Unit {
  sweep_anims(c)
  let frame = c.frame_number()
  if mo.frame != frame {
    mo.entries.clear()
    mo.frame = frame
  }
  if mo.entries.is_empty() {
    forget_recs(c)
    return
  }
  let still = c.still()
  let scrolled : Map[Int, Double] = {}
  for e in mo.entries {
    let (nx, ny, nw, nh) = c.node_rect(e.node)
    let app_look = c.look_of(e.node)
    let mut look = app_look
    // its own move (for the log: what it is drawn from beside its scope's)
    let mut flip_dy = 0.0
    if e.key != 0 {
      let li = if e.measure { -1 } else { c.list_above(e.node) }
      let (ref, rx, ry) = if li >= 0 {
        let (lx, ly, _, _) = c.node_rect(li)
        let (pl, pt, _, _) = c.node_pad(li)
        let s = match scrolled.get(li) {
          Some(s) => s
          None => {
            let s = c.list_scrolled(li)
            scrolled[li] = s
            s
          }
        }
        (c.node_id(li), nx - lx - pl, ny - ly - pt + s)
      } else {
        match (if e.measure { None } else { scope_above(c, e.node) }) {
          Some(sc) => {
            let (sx, sy, _, sh) = c.node_rect(sc.node)
            let oy = if sc.scope == 2 { sy + sh } else { sy }
            (-7, nx - sx, ny - oy)
          }
          None => (0, nx, ny)
        }
      }
      let r = match mo.recs.get(e.key) {
        Some(r) => r
        None => {
          let r = Rec::new()
          // (what moves it said by its key, as layout_rest(KEY) asks of it: Tester::moving's "Anim \"layout KEY\"")
          let said = "layout " + e.name
          r.ox.name = said
          r.oy.name = said
          r.ef.name = said
          r.em.name = said
          mo.recs[e.key] = r
          r
        }
      }
      let lm = if li >= 0 { mo.lists.get(ref) } else { None }
      let was_seen = r.seen >= frame - 1 && r.ref == ref
      // where it shows in its list's view
      let vy = if li >= 0 {
        let (_, ly, _, _) = c.node_rect(li)
        ny - ly
      } else {
        ry
      }
      if e.flip && was_seen {
        let dx = r.x - rx
        let dy = if e.screen { r.vy - vy } else { r.y - ry }
        if dx.abs() > 0.5 || dy.abs() > 0.5 {
          // in a list told its rows: only as they change (else it is the list's own layout, taken at once)
          let changed = match lm {
            Some(l) => e.gate != 1 || c.now() - l.changed_at < 150.0
            None => true
          }
          if still || !changed {
            r.ox.snap(0.0)
            r.oy.snap(0.0)
            r.driven = false
          } else if e.drive >= 0.0 {
            r.fx = r.ox.get() + dx
            r.fy = r.oy.get() + dy
            r.driven = true
          } else {
            // closing over a row gone: a little late, unless it went ahead
            let delay = match lm {
              Some(l) if c.now() <= l.close_until && !l.lifted.contains(e.key) => 100.0
              _ => 0.0
            }
            let spec = match e.spec {
              Spring(a, b, t, _) => Spring(a, b, t, delay)
              Tween(a, b, _) => Tween(a, b, delay)
              Snap(_) => Snap(delay)
              Motion(tr) => Motion(tr.delayed(delay))
            }
            r.driven = false
            r.ox.step(c)
            r.ox.value = r.ox.value + dx
            r.ox.animate(0.0, spec)
            r.oy.step(c)
            r.oy.value = r.oy.value + dy
            r.oy.animate(0.0, spec)
          }
        }
      }
      // coming in: a row new to its list, or (entering) a node not there the frame before
      match e.enter {
        Some(t) if !still => {
          let arrived = if e.fresh {
            !was_seen
          } else {
            match lm {
              Some(l) =>
                match l.arrived.get(e.key) {
                  Some(at) => {
                    l.arrived.remove(e.key)
                    c.now() - at < 400.0
                  }
                  None => false
                }
              None => false
            }
          }
          if arrived {
            r.enter = Some(t)
            r.ef.snap(0.0)
            r.em.snap(0.0)
            r.ef.animate(1.0, t.fade_spec)
            r.em.animate(1.0, t.spec)
          }
        }
        _ => ()
      }
      r.x = rx
      r.y = ry
      r.vy = vy
      r.w = nw
      r.h = nh
      r.ref = ref
      r.seen = frame
      r.exit = e.exit
      r.list = ref
      match e.exit {
        // what it draws kept, for its copy should it leave its list
        Some(_) if li >= 0 => c.keep_drawing(e.node, li, r.drawing)
        Some(_) => ()
        None => r.drawing.insts.clear()
      }
      // its look: on the way to its place, coming in
      let (ox, oy) = if r.driven && e.drive >= 0.0 {
        let p = dclamp(e.drive, 0.0, 1.0)
        if p >= 1.0 {
          r.driven = false
        }
        (r.fx * (1.0 - p), r.fy * (1.0 - p))
      } else if r.driven {
        // what drove it is over
        r.driven = false
        (0.0, 0.0)
      } else {
        (r.ox.get(), r.oy.get())
      }
      if ox != 0.0 || oy != 0.0 {
        look = look.then({ ..@ui.still_look, dx: ox, dy: oy })
        flip_dy = oy
      }
      match r.enter {
        Some(t) => {
          let pf = r.ef.get()
          let pm = r.em.get()
          if pf >= 1.0 && pm >= 1.0 && !r.ef.running && !r.em.running {
            r.enter = None
          } else {
            look = look.then(t.at(pf, pm))
          }
        }
        None => ()
      }
    }
    match e.fly {
      Some((fx, fy, fs, px, py, ps)) => {
        let s = fs + (1.0 - fs) * ps
        let x = fx + (nx - fx) * px
        let y = fy + (ny - fy) * py
        look = look.then({ alpha: 1.0, dx: x - nx, dy: y - ny, sx: s, sy: s, ox: 0.0, oy: 0.0 })
      }
      None => ()
    }
    if look != app_look {
      c.set_look(e.node, look)
    }
    if logging() && e.name != "" && (!look.is_still() || e.fly is Some(_)) {
      @ui.log(
        "MOTION \{c.now()} \{e.name} x=\{nx + look.dx} y=\{ny + look.dy} w=\{nw * look.sx} h=\{nh * look.sy} alpha=\{look.alpha} dx=\{look.dx} dy=\{look.dy} scale=\{look.sx} fy=\{flip_dy}",
      )
    }
  }
  forget_recs(c)
}

///|
/// Forgets the places of what has not been built for a while.
fn forget_recs(c : @ui.Ctx) -> Unit {
  let frame = c.frame_number()
  if frame % 30 != 0 || mo.recs.is_empty() {
    return
  }
  let old : Array[Int] = []
  mo.recs.each(fn(k, r) { if frame - r.seen > 90 && !r.ox.running && !r.oy.running { old.push(k) } })
  for k in old {
    mo.recs.remove(k)
  }
  let lists : Array[Int] = []
  mo.lists.each(fn(k, l) { if frame - l.seen > 600 { lists.push(k) } })
  for k in lists {
    mo.lists.remove(k)
  }
}

///|
/// The copies of list node `li`'s rows gone, where they were, as they leave (under its rows: drawn before them).
fn draw_ghosts(c : @ui.Ctx, li : Int) -> Unit {
  if mo.ghosts.is_empty() {
    return
  }
  let id = c.node_id(li)
  let done : Array[Int] = []
  for gi, gh in mo.ghosts {
    if gh.list != id {
      continue
    }
    let pf = gh.pf.get()
    let pm = gh.pm.get()
    if pf >= 1.0 && pm >= 1.0 && !gh.pf.running && !gh.pm.running {
      done.push(gi)
      continue
    }
    // (its two Anims say their ends as they are read: frames until they are there)
    // from as it was (1) to its far end (0)
    c.draw_drawing(gh.drawing, li, gh.trans.at(1.0 - pf, 1.0 - pm))
  }
  let mut j = done.length() - 1
  while j >= 0 {
    mo.ghosts.remove(done[j]) |> ignore
    j = j - 1
  }
}
