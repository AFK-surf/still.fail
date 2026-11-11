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
// - a list's rows by key (list_keys): rows new to the list come in (an enter transition), rows gone
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
#derive(Eq)
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
  /// over both seen in one place (sf/motion.mbt rule 4)
  ground_first : Bool
}

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
  /// grown or shut for its cause: what it holds cut to as tall as it shows (its words a line more; a collapsible's
  /// content going in as it closes); false where what comes into it grows with it of itself, drawn whole (`grown_shown`)
  mut cut : Bool
  /// drawn whole while what moves with it goes over it (makes_room cuts it nowhere): a button on its way beside words
  /// moving past it, the ＋ and send of a composer as its field goes up over them
  mut whole : Bool
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
  /// Its drawn origin is also kept, for an action that takes it from what was shown.
  mut kept_drawn : Bool
  /// a frame its keyed nodes' places are taken in (scope): 1 from its top left, 2 from its bottom left
  mut scope : Int
  /// flown from (x, y, scale), how far across, down and grown
  mut fly : (Double, Double, Double, Double, Double, Double)?
  /// the same worked out once this frame is laid out (fly_by), in its place
  mut fly_by : (() -> (Double, Double, Double, Double, Double, Double))?
  /// placed by its own look but flying over rows, which must make room for it
  mut flying_placed : Bool
  /// its own ground changes shape for its cause (reshape), by `spec`
  mut reshape : Bool
  /// reshape: it goes from where it was with what it holds (laid out for another place: the web's morph), what is new
  /// in it carried on its ground
  mut carry : Bool
  /// reshape: it changes shape from its foot (reshape's `foot`)
  mut foot : Bool
  /// reshape: the moment its cause came, where that was before this frame (reshape's `at`; -inf: none said)
  mut at : Double
  /// how it is drawn, worked out once this frame is laid out (placed)
  mut placed : (() -> @ui.Look)?
}

///|
/// What a keyed node was, kept from frame to frame: where it was laid out (in its list's content, or the window),
/// when, its offset on the way to its place, its entrance, and how it was last drawn (for its copy when it leaves).
priv struct Rec {
  /// the speed its ground's way set off with as it was last reshaped for a cause, and the moment: built again in that
  /// moment, it sets off as fast again
  mut g_set_v : Double
  mut g_set_at : Double
  /// the same of its place's ways (across, down), as it was last set off again for a cause
  mut p_set_v : (Double, Double)
  mut p_set_at : Double
  mut x : Double
  mut y : Double
  mut w : Double
  mut h : Double
  /// the node it was laid out as, in the layout of the frame it was last seen in (`seen`)
  mut node : Int
  /// How a measured node was drawn after all of its ancestors' looks were applied.
  mut drawn : @ui.DrawnState?
  mut anchor : Int
  /// the frame it was last laid out in (what this frame's builds of it read: layout_entry)
  mut seen : Int
  /// whether what lays it out is built (from its first layout until it is no longer built: rec_unbuilt), and whether
  /// what reads how tall it was (measured) is: kept while either is, or while it moves (dead_let_go)
  mut alive : Bool
  mut read : Bool
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
  /// The current scope node for a scoped place, or -1 for a list or window place.
  mut scope_node : Int
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
  mut was_alive : Bool
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
  /// Translation inherited from a carried ground, excluded when reporting shape changes to what stands on it.
  mut g_carried_y : Double
  mut was_g_carried_y : Double
  mut was_g_carry : Bool
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
fn Rec::new() -> Rec {
  {
    x: 0.0,
    y: 0.0,
    w: 0.0,
    h: 0.0,
    node: -1,
    drawn: None,
    anchor: 0,
    seen: -10,
    alive: false,
    read: false,
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
    scope_node: -1,
    frame_at: -1,
    was_x: 0.0,
    was_y: 0.0,
    was_vy: 0.0,
    was_ref: 0,
    was_alive: false,
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
    g_carried_y: 0.0,
    g_set_v: 0.0,
    g_set_at: @double.neg_infinity,
    p_set_v: (0.0, 0.0),
    p_set_at: @double.neg_infinity,
    was_g_carried_y: 0.0,
    was_g_carry: false,
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
  /// over none of theirs (sf/motion.mbt rule 4; the user, 2026-10-29: 「它先缩下去，然后在目标位置挤出来」)
  reborn : Map[Int, Int]
  /// what moves its rows lifted over others (read where a row reads how long ago it was lifted: `lifted`)
  lift_mover : @ui.Mover
  /// rows let go without a copy left behind (swiped away: list_unghost)
  unghost : Map[Int, Bool]
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
  /// what the build being made said moves (by moving_of), until it is laid out (after_layout): what is said after
  /// that is another build's (a frame built again: its nodes other nodes), said anew (entries_anew)
  entries : Array[Moving]
  mut laid : Bool
  /// by node: its entry in `entries` (-1: none)
  at : Array[Int]
  recs : Map[Int, Rec]
  /// the keys of those whose node was no longer built while they moved: let go once they are still (rec_unbuilt)
  dead : Array[Int]
  lists : Map[Int, ListMo]
  ghosts : Array[Ghost]
}

///|
let mo : MotionState = {
  entries: [],
  laid: false,
  at: [],
  recs: {},
  dead: [],
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
  @ui.on_list_underlay(draw_ghosts)
  @ui.on_reset(reset)
}

///|
fn reset() -> Unit {
  mo.entries.clear()
  measure_at.clear()
  measure_size.clear()
  measure_tall.clear()
  measure_radii.clear()
  measure_names.clear()
  measure_told.clear()
  mo.at.clear()
  mo.laid = false
  mo.dead.clear()
  mo.recs.clear()
  mo.lists.clear()
  mo.ghosts.clear()
  reveal_heights.clear()
  anims.clear()
  anims_moving.clear()
  ripples.clear()
  foot_moved.clear()
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
  ignore(c)
  install()
  if mo.laid {
    entries_anew()
  }
  while mo.at.length() <= i {
    mo.at.push(-1)
  }
  if mo.at[i] >= 0 {
    return mo.entries[mo.at[i]]
  }
  let e : Moving = {
    node: i,
    key: 0,
    flip: false,
    cut: true,
    whole: false,
    spec: row_spring,
    by: "",
    drive: -1.0,
    screen: false,
    name: "",
    enter: None,
    exit: None,
    fresh: false,
    kept: 0,
    kept_drawn: false,
    scope: 0,
    fly: None,
    fly_by: None,
    flying_placed: false,
    reshape: false,
    carry: false,
    foot: false,
    at: @double.neg_infinity,
    placed: None,
  }
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
  if mo.laid {
    entries_anew()
  }
  while mo.at.length() <= i {
    mo.at.push(-1)
  }
  mo.at[i] = mo.entries.length()
  mo.entries.push({ ..e, node: i })
}

///|
/// The entries laid out (after_layout): what is said now is another build's, from none.
fn entries_anew() -> Unit {
  for e in mo.entries {
    if e.node < mo.at.length() {
      mo.at[e.node] = -1
    }
  }
  mo.entries.clear()
  mo.laid = false
}

///|
/// Node `i`'s entry this build, if it has one.
fn entry_of(c : @ui.Ctx, i : Int) -> Moving? {
  ignore(c)
  if !mo.laid && i >= 0 && i < mo.at.length() && mo.at[i] >= 0 {
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
/// own going on as it was: no difference found between frames moves anything (sf/motion.mbt of the app). `enter` is how a row new to its list comes in, `exit` how one gone leaves (a copy of it where it was).
/// `drive` (0 → 1, from the frame it moved): the move goes by that progress instead of `spec`. `screen`: in a list, by
/// where it shows in the list's view. `cut`: grown or shut for its cause, what it holds is cut to as tall as it shows (shut: what it holds past its room going in under its foot); false
/// where what is new in it grows with its room of itself (`grown_shown`): drawn whole, never cut through. `whole`: not
/// cut back for another of its list moving over it (makes_room), drawn whole on its way (a composer's ＋ and send, its
/// field going up past them as it opens: what is over them there is the field's own room, not words).
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
  cut? : Bool = true,
  whole? : Bool = false,
) -> Unit {
  let e = moving_of(c, i)
  e.name = key
  e.key = motion_key(key)
  e.flip = true
  e.cut = cut
  e.whole = whole
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
/// Node `i` keyed `key` changes shape for its cause: in the frame `by` (what it changes for:
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
/// foot: the user, 2026-10-30 「以底部为 origin」). `at`: the moment of the cause `by` changed for, said only on the
/// change that cause makes (words sent letting go of it at their declared moment): it and what moves with it set out
/// from then, as far on as the time since says, not from the frame that lays it out; one not come yet is not.
pub fn reshape(
  c : @ui.Ctx,
  i : Int,
  key : String,
  by~ : String,
  spec~ : Spec,
  carry? : Bool = false,
  foot? : Bool = false,
  at? : Double,
) -> Unit {
  let e = moving_of(c, i)
  e.name = key
  match at {
    Some(t) => e.at = t
    None => ()
  }
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
/// Node `i` flown as `fly` flies it, from where and how far on as `at` gives them (x, y, scale, px, py, ps), worked out
/// once this frame is laid out as `placed`'s are: what is read there of a way going on (where words sent are on theirs)
/// is read as the frame is laid out, not as it is built, so that what builds it is not built again each frame it goes.
pub fn fly_by(c : @ui.Ctx, i : Int, at : () -> (Double, Double, Double, Double, Double, Double)) -> Unit {
  let e = moving_of(c, i)
  if e.name == "" {
    e.name = "fly"
  }
  e.fly = Some((0.0, 0.0, 1.0, 1.0, 1.0, 1.0))
  e.fly_by = Some(at)
  c.stratum(i, Flying)
}

///|
/// A node placed by its own look flies over list rows, which leave its drawn room clear.
pub fn flying_placed(c : @ui.Ctx, i : Int) -> Unit {
  let e = moving_of(c, i)
  e.flying_placed = true
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
  e.kept_drawn = false
}

///|
/// Keep node `i`'s layout as for measure and its last drawn origin, for an action taking it from where it showed.
pub fn measure_drawn(c : @ui.Ctx, i : Int, key : String) -> Unit {
  let e = moving_of(c, i)
  e.kept = motion_key("measure\u{1}" + key)
  e.kept_drawn = true
}

///|
/// How tall the node kept as `key` was when last laid out (measure); what reads it is told as that changes, not as the
/// node gets wider (a page beside the sidebar on its way).
pub fn measured(c : @ui.Ctx, key : String) -> Double? {
  let k = motion_key("measure\u{1}" + key)
  measure_read(measure_tall, k, name=key)
  match mo.recs.get(k) {
    Some(r) => {
      // (kept while what reads it is built, laid out or not: let go with it, rec_unread)
      if c.on_unbuilt(hash_mix(0x72656164, k), fn() { rec_unread(k) }) {
        r.read = true
      }
      Some(r.h)
    }
    None => None
  }
}

///|
/// What read how tall keyed node `k` was (measured) is no longer built: kept only while what lays it out is, or while
/// it moves (dead_let_go).
fn rec_unread(k : Int) -> Unit {
  match mo.recs.get(k) {
    Some(r) => {
      r.read = false
      if !r.alive {
        mo.dead.push(k)
      }
    }
    None => ()
  }
}

///|
/// The shape of what is reshaped for cause `by` (reshape's `by`: its ground's way) told at moment `at` to stop where it
/// goes (Anim::stop_at): on from where it was then and as fast, slowing to rest, left there, short of where it is laid
/// out, till its next cause (the coordinator of the migration, 2026-11-10: a composer growing a line as words sent from
/// it hold it: the words gone, it grows no further for them). Only its shape: where it and its parts are placed goes on
/// to where they are laid out, which no next cause would set going again (a box sent from as it opened, its place
/// halfway there for good). One rule with a way set off again the other way (layout_entry): a motion changed carries
/// its speed.
pub fn stop_for(c : @ui.Ctx, by : String, at : Double) -> Unit {
  if by == "" {
    return
  }
  mo.recs.each(fn(_, r) {
    if r.alive && r.by == by {
      let way = ground_way(r, (r.x, r.y, r.w, r.h))
      if way > 0.0 {
        r.gp.stop_at(c, at, points=way)
      }
    }
  })
}

///|
/// How far over its laid out top the ground of the shape keyed `key` (reshape) is drawn now, on its way from the shape
/// it had (less than 0 while it is drawn lower: growing up to it): what stands on it moves with it so, in the same
/// frame. 0 at rest, and while it goes from where it was with what it holds (`carry`: to another place, not another
/// shape there).
pub fn reshaped_over(c : @ui.Ctx, key : String) -> Double {
  ignore(c)
  match mo.recs.get(motion_key(key)) {
    Some(r) if r.alive && !r.g_carry => {
      let p = r.gp.get(c)
      if p < 1.0 {
        ground_over(r.y, r.gy, r.g_carried_y, p)
      } else {
        0.0
      }
    }
    _ => 0.0
  }
}

///|
/// The way the ground of the node reshaping as `key` (reshape) last set out on: when and how long (the frames' clock),
/// as declared as it was told, so that what goes with that ground as drawn (reshaped_over) goes on that way while it
/// has not ended (built again at its end). None before it ever set out, or carried to another place.
pub fn reshape_way(c : @ui.Ctx, key : String) -> (Double, Double)? {
  ignore(c)
  match mo.recs.get(motion_key(key)) {
    Some(r) if r.alive && !r.g_carry && r.gp.start >= 0.0 => {
      // (what reads it built again at its declared end: Anim::over)
      ignore(r.gp.over(c))
      Some((r.gp.start, r.gp.dur))
    }
    _ => None
  }
}

///|
/// The frame the measured nodes were last laid out in (after_layout): their records' nodes (Rec's `node`) are that
/// layout's.
// kept across runs: said as each frame is laid out
let measures_laid_in : Ref[Int] = Ref(-1)

///|
/// Where the node kept as `key` (measure) was last laid out, in the window: x, y, w, h (None before it was, or once what
/// lays it out is no longer built: rec_unbuilt). Read as the frame is painted, where it is then: a frame painted alone
/// places what the clock moves (Ctx::moved_by, a page sliding) where it is now, nothing laid out, and what reads it as
/// it is painted (a look by Ctx::look_by, a glyph's by Ctx::glyphs_by) reads it there with what it is in, as laying
/// the frame out there reads it.
pub fn measured_rect(c : @ui.Ctx, key : String) -> (Double, Double, Double, Double)? {
  measure_read(measure_at, motion_key("measure\u{1}" + key), name=key)
  measure_read(measure_size, motion_key("measure\u{1}" + key), name=key)
  match mo.recs.get(motion_key("measure\u{1}" + key)) {
    // (its node the frame's: laid out in the layout the frame is painted from)
    Some(r) if r.alive && r.node >= 0 && r.seen == measures_laid_in.val && c.painting() => {
      let (x, y, _, _) = c.node_rect(r.node)
      Some((x, y, r.w, r.h))
    }
    Some(r) if r.alive => Some((r.x, r.y, r.w, r.h))
    _ => None
  }
}

///|
/// Where a measured node was drawn in the last frame, for an action taking it from there. Its place includes its own
/// and its ancestors' offsets; its size is as laid out (scales and clipping are not included). Unlike measured_rect,
/// this is a snapshot for an action, not a place for something to follow while the node moves.
pub fn measured_drawn_rect(c : @ui.Ctx, key : String) -> (Double, Double, Double, Double)? {
  measured_drawn_state(c, key).map(fn(s) { s.rect })
}

///|
/// The drawn rectangle, rectangular cuts and inherited opacity kept by measure_drawn, for an action taking the node
/// from where it showed. None once what measures it is no longer built.
pub fn measured_drawn_state(c : @ui.Ctx, key : String) -> @ui.DrawnState? {
  ignore(c)
  match mo.recs.get(motion_key("measure\u{1}" + key)) {
    Some(r) if r.alive => r.drawn
    _ => None
  }
}

///|
/// The resolved corners of a measured node, for a moving copy to keep its shape. Unequal corners come only from that
/// node's own shape; a fallback made without a node has the same radius at every corner.
pub struct MeasuredCorners {
  priv values : (Double, Double, Double, Double)
}

///|
pub fn MeasuredCorners::uniform(radius : Double) -> MeasuredCorners {
  { values: (radius, radius, radius, radius) }
}

///|
/// The corners as laid out: top left, top right, bottom right, bottom left.
pub fn MeasuredCorners::each(self : MeasuredCorners) -> (Double, Double, Double, Double) {
  self.values
}

///|
/// The same shape scaled uniformly, for a copy moving out from it or back into it.
pub fn MeasuredCorners::scaled(self : MeasuredCorners, by : Double) -> @ui.Radius {
  let (tl, tr, br, bl) = self.values
  @ui.Radius::Corners(tl * by, tr * by, br * by, bl * by)
}

///|
/// The four corners of the node kept as `key` (measure), as the last layout resolved them. What reads them is told
/// when their shape changes, even if the node's size stays the same.
pub fn measured_radii(c : @ui.Ctx, key : String) -> MeasuredCorners? {
  ignore(c)
  let k = motion_key("measure\u{1}" + key)
  measure_read(measure_size, k, name=key)
  measure_read(measure_radii, k, name=key)
  match mo.recs.get(k) {
    Some(r) if r.alive => Some({ values: r.rad })
    _ => None
  }
}

///|
/// How big the node kept as `key` (measure) was when last laid out: w, h (None before it was, or once what lays it
/// out is no longer built); what reads it is not told as it moves (a page it is on sliding in), as measured_rect's is.
pub fn measured_size(c : @ui.Ctx, key : String) -> (Double, Double)? {
  ignore(c)
  measure_read(measure_size, motion_key("measure\u{1}" + key), name=key)
  match mo.recs.get(motion_key("measure\u{1}" + key)) {
    Some(r) if r.alive => Some((r.w, r.h))
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
/// and its move's ends); once at rest, the latest end each was given (Anim::ended_at, before now); -1 when the key is
/// not known or none of it moved; +inf when told to move in the
/// frame just drawn (it starts at the next: the frame owed, Tester::draw). Only read.
pub fn layout_rest(key : String) -> Double {
  let k = motion_key(key)
  let mut e = -1.0
  let at = fn(a : Anim) {
    let x = a.ended_at()
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
/// List `id`'s rows by key kept while what builds the list is built (kept as its nodes too, its build not run: a pane
/// beside the one in use), let go once it is not (its page left, its pane slid away): come back, it is as the first time.
fn list_seen(c : @ui.Ctx, id : Int) -> Unit {
  ignore(c.on_unbuilt(hash_mix(0x6c697374, id), fn() { mo.lists.remove(id) }))
}

///|
/// What changes a list shows by its rows' keys: call while building, each frame, with the keys
/// of the rows of list `list` (as given to Ctx::list in the same scope) in order. The first time nothing moves, nor
/// the first time again after what builds it was not built (Android's list composed anew: its page come back to). As
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
      list_seen(c, id)
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
      }
      mo.lists[id] = l
      list_seen(c, id)
      return id
    }
  }
  list_seen(c, id)
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
  let ks : Array[Int] = Array(capacity=nk)
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
  if nb == 0 || c.still() {
    lm.unghost.clear()
    return id
  }
  lm.changed_frame = frame
  // (the rows between, before and now)
  let old : Map[Int, Int] = Map([])
  for i in lead..<(nb - tail) {
    old[before[i]] = i
  }
  let fresh : Map[Int, Int] = Map([])
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
  let kept_before : Map[Int, Int] = Map([])
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
            Some(rec) if rec.alive && rec.list == id && !rec.drawing.is_empty() && rec.exit is Some(_) => {
              let t = rec.exit.unwrap()
              let pf = Anim::new(0.0)
              let pm = Anim::new(0.0)
              pf.name = keys[i] + " leaving"
              pm.name = pf.name
              pf.animate(c, 1.0, t.fade_spec)
              pm.animate(c, 1.0, t.spec)
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
      Some(r) if r.alive && r.list == id && !r.drawing.is_empty() =>
        match r.exit {
          Some(t) => {
            let pf = Anim::new(0.0)
            let pm = Anim::new(0.0)
            pf.name = before_names[i] + " leaving"
            pm.name = pf.name
            pf.animate(c, 1.0, t.fade_spec)
            pm.animate(c, 1.0, t.spec)
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
  // 
  let left : Array[Int] = []
  lm.unghost.each(fn(k, _) { if !fresh.contains(k) && !ks.contains(k) { left.push(k) } })
  for k in left {
    lm.unghost.remove(k)
  }
  let stale : Array[Int] = []
  lm.arrived.each(fn(k, at) { if now >= at + 500.0 { stale.push(k) } })
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
/// How long a row that went ahead of others takes to pass over them.
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
/// over them; -1 otherwise.
pub fn lifted(c : @ui.Ctx, list : Int, key : String) -> Double {
  match mo.lists.get(list) {
    Some(lm) =>
      match lm.lifted.get(motion_key(key)) {
        Some(at) if c.moment() < at + lift_ms => {
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
        f.animate(c, to, t.fade_spec, start_at=at)
      }
      if m.target != to {
        m.animate(c, to, t.spec, start_at=at)
      }
    }
    None => {
      f.follow(c, to, t.fade_spec)
      m.follow(c, to, t.spec)
    }
  }
  // (read so: what reads it is built again as it is told and each frame while it goes, Anim::get)
  let (fv, mv) = (f.get(c), m.get(c))
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
/// How tall the node keyed `key` (layout) shows now, grown for its cause and on its way to as tall as it is laid out
/// (from its top); None where it shows whole. Read as it is drawn (a look_by): what is new in a room that does not cut
/// it (layout's `cut`) grows with it by this, as the old view `c` draws it.
pub fn grown_shown(c : @ui.Ctx, key : String) -> Double? {
  match mo.recs.get(motion_key(key)) {
    Some(r) => {
      let p = r.hp.get(c)
      if p < 1.0 {
        Some(dmax(r.hh + (r.h - r.hh) * p, 0.0))
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// How tall what `reveal(key)` shows was laid out whole, the last time it was (0: never): how far its room goes.
pub fn reveal_height(c : @ui.Ctx, key : String) -> Double {
  let k = motion_key("reveal\u{1}" + key)
  reveal_kept(c, k)
  reveal_heights.get(k).unwrap_or(0.0)
}

///|
/// How tall what each room showed was laid out whole, the last time it was, by its key: the room's own, set as what it
/// shows is laid out (layout_entry), kept while what asks for the room (reveal, reveal_height) is built, its room shut
/// too; let go with that (reveal_kept).
// kept across runs: forgotten as a Tester starts anew (reset)
let reveal_heights : Map[Int, Double] = Map([])

///|
/// Room `k` asked by what is built now: its height kept while that is built, let go once it is not.
fn reveal_kept(c : @ui.Ctx, k : Int) -> Unit {
  if c.on_unbuilt(hash_mix(0x72657665, k), fn() { reveal_heights.remove(k) |> ignore }) && !reveal_heights.contains(k) {
    reveal_heights[k] = 0.0
  }
}

///|
/// What `body` builds, as tall as `share` (0 → 1) of its own height (expandVertically / shrinkVertically, from its top
/// or with its foot kept), cut there when `clip`; all of it at 1. `align` places what it builds across, as its parent
/// would. `middle`: what it builds kept in the middle of its room, as big as it is open and faded out by half,
/// about the middle of what it draws (@ui.Ctx::held_look), cut by it at both ends, what is cut fading out to them (2026-10-31 the user: 「你要不两头裁呢？再加上淡化的边缘」, as a list's row coming and going is). Its own
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
  reveal_kept(c, k)
  let natural = reveal_heights.get(k).unwrap_or(0.0)
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
    // (as big as its room is open and gone by half, as a list's row coming and going where it is: what a card under a
    // post holds not cut by its room as it closes, 2026-10-31 the user: 「特殊情况下消息列表还是会出现比较明显的裁剪」
    // 「比如选择决策」)
    // (read where it is as it is painted: a list's row it is in, kept as its nodes, put back elsewhere among the frame's)
    let held = c.node_held(inner)
    c.look_by(inner, fn() {
      match held.at() {
        Some(i) => c.held_look(i, share)
        None => @ui.still_look
      }
    })
    let soft = @ui.cut_soft((natural - shown) / 2.0, shown / 2.0)
    c.fade_to(inner, outer, top=soft, foot=soft)
  }
}

// ── after layout ────────────────────────────────────────────────────────

///|
/// What moves this frame, worked out once its layout is done: each keyed node's place against the last frame's, its
/// entrance, where it is flown to; their looks then are what painting draws (the app's own look first).
fn after_layout(c : @ui.Ctx) -> Unit {
  // (none said by this build: those there are an earlier one's, laid out already)
  if mo.laid {
    entries_anew()
  }
  measures_unread()
  dead_let_go()
  anims_let_go(c)
  if mo.entries.is_empty() {
    return
  }
  // (the frame being made: each build of it lays it out from where the last frame drew it, and what changed in it (a
  // list's rows, a foot moved) changed for every build of it; what holds a frame's identity, none of its causes: kept)
  let frame = c.frame_number()
  measures_laid_in.val = frame
  let still = c.still()
  let scrolled : Map[Int, Double] = Map([])
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
  cause_at.clear()
  // (what reads where each goes told once all of it is worked out, and only where it came out otherwise: a build of
  // the frame again lays it out from where the frame began, as the first did)
  measures_told_once(c, fn() {
    laid_once(
      c,
      fn() {
        let entries_in_order = if order.is_empty() { mo.entries } else { order }
        for e in entries_in_order {
          // (what its move reads, read for what draws its node: the part's or the row's kept, whoever told it: Ctx::reads_for)
          c.reads_for(e.node, fn() { layout_entry(c, e, still, frame, scrolled) })
        }
        moved_together(c)
      },
    )
  })
  // what is drawn where things are this frame (placed): once every place this frame lays out is kept
  for e in mo.entries {
    match e.placed {
      Some(at) => c.reads_for(e.node, fn() { c.set_look(e.node, c.look_of(e.node).then(at())) })
      None => ()
    }
  }
  makes_room(c)
  // Take the drawn state after every node's look has been set: a measured node can be carried or cut by an ancestor.
  for e in mo.entries {
    if e.kept != 0 && e.kept_drawn {
      match mo.recs.get(e.kept) {
        Some(r) if r.seen == frame => r.drawn = Some(c.drawn_state(e.node))
        _ => ()
      }
    }
  }
  // (what this build said is laid out now: what is said after it is another build's)
  mo.laid = true
}

///|
/// What moves this frame for each cause (its `by`), on a Move: how far the furthest of it goes, and each of its motions
/// (where to, by what), set out again as long as that one, so what moves together for one cause (a composer's ground,
/// its words, its ＋ and its send) is on one clock (sf/motion.mbt: as long as its way is far).
// kept across runs: cleared as each frame's layout begins, taken as it ends (after_layout)
let together : Map[String, (Double, Array[(Anim, Double, Spec, Double?)])] = Map([])

///|
/// For each cause (`by`) a shape set off for at a moment said (reshape's `at`): that moment, from which what moves for
/// it this frame sets out.
// kept across runs: cleared as each frame's layout begins
let cause_at : Map[String, Double] = Map([])

///|
/// For each cause (`by`) a shape set off for from its foot (reshape's `foot`): the frame it did, and how far its foot
/// moved in that frame for nothing it changes for, which what moves with it takes at once. Kept for the frame, not for
/// one build of it: a build again of that frame (its rows kept or not) reads what the first did.
// (forgotten as the app is reset: frames are counted again from there, a cause's frame of before no frame of now)
let foot_moved : Map[String, (Int, Double)] = Map([])

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
fn moves_with(
  c : @ui.Ctx,
  by : String,
  far : Double,
  a : Anim,
  to : Double,
  spec : Spec,
  start_at? : Double,
  velocity? : Double,
) -> Unit {
  // (from the moment its cause came, where one was said: cause_at)
  let start_at = match start_at {
    Some(t) => Some(t)
    None => if by != "" { cause_at.get(by) } else { None }
  }
  a.animate(c, to, spec, start_at?, velocity?)
  guard by != "" && spec is Moved(_, _, _) else { return }
  match together.get(by) {
    Some((most, all)) => {
      all.push((a, to, spec, start_at))
      if far > most {
        together[by] = (far, all)
      }
    }
    None => together[by] = (far, [(a, to, spec, start_at)])
  }
}

///|
/// How fast a ground's way must go as it is set off again (its share a second) for it to go on from that speed.
let reshape_moving : Double = 0.05

///|
/// Whether `spec` sets out from rest whatever it is told (a tween on a curve that starts slow): set off again so while
/// it went, it would stop dead; a Move or a spring goes on from its speed as it is.
fn sets_out_from_rest(spec : Spec) -> Bool {
  match spec {
    Tween(len, Move | InOut | Leave | Flight, _) => len > 0.0
    _ => false
  }
}

///|
/// How long (seconds) what is set off again at speed goes on at that speed in the length its way is given.
let carry_stop_s : Double = 0.2

///|
/// How far a way said for what is set off again `ox`, `oy` off its end going `vx`, `vy` (points a second) toward it
/// goes: as far as it has to, or as far as its speed carries it, the further.
fn carried_way(ox : Double, vx : Double, oy : Double, vy : Double) -> Double {
  dmax(dmax(ox.abs(), oy.abs()), dmax(vx.abs(), vy.abs()) * carry_stop_s)
}

///|
/// How fast a part must go (points a second) as it is set off again for it to go on from that speed (half a point a
/// frame).
let part_moving : Double = 30.0

///|
/// How far (points) a ground's way from where it is drawn to shape `to` goes, along what changes most of it.
fn ground_way(r : Rec, to : (Double, Double, Double, Double)) -> Double {
  dmax(dmax((to.0 - r.gx).abs(), (to.1 - r.gy).abs()), dmax((to.2 - r.gw).abs(), (to.3 - r.gh).abs()))
}

///|
/// How fast (its share a second) a ground's way from shape `from` to `to` goes as it sets off, carrying on what its
/// way from `was_from` to `was_to` went at `v` (its share a second): along the side of it that changes most now.
fn ground_speed_carried(
  was_from : (Double, Double, Double, Double),
  was_to : (Double, Double, Double, Double),
  from : (Double, Double, Double, Double),
  to : (Double, Double, Double, Double),
  v : Double,
) -> Double {
  if v == 0.0 {
    return 0.0
  }
  let sides = [
    (was_to.0 - was_from.0, to.0 - from.0),
    (was_to.1 - was_from.1, to.1 - from.1),
    (was_to.2 - was_from.2, to.2 - from.2),
    (was_to.3 - was_from.3, to.3 - from.3),
  ]
  let mut most = sides[0]
  for s in sides {
    if s.1.abs() > most.1.abs() {
      most = s
    }
  }
  if most.1.abs() < 0.5 {
    0.0
  } else {
    v * most.0 / most.1
  }
}

///|
/// Each cause's motions as long as the furthest of them (moves_with): told again from where they set out this frame.
fn moved_together(c : @ui.Ctx) -> Unit {
  together.each(fn(_, g) {
    let (most, all) = g
    if all.length() < 2 {
      return
    }
    for m in all {
      let (a, to, spec, start_at) = m
      // (all said `far` by this layout: told again as long as the furthest; a way said longer for its own speed
      // (carried_way) kept as it was said)
      if spec is Moved(_, over, _) && over > most {
        continue
      }
      let s = spec.over(most)
      if s != spec {
        a.animate(c, to, s, start_at?, velocity=a.v0)
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
/// What comes into a list's place shows only in the room what was there has left (sf/motion.mbt rule 4, words over
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
    if e.fly is Some(_) || e.flying_placed {
      // A flying piece can be inside a moving bubble: include its ancestors' translations in its drawn position.
      let (_, _, fw, fh) = c.node_rect(e.node)
      let (fx, fy) = c.drawn_at(e.node)
      let l = c.look_of(e.node)
      flying.push((e.node, fx + l.ox * fw * (1.0 - l.sx), fy + l.oy * fh * (1.0 - l.sy), fw * l.sx, fh * l.sy))
    }
  }
  if moving.is_empty() && flying.is_empty() {
    return
  }
  for e in mo.entries {
    if e.key == 0 || e.reshape || e.whole {
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
        if mr.list != r.list || mr.scope_node != r.scope_node || me.node == e.node || mr.moving_dy.abs() <= r.moving_dy.abs() + 0.5 {
          continue
        }
        ignore(mr.oy.get(c))
        ignore(mr.hp.get(c))
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
      let (raw0, raw1) = if flying.is_empty() { (0.0, 0.0) } else { c.node_drawn_across(e.node) }
      let (node_x, _, _, _) = c.node_rect(e.node)
      let (draw_x, draw_y) = c.drawn_at(e.node)
      let (ax0, ax1) = (raw0 + draw_x - node_x, raw1 + draw_x - node_x)
      for f in flying {
        let (fnode, fx, fy, fw, fh) = f
        if fnode == e.node || fx + fw <= ax0 || fx >= ax1 || fy + fh <= draw_y || fy >= draw_y + nh {
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
        if fy + fh / 2.0 > draw_y + nh / 2.0 {
          bottom = dmin(bottom, fy - draw_y)
        } else {
          top = dmax(top, fy + fh - draw_y)
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
      // where it lies, measured_rect; its corners, measured_radii; told once all of it is written, so what is told reads
      // it as it is now)
      let resized = if made || r.w != nw || r.h != nh || !r.alive {
        Some(
          if made {
            "first"
          } else if !r.alive {
            "laid out again"
          } else {
            "\{r.w}x\{r.h} to \{nw}x\{nh}"
          },
        )
      } else {
        None
      }
      let taller = made || r.h != nh || !r.alive
      let radii = c.node_radii(e.node)
      let cornered = r.rad != radii
      let moved = r.x != nx || r.y != ny
      r.x = nx
      r.y = ny
      r.w = nw
      r.h = nh
      r.node = e.node
      r.rad = radii
      r.seen = frame
      rec_built(c, e.kept, r)
      // (what a room shows laid out: its height the room's, reveal)
      if reveal_heights.contains(e.kept) {
        reveal_heights[e.kept] = nh
      }
      match resized {
        Some(why) => {
          measure_changed(measure_size, e.kept, why)
          if taller {
            measure_changed(measure_tall, e.kept, why)
          }
        }
        None => ()
      }
      if moved {
        measure_changed(measure_at, e.kept, "moved")
      }
      if cornered {
        measure_changed(measure_radii, e.kept, "corners")
      }
    }
    if e.key != 0 {
      let li = c.list_above(e.node)
      let (anchor, scope_node, rx, ry) = if li >= 0 {
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
        (c.node_id(li), -1, nx - lx - pl, ny - ly - pt + s)
      } else {
        match scope_above(c, e.node) {
          Some(sc) => {
            let (sx, sy, _, sh) = c.node_rect(sc.node)
            let oy = if sc.scope == 2 { sy + sh } else { sy }
            (-7, sc.node, nx - sx, ny - oy)
          }
          None => (0, -1, nx, ny)
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
        r.was_ref = r.anchor
        r.was_alive = r.alive
        r.ox.step(c)
        r.oy.step(c)
        r.was_ox = r.ox.get(c)
        r.was_oy = r.oy.get(c)
        r.was_driven = r.driven
        r.was_by = r.by
        r.was_fx = r.fx
        r.was_fy = r.fy
        r.moved_now = false
        r.was_w = r.w
        r.was_h = r.h
        r.was_rad = r.rad
        r.gp.step(c)
        r.was_gp = r.gp.get(c)
        r.was_g_carry = r.g_carry
        r.was_g_carried_y = r.g_carried_y
        r.was_gx = r.gx
        r.was_gy = r.gy
        r.was_gw = r.gw
        r.was_gh = r.gh
        r.was_gr = r.gr
        r.hp.step(c)
        r.was_hp = r.hp.get(c)
        r.was_hh = r.hh
        r.g_now = false
      }
      let lm = if li >= 0 { mo.lists.get(anchor) } else { None }
      let was_seen = r.was_alive && r.was_ref == anchor
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
          // (where each went before set by hand: laid_once)
          ignore(r.ox.tells_now(c))
          ignore(r.oy.tells_now(c))
          r.ox.value = r.was_ox
          r.oy.value = r.was_oy
          // (on its way again as it was told: the same spec, its way as long as it was, not one of its own)
          let again = fn(a : Anim) { if a.spec is Snap(_) { e.spec } else { a.spec } }
          if r.was_ox == 0.0 { r.ox.snap(c, 0.0) } else { r.ox.animate(c, 0.0, again(r.ox)) }
          if r.was_oy == 0.0 { r.oy.snap(c, 0.0) } else { r.oy.animate(c, 0.0, again(r.oy)) }
        }
      }
      // gone ahead of others (list_keys' reborn): where it is now at once, come in there as a row new to it
      // (every build of the frame its list changed in: the frame's first lays it out where it was)
      let reborn = match lm {
        Some(l) => l.reborn.get(e.key) == Some(frame)
        None => false
      }
      if reborn {
        r.ox.snap(c, 0.0)
        r.oy.snap(c, 0.0)
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
        let was = (r.was_x, r.was_y, r.was_w, r.was_h)
        let (gx, gy, gw, gh) = shape_mix((r.was_gx, r.was_gy, r.was_gw, r.was_gh), was, r.was_gp)
        // (from its foot: as its ground sets off, below)
        let gy = gy + (if e.reshape && e.foot && !e.carry { foot_moved_by(was, (rx, ry, nw, nh)) } else { 0.0 })
        let ground = if e.reshape { shape_far((gx, gy, gw, gh), (rx, ry, nw, nh)) } else { 0.0 }
        way_far(dx, dy, nw - r.was_w, nh - r.was_h, ground)
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
            r.ox.snap(c, 0.0)
            r.oy.snap(c, 0.0)
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
            r.ox.snap(c, 0.0)
            r.oy.snap(c, 0.0)
          } else {
            // closing over a row gone: a little late, unless it went ahead
            let delay = match lm {
              Some(l) if c.moment() <= l.close_until && !l.lifted.contains(e.key) => 100.0
              _ => 0.0
            }
            // (how fast it went as it was set off: as it was set off before in this moment where it was built again
            // in it)
            let (vx, vy) = if r.p_set_at == c.moment() { r.p_set_v } else { (r.ox.velocity, r.oy.velocity) }
            r.p_set_v = (vx, vy)
            r.p_set_at = c.moment()
            // (set off again while it went: a Move on from that speed, as its shape's ground does, as long as how far
            // it has to go or how far its speed carries it, the further)
            // (only toward where it goes: turned back by its cause (sent words let the composer go as it grew), it sets
            // out from rest, not thrown past and turned in a frame (the user, 2026-11-09: 「发送反向时不带速度」))
            let toward = (cx + dx) * vx <= 0.0 && (cy + dy) * vy <= 0.0
            let carried = sets_out_from_rest(spec) && toward && (vx.abs() > part_moving || vy.abs() > part_moving)
            let spec = if carried {
              moved(over=carried_way(cx + dx, vx, cy + dy, vy))
            } else {
              spec.delayed(delay)
            }
            // (carried on from where it is now and how fast it goes now: from now, not from its cause's moment before)
            let start_at = if carried { Some(c.moment()) } else { None }
            r.driven = false
            r.moved_now = true
            ignore(r.ox.tells_now(c))
            r.ox.value = cx + dx
            moves_with(c, group, far, r.ox, 0.0, spec, start_at?, velocity=vx)
            ignore(r.oy.tells_now(c))
            r.oy.value = cy + dy
            moves_with(c, group, far, r.oy, 0.0, spec, start_at?, velocity=vy)
              }
        }
      }
      // grown for its cause (its words a line more), not in a list (whose rows make room for each other: makes_room):
      // what it holds is laid out as tall as it ends at once, but shows only as tall as it showed, going to as tall as
      // it is laid out with its move, so that what it has more comes out as it gets there, not drawn over what stands
      // by it that it moves away from or towards (the composer's field over its send, 2026-10-29: 「输入框变高的时候
      // 会盖住发送按钮」). Shut for its cause (laid out as nothing), cut so too (`cut`): it shows as tall as it showed,
      // going to nothing with its move, so that what it holds past its room (what goes, built till its declared end: a
      // collapsible's content as it closes) goes in under its foot as what is under it comes up, not drawn whole over
      // it. Shrunk to less with what it holds laid in it (its words a line less), shrunk with what it holds drawn whole
      // (not `cut`), or resized by nothing it moves for, it shows whole (a growth on its way going on, as far off its new height as it
      // was off its old). What comes out (or goes in) fades to the cut, each pixel by where it is (half a line out
      // shows its half, fading: 2026-10-30 「带渐隐，但不是整行渐隐」), over no more than it has gone (none as it sets off:
      // what showed is not faded then, the line that was last neither dimmed nor lit again, 「换行的时候最后两行会闪烁」)
      // and no more than it has to go (none as it ends: nothing lit or put out at once).
      r.shown_h = nh
      if e.flip && li < 0 {
        let shown = r.was_hh + (r.was_h - r.was_hh) * r.was_hp
        let caused = e.by != "" && r.was_by != "" && e.by != r.was_by
        if still || !was_seen || reborn {
          r.hp.snap(c, 1.0)
        } else if caused && (nh - r.was_h).abs() > 0.5 {
          r.hh = shown
          let goes = nh > shown + 0.5 || (e.cut && nh <= 0.5 && shown > 0.5)
          r.hp.snap(c, if goes { 0.0 } else { 1.0 })
          if goes {
            moves_with(c, group, far, r.hp, 1.0, spec)
          }
        } else if (nh - r.was_h).abs() > 0.5 {
          r.hh = r.was_hh + (nh - r.was_h)
        }
        let p = r.hp.get(c)
        if p < 1.0 {
          let h = r.hh + (nh - r.hh) * p
          r.shown_h = dmax(h, 0.0)
          if e.cut {
            // (what has come out and what is still to: growing, from as tall as it showed; shrinking, from as tall
            // as it is laid out)
            let soft = if nh >= r.hh { @ui.cut_soft(h - r.hh, nh - h) } else { @ui.cut_soft(r.hh - h, h - nh) }
            c.cut_to_top(e.node, dmax(h, 0.0), soft~)
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
                    c.moment() < at + 400.0
                  }
                  None => false
                }
              None => false
            }
          }
          if arrived {
            r.enter = Some(t)
            r.ef.snap(c, 0.0)
            r.em.snap(c, 0.0)
            r.ef.animate(c, 1.0, t.fade_spec)
            r.em.animate(c, 1.0, t.spec)
          }
        }
        _ => ()
      }
      // its ground on its way from the shape it had to the one it is laid out in, for its cause (reshape)
      if e.reshape {
        let to_r = corners_in(c.node_radii(e.node), nw, nh)
        let caused = e.by != "" && r.was_by != "" && e.by != r.was_by
        let was = (r.was_x, r.was_y, r.was_w, r.was_h)
        let laid = (rx, ry, nw, nh)
        let was_g = (r.was_gx, r.was_gy, r.was_gw, r.was_gh)
        let changed_shape = shape_changed(was, laid)
        let p0 = r.was_gp
        if still || !was_seen {
          r.gp.snap(c, 1.0)
          r.g_now = false
          r.g_carry = false
          r.g_carried_y = 0.0
        } else if caused && changed_shape {
          // from the shape it showed as the frame began (on its way, or as it was laid out)
          let wr = corners_in(r.was_rad, r.was_w, r.was_h)
          let (gx, gy, gw, gh) = shape_mix(was_g, was, p0)
          r.gx = gx
          r.gy = gy
          // A carry moves the ground to another place. If a resize interrupts it, preserve that visible position for
          // drawing while keeping the carried translation out of the room reported to what stands on the shape.
          r.g_carried_y = carried_y_from(r.was_g_carry, r.gy, r.was_y, r.was_g_carried_y, p0)
          r.gw = gw
          r.gh = gh
          // (from its foot: its foot moved this frame by what holds it there at once, its ground set off from there)
          if e.foot && !e.carry {
            let moved = foot_moved_by(was, laid)
            r.gy = r.gy + moved
            foot_moved[e.by] = (frame, moved)
          }
          r.gr = corners_mix(r.was_gr, wr, p0)
          // (as fast as its ground went on the way it was on, in this way's terms: along what changes most of it)
          let v = if r.g_set_at == c.moment() {
            r.g_set_v
          } else {
            ground_speed_carried(was_g, was, (r.gx, r.gy, r.gw, r.gh), laid, r.gp.velocity)
          }
          r.g_set_v = v
          r.g_set_at = c.moment()
          r.gp.snap(c, 0.0)
          // (its cause's moment said by what changes it, come by now: from then, it and what moves with it)
          let said_at = e.at > @double.neg_infinity && e.at <= c.moment()
          if said_at && group != "" {
            cause_at[group] = e.at
          }
          // (set off again while it went: a Move on from that speed (move_path), past its new shape a little where it
          // went toward it fast and back, not from rest on its curve, stopped dead (the user, 2026-11-09: 「冲过一点再弹回」))
          // (turned back too: on from its speed the other way, slowing on its Move's way past where it was a little, then
          // back to its new shape, not from rest, stopped dead as it turned (sizes_steady); the coordinator of the
          // migration, 2026-11-10: a composer growing a line let go of by words sent from it before it has grown)
          let spec = if sets_out_from_rest(spec) && v.abs() > reshape_moving {
            let way = ground_way(r, laid)
            moved(points=way, over=carried_way(-way, v * way, 0.0, 0.0))
          } else {
            spec
          }
          moves_with(c, group, far, r.gp, 1.0, spec, start_at?=if said_at { Some(e.at) } else { None }, velocity=v)
          r.g_now = true
          r.g_carry = e.carry
        } else {
          // what holds it moved or resized it: where it set out from as far off its new shape as it was off its old,
          // its way going on as it was (a build before this one set it off anew: back as the frame began)
          let (gx, gy, gw, gh) = shape_held(was_g, was, laid)
          r.gx = gx
          r.gy = gy
          r.g_carried_y = r.was_g_carried_y
          r.gw = gw
          r.gh = gh
          r.gr = r.was_gr
          if r.g_now {
            r.g_now = false
            // (as fast as it set off then)
            let v = r.gp.v0
            r.gp.snap(c, p0)
            if p0 < 1.0 {
              moves_with(c, group, far, r.gp, 1.0, spec, velocity=v)
            }
          }
        }
        let p = r.gp.get(c)
        if p < 1.0 {
          let (x, y, w, h) = ground_drawn_at((nx - rx, ny - ry), (r.gx, r.gy, r.gw, r.gh), laid, p)
          c.draw_ground(e.node, x, y, w, h, corners_mix(r.gr, to_r, p))
        }
      }
      r.rad = c.node_radii(e.node)
      r.x = rx
      r.y = ry
      r.by = e.by
      r.vy = vy
      r.w = nw
      r.h = nh
      r.anchor = anchor
      r.seen = frame
      rec_built(c, e.key, r)
      r.exit = e.exit
      r.list = anchor
      r.scope_node = scope_node
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
          Some((a, ar)) if ar.g_carry && ar.gp.get(c) < 1.0 => {
            r.on = a.key
            r.on_edges = carried_edges((nx, ny, nw, nh), c.node_rect(a.node))
          }
          _ => ()
        }
      }
      let (cx, cy) = match mo.recs.get(r.on) {
        Some(ar) if r.on != 0 && ar.seen == frame && ar.gp.get(c) < 1.0 => {
          let p = ar.gp.get(c)
          // (its own moves none meanwhile: where it is drawn is the ground's)
          r.ox.snap(c, 0.0)
          r.oy.snap(c, 0.0)
          r.driven = false
          carried_off((ar.gx, ar.gy, ar.gw, ar.gh), (ar.x, ar.y, ar.w, ar.h), p, r.on_edges)
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
        (r.ox.get(c), r.oy.get(c))
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
          let pf = r.ef.get(c)
          let pm = r.em.get(c)
          if pf >= 1.0 && pm >= 1.0 && !r.ef.running && !r.em.running {
            r.enter = None
          } else {
            look = look.then(t.at(pf, pm))
          }
        }
        None => ()
      }
    }
    match (match e.fly_by { Some(at) => Some(at()); None => e.fly }) {
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
/// What is kept of keyed node `key` (a place, a measure) laid out by what is built now: kept while that is built, let
/// go as it is no longer (rec_unbuilt).
fn rec_built(c : @ui.Ctx, key : Int, r : Rec) -> Unit {
  r.alive = true
  ignore(c.on_unbuilt(hash_mix(0x72656373, key), fn() { rec_unbuilt(key) }))
}

///|
/// What laid out keyed node `key` is no longer built (its page left, its row scrolled away): it is nowhere from now on
/// (measured_rect, measured_size: what reads them told), what was drawn of it let go; what is kept of it let go once it
/// is still and nothing reads how tall it was (dead_let_go).
fn rec_unbuilt(key : Int) -> Unit {
  match mo.recs.get(key) {
    Some(r) => {
      r.alive = false
      r.drawn = None
      measure_changed(measure_size, key, "not laid out")
      mo.dead.push(key)
    }
    None => ()
  }
}

///|
/// What is kept of the nodes no longer built, let go once it is still and nothing reads how tall it was (measured);
/// built again meanwhile, kept.
fn dead_let_go() -> Unit {
  if mo.dead.is_empty() {
    return
  }
  let keep : Array[Int] = []
  for k in mo.dead {
    match mo.recs.get(k) {
      Some(r) if !r.alive => {
        if r.ox.running || r.oy.running || r.gp.running || r.read {
          keep.push(k)
        } else {
          mo.recs.remove(k)
        }
      }
      _ => ()
    }
  }
  mo.dead.clear()
  mo.dead.append(keep)
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
    let pf = gh.pf.get(c)
    let pm = gh.pm.get(c)
    if pf >= 1.0 && pm >= 1.0 && !gh.pf.running && !gh.pm.running {
      done.push(gi)
      continue
    }
    // (its two Anims say their ends as they are read: frames until they are there)
    // from as it was (1) to its far end (0); not where a row of its list is drawn now: what goes gives way to what is
    // there or comes over it, never its words under theirs (sf/motion.mbt rule 4)
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
let measure_at : Map[Int, @signals.Signal[Int]] = Map([])

///|
/// What reads how big a node kept by its key is, or whether it is laid out (measured, measured_size, measured_rect: a
/// measure, a reveal's content) as it is built, told as that changes, not as it moves (a page it is on sliding in): a
/// signal by the key, made as it is first read.
// kept across runs: forgotten as a Tester starts anew (reset), each let go once nothing reads it
let measure_size : Map[Int, @signals.Signal[Int]] = Map([])

///|
/// What reads only how tall a node kept by its key is (measured), told as that changes, not as it gets wider.
// kept across runs: forgotten as a Tester starts anew (reset), each let go once nothing reads it
let measure_tall : Map[Int, @signals.Signal[Int]] = Map([])

///|
/// What reads the resolved corners of a measured node, independently of its position and size.
// kept across runs: forgotten as a Tester starts anew (reset), each let go once nothing reads it
let measure_radii : Map[Int, @signals.Signal[Int]] = Map([])

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
  // (as a layout's motions are worked out: told once it is done, if it came out otherwise: measures_told_once)
  match measures_held.val {
    Some(held) => {
      if !held.iter().any(fn(h) { physical_equal(h.0, said) && h.1 == key }) {
        held.push((said, key, why))
      }
      return
    }
    None => ()
  }
  match said.get(key) {
    Some(s) => {
      if @ui.perf_counting() && s.watched() {
        measure_count(key, why)
      }
      s.set(s.untracked() + 1)
    }
    None => ()
  }
}

///|
/// While a layout's measures are taken (measures_told_once): each told and why, told once it is done.
// kept across runs: set and let go within one layout
let measures_held : Ref[Array[(Map[Int, @signals.Signal[Int]], Int, String)]?] = Ref(None)

///|
/// What of kept `r` the readers of measure `said` read (measured_size: its size and whether what lays it out is built;
/// measured_rect's place: where it lies; measured_radii: its corners), as measure_changed tells them.
fn measured_as(
  said : Map[Int, @signals.Signal[Int]],
  r : (Double, Double, Double, Double, (Double, Double, Double, Double), Bool)?,
) -> (Double, Double, (Double, Double, Double, Double), Bool)? {
  r.map(fn(r) {
    let (x, y, w, h, rad, seen) = r
    if physical_equal(said, measure_at) {
      (x, y, (0.0, 0.0, 0.0, 0.0), true)
    } else if physical_equal(said, measure_radii) {
      (0.0, 0.0, rad, true)
    } else {
      (w, h, (0.0, 0.0, 0.0, 0.0), seen)
    }
  })
}

///|
/// Kept `r`'s place, size, corners and whether what lays it out is built.
fn measured_now(r : Rec?) -> (Double, Double, Double, Double, (Double, Double, Double, Double), Bool)? {
  r.map(fn(r) { (r.x, r.y, r.w, r.h, r.rad, r.alive) })
}

///|
/// `f`, the measures it tells told only once it is done, each whose kept came out otherwise than before it: a build of
/// the frame again lays it out as the first did, and two nodes measured by one key (two pages' alike) each told in it.
fn measures_told_once(c : @ui.Ctx, f : () -> Unit) -> Unit {
  let was : Map[Int, (Double, Double, Double, Double, (Double, Double, Double, Double), Bool)] = Map([])
  mo.recs.each(fn(k, r) { was[k] = measured_now(Some(r)).unwrap() })
  let held = []
  let outer = measures_held.val
  measures_held.val = Some(held)
  f()
  measures_held.val = outer
  for h in held {
    let (said, key, why) = h
    if measured_as(said, measured_now(mo.recs.get(key))) != measured_as(said, was.get(key)) {
      measure_changed(said, key, why)
      // A height read during this build must be reflected in the same frame that lays out its new height.
      if physical_equal(said, measure_tall) {
        match said.get(key) {
          Some(signal) if signal.watched() => c.built_from_changed("measured height changed")
          _ => ()
        }
      }
    }
  }
}

///|
/// The keys of the measures read while the frame probe counts (@ui.perf_counting), by their hash.
// kept across runs: the performance record's, read by nothing else
let measure_names : Map[Int, String] = Map([])

///|
/// How often each measure read told what read it since the record last asked, by its key and why.
// kept across runs: the performance record's, read by nothing else
let measure_told : Map[String, Int] = Map([])

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
  let out = StringBuilder()
  for i, e in all {
    if i >= 6 {
      break
    }
    out.write_string((if i == 0 { " " } else { " | " }) + "\{e.1} \{e.0}")
  }
  out.to_string()
}

///|
/// A build is laid out: the measures nothing reads let go (what laid one out no longer built tells its readers itself:
/// rec_unbuilt).
fn measures_unread() -> Unit {
  let unread : Array[Int] = []
  measure_at.each(fn(k, s) { if !s.watched() { unread.push(k) } })
  for k in unread {
    measure_at.remove(k)
  }
  unread.clear()
  measure_radii.each(fn(k, s) { if !s.watched() { unread.push(k) } })
  for k in unread {
    measure_radii.remove(k)
  }
  unread.clear()
  measure_tall.each(fn(k, s) { if !s.watched() { unread.push(k) } })
  for k in unread {
    measure_tall.remove(k)
  }
  unread.clear()
  measure_size.each(fn(k, s) { if !s.watched() { unread.push(k) } })
  for k in unread {
    measure_size.remove(k)
  }
}
