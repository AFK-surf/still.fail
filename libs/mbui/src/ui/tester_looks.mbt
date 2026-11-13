// A Tester's look at each frame painted alone or of its looks alone (frame_watch.mbt): the same frame built whole
// after it, as it began, nothing it says to tell told, and the two compared, the test failing where they differ; what
// a list moved with nothing built is found, pressed and read out by, and the words it keeps, compared too. Nothing of
// the app's frames asks it: the Tester has it look at each frame as it is drawn (frame_look).

///|
/// Whether each frame painted alone or of the looks alone is drawn whole after it as well and the two compared (a
/// Tester's: every test holds it); a host draws it once.
// kept across runs: set by each Tester as it is made (Tester::new), a bench's turned off
let looks_check : Ref[Bool] = Ref(false)

///|
/// What the frame is found, pressed and read out by, and the words it keeps, as lines (looks_check: a frame where a
/// list moved with nothing built against it built whole).
fn scroll_said(c : Ctx) -> Array[String] {
  let out : Array[String] = []
  for k in 0..<c.hit_ids.length() {
    let r = c.hit_rects
    let q = c.hit_clips
    out.push(
      "target \{c.hit_ids[k]} at \{r[k * 4]},\{r[k * 4 + 1]} \{r[k * 4 + 2]}×\{r[k * 4 + 3]} cut \{q[k * clip_n]},\{q[k * clip_n + 1]},\{q[k * clip_n + 2]},\{q[k * clip_n + 3]}",
    )
  }
  for sm in c.sems {
    let nd = c.nodes[sm.node]
    out.push("read out \{sm.id} \{sm.label} at \{nd.x},\{nd.y} \{nd.fw}×\{nd.fh}")
  }
  let keys : Array[String] = []
  words_kept.each(fn(k, _) { keys.push(k) })
  keys.sort()
  for k in keys {
    let w = words_kept[k]
    for p in w.pieces {
      out.push("words \{k} at \{p.x},\{p.y} \{p.w}×\{p.h} from \{p.start}")
    }
  }
  out
}

///|
/// The instances of `a`, `n` of them, that draw something: those its clip (16-19) or its outer clip (40-43), where it
/// has one, cut wholly away left out; and how many.
fn looks_seen(a : FixedArray[Double], n : Int) -> (FixedArray[Double], Int) {
  let out = FixedArray::make(n * inst_size + 1, 0.0)
  let mut k = 0
  let away = fn(b : Int, c : Int) {
    let set = a[b + c] != 0.0 || a[b + c + 1] != 0.0 || a[b + c + 2] != 0.0 || a[b + c + 3] != 0.0
    set &&
    a[b + 2] > 0.0 &&
    a[b + 3] > 0.0 &&
    (dmin(a[b] + a[b + 2], a[b + c + 2]) <= dmax(a[b], a[b + c]) ||
    dmin(a[b + 1] + a[b + 3], a[b + c + 3]) <= dmax(a[b + 1], a[b + c + 1]))
  }
  for q in 0..<n {
    let b = q * inst_size
    if away(b, 16) || away(b, 40) {
      continue
    }
    a.blit_to(out, len=inst_size, src_offset=b, dst_offset=k * inst_size)
    k = k + 1
  }
  (out, k)
}

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
  // (what is drawn of each: one its clips cut wholly away draws nothing, as a host draws it (a page's list's rows past
  // where it shows, kept in its group, cut by its header's clip: view_ride.mbt's inst_cut_to))
  let (alone, n) = looks_seen(alone, n)
  let (whole, m) = looks_seen(c.inst, c.ninst)
  let mut first = -1
  let mut slot = -1
  for q in 0..<(if n < m { n } else { m }) {
    let b = q * inst_size
    for j in 0..<inst_size {
      let x = alone[b + j]
      let y = whole[b + j]
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
      (whole[first * inst_size], whole[first * inst_size + 1])
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
      "the frame at \{at} ms \{kind} (\{n} instances) parts from it built whole (\{m}) at instance \{first}: \{inst(alone, first, n)}, built whole \{inst(whole, first, m)}; words there: \{there.join(" | ")}; \{looks_node_moved(c, then)}",
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
  if looks_unjudged.val {
    return
  }
  @halt.saying(said)
}

///|
/// Whether this Tester's frames are not judged (a frame not built whole, how what moves goes): a run whose frames are
/// only the way to what it tells its core (sfreplay's pace passes, held to their strict pass's messages), every other
/// run judging them.
// kept across runs: set by the Tester that asks it (Tester::frames_unjudged), off as each Tester is made
let looks_unjudged : Ref[Bool] = Ref(false)

///|
/// This Tester's frames not judged (looks_unjudged): `on` for its run.
pub fn Tester::frames_unjudged(self : Tester, on : Bool) -> Unit {
  looks_unjudged.val = on
  if on {
    self.motion = Results
  }
}

///|
/// Whether this Tester's frames are not judged for how what moves goes (words_over, rows_steady, sizes_steady,
/// gaps_steady), all else of them judged as ever: a sweep of every screen at rest, each opened with motion reduced, whose
/// frames are only the way to the screen it looks at (the app's corners, contrast, squeeze_said and words_large). For
/// CI's time while its runners are few (the user, 2026-11-12: 「先省吧，明天加机器，再改回来」): judged again once there
/// are more.
// kept across runs: set by the Tester that asks it (Tester::motion_unjudged), off as each Tester is made
let motion_unjudged : Ref[Bool] = Ref(false)

///|
/// This Tester's frames not judged for how what moves goes (motion_unjudged): `on` for its run.
pub fn Tester::motion_unjudged(self : Tester, on : Bool) -> Unit {
  ignore(self)
  motion_unjudged.val = on
  // (its file's bars not set beside what it found, none of it looked for: motion_runs, `MOTION unjudged <file>`)
  if on && motion_runs() {
    let at = looks_made_at.val
    println("MOTION unjudged \{match at.find(":") { Some(i) => at.unsafe_substring(start=0, end=i); None => at }}")
  }
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
  self.reads_own()
  ignore(self)
  built_why.val
}

///|
/// Why the last frame was painted alone, from the last build's tree ("" where it was built whole or of its looks
/// alone): what its paint read changed (the clock, where it read it so), a moment its paint waits for came, the paint
/// before it drew otherwise.
pub fn Tester::painted_why(self : Tester) -> String {
  self.reads_own()
  ignore(self)
  painted_why.val
}

///|
/// Whether two numbers of an instance draw the same: equal, both none (NaN), or apart by no more than the rounding of
/// adding a move to what was placed as laid out (Ctx::moved_place) leaves, a billionth of them: nothing a pixel shows.
fn drawn_same(x : Double, y : Double) -> Bool {
  x == y || (x.is_nan() && y.is_nan()) || (x - y).abs() <= 1.0e-9 * dmax(1.0, dmax(x.abs(), y.abs()))
}


///|
/// The nodes of the frame `c` painted last, as looks_compare says where one moved: kept as each frame painted ends.
fn looks_nodes_kept(c : Ctx) -> Unit {
  looks_nodes.clear()
  for i in 0..<c.count {
    let nd = c.nodes[i]
    looks_nodes.push((nd.x, nd.y, nd.fw, nd.fh, nd.text, nd.id, nd.tx, nd.ty, nd.opacity))
  }
}

///|
/// A frame as it is drawn, looked at where the Tester checks the looks (frame_look, looks_check): built whole or
/// painted alone, its nodes kept for the compare after it; painted alone or of its looks alone, built whole again as
/// it began (no row kept; what its builds say to tell told only where the frame told nothing of its own, a list moved
/// in it having told what follows it) and the two compared, the test failing where they differ.
fn looks_looked(
  c : Ctx,
  _w : Double,
  _h : Double,
  _scale : Double,
  t : Double,
  kind : Int,
  scrolled : Bool,
) -> Unit {
  if !looks_check.val {
    return
  }
  if kind < 2 {
    looks_nodes_kept(c)
  }
  if kind == 0 {
    return
  }
  c.flat_from(0)
  let n = c.ninst
  let alone = FixedArray::make(n * inst_size + 1, 0.0)
  c.inst.blit_to(alone, len=n * inst_size)
  let wake = looks_own.wake
  let cycling = looks_own.cycling
  let then = looks_nodes.copy()
  let painted = kind == 1
  // (a list moved with nothing built: what it is found and read out by, and its words, compared too)
  let was = if scrolled { Some(scroll_said(c)) } else { None }
  // (built whole as a frame begins: what the paint alone read, read anew by its paint; no row kept; no frame of the
  // app's, what a test asks of each frame not told of it)
  let hook = frame_hook.val
  frame_hook.val = None
  paint_phase.val = 0
  nodes_run.fresh = true
  nodes_run.whole = true
  frame_watch_of().read(fn() { frame_body_drawn(c, t, tell=!scrolled) }) |> ignore
  c.flat_from(0)
  frame_hook.val = hook
  looks_drawn.val = false
  painted_alone.val = false
  looks_compare(c, alone, n, wake, cycling, t, then, painted~)
  looks_nodes_kept(c)
  match was {
    Some(was) => {
      let now = scroll_said(c)
      if was != now {
        let mut k = 0
        while k < was.length() && k < now.length() && was[k] == now[k] {
          k = k + 1
        }
        looks_fail(
          "the frame at \{t.to_int()} ms, a list moved with nothing built, parts from it built whole: \{was.get(k).unwrap_or("none")}, built whole \{now.get(k).unwrap_or("none")}; built whole because \{built_why.val}",
        )
      }
    }
    None => ()
  }
}

///|
/// How many frames were drawn of their looks alone so far (frame_watch.mbt: nothing built, laid out or painted, a list
/// moved by its header), each drawn whole after it as well and compared where the looks are checked.
pub fn Tester::looks_alone(self : Tester) -> Int {
  self.reads_own()
  ignore(self)
  looks_frames.val
}
