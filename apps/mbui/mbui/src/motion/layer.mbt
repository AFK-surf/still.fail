// Motion over layout: how nodes move without the layout knowing. All of it only changes how things are drawn (a
// look, @ui.Ctx::set_look; copies drawn under a list's rows): nothing here is laid out differently, nothing takes a
// tap, a focus or words, and nothing waits for it. A node is tapped where it is laid out, at once, whatever it looks
// like meanwhile. Over that:
//
// - layout animation by key (Motion's `layout`, FLIP, Compose's animateItem placement): a node with a key whose
//   laid-out place changed since the last frame is drawn from where it was and goes to its new place on a spring (or
//   a tween, or a progress the app drives), carrying on from where it had got to. In a list a place is the row's
//   place in the list's content, not on the screen, so scrolling moves nothing (but what the list put its rows down
//   by to hold its foot as they changed: a row gone at its end, the rows over it coming down over its place);
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
  /// a panel's (what is put over others, its own ground under its words): faded in whole under its words before they
  /// come in over it, they going before it as it goes (Look's `words`), so that never are its words and what it is put
  /// over both seen in one place (docs/motion.md rule 4)
  ground_first : Bool
} derive(Show, Eq)

///|
/// A transition: fadeIn/Out to `fade`, scaleIn/Out to `scale`, slideIn/Out by `dx`, `dy`; all by `spec` unless the
/// fade has its own. `ground_first`: a panel's, its ground's fade in the first half of its own and its words' in the
/// second.
pub fn trans(
  fade? : Double = 1.0,
  scale? : Double = 1.0,
  ox? : Double = 0.5,
  oy? : Double = 0.5,
  dx? : Double = 0.0,
  dy? : Double = 0.0,
  spec? : Spec = tween(300.0, ease=Out),
  fade_spec? : Spec,
  ground_first? : Bool = false,
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
    ground_first,
  }
}

///|
/// How it looks `pf` of the way in by its opacity and `pm` by the rest (1: all the way in, as laid out).
pub fn Trans::at(self : Trans, pf : Double, pm : Double) -> @ui.Look {
  let s = self.scale + (1.0 - self.scale) * pm
  let a = self.fade + (1.0 - self.fade) * pf
  // (its ground whole by half its fade, its words from there: the words' own opacity over the ground's)
  let (alpha, words) = if self.ground_first {
    let ground = dmin(1.0, 2.0 * a)
    (ground, if ground > 0.0 { dmax(0.0, 2.0 * a - 1.0) / ground } else { 0.0 })
  } else {
    (a, 1.0)
  }
  {
    alpha,
    dx: self.dx * (1.0 - pm),
    dy: self.dy * (1.0 - pm),
    sx: s,
    sy: s,
    ox: self.ox,
    oy: self.oy,
    rot: 0.0,
    circle: 0.0,
    words,
  }
}

// ── what this frame asks ────────────────────────────────────────────────

///|
/// A node of this frame with motion: its motion key and what the layer does with it.
priv struct Moving {
  node : Int
  mut key : Int
  /// layout animation: by `spec`, when its cause changed (`by`: what it moves for, as said this build; "" none) or, in
  /// a list told its rows, as they change; `drive` ≥ 0: the move goes by that progress the app gives (0 → 1)
  mut flip : Bool
  mut spec : Spec
  mut by : String
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
  /// what its size and place in the window are kept as (reveal's content, measure; 0: nothing), apart from `key`, so
  /// that a node measured can move by its layout too, in its list or scope
  mut kept : Int
  /// a frame its keyed nodes' places are taken in (scope): 1 from its top left, 2 from its bottom left
  mut scope : Int
  /// flown from (x, y, scale), how far across, down and grown
  mut fly : (Double, Double, Double, Double, Double, Double)?
  /// its own ground changes shape for its cause (reshape), by `spec`
  mut reshape : Bool
  /// reshape: it goes from where it was with what it holds (laid out for another place: the web's morph), what is new
  /// in it carried on its ground
  mut carry : Bool
  /// reshape: it changes shape from its foot (reshape's `foot`)
  mut foot : Bool
  /// how it is drawn, worked out once this frame is laid out (placed)
  mut placed : (() -> @ui.Look)?
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
  /// what the app drives a move by: its offset as if the progress were 0 (it is drawn off its place by that times what
  /// is left of the progress), and the progress it was last drawn at
  mut fx : Double
  mut fy : Double
  mut driven : Bool
  mut drove : Double
  mut enter : Trans?
  ef : Anim
  em : Anim
  /// how it was last drawn, relative to its list's corner
  drawing : @ui.Drawing
  mut exit : Trans?
  mut list : Int
  /// how far down from its place it is drawn on its way there this frame (0: in its place; makes_room)
  mut moving_dy : Double
  /// how tall it shows this frame (as tall as it is laid out, or less: grown for its cause, coming out with its move;
  /// makes_room)
  mut shown_h : Double
  /// where it was drawn last frame (its last build's place), taken as this frame first lays it out: every build of a
  /// frame (frame_body) moves it from there, none from another build's place, which was never drawn; and its offsets
  /// then, which a move this frame sets from (not adds to, once a build)
  mut frame_at : Int
  mut was_x : Double
  mut was_y : Double
  mut was_vy : Double
  mut was_ref : Int
  mut was_seen : Int
  mut was_ox : Double
  mut was_oy : Double
  /// what it moved for (layout's `by`) as last laid out, and as the frame before laid it out
  mut by : String
  mut was_by : String
  /// and its drive then, if driven
  mut was_driven : Bool
  mut was_fx : Double
  mut was_fy : Double
  /// a build of this frame moved it (its offsets set from was_ox, was_oy, or the drive then)
  mut moved_now : Bool
  /// reshape: the shape its ground set out from (x, y in its list or scope, w, h, its corners: top left, then round
  /// it), how far it has gone there (0 → 1), its corners as last laid out; and the same as the frame before left them
  mut gx : Double
  mut gy : Double
  mut gw : Double
  mut gh : Double
  mut gr : (Double, Double, Double, Double)
  gp : Anim
  mut rad : (Double, Double, Double, Double)
  mut was_w : Double
  mut was_h : Double
  mut was_rad : (Double, Double, Double, Double)
  mut was_gx : Double
  mut was_gy : Double
  mut was_gw : Double
  mut was_gh : Double
  mut was_gr : (Double, Double, Double, Double)
  mut was_gp : Double
  /// a build of this frame set its ground off anew
  mut g_now : Bool
  /// whether its ground set off as last with what it holds (reshape's `carry`)
  mut g_carry : Bool
  /// a move grown for its cause (layout, not in a list: its words a line more): the height it showed at as that set
  /// off, how far it has gone to the height it is laid out at (0 → 1); and the same as the frame before left them
  mut hh : Double
  hp : Anim
  mut was_hh : Double
  mut was_hp : Double
  /// a node new in a shape gone with what it holds, carried on its ground (reshape's `carry`): that shape's key (0:
  /// none), and the edges of it it keeps to (1: its right, rather than its left; 2: its foot, rather than its top)
  mut on : Int
  mut on_edges : Int
}

///|
/// Corners `r` (top left, then round it) as a box `w` by `h` draws them: each no more than half its shorter side.
fn corners_in(r : (Double, Double, Double, Double), w : Double, h : Double) -> (Double, Double, Double, Double) {
  let half = dmin(w, h) / 2.0
  (dmin(r.0, half), dmin(r.1, half), dmin(r.2, half), dmin(r.3, half))
}

///|
/// Corners `a` gone `p` of the way to `b`, each its own.
fn corners_mix(
  a : (Double, Double, Double, Double),
  b : (Double, Double, Double, Double),
  p : Double,
) -> (Double, Double, Double, Double) {
  (a.0 + (b.0 - a.0) * p, a.1 + (b.1 - a.1) * p, a.2 + (b.2 - a.2) * p, a.3 + (b.3 - a.3) * p)
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
    drove: 0.0,
    moving_dy: 0.0,
    shown_h: 0.0,
    enter: None,
    ef: Anim::new(1.0),
    em: Anim::new(1.0),
    drawing: @ui.Drawing::new(),
    exit: None,
    list: 0,
    frame_at: -1,
    was_x: 0.0,
    was_y: 0.0,
    was_vy: 0.0,
    was_ref: 0,
    was_seen: -10,
    was_ox: 0.0,
    was_oy: 0.0,
    by: "",
    was_by: "",
    was_driven: false,
    was_fx: 0.0,
    was_fy: 0.0,
    moved_now: false,
    gx: 0.0,
    gy: 0.0,
    gw: 0.0,
    gh: 0.0,
    gr: (0.0, 0.0, 0.0, 0.0),
    gp: Anim::new(1.0),
    rad: (0.0, 0.0, 0.0, 0.0),
    was_w: 0.0,
    was_h: 0.0,
    was_rad: (0.0, 0.0, 0.0, 0.0),
    was_gx: 0.0,
    was_gy: 0.0,
    was_gw: 0.0,
    was_gh: 0.0,
    was_gr: (0.0, 0.0, 0.0, 0.0),
    was_gp: 1.0,
    g_now: false,
    hh: 0.0,
    hp: Anim::new(1.0),
    was_hh: 0.0,
    was_hp: 1.0,
    g_carry: false,
    on: 0,
    on_edges: 0,
  }
}

///|
/// A list's rows by key, as last told (list_keys): the frame they last changed in, which came in, which went ahead of
/// others, until when the rest wait to close over what left.
priv struct ListMo {
  mut keys : Array[Int]
  /// the same, as given (what a row's copy is named by as it leaves)
  mut names : Array[String]
  mut changed_frame : Int
  mut close_until : Double
  arrived : Map[Int, Double]
  lifted : Map[Int, Double]
  /// rows gone ahead of others this change: not moved across them, but gone from where they were (a copy shrinking
  /// there as the rest close over it) and come in where they are now (grown in as the rest make room), each its words
  /// over none of theirs (docs/motion.md rule 4; the user, 2026-10-29: 「它先缩下去，然后在目标位置挤出来」)
  reborn : Map[Int, Int]
  /// what moves its rows lifted over others (read where a row reads how long ago it was lifted: `lifted`)
  lift_mover : @ui.Mover
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
  /// by node: its entry this build (when `stamp` is this build: Ctx::build_number, a frame built again another, its
  /// nodes other nodes)
  at : Array[Int]
  stamp : Array[Int]
  /// the build `entries` are of
  mut build : Int
  recs : Map[Int, Rec]
  lists : Map[Int, ListMo]
  ghosts : Array[Ghost]
}

///|
let mo : MotionState = {
  entries: [],
  at: [],
  stamp: [],
  build: -1,
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
  measure_at.clear()
  measure_size.clear()
  measure_names.clear()
  measure_told.clear()
  mo.at.clear()
  mo.stamp.clear()
  mo.build = -1
  mo.recs.clear()
  mo.lists.clear()
  mo.ghosts.clear()
  anims.clear()
  ripples.clear()
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
    @ui.log("MOTION \{c.moment()} \{key} \{fields}")
  }
}

///|
let motion_log : Ref[Int] = { val: -1 }

///|
/// The entry of node `i` this build, made when it has none.
fn moving_of(c : @ui.Ctx, i : Int) -> Moving {
  install()
  let build = c.build_number()
  if mo.build != build {
    mo.entries.clear()
    mo.build = build
  }
  while mo.at.length() <= i {
    mo.at.push(-1)
    mo.stamp.push(-1)
  }
  if mo.stamp[i] == build && mo.at[i] >= 0 {
    return mo.entries[mo.at[i]]
  }
  let e : Moving = {
    node: i,
    key: 0,
    flip: false,
    spec: row_spring,
    by: "",
    drive: -1.0,
    screen: false,
    name: "",
    enter: None,
    exit: None,
    fresh: false,
    kept: 0,
    scope: 0,
    fly: None,
    reshape: false,
    carry: false,
    foot: false,
    placed: None,
  }
  mo.stamp[i] = build
  mo.at[i] = mo.entries.length()
  mo.entries.push(e)
  // (a list's row kept as its nodes says it again of its node where it is put back, as built: @ui.built_again)
  @ui.built_again(fn(by) { moving_again(e, i + by) })
  e
}

///|
/// Entry `e`, as its build said it, said again of node `i` in this build (a list's row kept as its nodes, put back
/// there: @ui.built_again).
fn moving_again(e : Moving, i : Int) -> Unit {
  let build = @ui.current().build_number()
  if mo.build != build {
    mo.entries.clear()
    mo.build = build
  }
  while mo.at.length() <= i {
    mo.at.push(-1)
    mo.stamp.push(-1)
  }
  mo.stamp[i] = build
  mo.at[i] = mo.entries.length()
  mo.entries.push({ ..e, node: i })
}

///|
/// Node `i`'s entry this build, if it has one.
fn entry_of(c : @ui.Ctx, i : Int) -> Moving? {
  let build = c.build_number()
  if mo.build == build && i >= 0 && i < mo.stamp.length() && mo.stamp[i] == build && mo.at[i] >= 0 {
    Some(mo.entries[mo.at[i]])
  } else {
    None
  }
}

///|
/// Node `i` keyed `key` moves to its new place for its cause (Motion's `layout`, FLIP, set off by what moved it):
/// `by` is what it moves for (its words, its page, the row over it: any value naming that state); in the frame `by`
/// changes, it is drawn where it was and goes by `spec` to where it is now, carrying on from wherever it had got to. A
/// row of a list told its rows (list_keys) that names no cause of its own moves for their change. Moved by nothing it
/// moves for (a window resized, a keyboard, a pane made narrower), it is put in its new place at once, a move of its
/// own going on as it was: no difference found between frames moves anything (docs/motion.md of the app). `enter` is how a row new to its list comes in, `exit` how one gone leaves (a copy of it where it was).
/// `drive` (0 → 1, from the frame it moved): the move goes by that progress instead of `spec`. `screen`: in a list, by
/// where it shows in the list's view.
pub fn layout(
  c : @ui.Ctx,
  i : Int,
  key : String,
  spec? : Spec = row_spring,
  by? : String = "",
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
  if by != "" {
    e.by = by
  }
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
/// leaves by `exit`, a copy of it). `by`: what it would move for, kept each frame, so a layout motion it is given in a
/// later frame knows whether that changed (layout's `by`).
pub fn keyed(c : @ui.Ctx, i : Int, key : String, exit? : Trans, by? : String = "") -> Unit {
  let e = moving_of(c, i)
  e.name = key
  e.key = motion_key(key)
  if exit is Some(_) {
    e.exit = exit
  }
  if by != "" {
    e.by = by
  }
}

///|
/// Node `i` keyed `key` comes in by `enter` the first frame it is built (not when its key was built the frame
/// before): what is new as the app says (a message said while the chat shows). `at_once`: it is there at once this
/// frame (what a page opened with), known as built for the frames after, as a frame kept unbuilt knows it.
pub fn entering(
  c : @ui.Ctx,
  i : Int,
  key : String,
  enter : Trans,
  at_once? : Bool = false,
) -> Unit {
  let e = moving_of(c, i)
  e.name = key
  e.key = motion_key(key)
  // (seen where a part or a row drawn again that it is in shows it: built again, it is not new)
  e.enter = if at_once { None } else { Some(enter) }
  e.fresh = true
}

///|
/// Node `i` keyed `key` changes shape for its cause (the web's morph.ts `grow`): in the frame `by` (what it changes for:
/// its words, its files, its being opened) changes, what it holds is laid out as it ends at once, and its own ground
/// (its colour, glass, shadow, border and corners) goes by `spec` from the shape it showed to the one it is laid out
/// in, carrying on from wherever it had got to. What in it moves with it says so itself (`layout` with the same `by`);
/// what is new in it is in its place from the first. With `carry` (laid out for another place: the web's morph.ts
/// `morph`, a composer gone to another page), it goes from where it was with what it holds: a keyed node in it new to
/// it while its ground is on its way (not built the frame before: a part the other place has and this did not) is
/// carried on that ground, as far from its nearer edges as it is laid out, until the ground is there. Moved or resized
/// by nothing it changes for (a window, a keyboard), its ground is where it is laid out at once, a change of its own
/// going on from there. Only drawn so: tapped where it is laid out. With `foot`, it changes shape from its foot: as it
/// sets off, what moved its foot in that same frame for nothing it changes for (a keyboard coming as it opens) is
/// where it is laid out at once, its ground and what moves with it (`layout` with the same `by`) setting off from
/// their shape and places carried there, only their growing up from the foot on its way (a composer opened at its
/// foot: the user, 2026-10-30 「以底部为 origin」).
pub fn reshape(
  c : @ui.Ctx,
  i : Int,
  key : String,
  by~ : String,
  spec~ : Spec,
  carry? : Bool = false,
  foot? : Bool = false,
) -> Unit {
  let e = moving_of(c, i)
  e.name = key
  e.key = motion_key(key)
  // (seen where a part or a row drawn again that it is in shows it: built again, it reshapes from there)
  e.reshape = true
  e.carry = carry
  e.foot = foot
  e.spec = spec
  if by != "" {
    e.by = by
  }
}

///|
/// Node `i` flown from (`x`, `y`, at `scale`) to where it is laid out (a shared element: Motion's `layoutId`): its
/// top left `px` of the way across, `py` of the way down and `ps` of the way grown (the words sent from the composer
/// to their bubble), drawn as what flies is (@ui.Stratum's Flying). Only drawn so: it is where it is laid out for
/// anything else.
pub fn fly(
  c : @ui.Ctx,
  i : Int,
  x : Double,
  y : Double,
  scale? : Double = 1.0,
  px~ : Double,
  py~ : Double,
  ps? : Double = 1.0,
) -> Unit {
  let e = moving_of(c, i)
  if e.name == "" {
    e.name = "fly"
  }
  e.fly = Some((x, y, scale, px, py, ps))
  c.stratum(i, Flying)
}

///|
/// The keyed nodes in node `i` take their places from its top left, or with `bottom` from its bottom left (what
/// stands on a bottom edge: the composer's parts), so that it moving (a keyboard coming up) moves none of them.
pub fn scope(c : @ui.Ctx, i : Int, bottom? : Bool = false) -> Unit {
  let e = moving_of(c, i)
  e.scope = if bottom { 2 } else { 1 }
}

///|
/// Node `i` drawn by `at`, worked out once this frame is laid out: what `at` reads of where things are (measured,
/// measured_rect) is where this frame has them then, not where the frame before did. For what is drawn where real
/// things are while they move (a picture flying between rows of a list that glides meanwhile, a list drawn up behind
/// what carries it): it goes with them in the same frame, never a frame behind. Over its own look. Only drawn so:
/// tapped where it is laid out.
pub fn placed(c : @ui.Ctx, i : Int, at : () -> @ui.Look) -> Unit {
  let e = moving_of(c, i)
  e.placed = Some(at)
}

///|
/// Node `i`'s height is kept as `key`'s (measured reads it).
pub fn measure(c : @ui.Ctx, i : Int, key : String) -> Unit {
  let e = moving_of(c, i)
  e.kept = motion_key("measure\u{1}" + key)
}

///|
/// How tall the node kept as `key` was when last laid out (measure).
pub fn measured(c : @ui.Ctx, key : String) -> Double? {
  ignore(c)
  measure_read(measure_size, motion_key("measure\u{1}" + key), name=key)
  match mo.recs.get(motion_key("measure\u{1}" + key)) {
    Some(r) => Some(r.h)
    None => None
  }
}

///|
/// How far over its laid out top the ground of the shape keyed `key` (reshape) is drawn now, on its way from the shape
/// it had (less than 0 while it is drawn lower: growing up to it): what stands on it moves with it so, in the same
/// frame. 0 at rest, and while it goes from where it was with what it holds (`carry`: to another place, not another
/// shape there).
pub fn reshaped_over(c : @ui.Ctx, key : String) -> Double {
  match mo.recs.get(motion_key(key)) {
    Some(r) if r.seen >= c.frame_number() - 1 && !r.g_carry => {
      let p = r.gp.get()
      if p < 1.0 {
        (r.y - r.gy) * (1.0 - p)
      } else {
        0.0
      }
    }
    _ => 0.0
  }
}

///|
/// Where the node kept as `key` (measure) was last laid out, in the window: x, y, w, h (None before it was, or once it
/// has not been for a frame).
pub fn measured_rect(c : @ui.Ctx, key : String) -> (Double, Double, Double, Double)? {
  measure_read(measure_at, motion_key("measure\u{1}" + key), name=key)
  measure_read(measure_size, motion_key("measure\u{1}" + key), name=key)
  match mo.recs.get(motion_key("measure\u{1}" + key)) {
    Some(r) if r.seen >= c.frame_number() - 1 => Some((r.x, r.y, r.w, r.h))
    _ => None
  }
}

///|
/// How big the node kept as `key` (measure) was when last laid out: w, h (None before it was, or once it has not been
/// for a frame); what reads it is not told as it moves (a page it is on sliding in), as measured_rect's is.
pub fn measured_size(c : @ui.Ctx, key : String) -> (Double, Double)? {
  measure_read(measure_size, motion_key("measure\u{1}" + key), name=key)
  match mo.recs.get(motion_key("measure\u{1}" + key)) {
    Some(r) if r.seen >= c.frame_number() - 1 => Some((r.w, r.h))
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
/// The shape node `i` is in that goes from where it was with what it holds (reshape's `carry`), if any: its entry and
/// what is kept of it.
fn carrier(c : @ui.Ctx, i : Int) -> (Moving, Rec)? {
  let mut p = c.node_parent(i)
  while p >= 0 {
    if c.node_is_list(p) {
      return None
    }
    match entry_of(c, p) {
      Some(e) if e.reshape =>
        return match mo.recs.get(e.key) {
          Some(r) => Some((e, r))
          None => None
        }
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
    Some(r) => {
      [r.ox, r.oy, r.ef, r.em, r.gp, r.hp].each(at)
      // (carried on a shape's ground: until that is there)
      match mo.recs.get(r.on) {
        Some(ar) if r.on != 0 => at(ar.gp)
        _ => ()
      }
    }
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
/// List `l` shown in `frame`, and in each frame what built it is kept as its nodes, its build not run (a pane beside
/// the one in use: @ui.built_again): a frame it showed in so is no frame it was away.
fn list_seen(l : ListMo, frame : Int) -> Unit {
  l.seen = frame
  @ui.built_again(fn(_) { l.seen = @ui.current().frame_number() })
}

///|
/// What changes a list shows by its rows' keys (ListMotion.kt update): call while building, each frame, with the keys
/// of the rows of list `list` (as given to Ctx::list in the same scope) in order. The first time nothing moves, nor
/// the first time again after a frame it was not built in (Android's list composed anew: its page come back to). As
/// they change: rows new to it come in (layout's `enter`), rows gone that showed leave by a copy (its `exit`), rows
/// that went ahead of others go from where they were by a copy and come in where they are, never across them (one with
/// no copy to leave by, never drawn or with no `exit`, passes over them: lifted), the rest close over what left 100 ms
/// late, and in the frame of the
/// change the rows' moves are the list's (moved to on their springs); otherwise rows are put in their places at once:
/// the list's rows laid out in that frame (frame_body builds it again while what it read changes), no window of time
/// after it lets in a move another cause made.
/// `liftable`: which keys can go ahead of others so (not a day's heading). Its answer is the list's id (for lifted, from its
/// rows).
pub fn list_keys(
  c : @ui.Ctx,
  list : String,
  keys : Array[String],
  liftable? : (String) -> Bool = fn(_) { true },
) -> Int {
  install()
  let id = c.id(list)
  let now = c.moment()
  let frame = c.frame_number()
  // the very names of the frame before (a list that keeps them while it is the same): nothing to work out again, as
  // many as it has rows
  match mo.lists.get(id) {
    Some(l) if physical_equal(l.names, keys) => {
      list_seen(l, frame)
      return id
    }
    _ => ()
  }
  let lm = match mo.lists.get(id) {
    Some(l) => l
    None => {
      let l = {
        keys: keys.map(motion_key),
        names: keys,
        changed_frame: -1,
        close_until: -1.0e9,
        arrived: {},
        lifted: {},
        reborn: {},
        lift_mover: @ui.Mover::new(),
        unghost: {},
        seen: frame,
      }
      mo.lists[id] = l
      list_seen(l, frame)
      return id
    }
  }
  // not shown the frame before (its page come back to, its pane slid to): drawn anew, as the first time
  let away = lm.seen < frame - 1
  list_seen(lm, frame)
  // only what is between the rows alike at its start and at its end changed (a row come at the end, one gone, one
  // moved: what is between them, never every row of a long list); the keys are each row's own (a key twice in a list is
  // no list's)
  let before = lm.keys
  let before_names = lm.names
  let nb = before.length()
  let nk = keys.length()
  let mut lead = 0
  while lead < nb && lead < nk && before_names[lead] == keys[lead] {
    lead += 1
  }
  let mut tail = 0
  while tail < nb - lead && tail < nk - lead && before_names[nb - 1 - tail] == keys[nk - 1 - tail] {
    tail += 1
  }
  if lead == nb && lead == nk {
    lm.names = keys
    return id
  }
  let ks : Array[Int] = Array::new(capacity=nk)
  for i in 0..<lead {
    ks.push(before[i])
  }
  for i in lead..<(nk - tail) {
    ks.push(motion_key(keys[i]))
  }
  for i in (nb - tail)..<nb {
    ks.push(before[i])
  }
  lm.keys = ks
  lm.names = keys
  // nothing to move from: only where they are is kept
  if nb == 0 || away || c.still() {
    lm.unghost.clear()
    return id
  }
  lm.changed_frame = frame
  // (the rows between, before and now)
  let old : Map[Int, Int] = {}
  for i in lead..<(nb - tail) {
    old[before[i]] = i
  }
  let fresh : Map[Int, Int] = {}
  for i in lead..<(nk - tail) {
    fresh[ks[i]] = i
  }
  for i in lead..<(nk - tail) {
    if !old.contains(ks[i]) {
      lm.arrived[ks[i]] = now
    }
  }
  // which of the rows there before and now went ahead of others (those alike at the start and the end went ahead of
  // none)
  let mut kept_i = 0
  let kept_before : Map[Int, Int] = {}
  let mut j = 0
  for i in lead..<(nb - tail) {
    if fresh.contains(before[i]) {
      kept_before[before[i]] = j
      j = j + 1
    }
  }
  for i in lead..<(nk - tail) {
    let k = ks[i]
    if old.contains(k) {
      match kept_before.get(k) {
        Some(r) if r > kept_i && liftable(keys[i]) =>
          // gone from where it was, by a copy as a row gone goes, and come in where it is as a row new comes
          match mo.recs.get(k) {
            Some(rec) if rec.seen >= frame - 2 && rec.list == id && !rec.drawing.is_empty() && rec.exit is Some(_) => {
              let t = rec.exit.unwrap()
              let pf = Anim::new(0.0)
              let pm = Anim::new(0.0)
              pf.name = keys[i] + " leaving"
              pm.name = pf.name
              pf.animate(1.0, t.fade_spec)
              pm.animate(1.0, t.spec)
              mo.ghosts.push({ list: id, key: k, drawing: rec.drawing.copy(), trans: t, pf, pm })
              lm.reborn[k] = frame
              lm.arrived[k] = now
              lm.close_until = now + 50.0
            }
            // (none drawn yet, or one leaving no copy: over the others as before)
            _ => {
              lm.lifted[k] = now
              // frames while it passes over the others (lift_ms from now)
              c.moving(lm.lift_mover, (Lift::{ at: now }) as &@ui.Moving, what="a row lifted")
            }
          }
        _ => ()
      }
      kept_i = kept_i + 1
    }
  }
  // the rows gone that showed leave by a copy of them
  let mut gone = false
  for i in lead..<(nb - tail) {
    let k = before[i]
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
  // (one let go without a copy stays so until it leaves: ListMotion.kt swiped.retainAll)
  let left : Array[Int] = []
  lm.unghost.each(fn(k, _) { if !fresh.contains(k) && !ks.contains(k) { left.push(k) } })
  for k in left {
    lm.unghost.remove(k)
  }
  let stale : Array[Int] = []
  lm.arrived.each(fn(k, at) { if now - at >= 500.0 { stale.push(k) } })
  for k in stale {
    lm.arrived.remove(k)
  }
  let past : Array[Int] = []
  lm.reborn.each(fn(k, f) { if f < frame { past.push(k) } })
  for k in past {
    lm.reborn.remove(k)
  }
  id
}

///|
/// Row `key` of list `list` leaves without a copy (it went out of sight already: swiped away) when it leaves; `off`
/// false: with one again (its archiving refused, it came back).
pub fn list_unghost(c : @ui.Ctx, list : Int, key : String, off? : Bool = true) -> Unit {
  ignore(c)
  match mo.lists.get(list) {
    Some(lm) =>
      if off {
        lm.unghost[motion_key(key)] = true
      } else {
        lm.unghost.remove(motion_key(key))
      }
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
        Some(at) if c.moment() - at < lift_ms => {
          // (read by what is built: built again each frame while it passes over the others, Ctx::shows_motion)
          c.shows_motion(lm.lift_mover, true)
          c.moment() - at
        }
        Some(_) => {
          c.shows_motion(lm.lift_mover, false)
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
/// shows (for @ui.Ctx::look), None once it has gone (then it need not be built). The first time it is asked it is as
/// it is, without motion, unless `initial` (Motion's: shown then, it comes in by `enter` as it would later: a panel
/// opened by what it is asked for the first time). While it goes it is only drawn: build it under `leaving`.
/// `start_at`: when what changed it happened (the frames' clock), its motion from then rather than from this frame.
pub fn presence(
  c : @ui.Ctx,
  key : String,
  shown : Bool,
  enter? : Trans = trans(fade=0.0),
  exit? : Trans,
  initial? : Bool = false,
  start_at? : Double,
) -> @ui.Look? {
  let out = match exit {
    Some(t) => t
    None => enter
  }
  let to = if shown { 1.0 } else { 0.0 }
  let from = if initial { 0.0 } else { to }
  let f = anim(c, key + "\u{1}fade", from)
  let m = anim(c, key + "\u{1}move", from)
  let t = if shown { enter } else { out }
  match start_at {
    Some(at) => {
      if f.target != to {
        f.animate(to, t.fade_spec, start_at=at)
      }
      if m.target != to {
        m.animate(to, t.spec, start_at=at)
      }
    }
    None => {
      f.follow(to, t.fade_spec)
      m.follow(to, t.spec)
    }
  }
  // (read so: what reads it is built again as it is told and each frame while it goes, Anim::get)
  let (fv, mv) = (f.get(), m.get())
  if !shown && fv <= 0.0 && mv <= 0.0 {
    return None
  }
  let l = t.at(fv, mv)
  if logging() && (f.running || m.running) {
    @ui.log("MOTION \{c.moment()} \{key} alpha=\{l.alpha} dx=\{l.dx} dy=\{l.dy} scale=\{l.sx}")
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
/// How tall what `reveal(key)` shows was laid out whole, the last time it was (0: never): how far its room goes.
pub fn reveal_height(key : String) -> Double {
  match mo.recs.get(motion_key("reveal\u{1}" + key)) {
    Some(r) => r.h
    None => 0.0
  }
}

///|
/// What `body` builds, as tall as `share` (0 → 1) of its own height (expandVertically / shrinkVertically, from its top
/// or with its foot kept), cut there when `clip`; all of it at 1. `align` places what it builds across, as its parent
/// would. `middle`: what it builds kept in the middle of its room and cut by it at both ends, what is cut fading out
/// to them (2026-10-31 the user: 「你要不两头裁呢？再加上淡化的边缘」, as a list's row coming and going is). Its own
/// height is the one it was last laid out with (none the first frame, when it is nothing tall). The one helper here
/// that lays out: a height the app animates (what is in it is tapped where it is laid out, as anything).
pub fn reveal(
  c : @ui.Ctx,
  key : String,
  share : Double,
  from_top? : Bool = true,
  clip? : Bool = false,
  middle? : Bool = false,
  align? : @ui.Align = AStretch,
  body : () -> Unit,
) -> Unit {
  let k = motion_key("reveal\u{1}" + key)
  let natural = match mo.recs.get(k) {
    Some(r) => r.h
    None => 0.0
  }
  let whole = share >= 1.0
  let shown = natural * dmax(share, 0.0)
  let mut inner = -1
  let outer = c.box(
    w=Fill(1.0),
    h=if whole { Auto } else { Px(shown) },
    clip=(clip || middle) && !whole,
    align~,
    justify=if middle { JCenter } else if from_top { JStart } else { JEnd },
    fn() {
      inner = c.box(w=Fill(1.0), align~, body)
      let e = moving_of(c, inner)
      e.kept = k
    },
  )
  if middle && !whole {
    let soft = @ui.cut_soft((natural - shown) / 2.0, shown / 2.0)
    c.fade_to(inner, outer, top=soft, foot=soft)
  }
}

// ── after layout ────────────────────────────────────────────────────────

///|
/// What moves this frame, worked out once its layout is done: each keyed node's place against the last frame's, its
/// entrance, where it is flown to; their looks then are what painting draws (the app's own look first).
fn after_layout(c : @ui.Ctx) -> Unit {
  sweep_anims(c)
  let frame = c.frame_number()
  let build = c.build_number()
  if mo.build != build {
    mo.entries.clear()
    mo.build = build
  }
  if mo.entries.is_empty() {
    forget_recs(c)
    return
  }
  let still = c.still()
  let scrolled : Map[Int, Double] = {}
  // (shapes first: what is carried on one's ground is placed by where that is this frame)
  let order = mo.entries.filter(fn(e) { e.reshape })
  if !order.is_empty() {
    for e in mo.entries {
      if !e.reshape {
        order.push(e)
      }
    }
  }
  together.clear()
  for e in if order.is_empty() { mo.entries } else { order } {
    // (what its move reads, read for what draws its node: the part's or the row's kept, whoever told it: Ctx::reads_for)
    c.reads_for(e.node, fn() { layout_entry(c, e, still, frame, scrolled) })
  }
  moved_together()
  // what is drawn where things are this frame (placed): once every place this frame lays out is kept
  for e in mo.entries {
    match e.placed {
      Some(at) => c.reads_for(e.node, fn() { c.set_look(e.node, c.look_of(e.node).then(at())) })
      None => ()
    }
  }
  makes_room(c)
  forget_recs(c)
}

///|
/// What moves this frame for each cause (its `by`), on a Move: how far the furthest of it goes, and each of its motions
/// (where to, by what), set out again as long as that one, so what moves together for one cause (a composer's ground,
/// its words, its ＋ and its send) is on one clock (docs/motion.md: as long as its way is far).
// kept across runs: cleared as each frame's layout begins, taken as it ends (after_layout)
let together : Map[String, (Double, Array[(Anim, Double, Spec)])] = {}

///|
/// For each cause (`by`) a shape set off for from its foot (reshape's `foot`): the frame it did, and how far its foot
/// moved in that frame for nothing it changes for, which what moves with it takes at once. Kept for the frame, not for
/// one build of it: a build again of that frame (its rows kept or not) reads what the first did.
// kept across runs: read for the frame it was set in only
let foot_moved : Map[String, (Int, Double)] = {}

///|
/// How far the foot of the shape set off for cause `by` from its foot in frame `frame` moved for nothing it changes for
/// (0: none).
fn foot_moved_in(by : String, frame : Int) -> Double {
  match foot_moved.get(by) {
    Some((f, d)) if by != "" && f == frame => d
    _ => 0.0
  }
}

///|
/// `a` off to `to` by `spec` (said to go `far`), for cause `by` ("" none: on its own).
fn moves_with(by : String, far : Double, a : Anim, to : Double, spec : Spec) -> Unit {
  a.animate(to, spec)
  guard by != "" && spec is Moved(_, _, _) else { return }
  match together.get(by) {
    Some((most, all)) => {
      all.push((a, to, spec))
      if far > most {
        together[by] = (far, all)
      }
    }
    None => together[by] = (far, [(a, to, spec)])
  }
}

///|
/// Each cause's motions as long as the furthest of them (moves_with): told again from where they set out this frame.
fn moved_together() -> Unit {
  together.each(fn(_, g) {
    let (most, all) = g
    if all.length() < 2 {
      return
    }
    for m in all {
      let (a, to, spec) = m
      // (all said `far` by this layout: told again as long as the furthest)
      let s = spec.over(most)
      if s != spec {
        a.animate(to, s)
      }
    }
  })
  together.clear()
}

///|
/// Where down the window the rows of list `list` (its id) are drawn this frame, in their places or on their way there:
/// what a row gone from it, drawn as it goes, gives way to (draw_ghosts), never under their words.
fn rows_drawn(c : @ui.Ctx, list : Int) -> Array[(Double, Double)] {
  let out = []
  for e in mo.entries {
    if e.key == 0 || e.reshape {
      continue
    }
    guard mo.recs.get(e.key) is Some(r) && r.list == list else { continue }
    let (_, y, _, h) = c.node_rect(e.node)
    let dy = c.look_of(e.node).dy
    out.push((y + dy, y + dy + h))
  }
  out
}

///|
/// How far before the edge of the room left it a row coming into its place fades in (makes_room): a cut's softness.
let room_soft : Double = @ui.cut_soft_most

///|
/// What comes into a list's place shows only in the room what was there has left (docs/motion.md rule 4, words over
/// words): a row in its place (one new to the list, or one a row closes over) is not drawn where a row of the same
/// list on its way to its place still is, as that one goes there (an agent's line gliding down from where a message
/// came in, the rows closing up over one gone). The row on its way is drawn whole, over its old place; the one in its
/// place is cut back to the room left it, shown more as that one goes, never two rows' words in one place (the user,
/// 2026-10-29: 「会闪」: not out, then in). What the two move by together (words sent flying, the rows over them going
/// up with them) changes nothing of that: of two rows that meet, the one further from its place is drawn whole, the
/// other cut, as when that one stood still.
fn makes_room(c : @ui.Ctx) -> Unit {
  let moving : Array[(Moving, Rec)] = []
  for e in mo.entries {
    if e.key == 0 || e.reshape {
      continue
    }
    match mo.recs.get(e.key) {
      Some(r) if r.list != 0 && r.moving_dy.abs() > 0.5 => moving.push((e, r))
      _ => ()
    }
  }
  // what flies over the rows (words sent to their bubble): where it is drawn now
  let flying : Array[(Int, Double, Double, Double, Double)] = []
  for e in mo.entries {
    if e.fly is Some(_) {
      let (fx, fy, fw, fh) = c.node_rect(e.node)
      let l = c.look_of(e.node)
      flying.push((e.node, fx + l.dx + l.ox * fw * (1.0 - l.sx), fy + l.dy + l.oy * fh * (1.0 - l.sy), fw * l.sx, fh * l.sy))
    }
  }
  if moving.is_empty() && flying.is_empty() {
    return
  }
  for e in mo.entries {
    if e.key == 0 || e.reshape {
      continue
    }
    guard mo.recs.get(e.key) is Some(r) && r.list != 0 else { continue }
    // (read for what draws it: the moves it is cut by, as they go)
    c.reads_for(e.node, fn() {
      let (_, ny, _, nh) = c.node_rect(e.node)
      let look = c.look_of(e.node)
      let dy = look.dy
      // (across, where it draws: rows side by side, a composer's ＋ and send beside its words, are in no one place)
      let (ex0, ex1) = c.node_drawn_across(e.node)
      let mut top = 0.0
      let mut bottom = nh
      for m in moving {
        let (me, mr) = m
        if mr.list != r.list || me.node == e.node || mr.moving_dy.abs() <= r.moving_dy.abs() + 0.5 {
          continue
        }
        ignore(mr.oy.get())
        ignore(mr.hp.get())
        let (_, my, _, mh) = c.node_rect(me.node)
        let mlook = c.look_of(me.node)
        let mdy = mlook.dy
        let (mx0, mx1) = c.node_drawn_across(me.node)
        if mx1 + mlook.dx <= ex0 + look.dx || mx0 + mlook.dx >= ex1 + look.dx {
          continue
        }
        if my >= ny + nh - 0.5 {
          // laid under it, drawn up over it: its words from that one's top on not drawn
          bottom = dmin(bottom, my + mdy - (ny + dy))
        } else if my + mh <= ny + 0.5 {
          // laid over it, drawn down over it (as much of it as shows: grown, coming out with its move)
          top = dmax(top, my + mdy + dmin(mh, mr.shown_h) - (ny + dy))
        }
      }
      // what flies over it: none of it drawn where that is, on the side of it that is (its words under none of them,
      // shown again as it goes on: an agent's line, a message's time, under words sent on their way up)
      let (ax0, ax1) = if flying.is_empty() { (0.0, 0.0) } else { c.node_drawn_across(e.node) }
      for f in flying {
        let (fnode, fx, fy, fw, fh) = f
        if fnode == e.node || fx + fw <= ax0 || fx >= ax1 || fy + fh <= ny + dy || fy >= ny + dy + nh {
          continue
        }
        // (not the row it flies to, which holds it)
        let mut q = fnode
        while q >= 0 && q != e.node {
          q = c.node_parent(q)
        }
        if q == e.node {
          continue
        }
        if fy + fh / 2.0 > ny + dy + nh / 2.0 {
          bottom = dmin(bottom, fy - (ny + dy))
        } else {
          top = dmax(top, fy + fh - (ny + dy))
        }
      }
      // (its edge soft: what it draws fades in over room_soft as it is shown, the softness going as the room opens
      // whole, so that the last of it shows as it was, not at once)
      if bottom < nh {
        c.cut_to_top(e.node, dmax(bottom, 0.0), soft=dmin(room_soft, nh - bottom))
      }
      if top > 0.0 {
        c.cut_to_bottom(e.node, dmax(nh - top, 0.0), soft=dmin(room_soft, top))
      }
    })
  }
}

///|
/// Entry `e` laid out this frame (after_layout): where it is kept, how it moves from where it showed, the look it is
/// drawn by.
fn layout_entry(c : @ui.Ctx, e : Moving, still : Bool, frame : Int, scrolled : Map[Int, Double]) -> Unit {
    let (nx, ny, nw, nh) = c.node_rect(e.node)
    let app_look = c.look_of(e.node)
    let mut look = app_look
    // its own move (for the log: what it is drawn from beside its scope's)
    let mut flip_dy = 0.0
    if e.kept != 0 {
      let made = !mo.recs.contains(e.kept)
      let r = match mo.recs.get(e.kept) {
        Some(r) => r
        None => {
          let r = Rec::new()
          mo.recs[e.kept] = r
          r
        }
      }
      // (what reads it told as what it reads of it changes: how big it is or whether it is laid out, measured, measured_size;
      // where it lies, measured_rect)
      if made || r.w != nw || r.h != nh || r.seen < frame - 1 {
        measure_changed(measure_size, e.kept, if made {
          "first"
        } else if r.seen < frame - 1 {
          "laid out again"
        } else {
          "\{r.w}x\{r.h} to \{nw}x\{nh}"
        })
      }
      if r.x != nx || r.y != ny {
        measure_changed(measure_at, e.kept, "moved")
      }
      r.x = nx
      r.y = ny
      r.w = nw
      r.h = nh
      r.seen = frame
    }
    if e.key != 0 {
      let li = c.list_above(e.node)
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
        match scope_above(c, e.node) {
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
          r.gp.name = said
          r.hp.name = said
          mo.recs[e.key] = r
          r
        }
      }
      // (the first build of this frame to lay it out: where it was drawn, and its offsets then)
      if r.frame_at != frame {
        r.frame_at = frame
        r.was_x = r.x
        r.was_y = r.y
        r.was_vy = r.vy
        r.was_ref = r.ref
        r.was_seen = r.seen
        r.ox.step(c)
        r.oy.step(c)
        r.was_ox = r.ox.get()
        r.was_oy = r.oy.get()
        r.was_driven = r.driven
        r.was_by = r.by
        r.was_fx = r.fx
        r.was_fy = r.fy
        r.moved_now = false
        r.was_w = r.w
        r.was_h = r.h
        r.was_rad = r.rad
        r.gp.step(c)
        r.was_gp = r.gp.get()
        r.was_gx = r.gx
        r.was_gy = r.gy
        r.was_gw = r.gw
        r.was_gh = r.gh
        r.was_gr = r.gr
        r.hp.step(c)
        r.was_hp = r.hp.get()
        r.was_hh = r.hh
        r.g_now = false
      }
      let lm = if li >= 0 { mo.lists.get(ref) } else { None }
      let was_seen = r.was_seen >= frame - 1 && r.was_ref == ref
      // its list held at its foot as its rows changed (one gone, at its end): all it showed put down as far as they
      // lost, its place in it the same, moved so for that change all the same (the rows over a row gone come down
      // over it, those under it stay), and one come into view over them so comes down with them, from out of view
      let pinned = if li >= 0 { c.list_pinned_by(li) } else { 0.0 }
      let pinned_in = e.flip &&
        !was_seen &&
        pinned > 0.5 &&
        (match lm {
          Some(l) => l.changed_frame == frame
          None => false
        })
      // where it shows in its list's view
      let vy = if li >= 0 {
        let (_, ly, _, _) = c.node_rect(li)
        ny - ly
      } else {
        ry
      }
      // (a build before this one moved it, this one does not: its offsets as they were when the frame began)
      let undo = fn() {
        if r.moved_now {
          r.moved_now = false
          r.driven = r.was_driven
          r.fx = r.was_fx
          r.fy = r.was_fy
          r.ox.value = r.was_ox
          r.oy.value = r.was_oy
          // (on its way again as it was told: the same spec, its way as long as it was, not one of its own)
          let again = fn(a : Anim) { if a.spec is Snap(_) { e.spec } else { a.spec } }
          if r.was_ox == 0.0 { r.ox.snap(0.0) } else { r.ox.animate(0.0, again(r.ox)) }
          if r.was_oy == 0.0 { r.oy.snap(0.0) } else { r.oy.animate(0.0, again(r.oy)) }
        }
      }
      // gone ahead of others (list_keys' reborn): where it is now at once, come in there as a row new to it
      // (every build of the frame its list changed in: the frame's first lays it out where it was)
      let reborn = match lm {
        Some(l) => l.reborn.get(e.key) == Some(frame)
        None => false
      }
      if reborn {
        r.ox.snap(0.0)
        r.oy.snap(0.0)
        r.driven = false
        r.moved_now = false
      }
      if !(e.flip && (was_seen || pinned_in)) || reborn {
        undo()
      }
      // how far it goes for its cause, the furthest of all it moves (its place, its height, its ground's corners), in
      // points: a Move of it as long as that (Spec::over), each of them on the same clock
      let far = {
        let dx = r.was_ox + (if was_seen { r.was_x - rx } else { 0.0 })
        let dy = r.was_oy + (if !was_seen {
          -pinned
        } else if e.screen {
          r.was_vy - vy
        } else {
          r.was_y - ry - pinned
        }) +
          foot_moved_in(e.by, frame)
        let p0 = r.was_gp
        let gx = r.was_gx + (r.was_x - r.was_gx) * p0
        // (from its foot: as its ground sets off, below)
        let gy = r.was_gy + (r.was_y - r.was_gy) * p0 +
          (if e.reshape && e.foot && !e.carry { ry + nh - (r.was_y + r.was_h) } else { 0.0 })
        let gw = r.was_gw + (r.was_w - r.was_gw) * p0
        let gh = r.was_gh + (r.was_h - r.was_gh) * p0
        let ground = if e.reshape {
          dmax(dmax((gx - rx).abs(), (gy - ry).abs()), dmax((gx + gw - rx - nw).abs(), (gy + gh - ry - nh).abs()))
        } else {
          0.0
        }
        dmax(dmax(dx.abs(), dy.abs()), dmax(dmax((nh - r.was_h).abs(), (nw - r.was_w).abs()), ground))
      }
      // (one whose way is said for it, as long as that: what moves on another's clock)
      let spec = if e.spec.way_said() { e.spec } else { e.spec.over(far) }
      let group = if e.spec.way_said() { "" } else { e.by }
      if e.flip && (was_seen || pinned_in) && !reborn {
        let dx = if was_seen { r.was_x - rx } else { 0.0 }
        let dy = if !was_seen {
          -pinned
        } else if e.screen {
          r.was_vy - vy
        } else {
          r.was_y - ry - pinned
        }
        if dx.abs() <= 0.5 && dy.abs() <= 0.5 {
          undo()
        }
        if dx.abs() > 0.5 || dy.abs() > 0.5 {
          // moved for its cause: a progress the app drives it by, what it names changed since the frame before, or (it
          // naming none) its list's rows; else what holds it moved it, taken at once
          let changed = e.drive >= 0.0 ||
            (if e.by != "" {
              r.was_by != "" && e.by != r.was_by
            } else {
              match lm {
                Some(l) => l.changed_frame == frame
                None => false
              }
            })
          // (with a shape set off from its foot for the same cause: what moved that foot for nothing it changes for
          // taken at once, as the shape's ground takes it: reshape's `foot`)
          let dy = if changed { dy + foot_moved_in(e.by, frame) } else { dy }
          // what is left of the progress driving it now, and where it is drawn off its place as the frame begins: on
          // the drive it was on (the same progress, gone on to now) or its spring; a move carries on from there
          let left = if e.drive >= 0.0 { 1.0 - dclamp(e.drive, 0.0, 1.0) } else { 0.0 }
          let (cx, cy) = if r.was_driven {
            let l = if e.drive >= 0.0 { left } else { 1.0 - r.drove }
            (r.was_fx * l, r.was_fy * l)
          } else {
            (r.was_ox, r.was_oy)
          }
          if still || (e.drive >= 0.0 && left <= 0.0) {
            r.ox.snap(0.0)
            r.oy.snap(0.0)
            r.driven = false
            r.moved_now = false
          } else if !changed {
            // what holds it moved it: there at once, a move of its own going on as it was
            undo()
          } else if e.drive >= 0.0 {
            // the rest of its way by what is left of the progress (a move as it sets off: all of it)
            r.fx = (cx + dx) / left
            r.fy = (cy + dy) / left
            r.driven = true
            r.moved_now = true
            r.ox.snap(0.0)
            r.oy.snap(0.0)
          } else {
            // closing over a row gone: a little late, unless it went ahead
            let delay = match lm {
              Some(l) if c.moment() <= l.close_until && !l.lifted.contains(e.key) => 100.0
              _ => 0.0
            }
            let spec = spec.delayed(delay)
            r.driven = false
            r.moved_now = true
            r.ox.value = cx + dx
            moves_with(group, far, r.ox, 0.0, spec)
            r.oy.value = cy + dy
            moves_with(group, far, r.oy, 0.0, spec)
          }
        }
      }
      // grown for its cause (its words a line more), not in a list (whose rows make room for each other: makes_room):
      // what it holds is laid out as tall as it ends at once, but shows only as tall as it showed, going to as tall as
      // it is laid out with its move, so that what it has more comes out as it gets there, not drawn over what stands
      // by it that it moves away from or towards (the composer's field over its send, 2026-10-29: 「输入框变高的时候
      // 会盖住发送按钮」). Shrunk, or resized by nothing it moves for, it shows whole (a growth on its way going on, as far
      // off its new height as it was off its old). What comes out fades to the cut, each pixel by where it is (half a
      // line out shows its half, fading: 2026-10-30 「带渐隐，但不是整行渐隐」), over no more than it has gone (none as it
      // sets off: what showed is not faded then, the line that was last neither dimmed nor lit again, 「换行的时候最后两行
      // 会闪烁」) and no more than it has to go (none as it ends: nothing lit at once).
      r.shown_h = nh
      if e.flip && li < 0 {
        let shown = r.was_hh + (r.was_h - r.was_hh) * r.was_hp
        let caused = e.by != "" && r.was_by != "" && e.by != r.was_by
        if still || !was_seen || reborn {
          r.hp.snap(1.0)
        } else if caused && (nh - r.was_h).abs() > 0.5 {
          r.hh = shown
          r.hp.snap(if nh > shown + 0.5 { 0.0 } else { 1.0 })
          if nh > shown + 0.5 {
            moves_with(group, far, r.hp, 1.0, spec)
          }
        } else if (nh - r.was_h).abs() > 0.5 {
          r.hh = r.was_hh + (nh - r.was_h)
        }
        let p = r.hp.get()
        if p < 1.0 {
          let h = r.hh + (nh - r.hh) * p
          r.shown_h = dmax(h, 0.0)
          c.cut_to_top(e.node, dmax(h, 0.0), soft=@ui.cut_soft(h - r.hh, nh - h))
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
                    c.moment() - at < 400.0
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
      // its ground on its way from the shape it had to the one it is laid out in, for its cause (reshape)
      if e.reshape {
        let to_r = corners_in(c.node_radii(e.node), nw, nh)
        let caused = e.by != "" && r.was_by != "" && e.by != r.was_by
        let changed_shape = (r.was_x - rx).abs() > 0.5 ||
          (r.was_y - ry).abs() > 0.5 ||
          (r.was_w - nw).abs() > 0.5 ||
          (r.was_h - nh).abs() > 0.5
        let p0 = r.was_gp
        if still || !was_seen {
          r.gp.snap(1.0)
          r.g_now = false
        } else if caused && changed_shape {
          // from the shape it showed as the frame began (on its way, or as it was laid out)
          let wr = corners_in(r.was_rad, r.was_w, r.was_h)
          r.gx = r.was_gx + (r.was_x - r.was_gx) * p0
          r.gy = r.was_gy + (r.was_y - r.was_gy) * p0
          r.gw = r.was_gw + (r.was_w - r.was_gw) * p0
          r.gh = r.was_gh + (r.was_h - r.was_gh) * p0
          // (from its foot: its foot moved this frame by what holds it there at once, its ground set off from there)
          if e.foot && !e.carry {
            let moved = ry + nh - (r.was_y + r.was_h)
            r.gy = r.gy + moved
            foot_moved[e.by] = (frame, moved)
          }
          r.gr = corners_mix(r.was_gr, wr, p0)
          r.gp.snap(0.0)
          moves_with(group, far, r.gp, 1.0, spec)
          r.g_now = true
          r.g_carry = e.carry
        } else {
          // what holds it moved or resized it: where it set out from as far off its new shape as it was off its old,
          // its way going on as it was (a build before this one set it off anew: back as the frame began)
          r.gx = r.was_gx + (rx - r.was_x)
          r.gy = r.was_gy + (ry - r.was_y)
          r.gw = r.was_gw + (nw - r.was_w)
          r.gh = r.was_gh + (nh - r.was_h)
          r.gr = r.was_gr
          if r.g_now {
            r.g_now = false
            r.gp.snap(p0)
            if p0 < 1.0 {
              moves_with(group, far, r.gp, 1.0, spec)
            }
          }
        }
        let p = r.gp.get()
        if p < 1.0 {
          let ox = nx - rx
          let oy = ny - ry
          c.draw_ground(
            e.node,
            ox + r.gx + (rx - r.gx) * p,
            oy + r.gy + (ry - r.gy) * p,
            r.gw + (nw - r.gw) * p,
            r.gh + (nh - r.gh) * p,
            corners_mix(r.gr, to_r, p),
          )
        }
      }
      r.rad = c.node_radii(e.node)
      r.x = rx
      r.y = ry
      r.by = e.by
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
      // carried on the ground of a shape gone with what it holds, new in it as that set off (reshape's carry): placed
      // by that ground, as far from its nearer edges as it is laid out, until the ground is there
      if r.on == 0 && !was_seen && !still && !e.reshape {
        match carrier(c, e.node) {
          Some((a, ar)) if ar.g_carry && ar.gp.get() < 1.0 => {
            let (ax, ay, aw, ah) = c.node_rect(a.node)
            r.on = a.key
            r.on_edges = (if nx + nw / 2.0 > ax + aw / 2.0 { 1 } else { 0 }) +
              (if ny + nh / 2.0 > ay + ah / 2.0 { 2 } else { 0 })
          }
          _ => ()
        }
      }
      let (cx, cy) = match mo.recs.get(r.on) {
        Some(ar) if r.on != 0 && ar.seen == frame && ar.gp.get() < 1.0 => {
          let p = ar.gp.get()
          let gx = ar.gx + (ar.x - ar.gx) * p
          let gy = ar.gy + (ar.y - ar.gy) * p
          let gw = ar.gw + (ar.w - ar.gw) * p
          let gh = ar.gh + (ar.h - ar.gh) * p
          // (its own moves none meanwhile: where it is drawn is the ground's)
          r.ox.snap(0.0)
          r.oy.snap(0.0)
          r.driven = false
          (
            if r.on_edges % 2 == 1 { gx + gw - ar.x - ar.w } else { gx - ar.x },
            if r.on_edges >= 2 { gy + gh - ar.y - ar.h } else { gy - ar.y },
          )
        }
        _ => {
          r.on = 0
          (0.0, 0.0)
        }
      }
      // its look: on the way to its place, coming in
      let (ox, oy) = if r.driven && e.drive >= 0.0 {
        let p = dclamp(e.drive, 0.0, 1.0)
        r.drove = p
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
      let ox = ox + cx
      let oy = oy + cy
      r.moving_dy = oy
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
        look = look.then({ alpha: 1.0, dx: x - nx, dy: y - ny, sx: s, sy: s, ox: 0.0, oy: 0.0, rot: 0.0, circle: 0.0, words: 1.0 })
      }
      None => ()
    }
    if look != app_look {
      c.set_look(e.node, look)
    }
    if logging() && e.name != "" && (!look.is_still() || e.fly is Some(_)) {
      @ui.log(
        "MOTION \{c.moment()} \{e.name} x=\{nx + look.dx} y=\{ny + look.dy} w=\{nw * look.sx} h=\{nh * look.sy} alpha=\{look.alpha} dx=\{look.dx} dy=\{look.dy} scale=\{look.sx} fy=\{flip_dy}",
      )
    }
}

///|
/// Forgets the places of what has not been built for a while.
fn forget_recs(c : @ui.Ctx) -> Unit {
  let frame = c.frame_number()
  // (what reads a measure laid out last frame and not this one: none from the next frame, measured_rect)
  measures_lapsed(frame)
  if frame % 30 != 0 || mo.recs.is_empty() {
    return
  }
  let old : Array[Int] = []
  mo.recs.each(fn(k, r) {
    if frame - r.seen > 90 && !r.ox.running && !r.oy.running && !r.gp.running {
      old.push(k)
    }
  })
  for k in old {
    mo.recs.remove(k)
    // (a measure forgotten: none from now on, what read it told)
    measure_changed(measure_size, k, "forgotten")
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
    // from as it was (1) to its far end (0); not where a row of its list is drawn now: what goes gives way to what is
    // there or comes over it, never its words under theirs (docs/motion.md rule 4)
    c.draw_drawing(gh.drawing, li, gh.trans.at(1.0 - pf, 1.0 - pm), apart=rows_drawn(c, id))
  }
  let mut j = done.length() - 1
  while j >= 0 {
    mo.ghosts.remove(done[j]) |> ignore
    j = j - 1
  }
}

// ── a measure read as it is built ───────────────────────────────────────

///|
/// What reads where a node kept by its key lies (measured_rect: where a flight lands) as it is built, told as it moves:
/// a signal by the key, made as it is first read.
// kept across runs: forgotten as a Tester starts anew (reset), each let go once nothing reads it
let measure_at : Map[Int, @signals.Signal[Int]] = {}

///|
/// What reads how big a node kept by its key is, or whether it is laid out (measured, measured_size, measured_rect: a
/// measure, a reveal's content) as it is built, told as that changes, not as it moves (a page it is on sliding in): a
/// signal by the key, made as it is first read.
// kept across runs: forgotten as a Tester starts anew (reset), each let go once nothing reads it
let measure_size : Map[Int, @signals.Signal[Int]] = {}

///|
/// Measure `key` read of `said` as what is built is built: built again as what it reads of it changes.
fn measure_read(said : Map[Int, @signals.Signal[Int]], key : Int, name~ : String) -> Unit {
  if @ui.perf_counting() && !measure_names.contains(key) {
    measure_names[key] = name
  }
  let s = match said.get(key) {
    Some(s) => s
    None => {
      let s = @signals.signal(0)
      said[key] = s
      s
    }
  }
  s.get() |> ignore
}

///|
/// Measure `key` laid out other than `said`'s readers read it (or for the first time, or no longer): they are told.
fn measure_changed(said : Map[Int, @signals.Signal[Int]], key : Int, why : String) -> Unit {
  match said.get(key) {
    Some(s) => {
      if @ui.perf_counting() && s.watched() {
        measure_count(key, why)
      }
      s.set(@signals.untracked(fn() { s.get() }) + 1)
    }
    None => ()
  }
}

///|
/// The keys of the measures read while the frame probe counts (@ui.perf_counting), by their hash.
// kept across runs: the performance record's, read by nothing else
let measure_names : Map[Int, String] = {}

///|
/// How often each measure read told what read it since the record last asked, by its key and why.
// kept across runs: the performance record's, read by nothing else
let measure_told : Map[String, Int] = {}

///|
/// Measure `key` telling what reads it, for `why`: counted for the performance record ("measures:", the most told
/// first), what is built again for it found by its key, not only by where it was told.
fn measure_count(key : Int, why : String) -> Unit {
  if measure_told.is_empty() {
    @ui.perf_also("measures", measures_said)
  }
  let name = match measure_names.get(key) {
    Some(n) => n
    None => "#\{key}"
  }
  let k = name + " " + why
  measure_told[k] = measure_told.get(k).unwrap_or(0) + 1
}

///|
/// The measures told since last asked, the 6 most told first (`<count> <key> <why>`), and forgotten.
fn measures_said(span : Double) -> String {
  ignore(span)
  let all = measure_told.to_array()
  measure_told.clear()
  all.sort_by(fn(a, b) {
    let c = b.1.compare(a.1)
    if c != 0 { c } else { a.0.compare(b.0) }
  })
  let out = StringBuilder::new()
  for i, e in all {
    if i >= 6 {
      break
    }
    out.write_string((if i == 0 { " " } else { " | " }) + "\{e.1} \{e.0}")
  }
  out.to_string()
}

///|
/// The frame `frame` is laid out: the measures read that were laid out the frame before and not in this one are
/// nowhere from the next frame on (measured_size, measured_rect), what read them told; those nothing reads let go.
fn measures_lapsed(frame : Int) -> Unit {
  let unread : Array[Int] = []
  measure_at.each(fn(k, s) { if !s.watched() { unread.push(k) } })
  for k in unread {
    measure_at.remove(k)
  }
  if measure_size.is_empty() {
    return
  }
  let gone : Array[Int] = []
  measure_size.each(fn(k, s) {
    if !s.watched() {
      gone.push(k)
    } else {
      match mo.recs.get(k) {
        Some(r) if r.seen == frame - 1 => {
          if @ui.perf_counting() {
            measure_count(k, "not laid out")
          }
          s.set(@signals.untracked(fn() { s.get() }) + 1)
        }
        _ => ()
      }
    }
  })
  for k in gone {
    measure_size.remove(k)
  }
}
