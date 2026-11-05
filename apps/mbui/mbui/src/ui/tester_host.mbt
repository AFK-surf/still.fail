// Each frame a Tester draws as a host would see it, counted: whether the app asked for it, whether the old frame was
// built again (and the kept parts and rows with it), what of the window was drawn again (the parts handed to the host,
// @damage.Parts::take), how much glass was copied again for it, how much was laid out. Counts, never times: the same
// on every machine. What a phone shows as a stutter (every key building the old frame whole, every frame drawn over
// the whole window) is a count here, asserted.

///|
/// One frame as the host got it.
pub(all) struct HostFrame {
  /// its time on the clock
  at : Double
  /// whether the frame before asked for it (an input, a wake, a motion going on); false: a host draws none here
  asked : Bool
  /// whether what it drew differs from the frame before (Tester::frame_hash)
  changed : Bool
  /// the old frame built again (none of FramePerf's looks, painted, alone), and why (Tester::built_why)
  old_built : Bool
  why : String
  /// the rows and kept parts built anew in it (FramePerf's rows)
  parts_built : Int
  /// drawn by the window's tree alone (frame_drawn's FrameDrawnAs Alone; else built, painted alone or of its looks), and
  /// where it was asked to be and could not, why (Scene's alone_why: the old frame painted it then)
  tree_alone : Bool
  alone_why : String
  /// the window's tree's layers drawn again in it, the instances they came to (their own: SceneWork's `layers`,
  /// `recorded`), and the instances moved, as they were, to another place in the frame (scene_moved_insts)
  layers_drawn : Int
  insts_recorded : Int
  insts_moved : Int
  /// the parts of the window drawn again (x, y, w, h; w < 0: all of it), their share of the window (1: all) and why
  /// it was whole (@damage.Parts::why: 0 it was not)
  damage : Array[(Double, Double, Double, Double)]
  damage_share : Double
  whole_why : Int
  /// the area of glass copied again for it (each capture of glass a part reaches, where the part reaches it)
  glass : Double
  /// nodes laid out anew in it (the old frame's and the window's tree's) and the old frame's builds
  laid : Int
  passes : Int
  /// what was done between the frame before and this one, outside any frame (the events taken then: Tree::event_said,
  /// at_cause, settle_now; what a host's PERF and a frame's counts do not see): the window's tree's nodes made,
  /// bindings run, structure bindings run (show, pick, each), nodes laid out, settles; and each count a test said
  /// (Tester::count_between), by its name
  between : Array[(String, Int)]
} derive(Show)

///|
/// The frames recorded since Tester::record_host (None: not recording).
// kept across runs: a test's, begun and taken by it; put back as a run begins (Tester::new: host_record_forget)
let host_record : Ref[Array[HostFrame]?] = Ref(None)

///|
/// Whether the next frame drawn is one the app asked for (Tester::run_as_host says; any other frame is a test's input's
/// or a moment it names, which a host draws).
// kept across runs: set for one frame by run_as_host, true otherwise
let host_asked_next : Ref[Bool] = Ref(true)

///|
/// The parts the last frame handed its host and the glass copied for them (h_present, a Tester's).
// kept across runs: written by each frame a Tester presents
let host_parts_last : Ref[(Array[(Double, Double, Double, Double)], Double)] = Ref(([], 0.0))

///|
/// The tree's nodes laid out so far, as the last frame recorded left them.
// kept across runs: written by each frame recorded
let host_tree_laid : Ref[Int] = Ref(0)

///|
/// The window's tree's layers drawn, instances recorded and moved so far, as the frame drawing now began.
// kept across runs: written by each frame recorded
let host_scene_began : Ref[(Int, Int, Int)] = Ref((0, 0, 0))

///|
fn host_scene_now() -> (Int, Int, Int) {
  (scene_work.layers, scene_work.recorded, scene_moved_insts.val)
}

///|
/// The hash of the frame recorded last.
// kept across runs: written by each frame recorded
let host_hash_last : Ref[Int64] = Ref(0L)

///|
/// The window's tree's work and the test's counts as the frame recorded last ended (host_work_now's).
// kept across runs: written by each frame recorded; put back as a run begins (host_record_forget)
let host_work_end : Ref[Array[(String, Int)]] = Ref([])

///|
/// What was done between the frame before and the one drawing now (host_frame_begin's).
// kept across runs: written by each frame recorded; put back as a run begins (host_record_forget)
let host_between_now : Ref[Array[(String, Int)]] = Ref([])

///|
/// The counts a test said (Tester::count_between), each read as frames begin and end.
// kept across runs: a test's, said by it; put back as a run begins (host_record_forget)
let host_counts : Array[(String, () -> Int)] = []

///|
fn host_record_forget() -> Unit {
  host_record.val = None
  host_asked_next.val = true
  host_parts_last.val = ([], 0.0)
  host_work_end.val = []
  host_between_now.val = []
  host_counts.clear()
}

///|
/// `count` read as each frame recorded begins and ends: what it went up by between them said in HostFrame's
/// `between` as `name` (an app's own work outside frames: a list's entries made, messages made).
pub fn Tester::count_between(self : Tester, name : String, count : () -> Int) -> Unit {
  ignore(self)
  host_counts.push((name, count))
}

///|
/// The window's tree's work and the test's counts now.
fn host_work_now() -> Array[(String, Int)] {
  let out : Array[(String, Int)] = match view_tree() {
    Some(t) => {
      let w = t.work()
      [("made", w.made), ("bound", w.bound), ("structure", w.structure), ("laid", w.laid), ("settles", w.settles)]
    }
    None => []
  }
  for c in host_counts {
    out.push((c.0, (c.1)()))
  }
  out
}

///|
/// A frame begins (frame_shown_at's start): what was done since the frame recorded last ended, kept for it.
fn host_frame_begin() -> Unit {
  guard host_record.val is Some(_) else { return }
  let now = host_work_now()
  let was = host_work_end.val
  host_between_now.val = now.mapi(fn(i, c) {
    let before = match was.get(i) {
      Some(b) if b.0 == c.0 => b.1
      _ => c.1
    }
    (c.0, c.1 - before)
  })
  host_scene_began.val = host_scene_now()
  // (the frame's own laying out counted from here: what came before it is `between`'s)
  host_tree_laid.val = match view_tree() {
    Some(t) => t.work().laid
    None => host_tree_laid.val
  }
}

///|
/// Every frame drawn from now on recorded as its host got it (Tester::host_frames takes them).
pub fn Tester::record_host(self : Tester) -> Unit {
  ignore(self)
  host_record.val = Some([])
  host_tree_laid.val = match view_tree() {
    Some(t) => t.work().laid
    None => 0
  }
  host_scene_began.val = host_scene_now()
  host_hash_last.val = drawn_hash()
  host_work_end.val = host_work_now()
}

///|
/// The frames recorded since Tester::record_host or the last taken, oldest first; recording goes on.
pub fn Tester::host_frames(self : Tester) -> Array[HostFrame] {
  ignore(self)
  match host_record.val {
    Some(r) => {
      let out = r.copy()
      r.clear()
      out
    }
    None => []
  }
}

///|
/// The frame just drawn at `at`, recorded where recording (frame_shown_at's end).
fn host_frame_drawn(at : Double) -> Unit {
  guard host_record.val is Some(r) else {
    host_asked_next.val = true
    return
  }
  let p = frame_perf()
  let tree_laid = match view_tree() {
    Some(t) => t.work().laid
    None => 0
  }
  let hash = drawn_hash()
  let (parts, glass) = host_parts_last.val
  let c = g()
  let area = parts.iter().fold(init=0.0, fn(a, q) { if q.2 < 0.0 || a < 0.0 { -1.0 } else { a + q.2 * q.3 } })
  let share = if area < 0.0 {
    1.0
  } else if c.window_w > 0.0 && c.window_h > 0.0 {
    area / (c.window_w * c.window_h)
  } else {
    0.0
  }
  let old_built = frame_drawn_as.val == Built
  r.push({
    at,
    asked: host_asked_next.val,
    changed: hash != host_hash_last.val,
    old_built,
    why: if old_built { built_why.val } else { "" },
    parts_built: if old_built { p.rows } else { 0 },
    tree_alone: frame_drawn_as.val == Alone,
    alone_why: scene.alone_why,
    layers_drawn: scene_work.layers - host_scene_began.val.0,
    insts_recorded: scene_work.recorded - host_scene_began.val.1,
    insts_moved: scene_moved_insts.val - host_scene_began.val.2,
    damage: parts,
    damage_share: share,
    whole_why: scene.parts.why(),
    glass,
    laid: p.laid + tree_laid - host_tree_laid.val,
    passes: p.passes,
    between: host_between_now.val,
  })
  host_between_now.val = []
  host_work_end.val = host_work_now()
  host_tree_laid.val = tree_laid
  host_hash_last.val = hash
  host_asked_next.val = true
}

///|
/// What the parts `parts` (h_present's) copy of glass again: each capture's area where a part reaches it, the window
/// `w` × `h` (a part with w < 0: all of the window).
fn host_glass_of(
  parts : Array[(Double, Double, Double, Double)],
  captures : Array[(Double, Double, Double, Double)],
  w : Double,
  h : Double,
) -> Double {
  let mut area = 0.0
  for c in captures {
    let (cx0, cy0, cx1, cy1) = (dmax(c.0, 0.0), dmax(c.1, 0.0), dmin(c.2, w), dmin(c.3, h))
    for q in parts {
      let (x0, y0, x1, y1) = if q.2 < 0.0 { (0.0, 0.0, w, h) } else { (q.0, q.1, q.0 + q.2, q.1 + q.3) }
      let iw = dmin(cx1, x1) - dmax(cx0, x0)
      let ih = dmin(cy1, y1) - dmax(cy0, y0)
      if iw > 0.0 && ih > 0.0 {
        area = area + iw * ih
      }
    }
  }
  area
}

///|
/// The display's frames for `ms` from now as a host draws them, recorded (Tester::record_host): each drawn, and said
/// asked or not by what the frame before asked for as it ended (on_frame's h_request_frame, h_request_frame_on,
/// h_wake_after). A frame not asked for that drew something else (HostFrame's asked false, changed true) is one a
/// phone never shows: what it drew stands still there until something else asks.
pub fn Tester::run_as_host(self : Tester, ms : Double) -> Unit {
  let end = self.on_grid(self.fake.time + ms)
  let mut on = self.fake.frames_on
  let mut first = true
  while self.fake.time < end - 1.0e-9 {
    let next = self.tick_after(self.fake.time)
    let woken = self.fake.wake >= 0.0 && self.fake.wake <= next + 1.0e-9
    let asked = if first {
      self.wanted_after() <= next + 1.0e-9
    } else {
      self.fake.wants || self.fake.frames_on != on || woken
    }
    first = false
    if woken {
      self.fake.wake = -1.0
    }
    on = self.fake.frames_on
    host_asked_next.val = asked
    self.frame_at(next)
  }
}

///|
/// The system's back (Tester::back's) the host says came at `at`, told now: no frame drawn.
pub fn Tester::back_told(self : Tester, at : Double) -> Unit {
  self.back_raw(2, 0.0, at)
}
