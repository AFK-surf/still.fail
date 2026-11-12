// A Tester's look at each pass of a frame's build that kept rows (kept_nodes.mbt): the frame built once more keeping
// none, as laid out, and the two compared node for node, the test failing where the rows kept are what parts them.
// Nothing of the app's frames asks it: the Tester does, as each pass is over (pass_looked).

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
fn Ctx::rows_check_begin(self : Ctx, kept0 : Int) -> Bool {
  if nodes_run.kept <= kept0 || rows_checking.val is Some(_) {
    return false
  }
  // (what it read changed as it was built or laid out, a measure taken as it was laid out: built again, it would build
  // otherwise, from what this pass left; the next frame builds it so)
  if nodes_run.told || layout_said.val != "" || watch_said.val != "" || frame_watch_of().changed_as_read() {
    return false
  }
  let rows = []
  for key, rn in kept_nodes {
    if rn.in_pool {
      rows.push((key.0, key.1, rn.base, rn.n, rn.built_at))
    }
  }
  rows_checking.val = Some({ lines: self.frame_said_lines(), rows, whole: None, at: -1, tells: self.tells.copy() })
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
        " look \{e.look} z \{e.z} only \{e.only} cut \{e.top},\{e.bottom} ground \{some_text(e.ground.map(fn(g) { "(\{g.0}, \{g.1}, \{g.2}, \{g.3}, \{rect_text(g.4)})" }))} by \{e.look_by is Some(_)} cycle \{e.cycle is Some(_)}"
      None => ""
    }
    // (its words and their face where it has words: a box keeps what an earlier node of the slot held, unread)
    let words = if nd.kind == kind_image {
      " \"\{nd.text}\" still \{nd.still} fade \{nd.fade}"
    } else if nd.kind == kind_rich {
      " \"\{nd.text}\" \{some_text(nd.rl.map(fn(r) { "(\{r.text}, \{list_text(r.line_w)}, \{list_text(r.line_y)})" }))}"
    } else if nd.kind != kind_text && nd.kind != kind_editor {
      ""
    } else {
      " \"\{nd.text}\" color \{nd.color} font \{nd.font_size} \{nd.weight} wrap \{nd.wrap} lines \{nd.max_lines}" +
      (if nd.kind == kind_text {
        " \{some_text(nd.tl.map(fn(t) { "(\{t.text}, \{t.w}, \{t.h})" }))}"
      } else if nd.kind == kind_rich {
        " \{some_text(nd.rl.map(fn(r) { "(\{r.text}, \{list_text(r.line_w)}, \{list_text(r.line_y)})" }))}"
      } else {
        ""
      })
    }
    out.push(
      "\{pos(i)} kind \{nd.kind} id \{nd.id} parent \{pos(nd.parent)} first \{pos(nd.first)} next \{pos(nd.next)} item \{nd.item} at \{said_at(nd.x)},\{said_at(nd.y)} \{said_at(nd.fw)}×\{said_at(nd.fh)} tx \{nd.tx},\{nd.ty} moved \{nd.moved_x},\{nd.moved_y} bg \{nd.bg} alpha \{nd.opacity} radius \{said_at(nd.radius)} \{some_text(nd.radii.map(fn(r) { "[" + r.map(fn(x) { said_at(x).to_string() }).join(", ") + "]" }))} border \{nd.border_w} \{nd.border_c} shadow \{nd.shadow} \{nd.shadow_c} clip \{nd.clip} hit \{nd.hit} points \{nd.points} layer \{nd.layer} \{nd.portal} \{nd.portal_id} size \{size_said(nd.w)} \{size_said(nd.h)} placed \{nd.at_l},\{nd.at_t},\{nd.at_r},\{nd.at_b}" +
      words +
      drawn,
    )
  }
  let sb = StringBuilder()
  for l in build_lists {
    l.said_take(self, 0).said_show(sb)
  }
  for l in sb.to_string().split("\n") {
    out.push(l.to_owned())
  }
  let sems = self.sems.map(fn(s) { (pos(s.node), "\{s.id} \{s.label} \{s.value} \{s.hidden}") })
  sems.sort_by(fn(a, b) { a.0.compare(b.0) })
  out.push("sems " + sems.map(fn(s) { "\{s.0} \{s.1}" }).join("; "))
  let corners = fn(a : Array[Int]) {
    let t = a.map(pos)
    t.sort()
    t
  }
  out.push("inners \{list_text(corners(self.inners))} \{list_text(corners(self.inners_or))} \{list_text(corners(self.arounds))}")
  let words = []
  words_kept.each(fn(k, w) { words.push("\{k}: \{w.text} \{list_text(w.pieces.map(fn(p) { rect_text((p.x, p.y, p.w, p.h)) }))}") })
  words.sort()
  out.push("words " + words.join("; "))
  let lit = self.lit_asked.iter().collect()
  lit.sort()
  let chooses = self.hand_chooses.iter().collect()
  chooses.sort()
  out.push("lit \{list_text(lit)} \{list_text(chooses)}")
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
fn rows_pass_looked(c : Ctx, at : Int, kept0 : Int) -> Bool {
  if !looks_check.val {
    return false
  }
  if at == 0 {
    c.rows_check_end()
  } else {
    c.rows_check_begin(kept0)
  }
}
