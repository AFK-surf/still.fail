// A Tester's look at each pass of a frame's build that kept rows (kept_nodes.mbt): the frame built once more keeping
// none, as laid out, and the two compared node for node, the test failing where the rows kept are what parts them.
// Nothing of the app's frames asks it: the Tester does, as each pass is over (pass_looked).
//
// Before it is built again, the pass that kept rows is painted as well, as a host paints it (frame_paint's
// `drawn_only`: its targets found and it drawn, nothing of it taken, told or given out), and what it drew and was
// found by kept; what that paint changed of what the frame goes on to do is put back (Ctx::kept_painted). Once the
// frame is painted, from the build keeping none, the two are compared, each instance drawn (as looks_compare does)
// and each target (its id, marks, rect and clip): where they part, a line is printed (KEPT-APART), nothing fails yet;
// what each Tester's frames came to is said as it is let go or the next is made (KEPT-SEEN). Tester::kept_compare
// (MBUI_KEPT_COMPARE=0) turns it off.
//
// What it does not close: the frame still goes on from the build keeping none, so a Tester's state after such a frame
// is not a host's (what the kept build would have left behind, `desk.next_sels` grown by frames painted between builds
// one case, the rows' drawings recorded by the build keeping none another, are not what a host would carry on with).
// What a kept build draws and is pressed by is compared, frame by frame; what a host's state comes to over many kept
// frames in a row is not. Nor what the frame does after its builds and before its paint (the packages' on_frame_built,
// words picked with the pointer, what is told outside): the kept build is painted before those, the frame's after.

///|
/// A pass of a frame's build that kept rows, as laid out (frame_said_lines), and where the rows it kept were among its
/// nodes (list, item, first node, how many): compared once the frame is built again keeping none (rows_check_end).
priv struct RowsCheck {
  lines : Array[String]
  rows : Array[(Int, Int, Int, Int, Double)]
  /// where it parted from the first build keeping none: that build's lines and the first line apart; the second such
  /// build says whether they part because rows were kept or because what was built changed as it was built
  mut whole : Array[String]?
  mut at : Int
  /// what the pass that kept rows said to tell outside (Ctx::after_build): the frame's, told as it was said; a build
  /// to compare with tells nothing (what is told once, felt as a hold opened its menu, it does not tell again)
  tells : Array[(Int, () -> Unit)]
}

///|
// kept across runs: set and let go within a frame
let rows_checking : Ref[RowsCheck?] = Ref(None)

///|
/// A pass of the frame's build is over (frame_body), `kept0` the rows kept before it: where a Tester checks frames
/// (looks_check) and it kept rows, what it built and said is taken, and the frame built once more keeping none (true:
/// the caller builds it again), the two compared as that is laid out (rows_check_end). In the frame, before what its
/// builds tell outside and before it is painted: built again from the same state, it must come out the same, node for
/// node, and say the same of the frame; so it is painted the same.
fn Ctx::rows_check_begin(self : Ctx, kept0 : Int, root : Int) -> Bool {
  if nodes_run.kept <= kept0 || rows_checking.val is Some(_) {
    return false
  }
  // (what it read changed as it was built or laid out, a measure taken as it was laid out: built again, it would build
  // otherwise, from what this pass left; the next frame builds it so)
  if nodes_run.told || layout_said.val != "" || watch_said.val != "" || frame_watch_of().changed_as_read() {
    kept_tally.skipped += 1
    return false
  }
  let rows = []
  for key, rn in kept_nodes {
    if rn.in_pool {
      rows.push((key.0, key.1, rn.base, rn.n, rn.built_at))
    }
  }
  rows_checking.val = Some({ lines: self.frame_said_lines(), rows, whole: None, at: -1, tells: self.tells.copy() })
  // (what the build that kept rows draws and is found by, kept to compare with the frame as it is painted: taken
  // after its lines, as a paint marks what it draws, kept_pass_drawn)
  if kept_compare.val {
    self.kept_painted(root)
  }
  nodes_run.fresh = true
  nodes_run.whole = true
  // (one pass of the frame, as a host builds it: not counted, FramePerf's `passes`)
  perf_at[3] = perf_at[3] - 1
  true
}

///|
/// The frame built again keeping no row (rows_check_begin) is laid out: what it built and said must be what the pass
/// that kept rows built and said. Where it is not, it is built once more keeping none (true: the caller builds it
/// again): that coming out as the first such build did, the rows kept are what parts them, and the test fails, saying
/// the first line they part at and the row kept that holds it; coming out otherwise, what was built changed as it was
/// built (from what no signal says), kept rows or not, and the next frame builds it so.
fn Ctx::rows_check_end(self : Ctx) -> Bool {
  guard rows_checking.val is Some(was) else { return false }
  let now = self.frame_said_lines()
  match was.whole {
    None => {
      let at = lines_apart(was.lines, now)
      if at < 0 {
        rows_checking.val = None
        self.tells.clear()
        self.tells.append(was.tells)
        return false
      }
      // (apart: built once more keeping none, to know whether what parts them is the rows kept)
      was.whole = Some(now)
      was.at = at
      perf_at[3] = perf_at[3] - 1
      return true
    }
    Some(whole) => {
      rows_checking.val = None
      // (built again keeping none, it built otherwise again: what it built changed as it was built, from what it
      // read that no signal says, kept rows or not; the next frame builds it so)
      if lines_apart(whole, now) >= 0 {
        self.tells.clear()
        self.tells.append(was.tells)
        return false
      }
    }
  }
  let now = was.whole.unwrap()
  let at = was.at
  let line = fn(a : Array[String], j : Int) { if j < a.length() { a[j] } else { "none" } }
  // (the row kept that holds the node, where the line is a node's)
  let mut holder = "none of the rows kept"
  for r in was.rows {
    if at >= r.2 && at < r.2 + r.3 {
      // (and the words it holds as built now, to know it by)
      let words = []
      for j in r.2..<imin(r.2 + r.3, self.count) {
        let t = self.nodes[j]
        if (t.kind == kind_text || t.kind == kind_rich) && t.text != "" && words.length() < 6 {
          words.push(t.text)
        }
      }
      holder = "list \{r.0}'s row \{r.1} (its node \{at - r.2}; its words: \{words.join(" | ")}; built at \{r.4.to_int()} ms)"
      // (all of it, both ways, where the Tester's said log asks: MBUI_ROWS_PARTED=1)
      if @hostapi.env("MBUI_ROWS_PARTED") == "1" {
        for j in r.2..<(r.2 + r.3) {
          println("ROWS-PARTED kept  \{line(was.lines, j)}")
          println("ROWS-PARTED built \{line(now, j)}")
        }
      }
    }
  }
  // (every line the two part at, the first 40, each way: what was kept that building anew did not make)
  let parted = StringBuilder()
  let mut shown = 0
  for j in 0..<imax(was.lines.length(), now.length()) {
    let a = line(was.lines, j)
    let b = line(now, j)
    if a != b && shown < 40 {
      shown += 1
      parted.write_string("\nPARTED kept  " + a)
      parted.write_string("\nPARTED built " + b)
    }
  }
  looks_fail(
    "the frame at \{self.clock.to_int()} ms, built keeping \{was.rows.length()} rows, (\{built_why.val}), parts from it built keeping none at line \{at} (\{holder}): kept \{line(was.lines, at)} / \{line(was.lines, at + 1)}; built \{line(now, at)} / \{line(now, at + 1)}" + parted.to_string(),
  )
  false
}

///|
/// The first line where `a` and `b` part (-1: none).
fn lines_apart(a : Array[String], b : Array[String]) -> Int {
  let n = imin(a.length(), b.length())
  for j in 0..<n {
    if a[j] != b[j] {
      return j
    }
  }
  if a.length() != b.length() {
    n
  } else {
    -1
  }
}

///|
/// What the frame built, as laid out, a line each: each node (what it is, where, how large, how it looks, what holds it
/// and what it holds, its look of draw.mbt's), then what it said of the frame (said.mbt's build lists, what is read out
/// and hidden from that, the corners worked out once laid out, the words kept, what asks to be lit).
fn Ctx::frame_said_lines(self : Ctx) -> Array[String] {
  let out = []
  // (in the tree's order, each node by where it is in it: what a frame is is its tree, not where in the frame's nodes
  // each was made, which a part kept as its nodes and the same built anew may make in another order)
  let order = self.tree_order()
  let at = Array::make(self.count, -1)
  for k, i in order {
    at[i] = k
  }
  let pos = fn(i : Int) { if i >= 0 && i < at.length() { at[i] } else { i } }
  for i in order {
    let nd = self.nodes[i]
    let drawn = match self.drawn_entry(i) {
      Some(e) =>
        " look \{e.look} z \{e.z} only \{e.only} cut \{e.top},\{e.bottom} ground \{e.ground} by \{e.look_by is Some(_)} cycle \{e.cycle is Some(_)}"
      None => ""
    }
    // (its words and their face where it has words: a box keeps what an earlier node of the slot held, unread)
    let words = if nd.kind == kind_image {
      " \"\{nd.text}\" still \{nd.still} fade \{nd.fade}"
    } else if nd.kind == kind_rich {
      " \"\{nd.text}\" \{nd.rl.map(fn(r) { (r.text, r.line_w, r.line_y) })}"
    } else if nd.kind != kind_text && nd.kind != kind_editor {
      ""
    } else {
      " \"\{nd.text}\" color \{nd.color} font \{nd.font_size} \{nd.weight} wrap \{nd.wrap} lines \{nd.max_lines}" +
      (if nd.kind == kind_text {
        " \{nd.tl.map(fn(t) { (t.text, t.w, t.h) })}"
      } else if nd.kind == kind_rich {
        " \{nd.rl.map(fn(r) { (r.text, r.line_w, r.line_y) })}"
      } else {
        ""
      })
    }
    out.push(
      "\{pos(i)} kind \{nd.kind} id \{nd.id} parent \{pos(nd.parent)} first \{pos(nd.first)} next \{pos(nd.next)} item \{nd.item} at \{said_at(nd.x)},\{said_at(nd.y)} \{said_at(nd.fw)}×\{said_at(nd.fh)} tx \{nd.tx},\{nd.ty} moved \{nd.moved_x},\{nd.moved_y} bg \{nd.bg} alpha \{nd.opacity} radius \{said_at(nd.radius)} \{nd.radii.map(fn(r) { r.map(said_at) })} border \{nd.border_w} \{nd.border_c} shadow \{nd.shadow} \{nd.shadow_c} clip \{nd.clip} hit \{nd.hit} points \{nd.points} layer \{nd.layer} \{nd.portal} \{nd.portal_id} size \{size_said(nd.w)} \{size_said(nd.h)} placed \{nd.at_l},\{nd.at_t},\{nd.at_r},\{nd.at_b}" +
      words +
      drawn,
    )
  }
  let sb = StringBuilder()
  for l in build_lists {
    l.said_take(self, 0).said_show(sb)
  }
  for l in sb.to_string().split("\n") {
    out.push(l.to_string())
  }
  let sems = self.sems.map(fn(s) { (pos(s.node), "\{s.id} \{s.label} \{s.value} \{s.hidden}") })
  sems.sort_by(fn(a, b) { a.0.compare(b.0) })
  out.push("sems " + sems.map(fn(s) { "\{s.0} \{s.1}" }).join("; "))
  let corners = fn(a : Array[Int]) {
    let t = a.map(pos)
    t.sort()
    t
  }
  out.push("inners \{corners(self.inners)} \{corners(self.inners_or)} \{corners(self.arounds)}")
  let words = []
  words_kept.each(fn(k, w) { words.push("\{k}: \{w.text} \{w.pieces.map(fn(p) { (p.x, p.y, p.w, p.h) })}") })
  words.sort()
  out.push("words " + words.join("; "))
  let lit = self.lit_asked.iter().collect()
  lit.sort()
  let chooses = self.hand_chooses.iter().collect()
  chooses.sort()
  out.push("lit \{lit} \{chooses}")
  // (the ids said numbered as Tester::said numbers them: that numbering let go, it numbers its own)
  if !said_log.on {
    said_log.ids.clear()
  }
  out
}

///|
/// A length as compared (frame_said_lines): to a millionth of a point, what is drawn the same is (frame_watch.mbt's
/// drawn_same), however its sum was added up.
fn said_at(x : Double) -> Double {
  (x * 1.0e6).round() / 1.0e6
}

///|
/// A size as compared (frame_said_lines).
fn size_said(s : Size) -> String {
  match s {
    Auto => "auto"
    Px(p) => "\{p}px"
    Fill(k) => "fill \{k}"
    Cut => "cut"
    Pct(p) => "\{p}%"
  }
}


///|
/// A pass of a frame's build is over: `0` as it is laid out, `1` as nothing else builds it again (`kept0` the rows kept
/// before it). Where the Tester checks the looks (looks_check): what kept rows built again keeping none and compared
/// (true: the frame builds it again).
fn rows_pass_looked(c : Ctx, at : Int, kept0 : Int, root : Int) -> Bool {
  if !looks_check.val {
    return false
  }
  if at == 0 {
    c.rows_check_end()
  } else {
    c.rows_check_begin(kept0, root)
  }
}

// ── what a build that kept rows draws and is found by ──────────────────────

///|
/// What a pass that kept rows drew and was found by, painted as it was built (Ctx::kept_painted): compared with the
/// frame as it is painted from the build keeping none (kept_drawn_compare).
priv struct KeptDrawn {
  clock : Double
  /// its instances, drawn out (what a host draws: ride_draw_out), `n` of them
  inst : FixedArray[Double]
  n : Int
  /// its targets as its paint found them, before the old views' were placed where the tree has them (old_hits_framed):
  /// each one's id, marks, rect (4 a target) and clip (clip_n a target)
  ids : Array[Int]
  marks : Array[Int]
  rects : Array[Double]
  clips : Array[Double]
}

///|
// kept across runs: set and let go within a frame
let kept_pass_drawn : Ref[KeptDrawn?] = Ref(None)

///|
/// Whether a pass that kept rows is painted and compared with the frame (Tester::kept_compare): on unless the test
/// program's environment says MBUI_KEPT_COMPARE=0, as each Tester is made.
// kept across runs: set as each Tester is made
let kept_compare : Ref[Bool] = Ref(true)

///|
/// What one Tester's frames came to, said as it is let go or the next is made (kept_seen_said): frames with rows kept
/// compared, those whose drawing or targets were apart, passes that kept rows not checked by today's conditions.
priv struct KeptSeen {
  /// where the Tester was made, its number among the run's Testers and its window (the scene, as its lines say it)
  mut made : String
  mut n : Int
  mut frames : Int
  mut drawn : Int
  mut targets : Int
  mut skipped : Int
}

///|
// kept across runs: said and begun again as each Tester is made
let kept_tally : KeptSeen = { made: "", n: 0, frames: 0, drawn: 0, targets: 0, skipped: 0 }

///|
/// Whether each pass of a frame's build that kept rows is painted as it was built as well, and what it draws and is
/// found by compared with the frame painted from it built keeping none, each that parts printed (KEPT-APART), never
/// failing (on as a Tester is made, unless MBUI_KEPT_COMPARE=0).
pub fn Tester::kept_compare(self : Tester, on : Bool) -> Unit {
  ignore(self)
  kept_compare.val = on
}

///|
/// What the last Tester's frames came to (KEPT-SEEN), said once; then begun again for the one made at `made` (none: a
/// Tester let go), `w` by `h`: said as its scene, the Tester's place, its number among the run's and its window.
fn kept_seen_said(made : String, w? : Double = 0.0, h? : Double = 0.0) -> Unit {
  if kept_tally.made != "" {
    println(
      "KEPT-SEEN \{kept_tally.made}|frames with rows kept that were compared \{kept_tally.frames}|apart drawn \{kept_tally.drawn}|apart targets \{kept_tally.targets}|skipped by today's conditions \{kept_tally.skipped}",
    )
  }
  kept_tally.n = if made == "" { kept_tally.n } else { kept_tally.n + 1 }
  kept_tally.made = if made == "" { "" } else { "\{made} tester #\{kept_tally.n} \{w}x\{h}" }
  kept_tally.frames = 0
  kept_tally.drawn = 0
  kept_tally.targets = 0
  kept_tally.skipped = 0
  kept_pass_drawn.val = None
}

///|
/// The instances `a` (`n` of them) drawn out as a host draws them, in a copy: each header of a group (ride_spans) put
/// out in its place, `a` and the spans left as they are.
fn kept_drawn_out(a : FixedArray[Double], n : Int) -> FixedArray[Double] {
  let out = FixedArray::make(n * inst_size + 1, 0.0)
  a.blit_to(out, len=n * inst_size)
  for k = ride_spans.length() - 1; k >= 0; k = k - 1 {
    if ride_spans[k] < n {
      ride_draw_out(out, ride_spans[k])
    }
  }
  out
}

///|
/// The pass just built, which kept rows, painted as a host paints it (frame_paint's `drawn_only`: drawn and its targets
/// found, nothing taken, told or given out), what it drew and was found by kept (kept_pass_drawn); then what that paint
/// changed of what the frame goes on to do put back as it stood: the frame is built again keeping none and painted
/// from that (rows_check_begin), as it was before this look.
fn Ctx::kept_painted(self : Ctx, root : Int) -> Unit {
  let wake_at = self.wake_at
  let base_wake = paint_base.wake
  let clock_at = paint_clock_at.val
  let said = paint_said.val
  let reads = clock_reads.val
  let culled = paint_culled.val
  let phase = paint_phase.val
  let uncompared = scroll_paint_uncompared.val
  let finds = targets_finds.val
  let sels = desk.next_sels.length()
  let targets_said = dr.targets_said
  let tree_scrolled = match view_app.val {
    Some(t) => Some(t.scrolled_held())
    None => None
  }
  @signals.untracked(fn() { frame_paint(self, root, drawn_only=true) })
  kept_pass_drawn.val = Some({
    clock: self.clock,
    inst: kept_drawn_out(self.inst, self.ninst),
    n: self.ninst,
    ids: self.next_hit_ids.copy(),
    marks: self.next_hit_marks.copy(),
    rects: self.next_hit_rects.copy(),
    clips: self.next_hit_clips.copy(),
  })
  self.wake_at = wake_at
  paint_base.wake = base_wake
  paint_clock_at.val = clock_at
  paint_said.val = said
  clock_reads.val = reads
  paint_culled.val = culled
  paint_phase.val = phase
  scroll_paint_uncompared.val = uncompared
  targets_finds.val = finds
  while desk.next_sels.length() > sels {
    desk.next_sels.pop() |> ignore
  }
  dr.targets_said = targets_said
  match (view_app.val, tree_scrolled) {
    (Some(t), Some(h)) => t.scrolled_put_back(h)
    _ => ()
  }
}

///|
/// The words of the frame's nodes over the point (`x`, `y`), the first six: what is drawn there, to know it by.
fn kept_words_at(c : Ctx, x : Double, y : Double) -> String {
  let there = []
  for i in 0..<c.count {
    let nd = c.nodes[i]
    if nd.text != "" && there.length() < 6 && x >= nd.x - 1.0 && x <= nd.x + nd.fw + 1.0 && y >= nd.y - 1.0 &&
      y <= nd.y + nd.fh + 1.0 {
      there.push(nd.text)
    }
  }
  there.join(" | ")
}

///|
/// Target `k` of `ids` (and its `marks`, `rects`, `clips`) as compared: its id, marks, rect and clip.
fn kept_target_said(ids : Array[Int], marks : Array[Int], rects : Array[Double], clips : Array[Double], k : Int) -> String {
  if k >= ids.length() {
    return "none"
  }
  let r = []
  for j in 0..<4 {
    r.push(said_at(rects.get(k * 4 + j).unwrap_or(0.0 / 0.0)))
  }
  let cl = []
  for j in 0..<clip_n {
    cl.push(said_at(clips.get(k * clip_n + j).unwrap_or(0.0 / 0.0)))
  }
  "\{ids[k]} marks \{marks.get(k).unwrap_or(0)} rect \{r} clip \{cl}"
}

///|
/// The frame just painted, from the build keeping none, against what the pass that kept rows drew and was found by
/// (kept_pass_drawn), where one was kept for this frame: each instance as looks_compare has them, each target line for
/// line; what parts printed (KEPT-APART: the first of each kind, and how many), never failing.
fn kept_drawn_compare(c : Ctx) -> Unit {
  guard kept_pass_drawn.val is Some(k) else { return }
  kept_pass_drawn.val = None
  if k.clock != c.clock {
    return
  }
  kept_tally.frames += 1
  let at = c.clock
  let (a, n) = looks_seen(k.inst, k.n)
  let (b, m) = looks_seen(kept_drawn_out(c.inst, c.ninst), c.ninst)
  let mut first = -1
  let mut apart = 0
  for q in 0..<imin(n, m) {
    let base = q * inst_size
    let mut same = true
    for j in 0..<inst_size {
      if !drawn_same(a[base + j], b[base + j]) {
        same = false
        break
      }
    }
    if !same {
      apart += 1
      if first < 0 {
        first = q
      }
    }
  }
  apart += (n - m).abs()
  if first < 0 && n != m {
    first = imin(n, m)
  }
  if apart > 0 {
    kept_tally.drawn += 1
    let (px, py) = if first < m {
      (b[first * inst_size], b[first * inst_size + 1])
    } else {
      (a[first * inst_size], a[first * inst_size + 1])
    }
    let words = kept_words_at(c, px + 1.0, py + 1.0)
    let nums = fn(x : FixedArray[Double], q : Int, cnt : Int) {
      if q >= cnt {
        "none"
      } else {
        let v = []
        for j in 0..<inst_size {
          v.push(x[q * inst_size + j].to_string())
        }
        v.join(" ")
      }
    }
    println(
      "KEPT-APART \{kept_tally.made}|\{at}|drawn|instance \{first} of \{n} kept, \{m} built|kept \{nums(a, first, n)}|built \{nums(b, first, m)}|apart \{apart}|words there: \{words}",
    )
  }
  let kn = k.ids.length()
  let bn = c.hit_ids.length()
  let mut tfirst = -1
  let mut tapart = 0
  for q in 0..<imax(kn, bn) {
    let x = kept_target_said(k.ids, k.marks, k.rects, k.clips, q)
    let y = kept_target_said(c.hit_ids, c.hit_marks, old_hits_rects, old_hits_clips, q)
    if x != y {
      tapart += 1
      if tfirst < 0 {
        tfirst = q
      }
    }
  }
  if tapart > 0 {
    kept_tally.targets += 1
    let (rs, rk) = if tfirst < bn { (old_hits_rects, tfirst) } else { (k.rects, tfirst) }
    let words = kept_words_at(c, rs.get(rk * 4).unwrap_or(0.0) + 1.0, rs.get(rk * 4 + 1).unwrap_or(0.0) + 1.0)
    println(
      "KEPT-APART \{kept_tally.made}|\{at}|target|\{tfirst} of \{kn} kept, \{bn} built|kept \{kept_target_said(k.ids, k.marks, k.rects, k.clips, tfirst)}|built \{kept_target_said(c.hit_ids, c.hit_marks, old_hits_rects, old_hits_clips, tfirst)}|apart \{tapart}|words there: \{words}",
    )
  }
}
