// What a frame does again, by what it read (docs/incremental.md). A frame's work, from taking what came from outside
// to the end of its paint, runs under one watch (mbui/signals' Watch): all it reads of signals is followed, and that is
// all it is built from: the core's data and the app's state, the frames' clock (frame_clock: Ctx::now), the host's
// settings it is drawn by (frame_env), what came from outside that is no signal yet (outside_said: what
// docs/determinism.md records, a message, a host's event, a step of the runtime's, a frame asked for between frames)
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
// for 0.03% of it). Where the Tester runs (looks_check), each frame painted alone or of its looks alone is drawn whole
// after it as well and the two must be the same: every test holds it.

///|
/// Where what the frames' watch was first told of since the frame before was set (Signal::set's place; "" none): said
/// with why the next frame is built.
// kept across runs: put back as each frame is decided
let frame_told_at : Ref[String] = Ref("")

///|
/// The frames' watch told between frames or as one begins: where, the first time since the frame before.
fn watch_told_at() -> Unit {
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
/// What of the host the frame is drawn by and reads as it is built (looks_env), as each frame begins.
// kept across runs: set as each frame begins
let frame_env : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

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
/// The run's watch: as what its last read read changes, a frame is owed (in a frame, by its end; between frames, the
/// host asked now).
fn frame_watch_of() -> @signals.Watch {
  match frame_watch.val {
    Some(w) => w
    None => {
      let w = @signals.watch(fn() {
        if frame_running.val && !frame_built.val {
          // (as the frame begins, before it is built: the frame itself sees it, frame_drawn)
          watch_told_at()
        } else if frame_running.val {
          // (what it read set again as it was built: the next frame is built from it, said where: Tester::assert_idle)
          g().wants_frame = true
          let by = match frame_watch.val {
            Some(w) => w.set_as_read()
            None => []
          }
          watch_said.val = if by.is_empty() {
            "a value it read changed as the frame ended, set at \{@signals.last_set_at()}"
          } else {
            "a value it read set again as it was built, at " + by.join(", ")
          }
        } else {
          watch_told_at()
          h_frame_owed()
        }
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
    clock_read_by(loc.to_string())
    frame_clock.get() |> ignore
  }
}

///|
/// The clock read followed by what shows a motion going (Ctx::shows_motion).
fn clock_read_here() -> Unit {
  if @signals.active_sub() is Some(_) {
    clock_read_by("a motion, the host's clock or its state (Ctx::shows_motion, @ui.now, @hostapi.polled)")
    frame_clock.get() |> ignore
  }
}

///|
/// Where the clock was read followed (`at`), kept as the first such read of the frame's build or of its paint.
fn clock_read_by(at : String) -> Unit {
  let first = if paint_phase.val == 1 {
    paint_clock_at
  } else if laying.val {
    layout_clock_at
  } else {
    clock_read_at
  }
  if first.val == "" {
    first.val = at
  }
}

///|
/// What the host keeps and changes with no event of its own, read (@hostapi.polled: a browser come back to a login),
/// is followed as the clock is: what reads it as it is built is built again each frame while it does.
fn init {
  @hostapi.polled.val = fn() { clock_read_here() }
}

///|
/// The frames' clock (ms), followed only before `end` (Ctx::now): what moves till then and is still from then on (a
/// spring's way, a fade), built again each frame till it is.
#callsite(autofill(loc))
pub fn Ctx::now_before(self : Ctx, end : Double, loc~ : SourceLoc) -> Double {
  if self.clock < end {
    clock_read(loc)
  }
  self.clock
}

///|
/// What came from outside and is no signal: what each frame's build reads (outside_said) built again.
fn outside_counted() -> Unit {
  outside_said.set(@signals.untracked(fn() { outside_said.get() }) + 1)
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
/// What the frame reads of what came from outside and of the host's settings, as it has taken them (frame_body):
/// followed. (Of the hand, what reads it reads it: hand.mbt.)
fn frame_inputs_read() -> Unit {
  outside_said.get() |> ignore
  frame_env.get() |> ignore
}
///|
/// The last frame as its paint ended (looks_keep): its instances, with the tags of its looks by the clock before they
/// were applied (`looks`: it has some); whether the next may be built from nothing it did not read (it left nothing to
/// come of its own: looks_left); the soonest moment anything but a look or a paint asked to be drawn at (-1: none),
/// from its build on.
priv struct LooksBase {
  /// its instances, kept only where it has looks (a frame of the looks alone draws them again); what they were said
  /// as one number (insts_said), for the next paint to know whether it drew the same
  mut inst : FixedArray[Double]
  mut said : Int64
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
  said: 0L,
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
/// Whether each frame painted alone or of the looks alone is drawn whole after it as well and the two compared (a
/// Tester's: every test holds it); a host draws it once.
// kept across runs: set by each Tester as it is made (Tester::new), a bench's turned off
let looks_check : Ref[Bool] = Ref(false)

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
/// Put back as a run begins (reset_globals): the run's watches let go, the first frame built whole.
fn looks_reset() -> Unit {
  nodes_forget()
  layout_said.val = ""
  frame_told_at.val = ""
  layout_clock_at.val = ""
  for w in [frame_watch, layout_watch, paint_watch] {
    match w.val {
      Some(w) => w.stop()
      None => ()
    }
    w.val = None
  }
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
  in_looks.val = false
}

///|
/// What of the host the frame is drawn by and its build reads (the window, its scale, the system's settings as
/// envrec.mbt records them, the faces' atlas, whether something reads the widgets out, the layout's epoch), as one line.
fn looks_env(c : Ctx, w : Double, h : Double, scale : Double) -> String {
  "\{w} \{h} \{scale} \{whole_px_layout()} \{font_scale()} \{h_atlas_generation()} \{h_a11y_on()} \{reduced_motion()} \{h_reduce_transparency()} \{system_dark()} \{window_inset()} \{h_h264_here()} \{h_stream_feeds()} \{h_stream_layers()} \{copy_shown()} \{layout_reuse.val} \{c.epoch} \{view_island_said()}"
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
/// `x` folded into `h` as tree_sig folds a length: to 1/64 of a point.
fn sig_num(h : Int64, x : Double) -> Int64 {
  hash_mix(h, (x * 64.0).round().to_int64())
}

///|
/// The frame's paint is over, its looks by the clock not applied yet (frame_paint): what it drew kept (with their tags,
/// where it has looks), for a frame of the looks alone; whether it drew what the paint before it drew.
fn looks_keep(c : Ctx) -> Unit {
  if looks_check.val {
    looks_nodes.clear()
    for i in 0..<c.count {
      let nd = c.nodes[i]
      looks_nodes.push((nd.x, nd.y, nd.fw, nd.fh, nd.text, nd.id, nd.tx, nd.ty, nd.opacity))
    }
  }
  // (what it drew said as one number, read once: not kept whole and compared with the paint before, two more passes
  // over every instance; kept whole only where a frame of the looks alone draws it again)
  let len = c.ninst * inst_size
  let said = insts_said(c.inst, c.ninst)
  looks_base.settled = looks_base.built && c.ninst == looks_base.n && said == looks_base.said
  looks_base.built = true
  looks_base.n = c.ninst
  looks_base.said = said
  looks_base.looks = !cycle_frame.is_empty()
  if looks_base.looks {
    if looks_base.inst.length() < len {
      looks_base.inst = FixedArray::make(len, 0.0)
    }
    c.inst.blit_to(looks_base.inst, len~)
  }
}

///|
/// The first `n` instances of `a` as one number (64 bits of FNV-1a over their numbers' bits): the same for instances
/// drawn the same (the tags of the looks by the clock, slot 20 below 0, all one: a tag each paint gives anew,
/// cycle_look.mbt; every NaN one).
fn insts_said(a : FixedArray[Double], n : Int) -> Int64 {
  // (four lanes, each folding every fourth number: one lane's multiply need not wait for the last, the lanes folded
  // into one at the end)
  let mut h0 = -3750763034362895579L
  let mut h1 = h0
  let mut h2 = h0
  let mut h3 = h0
  let end = n * inst_size
  let mut k = 0
  while k < end {
    let j = k % inst_size
    h0 = (h0 ^ inst_bits(a[k], j)) * 1099511628211L
    h1 = (h1 ^ inst_bits(a[k + 1], j + 1)) * 1099511628211L
    h2 = (h2 ^ inst_bits(a[k + 2], j + 2)) * 1099511628211L
    h3 = (h3 ^ inst_bits(a[k + 3], j + 3)) * 1099511628211L
    k = k + 4
  }
  (((h0 * 31L) ^ h1) * 31L ^ h2) * 31L ^ h3
}

///|
/// An instance's number `x` in its slot `j` as insts_said folds it: its bits; a tag of a look by the clock (slot 20
/// below 0) all one; every NaN one.
fn inst_bits(x : Double, j : Int) -> Int64 {
  if x != x {
    -2L
  } else if j == 20 && x < 0.0 {
    -1L
  } else {
    x.reinterpret_as_int64()
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
    (fake.val is Some(_) || outside_told.val)
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
    looks_apply(c)
  }
  c.t_build = 0.0
  c.t_layout = 0.0
  c.t_paint = work_now() - t0
  looks_drawn.val = true
  painted_alone.val = false
  looks_frames.val = looks_frames.val + 1
  // (a frame as any: told at its end, as frame_paint tells the others)
  match frame_hook.val {
    Some(f) if !looks_rebuilt.val => f()
    _ => ()
  }
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
/// paint waits for came or the paint before drew otherwise (painted_why); else of its looks alone. Where looks_check
/// says, one painted alone or of the looks alone is built whole after it as well and the two compared, the test failing
/// where they differ. When it began.
fn frame_drawn(c : Ctx, w : Double, h : Double, scale : Double, t : Double) -> Double {
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
  // (what the host says of the streams and the native views, read of it each frame: what changed come from outside)
  streams_arrive()
  views_arrive()
  // (the hand as the frame sees it: what read what changed of it told, hand.mbt)
  hand_arrive(c)
  // (what reads the clock and the host's settings read so: what read them is stale where they changed; what a part or
  // a list's row kept read of the frame and of a moment, told: kept_part.mbt's KeptClock)
  frame_clock.set(t)
  frame_env.set(looks_env(c, w, h, scale))
  clock_frame_start(t)
  // (the hand's discrete events since the frame before: what reads them takes them as it is built, and a frame that
  // takes one is built anew, its rows too: what took one changes as it is built what built before it read)
  let events = @signals.untracked(fn() { hand.events.get() })
  let evented = events != events_seen.val
  events_seen.val = events
  // (and what came from outside that is no signal: a part kept whatever else the frame built anew is built anew for it)
  let outside = outside_events.val != outside_seen.val
  outside_seen.val = outside_events.val
  let why = if said != "" {
    said
  } else if bench_whole.val && bench_measuring.val {
    "a bench building each frame whole"
  } else if watch.is_stale() {
    if clock_read_at.val != "" {
      "the clock read at \{clock_read_at.val}"
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
  let laid_why = if why != "" {
    ""
  } else if layout_said.val != "" {
    layout_said.val
  } else if layout_watch_of().is_stale() {
    if layout_clock_at.val != "" {
      "the clock read as it was laid out at \{layout_clock_at.val}"
    } else {
      "what its layout read changed"
    }
  } else if nodes_run.told {
    "what a part or a list's row read changed"
  } else if !paint_base.laid_same {
    "the one before it laid out otherwise"
  } else {
    ""
  }
  built_why.val = if why != "" { why } else { laid_why }
  frame_told_at.val = ""
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
    nodes_run.evented = evented || outside || test_step_came.val
    // (the hand's alone, gone to one old view: that one's part alone built for it, view_host.mbt)
    nodes_run.evented_only = if outside || test_step_came.val { -1 } else { went_to }
    test_step_came.val = false
    nodes_run.whole = bench_whole.val && bench_measuring.val
    return watch.read(fn() { frame_body(c, w, h, scale, t) })
  }
  let paint_why = if paint_told != "" {
    paint_told
  } else if paint.is_stale() {
    if paint_clock_at.val != "" {
      "the clock read as it was painted at \{paint_clock_at.val}"
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
  if !looks_check.val {
    return t0
  }
  let n = c.ninst
  let alone = FixedArray::make(n * inst_size + 1, 0.0)
  c.inst.blit_to(alone, len=n * inst_size)
  let wake = looks_own.wake
  let cycling = looks_own.cycling
  let then = looks_nodes.copy()
  let painted = painted_alone.val
  // (built whole as a frame begins: what the paint alone read, read anew by its paint; no row kept)
  paint_phase.val = 0
  nodes_run.fresh = true
  nodes_run.whole = true
  looks_rebuilt.val = true
  watch.read(fn() { frame_body(c, w, h, scale, t) }) |> ignore
  looks_rebuilt.val = false
  looks_drawn.val = false
  painted_alone.val = false
  looks_compare(c, alone, n, wake, cycling, t, then, painted~)
  t0
}

///|
/// Whether the frame is being built whole again to be compared with it as it was painted alone or of its looks alone
/// (looks_check): a check's, no frame of the app's (frame_hook is not told of it).
// kept across runs: set and let go within a frame
let looks_rebuilt : Ref[Bool] = Ref(false)

///|
/// How many of the hand's discrete events the frame before had seen (hand.mbt's `events`).
// kept across runs: only counts on with them
let events_seen : Ref[Int] = Ref(0)

///|
/// How many events from outside the frame before had seen (kept_part.mbt's `outside_events`).
// kept across runs: only counts on with them
let outside_seen : Ref[Int] = Ref(0)

///|
/// The frame painted alone or of the looks alone (`painted`; `alone`, `n` instances; its looks asking to be woken at
/// `wake`, or drawn each frame: `cycling`) against the same frame built whole (`c`'s): the same instances, its looks
/// asking the same, else the test fails, saying where they part: the first instance that differs (what it is and
/// where), and how many each drew.
fn looks_compare(
  c : Ctx,
  alone : FixedArray[Double],
  n : Int,
  wake : Double,
  cycling : Bool,
  t : Double,
  then : Array[(Double, Double, Double, Double, String, Int, Double, Double, Double)],
  painted~ : Bool,
) -> Unit {
  let at = t.to_int()
  let kind = if painted { "painted alone" } else { "of its looks alone" }
  let m = c.ninst
  let mut first = -1
  let mut slot = -1
  for q in 0..<(if n < m { n } else { m }) {
    let b = q * inst_size
    for j in 0..<inst_size {
      let x = alone[b + j]
      let y = c.inst[b + j]
      if first < 0 && !drawn_same(x, y) {
        first = q
        slot = j
      }
    }
  }
  if first < 0 && n != m {
    first = if n < m { n } else { m }
  }
  if first >= 0 {
    let inst = fn(a : FixedArray[Double], q : Int, k : Int) {
      if q >= k {
        "none"
      } else {
        let b = q * inst_size
        "kind \{a[b + 5]} at \{a[b]},\{a[b + 1]} \{a[b + 2]}×\{a[b + 3]}" +
        (if slot >= 0 { " (slot \{slot}: \{a[b + slot]})" } else { "" })
      }
    }
    // (what is drawn there, as built whole: the words of the nodes over the place)
    let (px, py) = if first < m {
      (c.inst[first * inst_size], c.inst[first * inst_size + 1])
    } else {
      (alone[first * inst_size], alone[first * inst_size + 1])
    }
    let there = []
    for i in 0..<c.count {
      let nd = c.nodes[i]
      if nd.text != "" && px >= nd.x - 1.0 && px <= nd.x + nd.fw + 1.0 && py >= nd.y - 1.0 && py <= nd.y + nd.fh + 1.0 {
        there.push(nd.text)
      }
    }
    looks_fail(
      "the frame at \{at} ms \{kind} (\{n} instances) parts from it built whole (\{m}) at instance \{first}: \{inst(alone, first, n)}, built whole \{inst(c.inst, first, m)}; words there: \{there.join(" | ")}; \{looks_node_moved(c, then)}",
    )
  }
  if cycling != looks_own.cycling || wake != looks_own.wake {
    let next = fn(cy : Bool, w : Double) { if cy { "each frame" } else { "at \{w}" } }
    looks_fail(
      "the frame at \{at} ms \{kind} has its looks ask for the next \{next(cycling, wake)}, built whole \{next(looks_own.cycling, looks_own.wake)}",
    )
  }
}

///|
/// Where the nodes of the frame a frame of its looks alone is drawn from were laid out (x, y, w, h), their words and
/// ids, kept where they are compared (looks_check): where it parts from the frame built whole, the first node laid out
/// elsewhere is said.
// kept across runs: written by each frame built whole while looks_check is on
let looks_nodes : Array[(Double, Double, Double, Double, String, Int, Double, Double, Double)] = []

///|
/// The first node laid out elsewhere in `c` than in the frame the looks alone were drawn from (looks_nodes), said.
fn looks_node_moved(
  c : Ctx,
  then : Array[(Double, Double, Double, Double, String, Int, Double, Double, Double)],
) -> String {
  if then.length() != c.count {
    return "\{then.length()} nodes then, \{c.count} now"
  }
  for i in 0..<c.count {
    let nd = c.nodes[i]
    let (x, y, w, h, text, id, tx, ty, op) = then[i]
    if nd.x != x ||
      nd.y != y ||
      nd.fw != w ||
      nd.fh != h ||
      nd.text != text ||
      nd.id != id ||
      nd.tx != tx ||
      nd.ty != ty ||
      nd.opacity != op {
      // (what it holds: the words under it)
      let words = []
      let mut j = nd.first
      while j >= 0 && words.length() < 4 {
        if c.nodes[j].text != "" {
          words.push(c.nodes[j].text)
        }
        j = c.nodes[j].next
      }
      let mut up = nd.parent
      let mut above = ""
      while up >= 0 && above == "" {
        let mut k = c.nodes[up].first
        while k >= 0 && above == "" {
          if c.nodes[k].text != "" {
            above = c.nodes[k].text
          }
          k = c.nodes[k].next
        }
        up = c.nodes[up].parent
      }
      return "node \{i} (id \{id}, \{text}) at \{x},\{y} \{w}×\{h} moved \{tx},\{ty} alpha \{op} then, \{nd.x},\{nd.y} \{nd.fw}×\{nd.fh} moved \{nd.tx},\{nd.ty} alpha \{nd.opacity} now; words in it: \{words.join(" | ")}; near: \{above}"
    }
  }
  "every node where it was"
}

///|
/// Where the Tester whose frames are compared was made (Tester::new's `loc`).
// kept across runs: set by each Tester as it is made
let looks_made_at : Ref[String] = Ref("")

///|
fn looks_fail(s : String) -> Unit {
  let said = "a frame not built whole (frame_watch.mbt), the Tester made at \{looks_made_at.val}: " +
    s +
    " (built whole last at \{looks_base.built_at.to_int()} ms\{if wall_read.val { "; the time of day read as it was built" } else { "" }}; what is said to move: \{g().moving_now().join("; ")})"
  println(said)
  abort(said)
}

///|
/// Whether each frame of the looks alone is drawn whole after it as well and the two compared (on in every Tester:
/// frame_watch.mbt's head): off for a run measured as a host runs it (mbui/src/film's bench).
pub fn Tester::check_looks(self : Tester, on : Bool) -> Unit {
  ignore(self)
  looks_check.val = on
}

///|
/// Why the last frame was built whole ("" where it was of its looks alone): it left more to come of its own, what it
/// read changed (the clock, where it read it so), a moment it waits for came.
pub fn Tester::built_why(self : Tester) -> String {
  ignore(self)
  built_why.val
}

///|
/// Why the last frame was painted alone, from the last build's tree ("" where it was built whole or of its looks
/// alone): what its paint read changed (the clock, where it read it so), a moment its paint waits for came, the paint
/// before it drew otherwise.
pub fn Tester::painted_why(self : Tester) -> String {
  ignore(self)
  painted_why.val
}

///|
/// A step of a test's (Tester::frame, Tester::run_for), or a change of how frames are drawn (a Tester's or a run's
/// measure: all that shows only while lit shown, what draws each instance kept): what it changed of what is no signal
/// shows at the next frame, which is built whole; no frame is asked for by it, what changed it draws its own.
fn test_stepped() -> Unit {
  frame_watch_of().touch()
  test_step_came.val = true
}

///|
/// A step of the test's came since the frame before (test_stepped): what the test changed of what is no signal (a
/// made-up core's state, a page opened by hand) is taken as an event from outside is, parts kept whatever else the frame
/// built anew built anew for it too (NodesRun's `evented`).
// kept across runs: set by each step of a test's, taken as the frame decides what it does
let test_step_came : Ref[Bool] = Ref(false)

///|
/// Whether two numbers of an instance draw the same: equal, both none (NaN), or apart by no more than the rounding of
/// adding a move to what was placed as laid out (Ctx::moved_place) leaves, a billionth of them: nothing a pixel shows.
fn drawn_same(x : Double, y : Double) -> Bool {
  x == y || (x.is_nan() && y.is_nan()) || (x - y).abs() <= 1.0e-9 * dmax(1.0, dmax(x.abs(), y.abs()))
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
