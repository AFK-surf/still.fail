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
/// What the last frame did: the nodes its builds made (the last build's), those laid out anew, those placed elsewhere
/// as they were and those where they were (layout.mbt's commit); the instances it drew; how long its builds, its layout
/// and its paint took (ms, by work_now); how many times it was built (a layout read back that moved builds it again).
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
  /// a frame of the window's tree alone, what of its scene changed drawn again where it is (scene_layers.mbt): nothing
  /// of the old frame built, laid out or painted
  alone : Bool
  /// the lists' rows it kept as their nodes and those it built (kept_nodes.mbt)
  kept : Int
  rows : Int
  build_ms : Double
  layout_ms : Double
  paint_ms : Double
  passes : Int
} derive(Show)

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
    alone: tree_alone_drawn.val,
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
/// Why the app asks for a frame (Tester::wanted_after), in words: the display's next frame's, else its wake's; "" when
/// it asks for none.
pub fn Tester::wanted_why(self : Tester) -> String {
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
/// `script` run (Tester::drive's steps) on the display's frames at `fps` a second, a frame drawn at one only where the
/// app asks for it there, as a host draws (Tester::wanted_after): `each` told, at each of the display's frames from the
/// script's step `log measure` on (what comes before it, the app opening, not measured), whether one was drawn there.
/// Until the script ends or `max` of the display's frames went by. What the Tester logged.
pub fn Tester::bench(
  self : Tester,
  script : String,
  fps? : Double = 120.0,
  max? : Int = 20000,
  each~ : (Tester, Bool) -> Unit,
) -> Array[String] {
  self.fake.logs.clear()
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
      self.frame_at(tick)
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
/// Whether each frame is said on the log (perf_frames_on), asked of the process the first time.
fn perf_frames_said() -> Bool {
  if perf_frames_on.val < 0 {
    perf_frames_on.val = if @hostapi.env("MBUI_PROBE_FRAMES") == "1" { 1 } else { 0 }
  }
  perf_frames_on.val == 1
}

///|
/// Frame at `t` presented (on_frame): what it did, its work and its presenting (ms), what of the window it drew again,
/// the GPU's time of the last done, the rows and parts it built and kept (kept_nodes.mbt), why it was built (the
/// last frame built's, frame_watch.mbt's built_why: what it read changed and where, a moment come, nothing for one of
/// its looks alone), a PERF line on the log, where asked (perf_frames_on): what still.fail's scripts/appbench.sh reads
/// of a phone.
fn perf_log(c : Ctx, t : Double, work : Double, present : Double) -> Unit {
  if !perf_frames_said() {
    return
  }
  let p = frame_perf()
  h_log(
    "PERF t=\{t} work=\{work} build=\{c.t_build} layout=\{c.t_layout} paint=\{c.t_paint} present=\{present} gpu=\{h_gpu_ms()} nodes=\{p.nodes} laid=\{p.laid} insts=\{p.insts} looks=\{if p.looks { 1 } else { 0 }} painted=\{if p.painted { 1 } else { 0 }} share=\{presented_share.val} whole=\{scene.parts.why()} passes=\{p.passes} rows=\{nodes_run.built} kept=\{nodes_run.kept} pp=\{paint_split_said()} po=\{(paint_old_ms.val * 100.0).round() / 100.0} pb=\{parts_built_said()} walk=\{walk_said()} shaped=\{host_shaped.val} glyphs=\{host_glyphs.val} why=\{built_why.val.escape()} painted_why=\{painted_why.val.escape()}",
  )
  host_shaped.val = 0
  host_glyphs.val = 0
  paint_old_ms.val = 0.0
}

///|
/// Where a frame's paint went (frame_paint's, said on its PERF line as `pp=` where asked: perf_frames_on), its parts'
/// times (ms) in the order it paints them: the input targets found (Ctx::view_targets), what of the tree changed taken
/// and drawn alone, the window's tree walked with the old views in it, what is drawn over them, the glyphs drawn
/// ahead, the scene's segments and its end, the looks, shots and native views, what a screen reader reads, the rest;
/// and after it, the runtime's fibers (fx_frame_end). `po=`: of the walk, the old views painted in it.
// kept across runs: said and set to nothing by each PERF line
let paint_split : FixedArray[Double] = FixedArray::make(10, 0.0)

///|
// kept across runs: said and set to nothing by each PERF line
let paint_old_ms : Ref[Double] = Ref(0.0)

///|
// kept across runs: how deep in old views painted the paint is (only the outermost timed)
let paint_old_depth : Ref[Int] = Ref(0)

///|
/// `f`, old views painted in the walk of the window's tree, timed into paint_old_ms where asked.
fn paint_old_timed(f : () -> Unit) -> Unit {
  if perf_frames_on.val != 1 || paint_old_depth.val > 0 {
    f()
    return
  }
  paint_old_depth.val = 1
  let t0 = work_now()
  f()
  paint_old_ms.val = paint_old_ms.val + work_now() - t0
  paint_old_depth.val = 0
}

///|
/// The parts built since the last PERF line that took longest (`pb=`, where asked: perf_frames_on), at most
/// three: what it is (its name, else where it is made), why it was built (new, what it read changed, another key, the
/// frame built anew, …: Ctx::part_nodes), how long it took (ms, what it holds built with it).
// kept across runs: said and set to nothing by each PERF line
let parts_built_most : Array[(String, String, Double)] = []

///|
/// A part built (Ctx::part_nodes): `what`, why, in `ms`.
fn part_built_said(what : String, why : String, ms : Double) -> Unit {
  // (where it is made, said by its file and line alone)
  let what = match what.split("/").collect().last() {
    Some(s) => {
      let bits = s.split(":").collect()
      if bits.length() > 1 { "\{bits[0]}:\{bits[1]}" } else { s.to_string() }
    }
    None => what
  }
  parts_built_most.push((what, why, ms))
  parts_built_most.sort_by(fn(a, b) { b.2.compare(a.2) })
  while parts_built_most.length() > 3 {
    parts_built_most.pop() |> ignore
  }
}

///|
/// parts_built_most as said on a PERF line, let go.
fn parts_built_said() -> String {
  let s = parts_built_most.map(fn(p) { "\{p.0}/\{p.1}/\{(p.2 * 100.0).round() / 100.0}" }).join(";")
  parts_built_most.clear()
  s
}

///|
/// The nodes of the window's tree its walks went through since the last PERF line, and those of them that drew
/// something of their own (`walk=`, where asked: perf_frames_on); with what the scene drew of its layers and copied of
/// them as kept (SceneWork's, since the last).
// kept across runs: said and set to nothing by each PERF line
let walk_nodes : Ref[Int] = Ref(0)

///|
// kept across runs: as walk_nodes
let walk_drew : Ref[Int] = Ref(0)

///|
/// The layers drawn as they keep how they are drawn, the tree not gone through for them (Ctx::tree_walk's `kept`).
// kept across runs: as walk_nodes
let walk_kept : Ref[Int] = Ref(0)

///|
// kept across runs: the scene's work as the last PERF line said it
let scene_work_said : Ref[SceneWork?] = Ref(None)

///|
/// walk_nodes, walk_drew and the scene's layers drawn, copied, its instances made and copied since the last PERF line,
/// said and set to nothing.
fn walk_said() -> String {
  let now = scene_done()
  let was = scene_work_said.val.unwrap_or(now)
  scene_work_said.val = Some(now)
  let s = "\{walk_nodes.val}/\{walk_drew.val}/\{walk_kept.val} layers=\{now.layers - was.layers}/\{now.copied - was.copied} made=\{now.recorded - was.recorded}/\{now.copied_insts - was.copied_insts}"
  walk_nodes.val = 0
  walk_drew.val = 0
  walk_kept.val = 0
  s
}

///|
// kept across runs: where the part being timed began
let paint_split_at : Ref[Double] = Ref(0.0)

///|
/// What the host shaped and the glyphs it drew since the last PERF line (`shaped=`, `glyphs=`).
// kept across runs: said and set to nothing by each PERF line
let host_shaped : Ref[Int] = Ref(0)

///|
// kept across runs: as host_shaped
let host_glyphs : Ref[Int] = Ref(0)

///|
/// A part of the paint (paint_split) begun.
fn paint_split_begin() -> Unit {
  if perf_frames_on.val == 1 {
    paint_split_at.val = work_now()
  }
}

///|
/// Part `k` of the paint (paint_split) done, the next begun.
fn paint_split_mark(k : Int) -> Unit {
  if perf_frames_on.val == 1 {
    let t = work_now()
    paint_split[k] = paint_split[k] + t - paint_split_at.val
    paint_split_at.val = t
  }
}

///|
/// paint_split as said on a PERF line, set to nothing.
fn paint_split_said() -> String {
  let s = paint_split.iter().map(fn(v) { ((v * 100.0).round() / 100.0).to_string() }).collect().join(",")
  paint_split.fill(0.0)
  s
}

///|
/// How many times the host said it wrote to the performance record (hostcall.mbt's on_outside: outside_perf).
// kept across runs: counted on (what reads it follows it), never put back
let perf_written : @signals.Signal[Int] = @signals.signal(0)

///|
/// The host wrote to the performance record: what reads how much it holds told (perf_size).
fn perf_told() -> Unit {
  perf_written.set(@signals.untracked(fn() { perf_written.get() }) + 1)
}

///|
/// How many bytes the performance record's files hold (@hostapi.perf_size), as the host last said it wrote them: what
/// reads it follows each write the host tells (outside_perf), nothing asked of the host on a clock; read again where
/// the record is turned on or off (what turns it says so).
pub fn perf_size() -> Double {
  perf_written.get() |> ignore
  @hostapi.perf_size()
}
