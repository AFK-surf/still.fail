// What a frame does again, by what it read. A frame's work, from taking what came from outside
// to the end of its paint, runs under one watch (mbui/signals' Watch): all it reads of signals is followed, and that is
// all it is built from: the core's data and the app's state, the frames' clock (frame_clock: Ctx::now), the host's
// settings it is drawn by (host_said.mbt: one signal each, read where used), what came from outside that is no signal yet (outside_said: what
// records, a message, a host's event, a step of the runtime's, a frame asked for between frames)
// and the hand as what reads it reads it (hand.mbt: what the pointer is over, what is pressed, clicked, focused, the
// hand's events; a pointer moved over what lights nothing changes none of it). So the next frame is built anew where
// any of it changed (the watch is stale), where a moment it read the clock as came (a wake: Ctx::wake_in, Ctx::every,
// a cycle's step), or where it asked for another itself (a frame asked for, a motion going, a fiber stepping a frame at
// a time, a layout read back that moved). Nothing is listed: what was not read changes nothing, what was read is
// followed by the read itself.
//
// Its paint runs under a watch of its own (paint_watch): what is read only as the frame is painted (where a node is
// placed by the clock, Ctx::moved_by: a page sliding; a look worked out there, Ctx::look_by: a fade, a move; a picture
// fading in) is followed by it alone. So where nothing the build read changed, and the last two builds laid out the
// same (what a build leaves for the next to read, a size it measured, a place it was drawn at, has settled: tree_sig),
// but what the paint read did (the clock, read by a motion going as it is drawn), the frame is painted again from the
// last build's tree as laid out, nothing built or laid out (a page's slide: its frames were each built and laid out
// whole for where it was drawn). Where that did not change either and the last two paints drew the same, nothing it
// shows changes but its looks by the clock (cycle_look.mbt: a spinner turning, the spokes stepping, a breath): the
// frame is the last one's instances as they were painted, each look applied at its time, nothing built, laid out or
// painted (2026-10-27: ~16 frames a second while chats are at work, each building, laying out and painting the window
// for 0.03% of it). A Tester draws each frame painted alone or of its looks alone whole after it as well, and the two
// must be the same: every test holds it (tester_looks.mbt).

///|
/// Where what the frames' watch was first told of since the frame before was set (Signal::set's place; "" none): said
/// with why the next frame is built.
// kept across runs: put back as each frame is decided
let frame_told_at : Ref[String] = Ref("")

///|
/// When what the frames' watch was told of since the frame before was told (each moment once, as told): the moment of
/// its cause (the window's tree's, an event's or a moment's falling due as it tells it), else the frame's being drawn,
/// else the host's now between frames.
// kept across runs: put back as each frame is decided
let frame_told_moments : Array[(Double, String)] = []

///|
/// The moments the build under way was told by (frame_told_moments, as the frame was decided): what a wait asked in it
/// without its own `since` counts from (Ctx::held), the latest of them.
// kept across runs: set as each frame is decided
let build_causes : Array[(Double, String)] = []

///|
/// How many sets there had been as a watch was last told (watch_told_moment): what came after it was told is no cause
/// it has a moment of, a watch told once till it is read.
// kept across runs: a count read only as a difference
let told_sets : Ref[Int] = Ref(0)

///|
/// How many sets there had been as the frame being drawn began (on_frame): what it sets itself (its clock) told
/// nothing before it.
// kept across runs: set as each frame begins
let frame_start_sets : Ref[Int] = Ref(0)

///|
/// Whether more sets came after the last telling before the build under way was decided (build_causes): a cause of it
/// that may be later than the moment it was told at, said where a wait counts from that (Ctx::held, held_causes).
// kept across runs: set as each frame is decided
let build_told_more : Ref[Bool] = Ref(false)

///|
/// The moment of what is told now (frame_told_moments').
/// Said with where it came from: `tree` (an event, a moment falling due, a structure's change), `frame` (told as a frame
/// was drawn: under a Tester, what its fake host tells as each frame is about to begin, a posted message among it, at
/// the frame's moment), `between` (the host's now between frames).
fn told_moment() -> (Double, String) {
  match tree_cause() {
    Some(m) => (m, "tree")
    None => if frame_moment.val >= 0.0 { (frame_moment.val, "frame") } else { (h_now(), "between") }
  }
}

///|
/// What the frames' watch is told now: its moment kept, once.
fn watch_told_moment() -> Unit {
  told_sets.val = @signals.sets_said()
  let m = told_moment()
  if !frame_told_moments.iter().any(fn(x) { x.0 == m.0 }) {
    frame_told_moments.push(m)
  }
}

///|
/// The frames' watch told between frames or as one begins: where, the first time since the frame before.
fn watch_told_at() -> Unit {
  watch_told_moment()
  if frame_told_at.val == "" {
    frame_told_at.val = @signals.last_set_at()
  }
}

///|
/// The frames' clock, as each frame begins (on_frame): what reads it followed (Ctx::now) is built again each frame.
// kept across runs: set as each frame begins
let frame_clock : @signals.Signal[Double] = @signals.signal(0.0)

///|
/// What came from outside that is no signal yet, counted (outside_came): what reads it (each frame's build) is built
/// again as it comes.
// kept across runs: only counts on
let outside_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// The watch the frames' work runs under (made with the run: frame_watch_of).
// kept across runs: let go and made anew as a run begins (looks_reset)
let frame_watch : Ref[@signals.Watch?] = Ref(None)

///|
/// The watch the frames' layout runs under (made with the run: layout_watch_of), within the frame's: what only the
/// layout reads (a list's place, what the hand did to it, its motions by the clock; what is worked out once laid out)
/// is followed by it alone, and lays the next frame out again with the lists' rows kept (kept_nodes.mbt).
// kept across runs: let go and made anew as a run begins (looks_reset)
let layout_watch : Ref[@signals.Watch?] = Ref(None)

///|
/// What the layout's watch said asks for the next frame, told as a frame was drawn ("" none: put back as each frame is
/// built); where the last frame's layout first read the clock followed ("" none).
// kept across runs: written as the watch is told, put back as each frame is built
let layout_said : Ref[String] = Ref("")

///|
// kept across runs: put back as each frame is built
let layout_clock_at : Ref[String] = Ref("")

///|
/// Whether the frame is being laid out (frame_body, under layout_watch): where the clock is read then is said so.
// kept across runs: set and let go within a frame
let laying : Ref[Bool] = Ref(false)

///|
/// Whether the pass of the frame's build under way is still to be laid out (frame_body): what its layout read told
/// meanwhile is read anew as it is.
// kept across runs: set and let go within a frame
let layout_coming : Ref[Bool] = Ref(false)

///|
/// The run's layout watch: as what its last layout read changes, the frame is laid out again (in a frame, by its end:
/// the next; between frames, a frame asked of the host now).
fn layout_watch_of() -> @signals.Watch {
  match layout_watch.val {
    Some(w) => w
    None => {
      let w = @signals.watch(fn() {
        if frame_running.val && !frame_built.val {
          ()
        } else if frame_running.val && layout_coming.val && !laying.val {
          // (told as the frame is built, before it is laid out: laid out after it, it reads it anew)
          ()
        } else if frame_running.val {
          let by = match layout_watch.val {
            Some(w) => w.set_as_read()
            None => []
          }
          layout_said.val = if by.is_empty() {
            "a value its layout read changed as it was laid out, set at \{@signals.last_set_at()}"
          } else {
            "a value its layout read set again as it was laid out, at " + by.join(", ")
          }
        } else {
          h_frame_owed()
        }
      })
      layout_watch.val = Some(w)
      w
    }
  }
}

///|
/// Whether the frame left its layout or a list's row kept something to come (what they read changed as it was drawn):
/// the next frame is asked for, to lay it out.
fn layout_left() -> Bool {
  layout_said.val != "" || nodes_run.told
}

///|
/// The watch the frames' paint runs under (made with the run: paint_watch_of).
// kept across runs: let go and made anew as a run begins (looks_reset)
let paint_watch : Ref[@signals.Watch?] = Ref(None)

///|
/// Where the frame is in its paint: 0 not painted yet, 1 painting, 2 painted (frame_paint); what the paint's watch is
/// told before it is painted, the paint reads anew.
// kept across runs: put back as each frame begins (on_frame)
let paint_phase : Ref[Int] = Ref(0)

///|
/// Where the last frame built first read the clock followed ("" none): why the next is built again.
// kept across runs: put back as each frame is built
let clock_read_at : Ref[String] = Ref("")

///|
/// Where the last frame's paint first read the clock followed ("" none): why the next is painted again.
// kept across runs: put back as each frame is painted
let paint_clock_at : Ref[String] = Ref("")

///|
/// Whether the last frame built read the time of day (@ui.wall_ms), not followed: what shows it reads it as a moment
/// (Ctx::every).
// kept across runs: put back as each frame is built
let wall_read : Ref[Bool] = Ref(false)

///|
/// Why the last frame was built whole ("" not: painted alone, or of its looks alone).
// kept across runs: written by each frame
let built_why : Ref[String] = Ref("")

///|
/// Why the last frame was painted alone ("" not: built whole, or of its looks alone).
// kept across runs: written by each frame
let painted_why : Ref[String] = Ref("")

///|
/// What the frames' watch said asks for the next frame, where it was told as a frame was drawn ("" none: put back as
/// each frame begins).
// kept across runs: written as the watch is told
let watch_said : Ref[String] = Ref("")

///|
/// Whether the frame being drawn has begun being built (frame_drawn, on to on_frame's end): what its watch is told
/// from then on is for the next frame.
// kept across runs: set and let go within a frame
let frame_built : Ref[Bool] = Ref(false)

///|
/// Whether a frame is being drawn (on_frame, from its start to its end): what it asks of the host is its own.
// kept across runs: set and let go within a frame
let frame_running : Ref[Bool] = Ref(false)

///|
/// The moment of the frame being drawn (on_frame's, frame_offscreen's `t`, from its start to its end, before even what
/// came from outside is handed on), else -1: the runtime's clock in a frame (fx_runtime).
// kept across runs: set and let go within a frame
let frame_moment : Ref[Double] = Ref(-1.0)

///|
/// The frames drawn so far, on the display or offscreen (on_frame's, frame_offscreen's): which host's event a fiber
/// forked in one came in (fx_runtime).
// kept across runs: only ever counts up
let frame_serial : Ref[Int] = Ref(0)

///|
/// Whether an offscreen frame is being drawn (frame_offscreen): it asks the host for nothing, no frame and no wake.
fn offscreen_frame() -> Bool {
  frame_moment.val >= 0.0 && !frame_running.val
}

///|
/// The run's watch: as what its last read read changes, a frame is owed (in a frame, by its end; between frames, the
/// host asked now).
fn frame_watch_of() -> @signals.Watch {
  match frame_watch.val {
    Some(w) => w
    None => {
      let w = @signals.watch(fn() {
        frame_read_told(fn() {
          match frame_watch.val {
            Some(w) => w.set_as_read()
            None => []
          }
        })
      })
      frame_watch.val = Some(w)
      w
    }
  }
}

///|
/// What the paint's watch said asks for the next frame's paint, where it was told as a frame was drawn ("" none: put
/// back as each frame begins).
// kept across runs: written as the watch is told
let paint_said : Ref[String] = Ref("")

///|
/// The run's paint watch: as what its last paint read changes, the frame is painted again (in a frame, once it is
/// painted: the next; between frames, a frame asked of the host now). Told before the frame's paint, nothing: that
/// paint reads it anew.
fn paint_watch_of() -> @signals.Watch {
  match paint_watch.val {
    Some(w) => w
    None => {
      let w = @signals.watch(fn() {
        if frame_running.val && paint_phase.val == 0 {
          ()
        } else if frame_running.val {
          paint_said.val = "a value its paint read changed as it was painted"
        } else {
          h_frame_owed()
        }
      })
      paint_watch.val = Some(w)
      w
    }
  }
}

///|
/// The clock read followed where something reads (Ctx::now: a frame's build or paint, a computed), `loc` the reader.
fn clock_read(loc : SourceLoc) -> Unit {
  if @signals.active_sub() is Some(_) {
    clock_read_by(loc.to_string(), None)
    frame_clock.get() |> ignore
  }
}

///|
/// The clock read followed by what shows a motion going (Ctx::shows_motion: `who`'s, else the host's clock or its
/// state): the record names the motion (Mover::told_as) where it was told who it is.
fn clock_read_here(who? : Mover) -> Unit {
  if @signals.active_sub() is Some(_) {
    clock_read_by("a motion, the host's clock or its state (Ctx::shows_motion, @hostapi.polled)", who)
    frame_clock.get() |> ignore
  }
}

///|
/// Where the last frame built, laid out or painted first read the clock followed, which motion read it (`who`: the
/// mover, kept beside `*_clock_at` as it is set and read only while that says a place; named as the record is written:
/// clock_said).
// kept across runs: written with clock_read_at, layout_clock_at and paint_clock_at
let clock_read_who : Ref[Mover?] = Ref(None)

///|
// kept across runs: as clock_read_who
let layout_clock_who : Ref[Mover?] = Ref(None)

///|
// kept across runs: as clock_read_who
let paint_clock_who : Ref[Mover?] = Ref(None)

///|
/// Where a part or a list's row kept as its nodes (kept_part.mbt) first read the clock followed as the last frame
/// built it, and which motion ("" none): its watch told by the frames' clock as the next begins, why it is built again.
// kept across runs: put back as each frame begins (frame_drawn)
let part_clock_at : Ref[String] = Ref("")

///|
/// How many times the clock was read followed, counted on (row_drawing.mbt: a row whose paint read it is not kept as
/// drawn).
// kept across runs: only counts on
let clock_reads : Ref[Int] = Ref(0)

///|
// kept across runs: as part_clock_at
let part_clock_who : Ref[Mover?] = Ref(None)

///|
/// Where the clock was read followed (`at`; by `who`'s motion, where it is known), kept as the first such read of the
/// frame's build, of its layout or of its paint (and of the parts it built). Only a place and a mover kept: the words
/// are worked out as the frame's why is (clock_said).
fn clock_read_by(at : String, who : Mover?) -> Unit {
  clock_reads.val += 1
  if paint_phase.val == 1 {
    if paint_clock_at.val == "" {
      paint_clock_at.val = at
      paint_clock_who.val = who
    }
  } else if laying.val {
    if layout_clock_at.val == "" {
      layout_clock_at.val = at
      layout_clock_who.val = who
    }
  } else {
    if clock_read_at.val == "" {
      clock_read_at.val = at
      clock_read_who.val = who
    }
    if part_building() && part_clock_at.val == "" {
      part_clock_at.val = at
      part_clock_who.val = who
    }
  }
}

///|
/// Where the clock was read (`at`) by `who`, in words: the motion it is, as it was told (`a motion of Anim "key", told
/// at <the app's place>`: Mover::told_as), else the place itself.
fn clock_said(at : String, who : Mover?) -> String {
  match who {
    Some(m) => {
      let named = m.named()
      if named == "" {
        at
      } else {
        "a motion of " + named
      }
    }
    None => at
  }
}

///|
/// The motion the last frame's why names (clock_said: "" none), counted by the record (app.mbt's probe_motions).
// kept across runs: written by each frame
let built_motion : Ref[String] = Ref("")

///|
/// What the host keeps and changes with no event of its own, read (@hostapi.polled: a browser come back to a login),
/// is followed as the clock is: what reads it as it is built is built again each frame while it does.
fn init {
  @hostapi.polled.val = fn() { clock_read_here() }
}

///|
/// An effect made as the frame's watch reads (a build, an after_build, a Ctx::tell: frame_body under frame_watch_of's
/// read) is that watch's, let go as it reads the next frame, whatever owner is set: a fault (@signals.effect_in_watch).
/// (What is handed on as the frame begins, the messages left for it and the window's runtime's timers and fibers, runs
/// outside that reading: take_messages, fx_frame_start.)
fn init {
  @signals.effect_in_watch.val = Some(fn(loc) {
    @view.fault(
      "an effect made as a frame is read (a build, an after_build, a Ctx::tell) is let go as the next frame is read: make it in a handler, or in @signals.untracked with its owner set (@signals.set_owner); made at \{loc}",
    )
  })
}

///|
/// The frames' clock (ms), followed only before `end` (Ctx::now): what moves till then and is still from then on (a
/// spring's way, a fade), built again each frame till it is.
#callsite(autofill(loc))
fn Ctx::now_before(self : Ctx, end : Double, loc~ : SourceLoc) -> Double {
  if self.clock < end {
    clock_read(loc)
  }
  self.clock
}

///|
/// The frames' clock (ms), followed as Ctx::now is, read for `who`'s motion (an Anim stepped to the frame): the
/// performance record names that motion (Mover::told_as) as what read it, not the place it was read at.
#callsite(autofill(loc))
pub fn Ctx::now_of(self : Ctx, who : Mover, loc~ : SourceLoc) -> Double {
  if @signals.active_sub() is Some(_) {
    clock_read_by(loc.to_string(), Some(who))
    frame_clock.get() |> ignore
  }
  self.clock
}

///|
/// What came from outside and is no signal: what each frame's build reads (outside_said) built again.
fn outside_counted() -> Unit {
  outside_said.set(outside_said.untracked() + 1)
}

///|
/// Between frames, what came from outside left for the next (messages_between, streams_said): counted, and that frame
/// asked for of the host itself. The watch tells the host only the first time since a frame (a value set before, while
/// the window is away: its frame not drawn), and a host that draws only what is asked from outside while away
/// (win_app.c told_between) must hear it again, as it heard each post before it was told between frames.
fn outside_left() -> Unit {
  outside_counted()
  h_frame_owed()
}

///|
/// What the frame reads of what came from outside, as it has taken it (frame_body): followed. (Of the hand, what reads
/// it reads it: hand.mbt; of the host's settings, what reads one reads it: host_said.mbt.)
fn frame_inputs_read() -> Unit {
  outside_said.get() |> ignore
}
///|
/// The last frame as its paint ended (looks_keep): its instances, with the tags of its looks by the clock before they
/// were applied (`looks`: it has some); whether the next may be built from nothing it did not read (it left nothing to
/// come of its own: looks_left); the soonest moment anything but a look or a paint asked to be drawn at (-1: none),
/// from its build on.
// `built` is read by its tests alone
#warnings("-unused_field")
priv struct LooksBase {
  /// its instances, kept only where it has looks (a frame of the looks alone draws them again)
  mut inst : FixedArray[Double]
  /// where its headers were among them (ride_spans), put back with them
  mut spans : Array[Int]
  mut n : Int
  mut looks : Bool
  mut ok : Bool
  /// of `ok`: it left nothing to come of its own (`left`), it told outside what the one before it told (`told_same`)
  mut left : Bool
  mut told_same : Bool
  mut wake : Double
  /// where `wake` was asked (said with why the frame it comes in is built: built_why)
  mut wake_by : String
  /// when the frame was last built whole (ms)
  mut built_at : Double
  /// whether it drew what the frame painted before it drew (`built`: there was one): what a paint leaves for the next
  /// one to read has settled, painted again it draws the same
  mut built : Bool
  mut settled : Bool
}

///|
// kept across runs: put back with the globals (looks_reset), else made again by each frame painted
let looks_base : LooksBase = {
  inst: FixedArray::make(0, 0.0),
  spans: [],
  n: 0,
  looks: false,
  ok: false,
  left: false,
  told_same: false,
  wake: -1.0,
  wake_by: "",
  built_at: -1.0,
  built: false,
  settled: false,
}

///|
/// A list's anchor moved in this frame, or something of the window's tree scrolled (view_paint). Its new drawing must not be treated as the one whose fingerprint was kept;
/// whether it happens to be identical need not be worked out while it is moving.
// kept across runs: cleared as each frame begins
let scroll_paint_uncompared : Ref[Bool] = Ref(false)

///|
/// What the last build laid out, as one number (tree_sig), whether there was one before it and whether it laid out the
/// same (`laid_same`: what a build leaves for the next to read, a size it measured, a place it was drawn at, has
/// settled, built again it lays out the same); the root of its tree; the soonest moment its paint asked to be drawn at
/// (-1: none), its looks by the clock's apart.
priv struct PaintBase {
  mut sig : Int64
  mut had : Bool
  mut laid_same : Bool
  mut root : Int
  mut wake : Double
}

///|
// kept across runs: put back with the globals (looks_reset), else made again by each frame built and painted
let paint_base : PaintBase = { sig: 0L, had: false, laid_same: false, root: 0, wake: -1.0 }

///|
/// Whether the looks by the clock are being applied (looks_apply): a wake asked now is theirs.
// kept across runs: set and let go within a frame
let in_looks : Ref[Bool] = Ref(false)

///|
/// What the looks by the clock asked for as they were last applied: the soonest wake (-1: none), a frame each frame.
priv struct LooksOwn {
  mut wake : Double
  mut cycling : Bool
}

///|
// kept across runs: written each time the looks are applied (looks_apply)
let looks_own : LooksOwn = { wake: -1.0, cycling: false }

///|
/// Whether the last frame was of its looks alone: what the frame did (FramePerf's `looks`).
// kept across runs: written by each frame
let looks_drawn : Ref[Bool] = Ref(false)

///|
/// Whether the last frame was painted alone, from the last build's tree (FramePerf's `painted`).
// kept across runs: written by each frame
let painted_alone : Ref[Bool] = Ref(false)

///|
/// How many frames of the looks alone were drawn (a test's: those drawn whole after them as well are counted too).
// kept across runs: only counts on
let looks_frames : Ref[Int] = Ref(0)

///|
/// How many frames were painted alone (a test's: those drawn whole after them as well are counted too).
// kept across runs: only counts on
let paints_alone : Ref[Int] = Ref(0)

///|
let laid_otherwise = "the one before it laid out otherwise"

///|
/// Release the run's frame readers while the resources they read still belong to that run.
fn frame_watches_let_go() -> Unit {
  for w in [frame_watch, layout_watch, paint_watch] {
    match w.val {
      Some(w) => w.stop()
      None => ()
    }
    w.val = None
  }
}

///|
/// Put back as a run begins (reset_globals): the run's watches let go, the first frame built whole.
fn looks_reset() -> Unit {
  nodes_forget()
  list_hand_forget()
  layout_said.val = ""
  frame_told_at.val = ""
  frame_told_moments.clear()
  build_causes.clear()
  build_told_more.val = false
  layout_clock_at.val = ""
  frame_watches_let_go()
  looks_base.n = 0
  looks_base.looks = false
  looks_base.ok = false
  looks_base.left = false
  looks_base.told_same = false
  looks_base.wake = -1.0
  looks_base.wake_by = ""
  looks_base.built = false
  looks_base.settled = false
  paint_base.had = false
  paint_base.laid_same = false
  paint_base.root = 0
  paint_base.wake = -1.0
  looks_tells.now = []
  looks_tells.before = []
  looks_drawn.val = false
  painted_alone.val = false
  clock_read_at.val = ""
  paint_clock_at.val = ""
  paint_said.val = ""
  paint_phase.val = 0
}

///|
/// As a frame built whole begins: no wake but a look's asked yet, the clock not read.
fn looks_frame_start() -> Unit {
  looks_base.ok = false
  looks_base.wake = -1.0
  looks_base.wake_by = ""
  clock_read_at.val = ""
  wall_read.val = false
}

///|
/// A wake at `t` asked (Ctx::wake_at_time): the looks' own, as they are applied; the paint's, as the frame is painted;
/// else the soonest anything else asked for: each kept for the frames to come that do not do again what asked it.
fn looks_wake(t : Double, loc : SourceLoc) -> Unit {
  let soonest = fn(w : Double) { w < 0.0 || t < w }
  if in_looks.val {
    if soonest(looks_own.wake) {
      looks_own.wake = t
    }
  } else if paint_phase.val == 1 {
    if soonest(paint_base.wake) {
      paint_base.wake = t
    }
  } else if soonest(looks_base.wake) {
    looks_base.wake = t
    looks_base.wake_by = loc.to_string()
  }
}

///|
/// The looks by the clock applied to what the frame drew (Ctx::cycle_looks), what they ask for said as theirs.
fn looks_apply(c : Ctx) -> Unit {
  looks_own.wake = -1.0
  looks_own.cycling = false
  in_looks.val = true
  c.cycle_looks()
  // (what columns scroll by their offsets alone moved by their headers to where they have them now: list_looks)
  list_looks(c)
  // (the window's tree's endless decorations on the resident clock (View::cycle_resident): its next step woken for,
  // said later, as a look's here is: nothing built for it; a step nobody can see waits)
  if view_resident_read() {
    match view_app.val {
      Some(tree) => c.wake_at_time(tree.resident_next(), later=true)
      None => ()
    }
  }
  in_looks.val = false
}

///|
/// Whether the window's tree draws an endless decoration on the resident clock where it can be seen
/// (@view.Tree::resident_read): its next step is the looks' to ask for, a frame of its looks alone's too.
fn view_resident_read() -> Bool {
  match view_app.val {
    Some(tree) => tree.resident_read() && app_visible()
    None => false
  }
}

///|
/// Each header of what a column scrolls by its offset alone among the frame's instances (view_ride.mbt's ListHead)
/// written as its column has it at the frame's moment (@view.Tree::scroll_off_of: how far it is scrolled then), the one
/// writer of where they are, a frame painted or of its looks alone: written in place again where something drew the
/// frame out since (a Tester's host, Ctx::flat_from), said among its headers again. While a column glides on by itself
/// (a fling, a wheel's notches easing in, what shows past an end going back: its end said), a frame each frame till that
/// end, and one woken for at it.
fn list_looks(c : Ctx) -> Unit {
  if list_heads.is_empty() {
    return
  }
  guard view_app.val is Some(tree) else { return }
  let a = c.inst
  for h in list_heads {
    guard h.at < c.ninst && tree.scroll_off_of(h.id, c.clock) is Some((ox, oy)) else { continue }
    let b = h.at * inst_size
    h.head.blit_to(a, len=inst_size, dst_offset=b)
    a[b] = h.bx + h.s * ox
    a[b + 1] = h.by + h.s * oy
    if !ride_spans.contains(h.at) {
      let mut j = ride_spans.length()
      while j > 0 && ride_spans[j - 1] > h.at {
        j = j - 1
      }
      ride_spans.insert(j, h.at)
    }
    match tree.glide_end_of(tree.scroll_off_by(h.id)) {
      Some(end) if c.clock < end => {
        c.cycling = true
        looks_own.cycling = true
        // (a frame at its end, not waited for: the glide's end is its column's motion's (on_glides, said moving till
        // then), and what is waited for is put down only as a frame is built, which a frame of the looks alone is not:
        // waited for here, it stayed after the rest, a Tester on a host keeping groups drawing every display frame
        // after a fling till its next input and never at rest, glide_wake_wbtest)
        c.wake_at_time(end, later=true)
      }
      _ => ()
    }
  }
}

///|
/// The frame is built and laid out, `root` its tree (frame_body): what it laid out said as one number, and whether the
/// build before it laid out the same.
fn laid_kept(c : Ctx, root : Int) -> Unit {
  let sig = tree_sig(c)
  paint_base.laid_same = paint_base.had && sig == paint_base.sig
  paint_base.had = true
  paint_base.sig = sig
  paint_base.root = root
}

///|
/// What the frame's build laid out and how it is to be drawn, as one number (FNV-1a): each node's kind, id, where it
/// is laid out and how large (where what places it by the clock, Ctx::moved_by, has it aside: the paint's, placed
/// again as each frame is painted), its colours, corners, border, shadow, opacity, offset, words and their face,
/// whether it cuts what it holds; each node drawn otherwise than plainly (draw.mbt's entries), its look as built, its
/// order, whether it is only drawn, cut, kept, or has a look worked out as it is painted or by the clock.
fn tree_sig(c : Ctx) -> Int64 {
  let mut h = -3750763034362895579L
  // (folded in place, no closure over `h`: a node's dozen and more numbers, for every node of every build)
  let moves = c.nodes.iter().take(c.count).any(fn(n) { n.moved_by is Some(_) })
  h = hash_mix(h, c.count.to_int64())
  for i in 0..<c.count {
    let n = c.nodes[i]
    h = hash_mix(h, n.kind.to_int64())
    h = hash_mix(h, n.id.to_int64())
    h = hash_mix(h, n.parent.to_int64())
    let (mx, my) = if moves { moved_over(c, i) } else { (0.0, 0.0) }
    h = sig_num(h, n.x - mx)
    h = sig_num(h, n.y - my)
    h = sig_num(h, n.fw)
    h = sig_num(h, n.fh)
    h = hash_mix(h, n.bg)
    h = hash_mix(h, n.color)
    h = hash_mix(h, n.border_c)
    h = hash_mix(h, n.shadow_c)
    h = sig_num(h, n.radius)
    h = sig_num(h, n.border_w)
    h = sig_num(h, n.shadow)
    h = sig_num(h, n.opacity)
    h = sig_num(h, n.tx)
    h = sig_num(h, n.ty)
    h = sig_num(h, n.font_size)
    h = hash_mix(h, n.weight.to_int64())
    h = hash_mix(h, (if n.clip { 1 } else { 0 }).to_int64())
    h = hash_mix(h, n.bones)
    if n.text != "" {
      h = hash_mix(h, n.text_said())
    }
  }
  for e in dr.entries {
    h = hash_mix(h, e.node.to_int64())
    let l = e.look
    h = sig_num(h, l.alpha)
    h = sig_num(h, l.dx)
    h = sig_num(h, l.dy)
    h = sig_num(h, l.sx)
    h = sig_num(h, l.sy)
    h = sig_num(h, l.rot)
    h = sig_num(h, l.circle)
    h = sig_num(h, l.words)
    h = hash_mix(h, e.z.to_int64())
    h = hash_mix(h, (if e.only { 1 } else { 0 }).to_int64())
    h = hash_mix(h, (if e.look_by is Some(_) { 1 } else { 0 }).to_int64())
    h = hash_mix(h, (if e.bg_by is Some(_) { 1 } else { 0 }).to_int64())
    h = hash_mix(h, (if e.glyphs_by is Some(_) { 1 } else { 0 }).to_int64())
    h = hash_mix(h, (if e.ink_by is Some(_) { 1 } else { 0 }).to_int64())
    h = hash_mix(h, (if e.notch_by is Some(_) { 1 } else { 0 }).to_int64())
    h = hash_mix(h, (if e.cut_by is Some(_) { 1 } else { 0 }).to_int64())
    h = hash_mix(h, (if e.cycle is Some(_) { 1 } else { 0 }).to_int64())
    h = hash_mix(h, (if e.keep is Some(_) { 1 } else { 0 }).to_int64())
    h = sig_num(h, e.bottom)
    h = sig_num(h, e.top)
    h = sig_num(h, e.right)
    h = sig_num(h, e.left)
    h = sig_num(h, e.cut_soft)
    h = hash_mix(h, e.fade_of.to_int64())
    h = sig_num(h, e.fades.0)
    h = sig_num(h, e.fades.1)
    h = sig_num(h, e.fades.2)
    h = sig_num(h, e.fades.3)
  }
  h
}

///|
/// `x` folded into `h` as tree_sig folds a length: to the bit. To 1/64 of a point, a layout still moving by less than
/// that a frame was taken as settled, the frames after it painted from it, and what was laid out where it had come to
/// at the next built whole: at 120 frames a second a way's last tenths of a point frozen where at 60 they were not
/// (kept_panes_wbtest, MBUI_TEST_FPS=120, 2026-11-09). A build of the same lays out the same to the bit.
fn sig_num(h : Int64, x : Double) -> Int64 {
  hash_mix(h, x.reinterpret_as_int64())
}

///|
/// The frame's paint is over, its looks by the clock not applied yet (frame_paint): what it drew kept (with their tags,
/// where it has looks), for a frame of the looks alone; whether it drew what the paint before it drew.
fn looks_keep(c : Ctx) -> Unit {
  // (what it drew said as one number, read once: not kept whole and compared with the paint before, two more passes
  // over every instance; kept whole only where a frame of the looks alone draws it again)
  let len = c.ninst * inst_size
  if scroll_paint_uncompared.val {
    // The old fingerprint says nothing about this drawing. Be conservative even when the movement happens not to
    // change a visible pixel: a later still paint establishes a new fingerprint before using the looks-only path.
    looks_base.settled = false
    looks_base.built = false
  } else {
    // (what a paint leaves for the next to read is told to the paint's watch as it changes (paint_watch_of): a paint
    // with nothing stale after it drew what the next would, never painted again to find out by comparing the two)
    looks_base.settled = true
    looks_base.built = true
  }
  looks_base.n = c.ninst
  looks_base.looks = !cycle_frame.is_empty()
  if looks_base.looks {
    // (its headers kept as they are, where they are among them: what the looks are applied to passes over their rooms,
    // inst_after; a list's moved again as it is drawn again, list_looks)
    if looks_base.inst.length() < len {
      looks_base.inst = FixedArray::make(len, 0.0)
    }
    c.inst.blit_to(looks_base.inst, len~)
    looks_base.spans = ride_spans.copy()
  }
}

///|
/// What the frames told outside (Ctx::after_build's ids, then Ctx::tell's), the last built and the one before.
priv struct LooksTold {
  mut now : Array[Int]
  mut before : Array[Int]
}

///|
// kept across runs: put back as a run begins (looks_reset), else said by each frame built whole
let looks_tells : LooksTold = { now: [], before: [] }

///|
/// What the frame built tells outside (frame_body): what that does is for the next frame to read, so the next is built
/// whole unless it told the same as the one before (said again each frame) and drew the same (looks_left).
fn looks_told(after : Array[Int], told : Array[Int]) -> Unit {
  looks_tells.before = looks_tells.now
  looks_tells.now = after + told
}

///|
/// The frame is over (on_frame), but for asking the next: whether the next may be built from nothing it did not read,
/// it left nothing to come of its own (no frame asked for, no fiber stepping a frame at a time, no layout read back
/// that moved; not the replay of parts kept, kept_part.mbt, which keeps its own; not on a host that tells nothing). A
/// motion going is no such thing: what reads it, as it is built or as it is painted, reads the clock, and is built or
/// painted again for it (Ctx::now); what does not read it does nothing for it.
fn looks_left(c : Ctx, held : Bool) -> Unit {
  let left = !c.wants_frame &&
    !c.fiber_frame &&
    !c.read_back_moved &&
    !held &&
    bench.mode == 0 &&
    // (a host that tells no events of its own (a picture decoded, a view ready) is read each build: every frame
    // built whole there)
    outside_told.val
  looks_base.left = left
  if looks_drawn.val || painted_alone.val {
    looks_base.ok = looks_base.ok && left
  } else {
    // (and it laid out what the one before it laid out, and told outside what that one told: built whole again, it
    // would lay out the same)
    looks_base.told_same = looks_tells.now == looks_tells.before
    looks_base.ok = left && paint_base.laid_same && looks_base.told_same
    looks_base.built_at = c.clock
  }
}

///|
/// Whether the frame is of its looks alone with nothing but lists moved by their headers written anew among the last
/// frame's instances (looks_frame): what the host draws again of it is found from those headers (h_present).
// kept across runs: false as each frame begins, and once it is presented
let looks_heads_only : Ref[Bool] = Ref(false)

///|
/// Whether the frame left its paint something to come (what its paint read changed as it was painted): the next frame
/// is asked for, to paint it.
fn paint_left() -> Bool {
  paint_said.val != ""
}

///|
/// The frame at `t` of the looks alone: the last frame's instances as painted, each look applied at `t`; when it is
/// drawn again is what the looks, the paint and the wakes asked before say. When it began (as frame_body's).
fn looks_frame(c : Ctx, t : Double) -> Double {
  perf_frame_start()
  let t0 = work_now()
  c.clock = t
  c.wants_frame = false
  c.cycling = false
  c.wake_at = looks_base.wake
  if paint_base.wake >= 0.0 && (c.wake_at < 0.0 || paint_base.wake < c.wake_at) {
    c.wake_at = paint_base.wake
  }
  // (and the moments the rows kept wait for: kept_part.mbt's KeptClock)
  dues_wake(c)
  if looks_base.looks {
    looks_base.inst.blit_to(c.inst, len=looks_base.n * inst_size)
    c.ninst = looks_base.n
    ride_spans.clear()
    ride_spans.append(looks_base.spans)
    looks_apply(c)
  } else if !list_heads.is_empty() {
    // (what columns scroll by their offsets alone moved by their headers, the rest as it was painted: list_looks; what
    // the host draws again of it found from those headers alone, h_present)
    looks_apply(c)
    looks_heads_only.val = true
  } else if view_resident_read() {
    // (the window's tree's endless decorations alone (View::cycle_resident): nothing of the old view by the clock, the
    // tree's resident step woken for as a frame built whole asks it, else the step asked for last, now come, is asked
    // again and the next never)
    looks_apply(c)
  }
  c.t_build = 0.0
  c.t_layout = 0.0
  c.t_paint = work_now() - t0
  looks_drawn.val = true
  painted_alone.val = false
  looks_frames.val = looks_frames.val + 1
  // (a frame as any: told at its end, as frame_paint tells the others)
  frame_hook_told(c)
  t0
}

///|
/// The frame at `t` painted alone: the last build's tree as it laid it out, painted again at `t` (what is worked out as
/// it is painted, at `t`: a look by Ctx::look_by, a picture's fade), its looks by the clock applied; when it is drawn
/// again is what its paint and the wakes its build asked say. When it began (as frame_body's).
fn paint_frame(c : Ctx, t : Double) -> Double {
  perf_frame_start()
  let t0 = work_now()
  c.clock = t
  c.wants_frame = false
  c.cycling = false
  c.read_back_moved = false
  c.frame_by = None
  c.wake_by = None
  c.wake_at = looks_base.wake
  dues_wake(c)
  paint_watch_of().read(fn() { frame_paint(c, paint_base.root, alone=true) })
  c.t_build = 0.0
  c.t_layout = 0.0
  c.t_paint = work_now() - t0
  looks_drawn.val = false
  painted_alone.val = true
  paints_alone.val = paints_alone.val + 1
  t0
}

///|
/// The frame at `t`: built whole under the run's watch where what the last read changed, a moment it waits for came
/// or it left something to come (why: built_why); else painted alone where what its paint read changed, a moment its
/// paint waits for came or the paint before drew otherwise (painted_why); else of its looks alone. When it began.
fn frame_drawn(c : Ctx, w : Double, h : Double, scale : Double, t : Double) -> Double {
  looks_heads_only.val = false
  // (where the hand's inputs since the frame before went, among the old views: view_host.mbt)
  let went_to = view_input_taken()
  let watch = frame_watch_of()
  let paint = paint_watch_of()
  let said = watch_said.val
  watch_said.val = ""
  let paint_told = paint_said.val
  paint_said.val = ""
  // (what was posted since the last frame taken: come from outside, it is handed on as the frame is built)
  messages_arrive()
  // (a Tester's fake host's answers come by the frame, told as it begins: what waits on them reads them)
  answers_by_the_frame()
  // (and what is taken as it comes, a pick's, a native call's: taken now into what reads it)
  takers_by_the_frame()
  // (what the host says of the streams and the native views, read of it each frame: what changed come from outside)
  streams_arrive()
  views_arrive()
  sites_arrive()
  // (what the system said of its notifications, read of it so: what reads it built again as it came, notify.mbt)
  notices_arrive()
  // (what came as the frame began told the window's tree: brought before what it does again is decided, where the old
  // views are placed part of that, and what a still pointer is over found so before the hand is said: view_host.mbt)
  view_arrived()
  // (the hand as the frame sees it: what read what changed of it told, hand.mbt)
  hand_arrive(c)
  // (what reads the clock and the host's settings read so: what read them is stale where they changed; what a part or
  // a list's row kept read of the frame and of a moment, told: kept_part.mbt's KeptClock)
  frame_clock.set(t)
  frame_settings_arrive(w, h, scale)
  clock_frame_start(t)
  // (the hand's discrete events since the frame before: what reads them takes them as it is built, and a frame that
  // takes one is built anew, its rows too: what took one changes as it is built what built before it read)
  // (the pointer's presses among them: hand_pressed)
  let events = @signals.untracked(fn() { hand.events.get() + hand.presses.get() })
  let typed = hand.typed.untracked()
  let evented = events != events_seen.val || typed != typed_seen.val
  // (what was typed into a field of an old view, and nothing else of the hand's: a part kept through it, built anew
  // for anything else that came, Ctx::kept_part's `typed_stays`)
  let typed_alone = events == events_seen.val && typed != typed_seen.val
  events_seen.val = events
  typed_seen.val = typed
  // (and what came from outside that is no signal: a part kept whatever else the frame built anew is built anew for it)
  let outside = outside_events.val != outside_seen.val
  outside_seen.val = outside_events.val
  // (the motions that read the clock as the last frame was built, laid out or painted: named as said here)
  built_motion.val = ""
  let said_clock = fn(at : String, who : Mover?) {
    let words = clock_said(at, who)
    if words != at {
      built_motion.val = words
    }
    words
  }
  let (part_at, part_who) = (part_clock_at.val, part_clock_who.val)
  part_clock_at.val = ""
  part_clock_who.val = None
  let why = if said != "" {
    said
  } else if bench_whole.val && bench_measuring.val {
    "a bench building each frame whole"
  } else if watch.is_stale() {
    if clock_read_at.val != "" {
      "the clock read at \{said_clock(clock_read_at.val, clock_read_who.val)}"
    } else {
      "what it read changed" + (if frame_told_at.val != "" { ", set at \{frame_told_at.val}" } else { "" })
    }
  } else if !looks_base.left {
    "it left more to come"
  } else if !looks_base.told_same {
    "it told outside otherwise"
  } else if looks_base.wake >= 0.0 && t >= looks_base.wake {
    "a moment it waits for came, asked at \{looks_base.wake_by}"
  } else {
    ""
  }
  // (else laid out again, built as it was built, its lists' rows kept where nothing they show changed: what its layout
  // read changed, what a row read, or the one before it laid out otherwise, what built may read)
  let mut laid_why = if why != "" {
    ""
  } else if layout_said.val != "" {
    layout_said.val
  } else if layout_watch_of().is_stale() {
    if layout_clock_at.val != "" {
      "the clock read as it was laid out at \{said_clock(layout_clock_at.val, layout_clock_who.val)}"
    } else {
      "what its layout read changed"
    }
  } else if nodes_run.told {
    let part = c.told_said()
    "what a part or a list's row read changed" +
    (if part != "" { ", \{part}" } else { "" }) +
    (match nodes_run.told_at {
      Some(at) => ", set at \{at}"
      None => ""
    }) +
    (if part_at != "" { ", the clock read in it at \{said_clock(part_at, part_who)}" } else { "" })
  } else if !paint_base.laid_same {
    laid_otherwise
  } else {
    ""
  }
  // (a list the hand moved, its rows staying: moved as they are, nothing built or laid out for it, what follows where
  // it stands told again; what was built reads where it stands only as list_hand_move asks it. The build before having
  // laid out otherwise is no reason to build: what it read back of that layout is asked there too)
  let mut list_scrolled = false
  // (an old view's list the hand moved: what is drawn in it moved with nothing it read told, no old view kept as drawn
  // in this frame, view_ride.mbt's island_still)
  old_lists_moved.val = !list_hand_dirty.is_empty()
  if old_lists_moved.val {
    islands_unkept()
  }
  if why == "" && (laid_why == "" || laid_why == laid_otherwise) && !list_hand_dirty.is_empty() {
    let stopped = c.list_hand_move(t)
    if stopped == "" {
      list_scrolled = true
      laid_why = ""
      // (what follows where a list stands told, as a build's are once it is laid out, before it is painted: what they
      // change of what is built shows from the next frame)
      for f in list_fast_tells {
        f()
      }
    } else {
      laid_why = "a list moved (" + stopped + ")"
    }
  }
  built_why.val = if why != "" { why } else { laid_why }
  frame_told_at.val = ""
  build_causes.clear()
  for m in frame_told_moments {
    build_causes.push(m)
  }
  build_told_more.val = !frame_told_moments.is_empty() && frame_start_sets.val > told_sets.val
  frame_told_moments.clear()
  frame_built.val = true
  if why != "" || laid_why != "" {
    looks_drawn.val = false
    painted_alone.val = false
    painted_why.val = ""
    layout_said.val = ""
    // (to be laid out: what its layout read told before, as what came for the frame is taken, it reads anew)
    layout_coming.val = true
    nodes_run.told = false
    nodes_run.fresh = why != "" || evented
    nodes_run.evented = evented || outside
    // (the hand's alone, gone to one old view: that one's part alone built for it, view_host.mbt)
    nodes_run.evented_only = if outside { -1 } else { went_to }
    // (and the frame after it, built for what that changed late in it (app.mbt's `inputs_taken`), nothing else come
    // meanwhile: the same)
    let typed_on = !evented && went_to < 0 && typed_frame_last.val >= 0
    nodes_run.typed_alone = !outside && ((typed_alone && went_to >= 0) || typed_on)
    if typed_on && !outside {
      nodes_run.evented_only = typed_frame_last.val
    }
    typed_frame_last.val = if nodes_run.typed_alone && !typed_on { nodes_run.evented_only } else { -1 }
    nodes_run.whole = bench_whole.val && bench_measuring.val
    let t0 = watch.read(fn() { frame_body_drawn(c, t) })
    frame_looked(c, w, h, scale, t, 0, false)
    return t0
  }
  typed_frame_last.val = -1
  // (what the window's tree was told as the frame went, brought before it is decided whether to paint: what that
  // changed of it painted, what changed nothing of it not: view_brought)
  view_arrived()
  let paint_why = if list_scrolled {
    "a list scrolled without changing its rows"
  } else if paint_told != "" {
    paint_told
  } else if paint.is_stale() {
    if paint_clock_at.val != "" {
      "the clock read as it was painted at \{said_clock(paint_clock_at.val, paint_clock_who.val)}"
    } else if view_due_at.val != "" {
      "the window's tree had something to do, set at \{view_due_at.val}"
    } else {
      "what its paint read changed"
    }
  } else if !looks_base.settled {
    "the paint before it drew otherwise"
  } else if paint_base.wake >= 0.0 && t >= paint_base.wake {
    "a moment its paint waits for came"
  } else {
    ""
  }
  painted_why.val = paint_why
  let t0 = if paint_why != "" { paint_frame(c, t) } else { looks_frame(c, t) }
  frame_looked(c, w, h, scale, t, if paint_why != "" { 1 } else { 2 }, list_scrolled)
  t0
}

///|
/// What looks at each frame as it is drawn, where something does (a Tester's: tester_looks.mbt): the frame `c` at `t`
/// in a window `w` × `h` at `scale`, built whole (`kind` 0), painted alone (1) or of its looks alone (2), a list moved
/// in it with nothing built (`scrolled`).
// kept across runs: set by each Tester as it is made, let go as its run ends
let frame_look : Ref[((Ctx, Double, Double, Double, Double, Int, Bool) -> Unit)?] = Ref(None)

///|
fn frame_looked(c : Ctx, w : Double, h : Double, scale : Double, t : Double, kind : Int, scrolled : Bool) -> Unit {
  match frame_look.val {
    Some(f) => f(c, w, h, scale, t, kind, scrolled)
    None => ()
  }
}

///|
/// How many of the hand's discrete events the frame before had seen (hand.mbt's `events`).
// kept across runs: only counts on with them
let events_seen : Ref[Int] = Ref(0)

///|
/// The old view's part what was typed alone went to in the frame before (nodes_run's `typed_alone`), -1: none, or that
/// frame was the one after it.
// kept across runs: said as each frame is built
let typed_frame_last : Ref[Int] = Ref(-1)

///|
/// How many times the frame before had seen something typed into a field of an old view (hand.mbt's `typed`).
// kept across runs: only counts on with them
let typed_seen : Ref[Int] = Ref(0)

///|
/// How many events from outside the frame before had seen (kept_part.mbt's `outside_events`).
// kept across runs: only counts on with them
let outside_seen : Ref[Int] = Ref(0)

///|
/// A step of a test's (Tester::frame, Tester::run_for), or a change of how frames are drawn (a Tester's or a run's
/// measure: all that shows only while lit shown, what draws each instance kept): what it changed of what is no signal
/// shows at the next frame, which is built whole; no frame is asked for by it, what changed it draws its own. What it
/// changed of what is no signal (a made-up core's state, a page opened by hand) is taken as an event from outside is
/// (outside_events): parts kept whatever else the frame built anew built anew for it too (NodesRun's `evented`).
fn test_stepped() -> Unit {
  frame_watch_of().touch()
  outside_events.val = outside_events.val + 1
}

///|
/// How far node `i` is placed off where it is laid out by what places it and what holds it by the clock
/// (Ctx::moved_by), all of them together.
fn moved_over(c : Ctx, i : Int) -> (Double, Double) {
  let mut x = 0.0
  let mut y = 0.0
  let mut p = i
  while p >= 0 {
    let n = c.nodes[p]
    x = x + n.moved_x
    y = y + n.moved_y
    p = n.parent
  }
  (x, y)
}

///|
/// What the frame's build read changed (the run's watch, or an old view's own: view_host.mbt), `set_as_read` saying
/// where it was set as it was read: a frame owed (as the frame begins, before it is built: the frame itself sees it,
/// frame_drawn; as it was built: the next frame, built from it, said where, Tester::assert_idle; between frames, the
/// host asked now).
fn frame_read_told(set_as_read : () -> Array[String]) -> Unit {
  if frame_running.val && !frame_built.val {
    watch_told_at()
  } else if frame_running.val {
    g().wants_frame = true
    watch_told_moment()
    let by = set_as_read()
    watch_said.val = if by.is_empty() {
      "a value it read changed as the frame ended, set at \{@signals.last_set_at()}"
    } else {
      "a value it read set again as it was built, at " + by.join(", ")
    }
  } else {
    watch_told_at()
    h_frame_owed()
  }
}
