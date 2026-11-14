// What a frame did, for whoever measures the app (a scripted run measured offscreen: mbui/src/film's bench, still.fail's
// scripts/appbench.sh): how much was built, laid out and drawn, and how long each took by the clock the work is timed
// by (work_now: a real host's; a Tester's, which the test's clock does not time, given one by the bench). Measured,
// never judged: nothing here asserts a time.

///|
/// The clock work is timed by (ms): the host's, unless a bench gave a Tester the machine's (set_work_clock).
// kept across runs: set by a bench before its Tester, for its run
let work_clock : Ref[(() -> Double)?] = Ref(None)

///|
/// The clock the frame's work is timed by from now on (Ctx's t_build, t_layout, t_paint, t_present; frame_perf): the
/// machine's for a bench over a Tester, whose own clock is the run's; None, the host's.
pub fn set_work_clock(f : (() -> Double)?) -> Unit {
  work_clock.val = f
}

///|
fn work_now() -> Double {
  match work_clock.val {
    Some(f) => f()
    None => h_now()
  }
}

///|
/// The first finger lifted since the last frame (ms on the work clock), for the time until a frame is submitted.
// kept across runs: reset as the hand is reset, or the first frame after the touch is submitted
let perf_touch_at : Ref[Double] = Ref(-1.0)

///|
fn perf_touch_started() -> Unit {
  if !@hostapi.perf_recording() {
    perf_touch_at.val = -1.0
  } else if perf_touch_at.val < 0.0 {
    perf_touch_at.val = work_now()
  }
}

///|
/// A frame submitted after a finger was lifted: this says the delay to submission, not when it appeared on screen or
/// whether it drew what the touch chose.
fn perf_touch_submitted(at : Double) -> Unit {
  let start = perf_touch_at.val
  perf_touch_at.val = -1.0
  if start >= 0.0 && @hostapi.perf_recording() && at >= start + probe_slow_ms {
    @hostapi.perf_line("touch: to_submit=\{((at - start) * 10.0).round() / 10.0}ms")
  }
}

///|
/// What the last frame did: the nodes its builds made (the last build's), those laid out anew, those placed elsewhere
/// as they were and those where they were (layout.mbt's commit); the instances it drew; how long its builds, its layout
/// and its paint took (ms, by work_now); how many times it was built (a layout read back that moved builds it again).
#derive(Debug)
pub(all) struct FramePerf {
  nodes : Int
  laid : Int
  placed : Int
  same : Int
  insts : Int
  /// a frame of its looks by the clock alone (frame_watch.mbt): nothing built, laid out or painted
  looks : Bool
  /// a frame painted alone, from the last build's tree (frame_watch.mbt): nothing built or laid out
  painted : Bool
  /// the lists' rows it kept as their nodes and those it built (kept_nodes.mbt)
  kept : Int
  rows : Int
  build_ms : Double
  layout_ms : Double
  paint_ms : Double
  passes : Int
}

///|
/// The layout's counts as the frame began, and how many builds it took (frame_body).
// kept across runs: written by each frame before it is read
let perf_at : FixedArray[Int] = FixedArray::make(4, 0)

///|
/// As a frame begins: where the layout's counts stand.
fn perf_frame_start() -> Unit {
  for j in 0..<3 {
    perf_at[j] = commit_counts[j]
  }
  perf_at[3] = 0
}

///|
/// What the last frame did (FramePerf).
pub fn Tester::frame_perf(self : Tester) -> FramePerf {
  self.reads_own()
  ignore(self)
  frame_perf()
}

///|
fn frame_perf() -> FramePerf {
  let c = g()
  {
    nodes: if looks_drawn.val || painted_alone.val { 0 } else { c.count },
    laid: commit_counts[0] - perf_at[0],
    placed: commit_counts[1] - perf_at[1],
    same: commit_counts[2] - perf_at[2],
    insts: c.ninst,
    looks: looks_drawn.val,
    painted: painted_alone.val,
    kept: if looks_drawn.val || painted_alone.val { 0 } else { nodes_run.kept },
    rows: if looks_drawn.val || painted_alone.val { 0 } else { nodes_run.built },
    build_ms: c.t_build,
    layout_ms: c.t_layout,
    paint_ms: c.t_paint,
    passes: perf_at[3],
  }
}

///|
/// When the app asks for its next frame, as it tells a host after the last one (on_frame): 0, the display's next
/// frame (a frame wanted, a motion going, a cycle shown, a fiber stepping a frame at a time, a frame asked for between
/// frames); else the moment it asked to be woken at; +inf, none.
pub fn Tester::wanted_after(self : Tester) -> Double {
  self.reads_own()
  self.wanted_next()
}

///|
/// Tester::wanted_after, its Tester not asked to be the one made last: the Tester's own check of its frames
/// (Tester::frame_at_said).
fn Tester::wanted_next(self : Tester) -> Double {
  let c = g()
  if self.fake.wants ||
    c.wants_frame ||
    c.took_input ||
    paint_left() ||
    layout_left() ||
    c.motion_left ||
    c.cycling ||
    c.fiber_frame ||
    posted_left() != "" {
    0.0
  } else if c.wake_at > 0.0 {
    c.wake_at
  } else {
    @double.infinity
  }
}

///|
/// How many times the app has asked its host for the next display frame for what goes on by the clock (a motion going,
/// a cycle shown, a fiber stepping a frame at a time), as a host is asked (on_frame): what draws it on a device. A
/// Tester draws none for it (its time goes by run_for).
pub fn Tester::frames_on(self : Tester) -> Int {
  self.fake.frames_on
}

///|
/// How many frames a second the last frame said what moves on by the clock needs, as a host is told (frame_pace.mbt,
/// @hostapi.frames_paced); 0 where it said none (the display's every frame, or no frame by the clock asked for).
pub fn Tester::frames_paced(self : Tester) -> Double {
  self.fake.paced
}

///|
/// Why the app asks for a frame (Tester::wanted_after), in words: the display's next frame's, else its wake's; "" when
/// it asks for none.
pub fn Tester::wanted_why(self : Tester) -> String {
  self.reads_own()
  let c = g()
  let why = []
  if self.fake.wants {
    why.push("a frame asked for between frames")
  }
  if c.wants_frame {
    why.push(
      "a frame asked for" +
      by_of(c.frame_by) +
      (if c.took_input { " (an input's frame after)" } else { "" }) +
      (if c.read_back_moved { " (read back moved: \{c.read_back_key})" } else { "" }),
    )
  }
  if paint_left() {
    why.push("a frame asked for to paint: " + paint_said.val)
  }
  if layout_left() {
    why.push(
      "a frame asked for to lay out: " +
      (if layout_said.val != "" { layout_said.val } else { "what a part or a list's row read changed" }),
    )
  }
  if c.took_input && !c.wants_frame {
    why.push("an input's frame after")
  }
  if c.motion_left {
    why.push("moving: " + c.moving_now().join("; "))
  }
  if c.cycling {
    why.push("cycling: " + self.cycles().join("; "))
  }
  if c.fiber_frame {
    why.push("a fiber stepping: " + fx.val.unsettled())
  }
  let posted = posted_left()
  if posted != "" {
    why.push(posted)
  }
  if why.is_empty() && c.wake_at > 0.0 {
    why.push(
      "a wake in \{(c.wake_at - c.clock).ceil().to_int()} ms" +
      by_of(c.wake_by) +
      (if c.periodic.is_empty() { "" } else { " (comes again: " + self.periodic().join("; ") + ")" }),
    )
  }
  why.join("; ")
}

///|
/// What a bench is told as the measured frame being drawn has been drawn by the app (Tester::bench's `around`)
// kept across runs: set by a bench as each measured frame begins, taken as it ends
let bench_frame_end : Ref[(() -> Unit)?] = Ref(None)

///|
fn bench_frame_ends() -> Unit {
  if bench_frame_end.val is Some(f) {
    bench_frame_end.val = None
    f()
  }
}

///|
/// `script` run (Tester::drive's steps) on the display's frames at `fps` a second, a frame drawn at one only where the
/// app asks for it there, as a host draws (Tester::wanted_after): `each` told, at each of the display's frames from the
/// script's step `log measure` on (what comes before it, the app opening, not measured), whether one was drawn there.
/// `around` told as each measured frame drawn begins (false) and as the app has drawn it (true: the Tester's own
/// checks of it after, which a device runs not), with the display's frame it is at: what counts a frame's work from
/// outside (mbui/film's mark, a profiled run's). Its frames keep not who drew each thing nor the lines of words drawn,
/// as a device's (the Tester's words-over check, words_over.mbt, finds nothing in them; Tester::text_runs none). Until
/// the script ends or `max` of the display's frames went by. What the Tester logged.
pub fn Tester::bench(
  self : Tester,
  script : String,
  fps? : Double = 120.0,
  max? : Int = 20000,
  each~ : (Tester, Bool) -> Unit,
  around? : (Int, Bool) -> Unit,
) -> Array[String] {
  self.fake.logs.clear()
  // (who drew each instance not kept, as a device keeps it not: the Tester's words-over check's, each instance's owner
  // noted as it is drawn and copied as a list's rows are kept, ~7% of a frame's instructions; from the script's start,
  // the rows it keeps made so before what is measured)
  let tracked = inst_owners.track
  inst_owners.track = false
  inst_owners_clear()
  // (nor the lines of words drawn, as a device keeps them not: Tester::text_runs's, each line of words noted as it is
  // drawn and copied as a list's rows are kept again)
  let runs = text_runs.on
  text_runs.on = false
  text_runs.runs.clear()
  drive_start(script, "")
  let step = 1000.0 / fps
  let mut tick = self.fake.time
  let mut n = 0
  let mut measuring = false
  while driver.val is Some(_) && n < max {
    tick = tick + step
    let due = self.wanted_after()
    let frame = due <= tick + 1.0e-9 || (measuring && bench_whole.val)
    if frame {
      if measuring && around is Some(f) {
        f(n, false)
        bench_frame_end.val = Some(fn() { f(n, true) })
      }
      self.frame_at(tick)
      // (a frame that drew nothing of the app's: ended here)
      bench_frame_ends()
    } else {
      // (no frame: the time goes on)
      self.fake.time = tick
    }
    if measuring {
      each(self, frame)
    } else {
      measuring = self.fake.logs.iter().any(fn(l) { l == "DRIVE LOG measure" })
      bench_measuring.val = measuring
    }
    n = n + 1
  }
  bench_measuring.val = false
  inst_owners.track = tracked
  text_runs.on = runs
  self.fake.logs.copy()
}

///|
/// Whether a bench builds every frame whole, keeping nothing, from its `log measure` on (Tester::bench_whole): what a
/// frame built anew costs, whatever it is built for.
// kept across runs: a bench's, set once as it begins
let bench_whole : Ref[Bool] = Ref(false)

///|
/// Whether a bench is past its script's `log measure` (Tester::bench).
// kept across runs: a bench's, let go as it ends
let bench_measuring : Ref[Bool] = Ref(false)

///|
/// Every frame of the bench from its `log measure` on drawn, and built whole, keeping nothing (no part, no row, no
/// layout of before but what the flex engine keeps): what building the frame anew costs (scripts/appbench.sh's
/// `whole`).
pub fn Tester::bench_whole(self : Tester, on : Bool) -> Unit {
  ignore(self)
  bench_whole.val = on
}

///|
/// Whether each frame a host draws is said on its log (MBUI_PROBE_FRAMES=1; on a phone `adb shell setprop
/// debug.mbui.probe_frames 1`, the app started anew): -1 not asked yet.
// kept across runs: asked once of the process
let perf_frames_on : Ref[Int] = Ref(-1)

///|
/// Frame at `t` presented (on_frame): what it did, its work and its presenting (ms), what of the window it drew again,
/// the GPU's time of the last done, the rows and parts it built and kept (kept_nodes.mbt), why it was built (the
/// last frame built's, frame_watch.mbt's built_why: what it read changed and where, a moment come, nothing for one of
/// its looks alone), a PERF line on the log, where asked (perf_frames_on): what still.fail's scripts/appbench.sh reads
/// of a phone.
fn perf_log(c : Ctx, t : Double, work : Double, present : Double) -> Unit {
  if perf_frames_on.val < 0 {
    perf_frames_on.val = if @hostapi.env("MBUI_PROBE_FRAMES") == "1" { 1 } else { 0 }
  }
  if perf_frames_on.val == 0 {
    return
  }
  let p = frame_perf()
  h_log(
    "PERF t=\{t} work=\{work} build=\{c.t_build} layout=\{c.t_layout} paint=\{c.t_paint} present=\{present} gpu=\{h_gpu_ms()} nodes=\{p.nodes} laid=\{p.laid} insts=\{p.insts} looks=\{if p.looks { 1 } else { 0 }} painted=\{if p.painted { 1 } else { 0 }} share=\{presented_share.val} passes=\{p.passes} rows=\{nodes_run.built} kept=\{nodes_run.kept} why=\{built_why.val.escape()}",
  )
}

///|
/// How many bytes the performance record's files hold as the host last said it wrote them (hostcall.mbt's on_outside:
/// outside_perf; -1: not said yet): what reads it (perf_size) follows a write that changed it, none that did not.
// kept across runs: said as the host tells a write, put back as a run begins (reset_globals)
let perf_bytes_said : @signals.Signal[Double] = @signals.signal(-1.0, same=fn(a, b) { a == b })

///|
/// The host wrote to the performance record: how much it holds now, told what reads it (perf_size).
fn perf_told() -> Unit {
  perf_bytes_said.set(@hostapi.perf_size())
}

///|
/// How many bytes the performance record's files hold (@hostapi.perf_size), as the host last said it wrote them: what
/// reads it follows each write the host tells (outside_perf) that changed it, nothing asked of the host on a clock;
/// read again where the record is turned on or off (what turns it says so).
pub fn perf_size() -> Double {
  perf_bytes_said.get() |> ignore
  @hostapi.perf_size()
}
