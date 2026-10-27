// What a frame does again, by what it read (docs/incremental.md). A frame's work, from taking what came from outside
// to the end of its paint, runs under one watch (mbui/signals' Watch): all it reads of signals is followed, and that is
// all it is built from: the core's data and the app's state, the frames' clock (frame_clock: Ctx::now), the host's
// settings it is drawn by (frame_env), what came from outside that is no signal yet (outside_said: what
// docs/determinism.md records, a message, a host's event, a step of the runtime's, a frame asked for between frames)
// and the hand's input (inputs_said). So the next frame is built anew where any of it changed (the watch is stale),
// where a moment it read the clock as came (a wake: Ctx::wake_in, Ctx::every, a cycle's step), or where it asked for
// another itself (a frame asked for, a motion going, a fiber stepping a frame at a time, a layout read back that
// moved). Nothing is listed: what was not read changes nothing, what was read is followed by the read itself.
//
// Else, and once the last two frames built whole drew the same (what a build leaves for the next to read, a size it
// measured, a place it was drawn at, has settled: no more frames would change it), nothing it shows changes but its
// looks by the clock (cycle_look.mbt: a spinner turning, the spokes stepping, a breath): the frame is the last one's
// instances as they were painted, each look applied at its time, nothing built, laid out or painted (2026-10-27: ~16
// frames a second while chats are at work, each building, laying out and painting the window for 0.03% of it). Where
// the Tester runs (looks_check), each such frame is drawn whole after it as well and the two must be the same: every
// test holds it.

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
/// The hand's inputs, counted (input_came): what the frame takes of them it reads as it begins.
// kept across runs: only counts on
let inputs_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// What of the host the frame is drawn by and reads as it is built (looks_env), as each frame begins.
// kept across runs: set as each frame begins
let frame_env : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

///|
/// The watch the frames' work runs under (made with the run: frame_watch_of).
// kept across runs: let go and made anew as a run begins (looks_reset)
let frame_watch : Ref[@signals.Watch?] = Ref(None)

///|
/// Where the last frame built first read the clock followed ("" none): why the next is built again.
// kept across runs: put back as each frame is built
let clock_read_at : Ref[String] = Ref("")

///|
/// Whether the last frame built read the time of day (@ui.wall_ms), not followed: what shows it reads it as a moment
/// (Ctx::every).
// kept across runs: put back as each frame is built
let wall_read : Ref[Bool] = Ref(false)

///|
/// Why the last frame was built whole ("" not: one of its looks alone).
// kept across runs: written by each frame
let built_why : Ref[String] = Ref("")

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
          ()
        } else if frame_running.val {
          // (what it read set again as it was built: the next frame is built from it, said where: Tester::assert_idle)
          g().wants_frame = true
          let by = match frame_watch.val {
            Some(w) => w.set_as_read()
            None => []
          }
          watch_said.val = if by.is_empty() {
            "a value it read changed as the frame ended"
          } else {
            "a value it read set again as it was built, at " + by.join(", ")
          }
        } else {
          h_frame_owed()
        }
      })
      frame_watch.val = Some(w)
      w
    }
  }
}

///|
/// The clock read followed where something reads (Ctx::now: a frame's build or paint, a computed), `loc` the reader.
fn clock_read(loc : SourceLoc) -> Unit {
  if @signals.active_sub() is Some(_) {
    if clock_read_at.val == "" {
      clock_read_at.val = loc.to_string()
    }
    frame_clock.get() |> ignore
  }
}

///|
/// The clock read followed by what shows a motion going (Ctx::shows_motion).
fn clock_read_here() -> Unit {
  if @signals.active_sub() is Some(_) {
    if clock_read_at.val == "" {
      clock_read_at.val = "a motion, the host's clock or its state (Ctx::shows_motion, @ui.now, @hostapi.polled)"
    }
    frame_clock.get() |> ignore
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
/// An input of the hand's came: what each frame reads of the hand (inputs_said) built again.
fn inputs_told() -> Unit {
  inputs_said.set(@signals.untracked(fn() { inputs_said.get() }) + 1)
}

///|
/// What the frame reads of what came from outside and of the hand, as it has taken them (frame_body): followed.
fn frame_inputs_read() -> Unit {
  outside_said.get() |> ignore
  inputs_said.get() |> ignore
  frame_env.get() |> ignore
}

///|
/// The last frame as its paint ended (looks_keep): its instances, with the tags of its looks by the clock before they
/// were applied (`looks`: it has some); whether the next may be of its looks alone (it left nothing to come but them:
/// looks_left); the soonest moment anything but a look asked to be drawn at (-1: none), from its build on.
priv struct LooksBase {
  mut inst : FixedArray[Double]
  mut n : Int
  mut looks : Bool
  mut ok : Bool
  mut wake : Double
  /// when the frame was last built whole (ms)
  mut built_at : Double
  /// whether it drew what the frame built whole before it drew (`built`: there was one): what a build leaves for the
  /// next one to read (a size it measured, a place it was drawn at) has settled, built again it draws the same
  mut built : Bool
  mut settled : Bool
}

///|
// kept across runs: put back with the globals (looks_reset), else made again by each frame built whole
let looks_base : LooksBase = {
  inst: FixedArray::make(0, 0.0),
  n: 0,
  looks: false,
  ok: false,
  wake: -1.0,
  built_at: -1.0,
  built: false,
  settled: false,
}

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
/// Whether each frame of the looks alone is drawn whole after it as well and the two compared (a Tester's: every test
/// holds it); a host draws it once.
// kept across runs: set by each Tester as it is made (Tester::new), a bench's turned off
let looks_check : Ref[Bool] = Ref(false)

///|
/// Whether the last frame was of its looks alone: what the frame did (FramePerf's `looks`).
// kept across runs: written by each frame
let looks_drawn : Ref[Bool] = Ref(false)

///|
/// How many frames of the looks alone were drawn (a test's: those drawn whole after them as well are counted too).
// kept across runs: only counts on
let looks_frames : Ref[Int] = Ref(0)

///|
/// Put back as a run begins (reset_globals): the run's watch let go, the first frame built whole.
fn looks_reset() -> Unit {
  match frame_watch.val {
    Some(w) => w.stop()
    None => ()
  }
  frame_watch.val = None
  looks_base.n = 0
  looks_base.looks = false
  looks_base.ok = false
  looks_base.wake = -1.0
  looks_base.built = false
  looks_base.settled = false
  looks_tells.now = []
  looks_tells.before = []
  looks_drawn.val = false
  clock_read_at.val = ""
}

///|
/// As a frame built whole begins: no wake but a look's asked yet, the clock not read.
fn looks_frame_start() -> Unit {
  looks_base.ok = false
  looks_base.wake = -1.0
  clock_read_at.val = ""
  wall_read.val = false
}

///|
/// A wake at `t` asked (Ctx::wake_at_time): the looks' own, as they are applied; else the soonest anything else asked
/// for, kept for the frames of the looks alone to come.
fn looks_wake(t : Double) -> Unit {
  if in_looks.val {
    if looks_own.wake < 0.0 || t < looks_own.wake {
      looks_own.wake = t
    }
  } else if looks_base.wake < 0.0 || t < looks_base.wake {
    looks_base.wake = t
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
  "\{w} \{h} \{scale} \{whole_px_layout()} \{font_scale()} \{h_atlas_generation()} \{h_a11y_on()} \{reduced_motion()} \{h_reduce_transparency()} \{system_dark()} \{window_inset()} \{h_h264_here()} \{h_stream_feeds()} \{h_ime_inset()} \{copy_shown()} \{layout_reuse.val} \{c.epoch}"
}

///|
/// The frame's paint is over, its looks by the clock not applied yet (frame_body): what it drew kept (with their tags,
/// where it has looks), for a frame of the looks alone.
fn looks_keep(c : Ctx) -> Unit {
  if looks_check.val {
    looks_nodes.clear()
    for i in 0..<c.count {
      let nd = c.nodes[i]
      looks_nodes.push((nd.x, nd.y, nd.fw, nd.fh, nd.text, nd.id, nd.tx, nd.ty, nd.opacity))
    }
  }
  let len = c.ninst * inst_size
  looks_base.settled = looks_base.built &&
    c.ninst == looks_base.n &&
    insts_same(c.inst, looks_base.inst, c.ninst)
  looks_base.built = true
  looks_base.n = c.ninst
  looks_base.looks = !cycle_frame.is_empty()
  if looks_base.inst.length() < len {
    looks_base.inst = FixedArray::make(len, 0.0)
  }
  c.inst.blit_to(looks_base.inst, len~)
}

///|
/// Whether the first `n` instances of `a` and `b` are drawn the same: the same numbers, but for the tags of the looks
/// by the clock (slot 20 below 0: a tag each paint gives anew, cycle_look.mbt).
fn insts_same(a : FixedArray[Double], b : FixedArray[Double], n : Int) -> Bool {
  for q in 0..<n {
    let o = q * inst_size
    for j in 0..<inst_size {
      let x = a[o + j]
      let y = b[o + j]
      if x != y && !(j == 20 && x < 0.0 && y < 0.0) && !(x.is_nan() && y.is_nan()) {
        return false
      }
    }
  }
  true
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
/// The frame is over (on_frame), but for asking the next: whether the next may be of its looks alone, it left nothing
/// to come of its own (no frame asked for, no motion going, no fiber stepping a frame at a time, no layout read back
/// that moved; not the replay of parts kept, kept_part.mbt, which keeps its own; not on a host that tells nothing).
fn looks_left(c : Ctx, held : Bool) -> Unit {
  let left = !c.wants_frame &&
    !c.motion_left &&
    !c.fiber_frame &&
    !c.read_back_moved &&
    !held &&
    bench.mode == 0 &&
    !parts_on.val &&
    // (a host that tells no events of its own (a picture decoded, a view ready) is read each build: every frame
    // built whole there)
    (fake.val is Some(_) || outside_told.val)
  if looks_drawn.val {
    looks_base.ok = looks_base.ok && left
  } else {
    // (and it drew what the one before it drew, and told outside what that one told: built whole again, it would draw
    // the same)
    looks_base.ok = left && looks_base.settled && looks_tells.now == looks_tells.before
    looks_base.built_at = c.clock
  }
}

///|
/// The frame at `t` of the looks alone: the last frame's instances as painted, each look applied at `t`; when it is
/// drawn again is what the looks and the wakes asked before say. When it began (as frame_body's).
fn looks_frame(c : Ctx, t : Double) -> Double {
  perf_frame_start()
  let t0 = work_now()
  c.clock = t
  c.wants_frame = false
  c.cycling = false
  c.wake_at = looks_base.wake
  if looks_base.looks {
    looks_base.inst.blit_to(c.inst, len=looks_base.n * inst_size)
    c.ninst = looks_base.n
    looks_apply(c)
  }
  c.t_build = 0.0
  c.t_layout = 0.0
  c.t_paint = work_now() - t0
  looks_drawn.val = true
  looks_frames.val = looks_frames.val + 1
  t0
}

///|
/// The frame at `t`: built whole under the run's watch where what the last read changed, a moment it waits for came
/// or it left something to come (why: built_why); else of its looks alone. Where looks_check says, one of the looks
/// alone is built whole after it as well and the two compared, the test failing where they differ. When it began.
fn frame_drawn(c : Ctx, w : Double, h : Double, scale : Double, t : Double) -> Double {
  let watch = frame_watch_of()
  let said = watch_said.val
  watch_said.val = ""
  // (what was posted since the last frame taken: come from outside, it is handed on as the frame is built)
  messages_arrive()
  // (a Tester's fake host's answers come by the frame, told as it begins: what waits on them reads them)
  answers_by_the_frame()
  // (what the host says of the streams and the native views, read of it each frame: what changed come from outside)
  streams_arrive()
  views_arrive()
  // (what reads the clock and the host's settings read so: what read them is stale where they changed)
  frame_clock.set(t)
  frame_env.set(looks_env(c, w, h, scale))
  let why = if said != "" {
    said
  } else if watch.is_stale() {
    if clock_read_at.val != "" {
      "the clock read at \{clock_read_at.val}"
    } else {
      "what it read changed"
    }
  } else if !looks_base.ok {
    if looks_base.settled { "it left more to come" } else { "the one before it drew otherwise" }
  } else if looks_base.wake >= 0.0 && t >= looks_base.wake {
    "a moment it waits for came"
  } else {
    ""
  }
  built_why.val = why
  frame_built.val = true
  if why != "" {
    looks_drawn.val = false
    return watch.read(fn() { frame_body(c, w, h, scale, t) })
  }
  let t0 = looks_frame(c, t)
  if !looks_check.val {
    return t0
  }
  let n = c.ninst
  let alone = FixedArray::make(n * inst_size + 1, 0.0)
  c.inst.blit_to(alone, len=n * inst_size)
  let wake = looks_own.wake
  let cycling = looks_own.cycling
  let then = looks_nodes.copy()
  watch.read(fn() { frame_body(c, w, h, scale, t) }) |> ignore
  looks_drawn.val = false
  looks_compare(c, alone, n, wake, cycling, t, then)
  t0
}

///|
/// The frame of the looks alone (`alone`, `n` instances; its looks asking to be woken at `wake`, or drawn each frame:
/// `cycling`) against the same frame built whole (`c`'s): the same instances, its looks asking the same, else the test
/// fails, saying where they part: the first instance that differs (what it is and where), and how many each drew.
fn looks_compare(
  c : Ctx,
  alone : FixedArray[Double],
  n : Int,
  wake : Double,
  cycling : Bool,
  t : Double,
  then : Array[(Double, Double, Double, Double, String, Int, Double, Double, Double)],
) -> Unit {
  let at = t.to_int()
  let m = c.ninst
  let mut first = -1
  let mut slot = -1
  for q in 0..<(if n < m { n } else { m }) {
    let b = q * inst_size
    for j in 0..<inst_size {
      let x = alone[b + j]
      let y = c.inst[b + j]
      if first < 0 && x != y && !(x.is_nan() && y.is_nan()) {
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
      "the frame at \{at} ms of its looks alone (\{n} instances) parts from it built whole (\{m}) at instance \{first}: \{inst(alone, first, n)}, built whole \{inst(c.inst, first, m)}; words there: \{there.join(" | ")}; \{looks_node_moved(c, then)}",
    )
  }
  if cycling != looks_own.cycling || wake != looks_own.wake {
    let next = fn(cy : Bool, w : Double) { if cy { "each frame" } else { "at \{w}" } }
    looks_fail(
      "the frame at \{at} ms of its looks alone has them ask for the next \{next(cycling, wake)}, built whole \{next(looks_own.cycling, looks_own.wake)}",
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
  let said = "a frame of the looks alone (frame_watch.mbt), the Tester made at \{looks_made_at.val}: " +
    s +
    " (built whole last at \{looks_base.built_at.to_int()} ms\{if wall_read.val { "; the time of day read as it was built" } else { "" }})"
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
/// A step of a test's (Tester::frame, Tester::run_for), or a change of how frames are drawn (a Tester's or a run's
/// measure: all that shows only while lit shown, what draws each instance kept): what it changed of what is no signal
/// shows at the next frame, which is built whole; no frame is asked for by it, what changed it draws its own.
fn test_stepped() -> Unit {
  frame_watch_of().touch()
}
