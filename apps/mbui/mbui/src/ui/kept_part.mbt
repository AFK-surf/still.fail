// A part kept as it was drawn while nothing it shows can have changed (Ctx::kept_part): what the view builds is built
// every frame, but a part the hand is not on (still.fail's panels: one behind the one in use on the tape, and the one
// in use between what the hand does in it) changes only by what comes from outside the hand on another part: the
// core's data, a timer, the system, a press or a key; its size and its ground; or time, where what it shows changes
// with it (a motion, a cycle, a clock). A frame with none of those (a list elsewhere scrolled, by a finger or a wheel,
// flung on; a mark's step, a look by the clock; what holds it moved, a page sliding out) draws it again from what its
// last build drew, not built, laid out nor painted anew: its instances as they were, moved with its box to where that
// is laid out now. Its build is recorded in its band (the clip it is drawn in, as far past it every way as that is wide
// and tall), unclipped by what is round it, and put in the clip it is drawn in, built or drawn again alike, as a list's
// row is (kept_rows.mbt): what is drawn again moved is what building it there draws, so long as what shows of it there
// was in its band, and it moved by whole device pixels (else it is built there). (Zed's GPUI keeps a view so,
// `AnyView::cached`: its last frame's paint replayed while it was not notified and its bounds are the same; Flutter's
// RepaintBoundary keeps a layer's picture drawn wherever its offset puts it.) One in use is read out (`read_out`:
// what it said to what reads the widgets said again, as a list's row's is), built once more the frame after an event
// came to it (what its handler set after what reads it was built), and built each frame while it holds what is built
// each frame wherever it is (a native view, the field that takes the keys).
//
// What it read of the core and of what was worked out of it (mbui/signals) is followed as it is built: a computed of
// its own runs its build, so a topic it read changed builds it again whatever else said, and what it read stays kept
// while it shows (what follows a computed keeps it). What it reads of time is read so too (KeptClock): the frame, where
// what it shows changes each frame (a motion going on read where it is now, a cycle drawn each frame, a layer it
// opened), and the moment what it shows changes at (a clock's step, a timer's end), whoever told the motion or the
// timer and wherever it was told (a look by the clock is not read: what it draws carries it, cycle_look.mbt); what the
// rows of a list in it read as they are laid out, after its build, is read by it too (kept_rows.mbt), and what moves
// what it laid out, read once the frame is laid out (the motion package's moves and reshapes, Ctx::reads_for): a
// dependence is said where it is read, never by who told a motion or when. What is not a signal is caught by what
// changes it: an event from outside (outside_events: what the host or the runtime did, not a pointer moved nor a wheel
// turned elsewhere), its `key` (what it is built from by its caller), the layout's epoch, a press held down on it or a
// wheel turned over it (what it holds may take them), the mouse's pointer over it (it lights what it points at). It is
// built the first frame it shows. Drawn again, what its build and its paint said of
// the frame is said again, moved with it, all of it by one rule (said.mbt): what takes the focus, the pointer's shape,
// what asks for a menu, what is told outside, its targets, what scrolls in it, the words that can be picked, its scroll
// bars, so keys, presses, the wheel and the pointer find in it what they found as it was built; and what the rows of
// its lists said, where they said it. It is never read out, built or not, so what is read out does not come and go with
// it.

///|
/// A part kept (Ctx::kept_part): what its build drew (its instances, where they were; the pieces of its shapes; the
/// glyphs' plots and the pictures they draw from), the computed its build runs in, and what it was built from.
priv struct KeptPart {
  id : Int
  /// its build's instances (the first `floats` numbers), the pieces of their shapes
  mut insts : FixedArray[Double]
  mut floats : Int
  segs : Array[Double]
  /// the atlases' plots its glyphs are drawn from (colour ones by part_colour_plot), the pictures it shows
  plots : Array[Int]
  plot_seen : Map[Int, Bool]
  images : Array[ImageEntry]
  /// the looks by the clock its instances are tagged with, by tag (cycle_look.mbt): drawn again, they go on
  cycles : Map[Int, CycleLook]
  /// read out (Ctx::kept_part's `read_out`: a panel in use): what its build said to what reads the widgets (relative
  /// to its box, as a row's: RowKept's `sems`), said again as it is drawn again; whether its last build was read out
  read : Bool
  sems : Array[SemNode]
  mut read_out : Bool
  /// its last build drew what is built each frame wherever it is: a native view's hole (put where it is each frame:
  /// native.mbt), the field that takes the keys (the keyboard's place, what it composes: sync_ime)
  mut holds_live : Bool
  /// its last build was for an event from outside: read out (in use: it takes the hand), it is built once more, for
  /// what read the event late in that frame (a state its handler set after what reads it was built), as the frame
  /// after an input is (inputrec.mbt)
  mut came_built : Bool
  /// its build, run by `tracker` as what it read changes or it is invalidated (what is no signal changed); the build
  /// now, and what the tracker answered as it last ran it
  tracker : @signals.Computed[Int]
  body : Ref[() -> Unit]
  /// what its build said of the frame (said.mbt's build lists), said again as it is drawn again; where each of them
  /// stood as it began
  built_marks : Array[Int]
  built_said : Array[&SaidAgain]
  /// a part's: the rows of its lists that said what their builds said where its lists' rows say theirs, in the order
  /// they said it (Ctx::row_build_said), as it was last shown: drawn again, it says theirs again where its box is laid
  /// out
  rows_said : Array[Int]
  mut stamp : Int
  /// what it was built from: its caller's key, the events from outside seen, the layout's epoch, the scale, the hand
  mut key : String
  mut outside : Int
  mut epoch : Int
  mut scale : Double
  mut pointing : Pointing
  /// the frame it was built in (-1: not yet), the frame its build was drawn in (painted, its instances taken), the
  /// frame it last showed in
  mut built : Int
  mut drawn : Int
  mut shown : Int
  /// drawn again this frame (not built)
  mut again : Bool
  /// a Tester's: the words its build drew (KeptWord), what the Tester finds in it while it is drawn again
  words : Array[KeptWord]
  /// what it drew covers as it was last drawn (x, y, w, h: its instances where they show): a press held or a wheel
  /// turned there is its; the mouse's pointer there lights what is in it
  mut rect : (Double, Double, Double, Double)
  /// where its box was laid out as its build was painted (x, y); what of it that recorded (its band: left, top, right,
  /// bottom, Ctx::part_paint_begin), and whether what it left nothing of where it was drawn was dropped (kept_drop); how
  /// far from there its box is as it is last drawn again (across, down)
  mut at : (Double, Double)
  mut band : (Double, Double, Double, Double)
  mut drops : Bool
  mut moved : (Double, Double)
  /// what its paint read of what floats over its scroll bars from outside it (Ctx::floated): each bar's rect, from its
  /// box's corner, and what of its top and its foot that took; read again where it is drawn again (Ctx::parts_placed)
  floats_read : Array[(Double, Double, Double, Double, Double, Double)]
  floats_was : Array[(Double, Double, Double, Double, Double, Double)]
  /// its box was moved where it could not be drawn again, or what floats over it from outside moved (Ctx::parts_placed):
  /// built, from its frame's first build, while they go on moving (each frame laid out elsewhere than the one before),
  /// not drawn again and then built again
  mut shifted : Bool
  /// what its build's paint said of the frame (said.mbt), said again as it is drawn again; where each of the frame's
  /// paint lists stood as it began
  said : Array[&SaidAgain]
  marks : Array[Int]
  /// of what its paint said, what the hand is found on: its targets' ids (what the pointer is over among them lights
  /// it), what scrolls in it (ids, rects as painted: a wheel turned there is its)
  hit_ids : Array[Int]
  scroll_ids : Array[Int]
  scroll_rects : Array[Double]
  /// whether what the pointer is over was one of its targets as it was built (Ctx::hovered: it lights what it points
  /// at)
  mut lit : Bool
  /// a list's row kept (kept_rows.mbt): what more it keeps; None a part's
  mut row : RowKept?
  /// what its build read of the layout (readback.mbt), kept for it while it is drawn again (KeptReads)
  reads : KeptReads
}

///|
/// What a part's or a row's build read of the layout (Ctx::laid_rect, laid_size, shown_across, left_out), by the box's
/// id, and how its build's frame laid that out: while it is drawn again (its build not run, its boxes not laid out), the
/// layout keeps them as they were, a row's moved with it, so that its next build reads what its last read, not a box
/// let go of (none: laid out by a guess, then again once read back, the frame between drawn from the guess).
priv struct KeptReads {
  laid : Map[Int, (Double, Double, Double, Double)?]
  shown : Map[Int, (String, (Double, Double)?)]
  left : Map[Int, Bool]
}

///|
fn KeptReads::clear(self : KeptReads) -> Unit {
  self.laid.clear()
  self.shown.clear()
  self.left.clear()
}

///|
/// Words a part kept drew as it was built, as a Tester finds words (Tester::find, rect_of, words): the node's words,
/// where it is laid out (x, y, w, h), where it is drawn and how opaque.
priv struct KeptWord {
  text : String
  x : Double
  y : Double
  w : Double
  h : Double
  drawn_x : Double
  drawn_y : Double
  alpha : Double
}

///|
/// The part being built now (0 none); the part whose build is being painted (0 none); the same of a list's row kept
/// (kept_rows.mbt: its id among the rows').
priv struct PartNow {
  mut part : Int
  mut painting : Int
  mut row : Int
  mut painting_row : Int
  /// the box node of the part whose build is being painted (-1 none)
  mut painting_node : Int
}

///|
// kept across runs: set round each part's build and paint and put back after it
let part_now : PartNow = {
  part: 0,
  painting: 0,
  row: 0,
  painting_row: 0,
  painting_node: -1,
}

///|
/// The parts kept, by id, and the run (its Ctx) they are kept in.
// kept across runs: let go of as another run's first frame begins (parts_frame_start)
let kept_parts : Map[Int, KeptPart] = {}

///|
priv struct PartsRun {
  mut ctx : Ctx?
  /// the runtime's steps as the last frame began (an event of its own since then is one from outside)
  mut steps : Int
}

///|
// kept across runs: the run it holds is compared with the frame's as each frame begins (parts_frame_start)
let parts_run : PartsRun = { ctx: None, steps: -1 }

///|
/// How many events have come from outside the hand on another part (kept_part.mbt's head): an input other than a pointer
/// moved or a wheel turned, a message, a host's answer, a step of the runtime's fibers or timers, a test's draw.
// kept across runs: it only counts on
let outside_events : Ref[Int] = Ref(0)

///|
/// An event from outside came (kept_part.mbt's head): every part kept is built anew by the next frame.
fn outside_came() -> Unit {
  outside_events.val = outside_events.val + 1
  // (and what each frame's build reads of it: frame_watch.mbt)
  outside_counted()
}

///|
/// A list's rows laid on the device's pixels as a host lays them (Ctx::rows_on_grid), from now on, or not (as every
/// frame of a Tester's was always laid out).
pub fn Tester::keep_parts(self : Tester, on : Bool) -> Unit {
  ignore(self)
  // (how frames are built changed by the test, a list's rows set on the pixels with it: the next built whole)
  if rows_grid_test.val != on {
    test_stepped()
  }
  rows_grid_test.val = on
}

///|
/// Whether (x, y) is on a part kept, as the last frame drew it: a wheel turned there is the part's, an event from
/// outside for it (it scrolls in its build).
fn part_under(x : Double, y : Double) -> Bool {
  let frame = g().frame_no
  for _, st in kept_parts {
    let (px, py, pw, ph) = st.rect
    if st.shown == frame && x >= px && x < px + pw && y >= py && y < py + ph {
      return true
    }
  }
  false
}

///|
/// A frame begins: the parts of another run forgotten; the runtime's steps since the last frame an event from outside.
fn parts_frame_start(c : Ctx) -> Unit {
  match parts_run.ctx {
    Some(was) if physical_equal(was, c) => ()
    _ => {
      parts_forget()
      parts_run.ctx = Some(c)
    }
  }
  let steps = fx.val.steps
  if steps != parts_run.steps {
    parts_run.steps = steps
    outside_came()
  }
}

///|
/// The frame is built: the parts and the rows that did not show in it let go (what they read no longer kept by them);
/// the moments those that did read are waited for.
fn parts_frame_end(c : Ctx) -> Unit {
  parts_gone(c)
  rows_frame_end(c)
  rows_nodes_end(c)
  clock_frame_end(c)
}

///|
/// The parts that did not show in this frame let go (what they read no longer kept by them).
fn parts_gone(c : Ctx) -> Unit {
  if kept_parts.is_empty() {
    return
  }
  let gone = []
  for id, st in kept_parts {
    if st.shown != c.frame_no {
      gone.push(id)
    }
  }
  for id in gone {
    match kept_parts.get(id) {
      Some(st) => st.tracker.dispose()
      None => ()
    }
    kept_parts.remove(id) |> ignore
  }
}

///|
fn parts_forget() -> Unit {
  for _, st in kept_parts {
    st.tracker.dispose()
  }
  kept_parts.clear()
  for _, st in kept_rows {
    st.tracker.dispose()
  }
  kept_rows.clear()
  row_ids.clear()
  kept_clock.dues.clear()
  part_now.part = 0
  part_now.painting = 0
  part_now.row = 0
  part_now.painting_row = 0
  part_now.painting_node = -1
}

///|
/// What `body` builds, in a box of its own filling the one being built (out of the flow: the one being built laid out
/// as if it held nothing else), not read out, and kept: built again only once something it shows can have changed
/// (kept_part.mbt's head), else drawn again as its last build drew it where its box is now, nothing of it built. `id`
/// names it; `key` is what its caller builds it from besides what it reads (its size, its ground: what else changes it;
/// not where it is, which moves what it drew with it), another key building it anew. Not read out, for a part nobody uses where it is (a panel behind the one in use); `read_out`,
/// read out as its build said it, built or drawn again (a panel in use: what reads the widgets reads it as a list's
/// row kept, semantics.mbt), built each frame while it holds what is built each frame wherever it is (a native view, the
/// field that takes the keys).
pub fn Ctx::kept_part(self : Ctx, id : Int, key : String, body : () -> Unit, read_out? : Bool = false) -> Unit {
  // kept as its nodes, under a watch of its own (kept_nodes.mbt)
  self.part_nodes(id, key, body, read_out)
}

///|
/// A part kept, not built yet: its build run by a computed of its own (`body` as it is set, again as what it read
/// changes or it is invalidated).
fn kept_new(id : Int, row~ : Bool) -> KeptPart {
  let body_now : Ref[() -> Unit] = Ref(fn() {  })
  let reads : KeptReads = { laid: {}, shown: {}, left: {} }
  let (built_marks, built_said) : (Array[Int], Array[&SaidAgain]) = ([], [])
  {
    id,
    insts: FixedArray::make(0, 0.0),
    floats: 0,
    segs: [],
    plots: [],
    plot_seen: {},
    images: [],
    cycles: {},
    read: false,
    sems: [],
    read_out: false,
    holds_live: false,
    came_built: false,
    tracker: @signals.computed(fn(_) {
      let c = g()
      let (layers, back) = (c.layers.length(), c.back_next)
      reads.clear()
      // (what it says of the frame as it is built taken, to be said again as it is drawn again; a row's said where
      // its list's rows say theirs, in their order: Ctx::rows_placed)
      c.build_marks(built_marks)
      (body_now.val)()
      c.build_take(built_marks, built_said, cut=row)
      // (a layer it opened, back it took: laid over the window and taken anew each frame, apart from what it draws)
      if c.layers.length() != layers || !physical_equal(c.back_next, back) {
        part_live()
      }
      part_stamp.val = part_stamp.val + 1
      part_stamp.val
    }),
    body: body_now,
    built_marks,
    built_said,
    rows_said: [],
    stamp: 0,
    key: "",
    outside: -1,
    epoch: -1,
    scale: 0.0,
    pointing: Finger,
    built: -1,
    drawn: -1,
    shown: -1,
    again: false,
    words: [],
    rect: (0.0, 0.0, 0.0, 0.0),
    at: (0.0, 0.0),
    band: (0.0, 0.0, 0.0, 0.0),
    drops: false,
    moved: (0.0, 0.0),
    floats_read: [],
    floats_was: [],
    shifted: false,
    said: [],
    marks: [],
    hit_ids: [],
    scroll_ids: [],
    scroll_rects: [],
    lit: false,
    row: None,
    reads,
  }
}

///|
/// The tracker's answers, one more each time a part's build runs.
// kept across runs: it only counts on
let part_stamp : Ref[Int] = Ref(0)

///|
/// Plots of the colour atlas, as a part keeps them (KeptPart.plots): past those of the other.
let part_colour_plot : Int = 1 << 20

///|
/// How many parts the last frame kept as their nodes (Ctx::kept_part, kept_nodes.mbt), not built.
pub fn Tester::parts_kept(self : Tester) -> Int {
  ignore(self)
  nodes_run.kept_at.iter().filter(fn(k) { k.1 < 0 }).count()
}

///|
/// Whether part `id` was drawn again this frame, as its last build drew it, not built.
pub fn Ctx::part_kept(self : Ctx, id : Int) -> Bool {
  ignore(self)
  match kept_parts.get(id) {
    Some(st) => st.shown == self.frame_no && st.again
    None => false
  }
}

///|
/// What `build` (a row of a list in part `part`, built as the list is laid out, after the part's own build) reads, read
/// by the part (0: no part's) as though its build had read it.
fn part_rows(part : Int, build : () -> Unit) -> Unit {
  if part == 0 || part_now.part == part {
    build()
    return
  }
  match kept_parts.get(part) {
    Some(st) => {
      let was = part_now.part
      part_now.part = part
      st.tracker.reading(build)
      part_now.part = was
    }
    None => build()
  }
}

///|
/// What `f` reads, read by the list's row kept `row` (0: none) and the part kept `part` (0: none) it is drawn in, as
/// though their builds had read it (Ctx::reads_for): the row's lent to the part, as what its build reads is
/// (kept_rows.mbt's row_of).
fn read_for(part : Int, row : Int, f : () -> Unit) -> Unit {
  let (was_part, was_row) = (part_now.part, part_now.row)
  part_now.part = part
  part_now.row = row
  match (kept_rows.get(row), kept_parts.get(part)) {
    (Some(rp), p) if row != 0 => {
      rp.tracker.reading(f)
      match p {
        Some(st) if part != 0 => rp.tracker.lend(st.tracker)
        _ => ()
      }
    }
    (_, Some(st)) if part != 0 => st.tracker.reading(f)
    _ => f()
  }
  part_now.part = was_part
  part_now.row = was_row
}

///|
/// What is being built now that is kept as it was built (a part, or a list's row: kept_rows.mbt, in a part or not) and
/// reads what is built in it after it ran, laid out later: its computed (None: none is).
fn part_holder() -> @signals.Computed[Int]? {
  if part_now.row != 0 {
    match kept_rows.get(part_now.row) {
      Some(st) => return Some(st.tracker)
      None => ()
    }
  }
  if part_now.part != 0 {
    match kept_parts.get(part_now.part) {
      Some(st) => return Some(st.tracker)
      None => ()
    }
  }
  None
}

///|
/// Whether what is built now is kept as it was built: a part's build, or a list's row's (kept_rows.mbt), a row on its own
/// as much as one in a part (on 小屏 a chat's messages are in none): what it reads of time is followed.
fn part_building() -> Bool {
  part_now.part != 0 || part_now.row != 0 || nodes_run.building is Some(_)
}

///|
/// What a build reads of time, as signals (kept_part.mbt's head): the frame, set as each begins (what shows what
/// changes each frame reads it: a motion going on, a cycle drawn each frame, a frame owed), and the moments what is
/// shown changes at (a clock's step, a timer's end, a motion's), each set as the first frame at or past it begins, in
/// order, with whether what is shown waits for it (`later`: none of those that read it does).
priv struct KeptClock {
  frame : @signals.Signal[Int]
  dues : Array[KeptDue]
}

///|
priv struct KeptDue {
  at : Double
  mut later : Bool
  come : @signals.Signal[Bool]
}

///|
// kept across runs: its frame only counts on; its moments let go as they come and with the parts (parts_forget)
let kept_clock : KeptClock = { frame: @signals.signal(0), dues: [] }

///|
/// What is painted now changes each frame (an image fading in, read as it is painted): the part or the list's row kept
/// whose build is being painted is built again each frame, as were it read as built.
fn painted_live() -> Unit {
  if part_now.painting != 0 || part_now.painting_row != 0 {
    read_for(part_now.painting, part_now.painting_row, fn() { part_live() })
  }
}

///|
/// What is built now shows what changes each frame (as what it holds moves): built again each frame, kept or not.
fn part_live() -> Unit {
  if part_building() {
    kept_clock.frame.get() |> ignore
  }
}

///|
/// What is built now changes at `t` (`later`: what is shown does not wait for it): built again in the first frame at
/// or past it, kept or not; one past already, the next frame's.
fn part_wake(now : Double, t : Double, later : Bool) -> Unit {
  if !part_building() || t == @double.infinity {
    return
  }
  if t <= now {
    kept_clock.frame.get() |> ignore
    return
  }
  let dues = kept_clock.dues
  let mut i = 0
  while i < dues.length() && dues[i].at < t {
    i = i + 1
  }
  let d = if i < dues.length() && dues[i].at == t {
    dues[i]
  } else {
    let d = { at: t, later: true, come: @signals.signal(false) }
    dues.insert(i, d)
    d
  }
  d.later = d.later && later
  d.come.get() |> ignore
}

///|
/// What is being built shows where `who`'s motion is now (an Anim, a Value, a spring: read so as they are read): built
/// again as it is told anew, wherever and whenever that is, and each frame while it goes (`going`); kept as it was drawn
/// or not (a part's, a list's row's: kept_part.mbt's head).
pub fn Ctx::shows_motion(self : Ctx, who : Mover, going : Bool) -> Unit {
  ignore(self)
  // (going, what reads it reads the clock: built again each frame, frame_watch.mbt)
  if going {
    clock_read_here()
  }
  if !part_building() {
    return
  }
  let said = match who.said {
    Some(s) => s
    None => {
      let s = @signals.signal(who.told)
      who.said = Some(s)
      s
    }
  }
  said.get() |> ignore
  if going {
    kept_clock.frame.get() |> ignore
  }
}

///|
/// What is being built changes at `t` (the frames' clock: a motion's declared end, read as whether it is over): built
/// again in the first frame at or past it (painted again, where it is read as it is painted: frame_watch.mbt), kept as
/// it was drawn or not.
pub fn Ctx::shows_until(self : Ctx, t : Double) -> Unit {
  if t > self.clock && t < @double.infinity {
    self.wake_at_time(t, later=true)
  } else {
    part_wake(self.clock, t, true)
  }
}

///|
/// A frame begins (frame_drawn, before what it does again is decided): what read the frame told it changed, and what
/// read a moment come.
fn clock_frame_start(t : Double) -> Unit {
  @signals.start_batch()
  kept_clock.frame.set(@signals.untracked(fn() { kept_clock.frame.get() }) + 1)
  let dues = kept_clock.dues
  let mut n = 0
  while n < dues.length() && dues[n].at <= t {
    dues[n].come.set(true)
    n = n + 1
  }
  if n > 0 {
    let left = dues.length() - n
    for k in 0..<left {
      dues[k] = dues[k + n]
    }
    dues.truncate(left)
  }
  @signals.end_batch()
}

///|
/// The frame is built (parts_frame_end): the moments a part or a row kept that showed reads are the host's wakes (one
/// drawn again asks none itself, its build not run); those nothing reads let go. Not the frame's own: what reads one
/// is built again as it comes, by what read it (its watch, told by clock_frame_start), not the frame anew.
fn clock_frame_end(c : Ctx) -> Unit {
  kept_clock.dues.retain(fn(d) { d.come.watched() })
  dues_wake(c)
}

///|
/// The moments a part or a row kept waits for asked of the host: the soonest is the frame's wake, where it is sooner
/// (a frame drawn from the last build's tree too: frame_watch.mbt).
fn dues_wake(c : Ctx) -> Unit {
  for d in kept_clock.dues {
    if d.at > c.clock {
      if c.wake_at < 0.0 || d.at < c.wake_at {
        c.wake_at = d.at
      }
      if !d.later && (c.wake_waited < 0.0 || d.at < c.wake_waited) {
        c.wake_waited = d.at
      }
    }
  }
}

///|
/// Picture `e` drawn, as a part's build is painted.
fn part_image(e : ImageEntry) -> Unit {
  // (a row's in a part's: both's)
  if part_now.painting != 0 {
    match kept_parts.get(part_now.painting) {
      Some(st) => st.image_used(e)
      None => ()
    }
  }
  if part_now.painting_row != 0 {
    match kept_rows.get(part_now.painting_row) {
      Some(st) => st.image_used(e)
      None => ()
    }
  }
}

///|
fn KeptPart::image_used(self : KeptPart, e : ImageEntry) -> Unit {
  for x in self.images {
    if physical_equal(x, e) {
      return
    }
  }
  self.images.push(e)
}

///|
/// A glyph drawn from `plot` of the colour atlas or the other, as a part's build is painted.
fn part_plot(colour : Bool, plot : Int) -> Unit {
  let p = if colour { plot + part_colour_plot } else { plot }
  // (a row's in a part's: both's)
  if part_now.painting != 0 {
    match kept_parts.get(part_now.painting) {
      Some(st) => st.plot_used(p)
      None => ()
    }
  }
  if part_now.painting_row != 0 {
    match kept_rows.get(part_now.painting_row) {
      Some(st) => st.plot_used(p)
      None => ()
    }
  }
}

///|
fn KeptPart::plot_used(self : KeptPart, p : Int) -> Unit {
  if !self.plot_seen.contains(p) {
    self.plot_seen[p] = true
    self.plots.push(p)
  }
}

///|
/// A part's build being painted (Ctx::part_paint_begin): the part painted before it (one it is in), and, where it is
/// recorded in its band, the clip it is put in (-1: painted plainly), where the frame's shapes' pieces stood, and how
/// many of what is put off to be drawn over everything (Ctx::kept_clip_into's `drops`).
priv struct PartPainting {
  was : Int
  was_node : Int
  cut : Int
  segs : Int
  over : Int
}

///|
/// Part `id`'s build about to be painted: its plots taken anew as its glyphs are drawn; where the frame's paint lists
/// stand; where its drawing may be kept (rows_on), its band pushed: a clip of its own, the one it is in's rect as far
/// past it every way as that is wide and tall, nothing of that one's corners nor any outer (as a list's row's is
/// recorded unclipped by its list: kept_rows.mbt), so that what it draws is what it would draw wherever its box is, and
/// it is drawn again moved (a page sliding wholly out of the window) as building it there draws it.
fn Ctx::part_paint_begin(self : Ctx, id : Int, node : Int) -> PartPainting {
  let was = part_now.painting
  let was_node = part_now.painting_node
  let cut = clip_top()
  let mut band = false
  match kept_parts.get(id) {
    Some(st) => {
      st.plots.clear()
      st.plot_seen.clear()
      st.images.clear()
      st.floats_was.clear()
      st.floats_was.append(st.floats_read)
      st.floats_read.clear()
      part_now.painting_node = node
      self.paint_marks(st.marks)
      if self.rows_on() {
        let s = clip_stack
        let (x0, y0, x1, y1) = (s[cut], s[cut + 1], s[cut + 2], s[cut + 3])
        let (w, h) = (x1 - x0, y1 - y0)
        st.band = (x0 - w, y0 - h, x1 + w, y1 + h)
        for v in [x0 - w, y0 - h, x1 + w, y1 + h] {
          clip_stack.push(v)
        }
        for _ in 0..<20 {
          clip_stack.push(0.0)
        }
        kept_cuts.push(cut)
        band = true
      }
    }
    None => ()
  }
  part_now.painting = id
  {
    was,
    was_node,
    cut: if band { cut } else { -1 },
    segs: self.segs.length(),
    over: dr.tops.length() + dr.overlay.length() + dr.raised.length(),
  }
}

///|
/// Part `id`'s build painted (its box node `node`), instances `i0` to the frame's last so far: kept as they are, with
/// the pieces of their shapes, where its box is, and what its paint said of the frame (said.mbt); recorded in its band,
/// put in the clip it is in, what it said too, as it is put there drawn again (Ctx::part_paint_again).
fn Ctx::part_paint_end(self : Ctx, id : Int, node : Int, i0 : Int, p : PartPainting) -> Unit {
  part_now.painting = p.was
  part_now.painting_node = p.was_node
  match kept_parts.get(id) {
    Some(st) => {
      if p.cut >= 0 {
        pop_clip()
        kept_cuts.pop() |> ignore
      }
      self.take_found(st)
      self.paint_take(st.marks, st.said)
      st.lit = self.part_lit(st)
      st.take_insts(self, i0)
      let n = self.nodes[node]
      // (built for a move it could not be drawn again by: so while its box, or what floats over it from outside, goes
      // on moving)
      if st.shifted &&
        (
          st.drawn != self.frame_no - 1 ||
          (n.x == st.at.0 && n.y == st.at.1 && st.floats_read == st.floats_was)
        ) {
        st.shifted = false
      }
      st.drawn = self.frame_no
      // (what is built each frame wherever it is: a native view's hole; the field that takes the keys)
      st.holds_live = st.holds_native() ||
        (self.focus != 0 && self.editors.contains(self.focus) && st.hit_ids.contains(self.focus))
      // (a Tester's: its words, found while it is drawn again)
      st.words.clear()
      if fake.val is Some(_) {
        st.words.append(self.part_words(node))
      }
      st.at = (n.x, n.y)
      st.moved = (0.0, 0.0)
      if p.cut >= 0 {
        self.paint_cut(st.marks)
        self.say_again(st.said, st.moved_by(0.0, 0.0, p.cut))
        st.drops = dr.tops.length() + dr.overlay.length() + dr.raised.length() == p.over
        self.kept_clip_into(p.cut, i0, p.segs, drops=st.drops)
      }
      st.rect = insts_cover(self.inst, i0, self.ninst)
    }
    None => ()
  }
}

///|
/// Where what part `self`'s paint said is said again: `dx` across and `dy` down from where it was said, in the clip at
/// `k` (the one it is drawn in), what of a clip was its band's left as far off as nothing cuts (said.mbt's Moved).
fn KeptPart::moved_by(self : KeptPart, dx : Double, dy : Double, k : Int) -> Moved {
  let (l, t, r, b) = self.band
  { dx, dy, cut: k, band_l: l, band_t: t, band_r: r, band_b: b, node: -1, by: 0 }
}

///|
/// Of what part `st`'s paint said from where it began (its marks), what the hand is found on: its targets' ids, what
/// scrolls in it, as painted.
fn Ctx::take_found(self : Ctx, st : KeptPart) -> Unit {
  let h0 = st.marks[said_hits]
  let s0 = st.marks[said_scrolls]
  st.hit_ids.clear()
  for h in h0..<self.next_hit_ids.length() {
    st.hit_ids.push(self.next_hit_ids[h])
  }
  st.scroll_ids.clear()
  st.scroll_rects.clear()
  for j in s0..<self.next_scroll_ids.length() {
    st.scroll_ids.push(self.next_scroll_ids[j])
  }
  for v in (s0 * 4)..<self.next_scroll_rects.length() {
    st.scroll_rects.push(self.next_scroll_rects[v])
  }
}

///|
/// `id`, the target said last (Ctx::push_hit), is only pointed at (Ctx::box `points`), said as it is painted.
fn Ctx::point_said(self : Ctx, id : Int) -> Unit {
  self.next_points[id] = true
  self.next_point_hits.push(self.next_hit_ids.length() - 1)
}

///|
/// Whether what the pointer is over (Ctx::hovered) is one of part `st`'s targets, as its paint said them.
fn Ctx::part_lit(self : Ctx, st : KeptPart) -> Bool {
  if self.hover == 0 && self.hover_in.is_empty() {
    return false
  }
  for id in st.hit_ids {
    if id == self.hover || self.hover_in.contains(id) {
      return true
    }
  }
  false
}

///|
/// The frame's instances from `i0` to its last so far taken as part `self`'s drawing, as they are, where they are, with
/// the pieces of their shapes and the looks by the clock they are tagged with.
fn KeptPart::take_insts(self : KeptPart, c : Ctx, i0 : Int) -> Unit {
  let st = self
  let a = c.inst
  let floats = (c.ninst - i0) * inst_size
  if st.insts.length() < floats {
    st.insts = FixedArray::make(floats, 0.0)
  }
  a.blit_to(st.insts, len=floats, src_offset=i0 * inst_size)
  st.floats = floats
  st.segs.clear()
  st.cycles.clear()
  let d = st.insts
  let mut q = 0
  while q < floats {
    if d[q + 5] == 11.0 {
      let first = d[q + 12].to_int()
      d[q + 12] = (st.segs.length() / 4).to_double()
      for v in (first * 4)..<((first + d[q + 13].to_int()) * 4) {
        st.segs.push(c.segs[v])
      }
    }
    // (the looks by the clock it holds, kept with it)
    let tag = cycle_tag_of(d, q)
    if tag != 0 && !st.cycles.contains(tag) {
      match cycle_frame.get(tag) {
        Some(cy) => st.cycles[tag] = cy
        None => ()
      }
    }
    q = q + inst_size
  }
}

///|
/// What the frame's instances `i0` to `i1` (in `a`) cover where they show, their rects within their cuts (x, y, w, h).
fn insts_cover(a : FixedArray[Double], i0 : Int, i1 : Int) -> (Double, Double, Double, Double) {
  let mut x0 = @double.infinity
  let mut y0 = @double.infinity
  let mut x1 = -@double.infinity
  let mut y1 = -@double.infinity
  for k in i0..<i1 {
    let q = k * inst_size
    let l = dmax(a[q], a[q + 16])
    let t = dmax(a[q + 1], a[q + 17])
    let r = dmin(a[q] + a[q + 2], a[q + 18])
    let b = dmin(a[q + 1] + a[q + 3], a[q + 19])
    if r > l && b > t {
      x0 = dmin(x0, l)
      y0 = dmin(y0, t)
      x1 = dmax(x1, r)
      y1 = dmax(y1, b)
    }
  }
  if x1 > x0 {
    (x0, y0, x1 - x0, y1 - y0)
  } else {
    (0.0, 0.0, 0.0, 0.0)
  }
}

///|
/// Whether part `self`'s drawing holds a native view's hole (drawn where the view is put each frame: native.mbt).
fn KeptPart::holds_native(self : KeptPart) -> Bool {
  let mut q = 0
  while q < self.floats {
    if self.insts[q + 5] == 9.0 {
      return true
    }
    q = q + inst_size
  }
  false
}

///|
/// The words of what node `root` holds (the part's box), as a Tester finds them.
fn Ctx::part_words(self : Ctx, root : Int) -> Array[KeptWord] {
  let out = []
  let inside = FixedArray::make(self.count, false)
  inside[root] = true
  for i in (root + 1)..<self.count {
    let n = self.nodes[i]
    if n.parent >= 0 && n.parent < self.count && inside[n.parent] {
      inside[i] = true
      if (n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor) && n.text != "" {
        let (x, y) = self.drawn_at(i)
        let mut alpha = 1.0
        let mut p = i
        while p >= 0 {
          alpha = alpha * self.nodes[p].opacity
          match self.drawn_entry(p) {
            Some(e) => alpha = alpha * e.look_now().alpha
            None => ()
          }
          p = self.nodes[p].parent
        }
        out.push({ text: n.text, x: n.x, y: n.y, w: n.fw, h: n.fh, drawn_x: x, drawn_y: y, alpha })
      }
      // (a list's row or a part drawn again in it: the words its build drew)
      out.append(self.kept_words_at(i))
    }
  }
  out
}

///|
/// The words drawn by the part kept that node `i` stands for this frame (drawn again), as a Tester finds them; none
/// for any other node.
fn Ctx::kept_words_at(self : Ctx, i : Int) -> Array[KeptWord] {
  match self.drawn_entry(i) {
    Some({ again: Some({ row: Some(rk), words, .. }), .. }) =>
      words.map(fn(w) { { ..w, y: w.y + rk.dy, drawn_y: w.drawn_y + rk.dy } })
    Some({ again: Some(st), .. }) => {
      let (dx, dy) = st.moved
      st.words.map(fn(w) { { ..w, x: w.x + dx, y: w.y + dy, drawn_x: w.drawn_x + dx, drawn_y: w.drawn_y + dy } })
    }
    _ => []
  }
}

///|
/// Part `st` drawn again (its box node `i`), as its build drew it, moved by how far its box is from where it was as that
/// build was painted (Ctx::parts_placed: no farther than its band holds what shows of it), put in the clip it is drawn
/// in: its instances, and what its paint said of the frame (said.mbt); where only targets are taken, only what it said.
fn Ctx::part_paint_again(self : Ctx, i : Int, st : KeptPart) -> Unit {
  let n = self.nodes[i]
  let (dx, dy) = (n.x - st.at.0, n.y - st.at.1)
  st.moved = (dx, dy)
  let k = clip_top()
  if dr.mode != mode_hits {
    let i0 = self.ninst
    let g0 = self.segs.length()
    self.insts_again(st)
    self.insts_moved(i0, st.band, dx, dy)
    self.kept_clip_into(k, i0, g0, drops=st.drops)
    st.rect = insts_cover(self.inst, i0, self.ninst)
  }
  self.say_again(st.said, st.moved_by(dx, dy, k))
}

///|
/// Part or row `st` drawn again: its instances as its build drew them, where they were, its shapes' pieces among this
/// frame's, its glass frosting captures of this frame's.
fn Ctx::insts_again(self : Ctx, st : KeptPart) -> Unit {
  self.insts_replay(st.insts, st.floats, st.segs)
  // (its looks by the clock, going on from where their cycles are now: cycle_look.mbt)
  for tag, cy in st.cycles {
    cycle_frame[tag] = cy
  }
}

///|
/// Instances painted before (the first `floats` numbers of `insts`, the pieces of their shapes `segs`) drawn again,
/// where they were: their shapes' pieces among this frame's, their glass frosting captures of this frame's.
fn Ctx::insts_replay(self : Ctx, insts : FixedArray[Double], floats : Int, segs : Array[Double]) -> Unit {
  let count = floats / inst_size
  while (self.ninst + count + 1) * inst_size > self.inst.length() {
    self.grow()
  }
  let i0 = self.ninst
  let a = self.inst
  let base = i0 * inst_size
  insts.blit_to(a, len=floats, dst_offset=base)
  let seg0 = (self.segs.length() / 4).to_double()
  self.segs.append(segs)
  let caps : Map[Int, Int] = {}
  for j in 0..<count {
    let b = base + j * inst_size
    let kind = a[b + 5]
    if kind == 11.0 {
      a[b + 12] = a[b + 12] + seg0
    } else if (kind == 5.0 || kind == 6.0) && a[b + 20] < 0.0 {
      // (a capture of its own in this frame, as it took one of its own in its build's)
      let was = (-a[b + 20]).to_int()
      let now = match caps.get(was) {
        Some(n) => n
        None => {
          glass_paint.run = glass_paint.run + 1
          caps[was] = glass_paint.run
          glass_paint.run
        }
      }
      a[b + 20] = -now.to_double()
      if kind == 5.0 {
        glass_paint.frost_run = now
      }
      glass_paint.run_start = -1
      glass_paint.run_len = 0
    }
  }
  self.ninst = i0 + count
}

///|
/// The parts drawn again in this build of the frame whose lists' rows said what their builds said (KeptPart's
/// `rows_said`), by their boxes' nodes.
// kept across runs: let go as each build of a frame starts (Ctx::parts_build_start)
let parts_laid_again : Map[Int, KeptPart] = {}

///|
/// The parts drawn again in this build of the frame, with their boxes' nodes (Ctx::parts_placed).
// kept across runs: let go as each build of a frame starts (Ctx::parts_build_start)
let parts_again : Array[(Int, KeptPart)] = []

///|
/// As a build of the frame starts: no part drawn again in it yet.
fn parts_build_start() -> Unit {
  parts_laid_again.clear()
  parts_again.clear()
}

///|
/// The frame laid out: each part drawn again where its box is now, as far from where its build was painted as that is
/// (KeptPart's `moved`), the packages told (on_drawn_again), the rows its drawing holds with it. One moved so that what
/// can show of it there (the window, cut by the clips round it as laid out) was not all recorded (past its band), moved
/// by less than whole device pixels (laid there, its words would be set on other pixels), or holding a native view
/// (put where it is by its build) is built there: the frame built again (Ctx::read_changed), and the frames after
/// built from their first build while its box goes on moving (KeptPart's `shifted`).
fn Ctx::parts_placed(self : Ctx) -> Unit {
  for p in parts_again {
    let (i, st) = p
    let n = self.nodes[i]
    let dx = n.x - st.at.0
    let dy = n.y - st.at.1
    st.moved = (dx, dy)
    // (what floats over its bars from outside it, where it is now: as its paint read it, else built)
    let floats_same = st.floats_read.iter().all(fn(r) {
      let (x0, y0, x1, y1, top, foot) = r
      self.floats_round(x0 + n.x, y0 + n.y, x1 + n.x, y1 + n.y, -1, None) == (top, foot)
    })
    if !floats_same {
      st.built = -1
      st.shifted = true
      self.read_changed("what floats over a part kept from outside it changed")
      continue
    }
    if dx != 0.0 || dy != 0.0 {
      let (l, t, r, b) = self.shown_at(i)
      let (bl, bt, br, bb) = st.band
      let sc = self.scale
      let whole = fn(v : Double) { (v * sc - (v * sc).round()).abs() < 0.000001 }
      if !whole(dx) ||
        !whole(dy) ||
        l - dx < bl ||
        t - dy < bt ||
        r - dx > br ||
        b - dy > bb ||
        st.holds_native() {
        st.built = -1
        st.shifted = true
        self.read_changed("a part kept moved past what its build drew")
        continue
      }
    }
    self.drawn_again_told((0, st.id), dx, dy, 0.0)
    for rid in st.rows_said {
      match kept_rows.get(rid) {
        Some({ row: Some(rk), .. } as rp) => self.drawn_again_told((1, rp.id), dx, rk.dy + dy, rk.rel)
        _ => ()
      }
    }
  }
}

///|
/// Where what is laid out in node `i` can show (x0, y0, x1, y1): what holds it all (the window, a layer over it), cut by
/// each box round it that clips, as laid out.
fn Ctx::shown_at(self : Ctx, i : Int) -> (Double, Double, Double, Double) {
  let mut x0 = -@double.infinity
  let mut y0 = -@double.infinity
  let mut x1 = @double.infinity
  let mut y1 = @double.infinity
  let mut j = self.nodes[i].parent
  while j >= 0 {
    let n = self.nodes[j]
    if n.clip || n.parent < 0 {
      x0 = dmax(x0, n.x)
      y0 = dmax(y0, n.y)
      x1 = dmin(x1, n.x + n.fw)
      y1 = dmin(y1, n.y + n.fh)
    }
    j = n.parent
  }
  (x0, y0, x1, y1)
}

///|
/// Node `i` laid out: where it is a part drawn again, what the rows of its lists said said again there, in their
/// order, as its lists say theirs as they are laid out (Ctx::rows_placed).
fn Ctx::parts_rows_laid(self : Ctx, i : Int) -> Unit {
  match parts_laid_again.get(i) {
    Some(st) => {
      parts_laid_again.remove(i)
      for rid in st.rows_said {
        match kept_rows.get(rid) {
          Some(rp) => self.say_again(rp.built_said, moved_to(i))
          None => ()
        }
      }
    }
    None => ()
  }
}

///|
/// The frame laid out: what the rows of the parts drawn again whose boxes were not laid out anew said (a box placed as
/// it was, with what holds it), said now.
fn Ctx::parts_rows_left(self : Ctx) -> Unit {
  let left = parts_laid_again.keys().collect()
  for i in left {
    self.parts_rows_laid(i)
  }
}

///|
/// What is kept as it was built and is being built now, the innermost: a list's row (1 and its id among the rows'), a
/// part (0 and its id), or none ((0, 0)). What a package keeps of what that build lays out is that row's or part's, kept
/// for it while it is drawn again (on_drawn_again).
pub fn kept_building() -> (Int, Int) {
  if part_now.row != 0 {
    (1, part_now.row)
  } else {
    (0, part_now.part)
  }
}

///|
/// Part or row `which` drawn again this frame, `dx` across and `dy` down the window from where its build laid it out,
/// `rel` down its list's rows: the packages told (on_drawn_again).
fn Ctx::drawn_again_told(self : Ctx, which : (Int, Int), dx : Double, dy : Double, rel : Double) -> Unit {
  for f in drawn_again_hooks {
    f(self, which, dx, dy, rel)
  }
}

///|
/// The kept parts and rows what is built now is in: a row's own, and the part it is in (what a part holds is its rows'
/// too, drawn again with it).
fn kept_reading() -> Array[KeptReads] {
  let out = []
  if part_now.row != 0 {
    match kept_rows.get(part_now.row) {
      Some(st) => out.push(st.reads)
      None => ()
    }
  }
  if part_now.part != 0 {
    match kept_parts.get(part_now.part) {
      Some(st) => out.push(st.reads)
      None => ()
    }
  }
  out
}

///|
/// Box `id` read as laid out (Ctx::laid_rect, laid_size) by what is built now.
fn kept_read_laid(id : Int) -> Unit {
  for r in kept_reading() {
    if !r.laid.contains(id) {
      r.laid[id] = None
    }
  }
}

///|
/// What box `id` shows across read (Ctx::shown_across, by the name `but`) by what is built now.
fn kept_read_shown(id : Int, but : String) -> Unit {
  for r in kept_reading() {
    if !r.shown.contains(id) {
      r.shown[id] = (but, None)
    }
  }
}

///|
/// Whether box `id` was left out read (Ctx::left_out) by what is built now.
fn kept_read_left(id : Int) -> Unit {
  for r in kept_reading() {
    if !r.left.contains(id) {
      r.left[id] = false
    }
  }
}

///|
/// Each part and row kept that this frame shows: its reads, how far across and down from where its build laid them out
/// it is (a part drawn again: its `moved`; a row: its dy), and whether it was drawn again (its build not run) or built.
fn Ctx::kept_shown(self : Ctx, f : (KeptReads, Double, Double, Bool) -> Unit) -> Unit {
  for _, st in kept_parts {
    if st.shown == self.frame_no {
      f(st.reads, st.moved.0, st.moved.1, st.again && st.built != self.frame_no)
    }
  }
  for _, st in kept_rows {
    match st.row {
      Some(rk) if st.shown == self.frame_no => f(st.reads, 0.0, rk.dy, rk.kept)
      _ => ()
    }
  }
}

///|
/// Before what was not read this frame is let go (reads_after_layout): what the builds of the parts and rows drawn
/// again read, kept as their builds' frames laid it out, moved with them.
fn Ctx::kept_reads_again(self : Ctx) -> Unit {
  self.kept_shown(fn(r, dx, dy, again) {
    if !again {
      return
    }
    for id, rect in r.laid {
      self.laid_watch[id] = self.frame_no
      match rect {
        Some((x, y, w, h)) => self.laid_rects[id] = (x + dx, y + dy, w, h)
        None => ()
      }
    }
    for id, s in r.shown {
      self.shown_watch[id] = (self.frame_no, s.0)
      match s.1 {
        Some(span) => self.shown_spans[id] = span
        None => ()
      }
    }
  })
}

///|
/// Once what was read is laid out anew (reads_after_layout): how this frame laid out what the parts and rows built in
/// it read, taken for them.
fn Ctx::kept_reads_taken(self : Ctx) -> Unit {
  self.kept_shown(fn(r, _, _, again) {
    if again {
      return
    }
    let laid = r.laid.keys().collect()
    for id in laid {
      r.laid[id] = self.laid_rects.get(id)
    }
    let shown = r.shown.keys().collect()
    for id in shown {
      match r.shown.get(id) {
        Some((but, _)) => r.shown[id] = (but, self.shown_spans.get(id))
        None => ()
      }
    }
  })
}

///|
/// As what rows left out is said anew (left_out_after_layout): what the parts and rows drawn again had left out kept
/// left out; what those built in this frame read of it, taken for them.
fn Ctx::kept_left(self : Ctx) -> Unit {
  self.kept_shown(fn(r, _, _, again) {
    let ids = r.left.keys().collect()
    for id in ids {
      if again {
        if r.left.get(id) == Some(true) {
          self.left_ids[id] = true
        }
      } else {
        r.left[id] = self.left_ids.contains(id)
      }
    }
  })
}

///|
/// Every part kept (Ctx::kept_part) and row kept built anew from the next build: what they show changed by what they do
/// not read (the screen's corners as the host first says them).
pub fn Ctx::forget_parts(self : Ctx) -> Unit {
  ignore(self)
  parts_forget()
}
