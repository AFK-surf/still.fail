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
  /// how it was drawn: "built" (the old frame built again), "painted" (painted alone), "looks" (of its looks by the clock
  /// alone), "alone" (by the window's tree alone): frame_drawn_as
  drawn_as : String
  /// the old frame built again (none of FramePerf's looks, painted, alone), and why (Tester::built_why; painted alone, why: Tester::painted_why)
  old_built : Bool
  why : String
  /// whether it was built for the inputs handed to the old frame alone (built_for_old_input: the first change it was
  /// built for told as one was taken, nothing else changed since but as they were taken): without them, none built
  for_old_input : Bool
  /// built, what else it was built for than those inputs ("" none)
  not_for_old_input : String
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
  /// the inputs handed to the old frame since the frame before, this frame the first to take them (took_input: each
  /// its kind, what it said, its moment); none where every input went to the window's tree or none came
  old_inputs : Array[String]
  /// the inputs the window's tree took since the frame before, as old_inputs are (pointer_in_now's, a node of the
  /// tree's or a hold of its own taking it)
  tree_inputs : Array[String]
  /// what the frame before left for this one to build (looks_left: the inputs it took, a frame asked, a layout read back
  /// that moved, a hold); "" none: what built this whole, if it was, came for it
  left_by : String
  /// the parts of the window drawn again (x, y, w, h; w < 0: all of it), their share of the window (1: all) and why
  /// it was whole (@damage.Parts::why: 0 it was not)
  damage : Array[(Double, Double, Double, Double)]
  damage_share : Double
  whole_why : Int
  /// what those parts were said as by their causes before any was taken together (x0, y0, x1, y1), and the captures of
  /// glass taken into them (@damage.Parts::said, glass_taken): whole (why 5) as they came to more than half the window
  damage_said : Array[(Double, Double, Double, Double)]
  glass_taken : Array[(Double, Double, Double, Double)]
  /// what changed of the picture from the frame before that the parts drawn again leave out: an instance drawn
  /// otherwise, come or gone, where it reaches, or a capture of glass under such a change, outside every part (none
  /// where it was drawn whole)
  missed : Array[String]
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
/// The inputs handed to the old frame since the frame recorded last began (took_input), and those the frame drawing now
/// took (host_frame_begin's).
// kept across runs: written as inputs come and frames begin; put back as a run begins (host_record_forget)
let host_inputs_coming : Ref[Array[String]] = Ref([])

///|
// kept across runs: written by each frame recorded; put back as a run begins (host_record_forget)
let host_inputs_now : Ref[Array[String]] = Ref([])

///|
/// The inputs the window's tree took, as host_inputs_coming and host_inputs_now are.
// kept across runs: written as inputs come and frames begin; put back as a run begins (host_record_forget)
let host_tree_coming : Ref[Array[String]] = Ref([])

///|
// kept across runs: written by each frame recorded; put back as a run begins (host_record_forget)
let host_tree_now : Ref[Array[String]] = Ref([])

///|
/// What the frame recorded last left for the next (looks_left_by as it ended).
// kept across runs: written by each frame recorded; put back as a run begins (host_record_forget)
let host_left_last : Ref[String] = Ref("")

///|
/// The picture the frame recorded last drew: each instance's numbers hashed as drawn_hash names them, and where its
/// pixels reach (x0, y0, x1, y1).
// kept across runs: written by each frame recorded; put back as a run begins (host_record_forget)
let host_drawn_last : Ref[Array[HostDrawn]] = Ref([])

///|
/// An input handed to the old frame (took_input): kept for the frame that takes it, where frames are recorded.
fn host_old_input(kind : String, t : Double, args : Array[Double]) -> Unit {
  guard host_record.val is Some(_) else { return }
  host_inputs_coming.val.push("\{kind} \{args} at \{t}")
}

///|
/// An input the window's tree took (pointer_in_now's): kept for the frame that takes it, where frames are recorded.
fn host_tree_input(kind : String, t : Double, args : Array[Double]) -> Unit {
  guard host_record.val is Some(_) else { return }
  host_tree_coming.val.push("\{kind} \{args} at \{t}")
}

///|
/// The counts a test said (Tester::count_between), each read as frames begin and end.
// kept across runs: a test's, said by it; put back as a run begins (host_record_forget)
let host_counts : Array[(String, () -> Int)] = []

///|
fn host_record_forget() -> Unit {
  host_inputs_coming.val = []
  host_inputs_now.val = []
  host_tree_coming.val = []
  host_tree_now.val = []
  host_left_last.val = ""
  host_drawn_last.val = []
  host_record.val = None
  scene.parts.keep_said(false)
  causes_count(false)
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
/// Just before on_frame, after the host's replies and renderer setup: work since the last completed frame.
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
  host_inputs_now.val = host_inputs_coming.val
  host_inputs_coming.val = []
  host_tree_now.val = host_tree_coming.val
  host_tree_coming.val = []
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
  scene.parts.keep_said(true)
  causes_count(true)
  host_tree_laid.val = match view_tree() {
    Some(t) => t.work().laid
    None => 0
  }
  host_scene_began.val = host_scene_now()
  host_hash_last.val = drawn_hash()
  host_work_end.val = host_work_now()
  host_inputs_coming.val = []
  host_tree_coming.val = []
  host_left_last.val = looks_left_by.val
  host_drawn_last.val = host_drawn_now()
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
/// Immediately after on_frame returns, before the Tester's checks and callbacks: the frame the host received.
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
  let drawn = host_drawn_now()
  let captures = []
  for k in 0..<c.ninst {
    match @damage.capture_of(c.inst, k) {
      Some((_, cap)) => captures.push(cap)
      None => ()
    }
  }
  let missed = host_missed(host_drawn_last.val, drawn, captures, parts, c.window_w, c.window_h)
  let old_built = frame_drawn_as.val == Built
  r.push({
    at,
    asked: host_asked_next.val,
    changed: hash != host_hash_last.val,
    old_built,
    drawn_as: match frame_drawn_as.val {
      Built => "built"
      Painted => "painted"
      Looks => "looks"
      Alone => "alone"
    },
    why: match frame_drawn_as.val {
      Built => built_why.val
      Painted => painted_why.val
      _ => ""
    },
    for_old_input: old_built && built_for_old_input.val == "",
    not_for_old_input: if old_built { built_for_old_input.val } else { "" },
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
    old_inputs: host_inputs_now.val,
    tree_inputs: host_tree_now.val,
    left_by: host_left_last.val,
    damage_said: scene.parts.said(),
    glass_taken: scene.parts.glass_taken(),
    missed,
  })
  host_between_now.val = []
  host_inputs_now.val = []
  host_tree_now.val = []
  host_left_last.val = looks_left_by.val
  host_drawn_last.val = drawn
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

///|
/// An instance of a picture drawn (host_drawn_now): its numbers as drawn_hash names them, hashed, and where its pixels
/// reach (x0, y0, x1, y1).
priv struct HostDrawn {
  hash : Int64
  reach : (Double, Double, Double, Double)
  numbers : FixedArray[Double]
}

///|
/// The picture the frame drawn now drew (host_drawn_last's): each instance drawn as drawn_hash names its numbers (a
/// picture by what it is, a glyph by its key: where the atlas holds them is none of its pixels; a band of a shape by
/// its pieces, not where they lie among the frame's: shape.mbt), and where its pixels reach. The pieces themselves
/// (kind 12) draw nothing.
fn host_drawn_now() -> Array[HostDrawn] {
  let c = g()
  let named = image_numbers(c)
  let keys = glyph_keys()
  let reach = @damage.Parts::new()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 12.0 {
      continue
    }
    let numbers = FixedArray::make(inst_size, 0.0)
    let mut h = -3750763034362895579L
    for j in 0..<inst_size {
      numbers[j] = inst_named(c, named, keys, k, j)
    }
    if c.inst[b + 5] == 11.0 {
      let mut p = -3750763034362895579L
      for i in 0..<c.inst[b + 13].to_int() {
        let (x0, y0, x1, y1) = seg_at(c.inst, c.ninst, c.inst[b + 12].to_int() + i)
        for v in [x0, y0, x1, y1] {
          p = (p ^ v.reinterpret_as_int64()) * 1099511628211L
        }
      }
      numbers[12] = p.to_double()
    }
    for j in 0..<inst_size {
      h = (h ^ numbers[j].reinterpret_as_int64()) * 1099511628211L
    }
    out.push({ hash: h, reach: reach.reach_of(c.inst, k, k + 1), numbers })
  }
  out
}

///|
/// What changed from picture `was` to `now` (host_drawn_now's) that `parts` (h_present's, x y w h; w < 0 all of it)
/// leave out, in a window `w` × `h`: each instance come or gone (one drawn otherwise is both) where it reaches; two
/// drawn as they were that overlap, one over the other now that was under it, where they overlap; and each capture of
/// glass of `now` (`captures`, x0 y0 x1 y1) such a change meets (what the glass shows is a blur of what is under it);
/// each outside every part. An instance drawn as it was is the same pixels wherever it stands in the list, but for
/// what is over it: of those, the order of the ones that overlap is compared.
fn host_missed(
  was : Array[HostDrawn],
  now : Array[HostDrawn],
  captures : Array[(Double, Double, Double, Double)],
  parts : Array[(Double, Double, Double, Double)],
  w : Double,
  h : Double,
) -> Array[String] {
  if parts.iter().any(fn(p) { p.2 < 0.0 }) {
    return []
  }
  let clip = fn(r : (Double, Double, Double, Double)) {
    (dmax(r.0, 0.0), dmax(r.1, 0.0), dmin(r.2, w), dmin(r.3, h))
  }
  let empty = fn(r : (Double, Double, Double, Double)) { r.2 <= r.0 || r.3 <= r.1 }
  let meet = fn(a : (Double, Double, Double, Double), b : (Double, Double, Double, Double)) {
    (dmax(a.0, b.0), dmax(a.1, b.1), dmin(a.2, b.2), dmin(a.3, b.3))
  }
  let held = fn(r : (Double, Double, Double, Double)) {
    parts.iter().any(fn(p) {
      r.0 >= p.0 - 1.0e-6 && r.1 >= p.1 - 1.0e-6 && r.2 <= p.0 + p.2 + 1.0e-6 && r.3 <= p.1 + p.3 + 1.0e-6
    })
  }
  // (each of `now` drawn as one of `was` was, the n-th of its numbers and place with the n-th: their places in each)
  let of_was : Map[(Int64, (Double, Double, Double, Double)), Array[Int]] = {}
  for k, i in was {
    match of_was.get((i.hash, i.reach)) {
      Some(ks) => ks.push(k)
      None => of_was[(i.hash, i.reach)] = [k]
    }
  }
  let paired : Map[(Int64, (Double, Double, Double, Double)), Int] = {}
  let pairs : Array[(Int, Int)] = []
  let kept = FixedArray::make(was.length(), false)
  let changed : Array[(String, (Double, Double, Double, Double), HostDrawn)] = []
  for k, i in now {
    let n = paired.get((i.hash, i.reach)).unwrap_or(0)
    match of_was.get((i.hash, i.reach)) {
      Some(ks) if n < ks.length() => {
        paired[(i.hash, i.reach)] = n + 1
        pairs.push((k, ks[n]))
        kept[ks[n]] = true
      }
      _ => changed.push(("come", clip(i.reach), i))
    }
  }
  for k, i in was {
    if !kept[k] {
      changed.push(("gone", clip(i.reach), i))
    }
  }
  // (one come where one went at the same place: what of its numbers differ, slot by slot)
  let otherwise = fn(x : HostDrawn, among : Array[HostDrawn]) {
    match among.search_by(fn(o) { o.reach == x.reach && o.hash != x.hash && o.numbers[0] == x.numbers[0] }) {
      Some(k) => {
        let o = among[k].numbers
        let d = []
        for j in 0..<inst_size {
          if o[j] != x.numbers[j] && d.length() < 6 {
            d.push("slot \{j} \{o[j]} to \{x.numbers[j]}")
          }
        }
        " (" + d.join(", ") + ")"
      }
      None => ""
    }
  }
  let out = []
  let areas = []
  for x in changed {
    if !empty(x.1) {
      areas.push(x.1)
      if !held(x.1) {
        out.push("\{x.0} at \{x.1}" + (if x.0 == "come" { otherwise(x.2, was) } else { "" }))
      }
    }
  }
  // (the pairs in `now`'s order, the most of them in `was`'s order too (its longest rising run of places in `was`) as
  // they were: two drawn the other way round have one outside it, compared with every other)
  let tails : Array[Int] = []
  let before = FixedArray::make(pairs.length(), -1)
  for p, q in pairs {
    let mut lo = 0
    let mut hi = tails.length()
    while lo < hi {
      let m = (lo + hi) / 2
      if pairs[tails[m]].1 < q.1 {
        lo = m + 1
      } else {
        hi = m
      }
    }
    if lo > 0 {
      before[p] = tails[lo - 1]
    }
    if lo == tails.length() {
      tails.push(p)
    } else {
      tails[lo] = p
    }
  }
  let in_order = FixedArray::make(pairs.length(), false)
  let mut p = if tails.is_empty() { -1 } else { tails[tails.length() - 1] }
  while p >= 0 {
    in_order[p] = true
    p = before[p]
  }
  for p, a in pairs {
    if in_order[p] {
      continue
    }
    for q, b in pairs {
      // (each two once: one outside the run with every one in it, and with each outside it after it)
      if q == p || (!in_order[q] && q < p) || (a.1 < b.1) == (p < q) {
        continue
      }
      let over = meet(clip(now[a.0].reach), clip(now[b.0].reach))
      if !empty(over) {
        areas.push(over)
        if !held(over) {
          out.push("drawn the other way round at \{over}")
        }
      }
    }
  }
  for cap in captures {
    let cap = clip(cap)
    let under = areas.iter().any(fn(x) { x.0 < cap.2 && cap.0 < x.2 && x.1 < cap.3 && cap.1 < x.3 })
    if !empty(cap) && under && !held(cap) {
      out.push("glass copying \{cap} under a change")
    }
  }
  out
}
