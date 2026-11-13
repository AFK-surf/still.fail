// Words over words: while something moves, no frame shows one node's words drawn over another's, both seen. Whatever
// a motion does (a row coming in where another still is, a word crossfaded into another in its place, a hint back
// over words still in the field, words flown across others, a panel fading in with its ground as clear as its words),
// what the person sees is two lines of words in one place, which reads as neither (the user, 2026-10-29:
// 「查一下现在哪些动效会存在文字叠文字的问题」「加，然后想想这些问题怎么系统性解决一下」). Held on every frame a Tester draws
// with a motion between its ends (Ctx::motion_left, a page in the hand), as the corner rule is held on every frame at
// rest: what a test walks through is checked, not only what a test of motion looks at. Words over words at rest are
// squeeze's (squeeze.mbt).
//
// Measured on the frame's instances, as the renderers draw them (contrast.mbt keeps whose each is: `track`): each
// glyph seen (its opacity 0.12 and up), a little inside its cell and cut by its clip; two of different nodes' that
// meet by a point and more each way, where nothing whole (a fill 0.9 opaque and up, a picture, glass) is drawn between
// them or over both there. Words of one node never count against each other; a row kept as drawn (kept_nodes.mbt) is
// one node's.
//
// What is over others now is known, a file at a time (`words_over_known`, given by the app's tests as their package
// starts): a Tester made in a file shows at most as many pairs as its file's bar, which only falls as they are mended.

///|
/// The least opacity a glyph is seen at.
let words_over_seen_least : Double = 0.12

///|
/// What one Tester has found: the pairs (their words), whether it holds the rule, the file it was made in and how many
/// that file may show.
priv struct WordsOver {
  mut held : Bool
  mut file : String
  pairs : Set[String]
  // (not held: each frame's, as it was found: Tester::words_over_frames)
  frames : Array[WordsOverAt]
}

///|
/// Words over words found on a frame drawn (any frame where the rule is not held: Tester::words_over_frames): the
/// moment it was drawn at, the words under and over, where they meet (the middle of where both are seen in the
/// window), whether the words over are a layer leaving.
#derive(Eq, Debug)
pub(all) struct WordsOverAt {
  at : Double
  under : String
  over : String
  x : Double
  y : Double
  leaving : Bool
}

///|
// kept across runs: begun anew by each Tester (words_over_begin)
let words_over : WordsOver = { held: true, file: "", pairs: Set([]), frames: [] }

///|
/// Each file's bar: how many pairs of words over words a Tester made there may show while what it walks through
/// moves (the app's tests' known faults, falling as they are mended).
// kept across runs: said once as a test program starts (its packages' `init`)
let words_over_bars : Map[String, Int] = Map([])

///|
/// Exact pairs intentionally shown during a particular test's closing overlay fade. A pair in any other motion is
/// still checked, as are all other words in the same test.
// kept across runs: named once as a test package starts, as words_over_bars is
let words_over_closing_pairs : Array[(String, String, String)] = []

///|
/// A test file's exact `(file, underneath, leaving)` pairs that its chosen closing fade intentionally shows together.
pub fn words_over_closing_expected(pairs : Array[(String, String, String)]) -> Unit {
  for pair in pairs {
    words_over_closing_pairs.push(pair)
  }
}

///|
fn words_over_expected_closing(file : String, under : String, over : String, leaving : Bool) -> Bool {
  leaving && words_over_closing_pairs.iter().any(fn(p) { p == (file, under, over) })
}

///|
/// The words over words known in the tests of the files `bars` names (the file a Tester is made in, as its `loc`
/// says it without line and column: "src/sfapp/chat_wbtest.mbt"), each how many pairs a Tester made there may show.
/// Said by a test package as it starts (`fn init`); only falls.
pub fn words_over_known(bars : Array[(String, Int)]) -> Unit {
  motion_bars_said("words_over", bars)
  for b in bars {
    words_over_bars.set(b.0, b.1)
  }
}

///|
/// A Tester made at `loc` starts finding: none found yet; `held`, whether a fault fails it.
fn words_over_begin(loc : String, held : Bool) -> Unit {
  words_over.held = held
  words_over.pairs.clear()
  words_over.frames.clear()
  words_over.file = match loc.find(":") {
    Some(i) => loc.unsafe_substring(start=0, end=i)
    None => loc
  }
  inst_owners.track = true
}

///|
/// The words node `i` draws, or the first a node in it draws (a row kept as drawn owns all its instances), cut short
/// to be said.
fn Ctx::words_over_words(self : Ctx, i : Int) -> String {
  let mut t = self.nodes[i].text
  if t == "" {
    for j in (i + 1)..<self.count {
      if self.nodes[j].text != "" && self.node_in(j, i) {
        t = self.nodes[j].text
        break
      }
    }
  }
  let t = t.replace_all(old="\n", new=" ")
  if t.length() > 40 {
    t.unsafe_substring(start=0, end=40) + "…"
  } else {
    t
  }
}

///|
/// Whether instance `j` hides what is drawn under it at (`px`, `py`): a fill nearly whole, a picture, glass.
fn words_over_hides(a : FixedArray[Double], j : Int, px : Double, py : Double) -> Bool {
  let (kind, o) = ground_kind(a, j, px, py)
  let b = j * inst_size
  let o = o * inst_fade_at(a, b, px, py)
  kind == 2 || (kind == 1 && o >= 0.9) || ((a[b + 5] == 5.0 || a[b + 5] == 6.0) && in_inst(a, b, px, py))
}

///|
/// Whether both glyphs `k1` and `k2` (`k1` drawn first) are seen at (`px`, `py`): nothing that hides drawn between
/// them there, nor over both.
fn Ctx::words_over_both_seen(self : Ctx, k1 : Int, k2 : Int, px : Double, py : Double) -> Bool {
  for j in (k1 + 1)..<self.ninst {
    if j != k2 && words_over_hides(self.inst, j, px, py) {
      return false
    }
  }
  true
}

///|
/// Whether `over` belongs to a leaving layer above `under`: not a change within a layer, an entrance, or a page move.
fn Ctx::words_over_leaving_layer(self : Ctx, under : InstBy, over : InstBy) -> Bool {
  let tree_of = fn(by : InstBy) -> @view.NodeId? {
    match by {
      Node(id) => Some(id)
      Old(i) if i >= 0 && i < self.count => self.nodes[i].island
      _ => None
    }
  }
  match (view_app.val, tree_of(over)) {
    (Some(tree), Some(top)) => {
      let above = tree.stack_of(top)
      let below = tree_of(under).map_or(-1, fn(id) { tree.stack_of(id) })
      tree.leaving(top) && above >= 0 && above > below
    }
    _ => false
  }
}

///|
/// The pairs of nodes' words the frame just drawn shows one over the other, each once: their words, where they meet.
fn Ctx::words_over_details(self : Ctx) -> Array[(String, String, Double, Double, Bool, String, String)] {
  self.flat_from(0)
  let a = self.inst
  let ks : Array[Int] = []
  let rs : Array[(Double, Double, Double, Double)] = []
  let os : Array[Int] = []
  // (who drew it, contrast.mbt's inst_by: each known here by a number of its own, an old view's node by its index, a
  // node of the window's tree's by one below them)
  let tree_nodes : Map[@view.NodeId, Int] = Map([])
  let who : Map[Int, InstBy] = Map([])
  for k in 0..<self.ninst {
    let b = k * inst_size
    let kind = a[b + 5]
    if (kind != 1.0 && kind != 3.0 && kind != 7.0) || a[b + 11] < words_over_seen_least {
      continue
    }
    let by = inst_by(k)
    if by == Nobody {
      continue
    }
    let o = match by {
      Nobody => -1
      Old(i) => i
      Node(id) =>
        match tree_nodes.get(id) {
          Some(o) => o
          None => {
            let o = -2 - tree_nodes.length()
            tree_nodes[id] = o
            o
          }
        }
    }
    who[o] = by
    // its ink, a little inside its picture and within its own cell across (a picture is made with room round its
    // ink: a full stop's spills well past its advance), cut by its clip and by the window: what lies past the window
    // is seen by no one, though its clip, the frame's base (0 to 1e9: Ctx::in_window), says none
    let (l, r) = inst_cell_of(k)
    // (and where it fades out towards a cut, scene.mbt 52-59, no more of it than is seen)
    let least = words_over_seen_least / a[b + 11]
    let x0 = dmax(dmax(a[b] + 0.75, a[b] + a[b + 2] * l), a[b + 16])
    let x0 = if a[b + 57] > 0.0 { dmax(x0, a[b + 56] + a[b + 57] * least) } else { x0 }
    let y0 = dmax(a[b + 1] + 0.75, a[b + 17])
    let y0 = if a[b + 53] > 0.0 { dmax(y0, a[b + 52] + a[b + 53] * least) } else { y0 }
    let x1 = dmin(dmin(a[b] + a[b + 2] - 0.75, a[b] + a[b + 2] * r), a[b + 18])
    let x1 = if a[b + 59] > 0.0 { dmin(x1, a[b + 58] - a[b + 59] * least) } else { x1 }
    let y1 = dmin(a[b + 1] + a[b + 3] - 0.75, a[b + 19])
    let y1 = if a[b + 55] > 0.0 { dmin(y1, a[b + 54] - a[b + 55] * least) } else { y1 }
    let (x0, y0, x1, y1) = (dmax(x0, 0.0), dmax(y0, 0.0), dmin(x1, self.width), dmin(y1, self.height))
    // (and by its outer, where it has one (40-51, a corner's radius: a round clip's in a square one): what the
    // renderers cut it by too; a rect there with no corner's radius is none, cutting nothing as they draw it)
    let (x0, y0, x1, y1) = if inst_has_outer(a, b) {
      (dmax(x0, a[b + 40]), dmax(y0, a[b + 41]), dmin(x1, a[b + 42]), dmin(y1, a[b + 43]))
    } else {
      (x0, y0, x1, y1)
    }
    if x1 > x0 && y1 > y0 {
      ks.push(k)
      rs.push((x0, y0, x1, y1))
      os.push(o)
    }
  }
  let out = []
  if ks.length() < 2 {
    return out
  }
  // (glyphs met through a grid of cells, not each with each)
  let cell = 24.0
  let grid : Map[Int, Array[Int]] = Map([])
  let pairs : Set[Int] = Set([])
  for q in 0..<ks.length() {
    let (x0, y0, x1, y1) = rs[q]
    for gx in (x0 / cell).to_int()..=(x1 / cell).to_int() {
      for gy in (y0 / cell).to_int()..=(y1 / cell).to_int() {
        let key = gy * 4096 + gx
        let here = match grid.get(key) {
          Some(v) => v
          None => {
            let v = []
            grid.set(key, v)
            v
          }
        }
        for p in here {
          if os[p] == os[q] || pairs.contains(os[p] * 65536 + os[q]) {
            continue
          }
          let (u0, v0, u1, v1) = rs[p]
          let ix0 = dmax(x0, u0)
          let iy0 = dmax(y0, v0)
          let ix1 = dmin(x1, u1)
          let iy1 = dmin(y1, v1)
          if ix1 - ix0 < 1.0 || iy1 - iy0 < 1.0 {
            continue
          }
          let px = (ix0 + ix1) / 2.0
          let py = (iy0 + iy1) / 2.0
          if !self.words_over_both_seen(ks[p], ks[q], px, py) {
            continue
          }
          pairs.add(os[p] * 65536 + os[q])
          let under = who.get(os[p]).unwrap_or(Nobody)
          let over = who.get(os[q]).unwrap_or(Nobody)
          out.push(
            (
              self.by_said(under),
              self.by_said(over),
              px,
              py,
              self.words_over_leaving_layer(under, over),
              self.words_over_made(under),
              self.words_over_made(over),
            ),
          )
        }
        here.push(q)
      }
    }
  }
  out
}

///|
/// The rule held on the frame just drawn, where something on it moves: a pair not found before by this Tester, past
/// its file's bar, fails the test at once, with what and where.
fn Tester::hold_words_over(self : Tester) -> Unit {
  let c = g()
  // (not held: every frame's, moving or not, kept as they are for the test to say which it shows, frame by frame:
  // Tester::words_over_frames)
  if !words_over.held {
    for f in c.words_over_details() {
      let (under, over, x, y, leaving, _, _) = f
      words_over.frames.push({ at: self.fake.time, under, over, x, y, leaving })
    }
    return
  }
  if !(c.motion_left || c.page_in_hand) {
    return
  }
  for f in c.words_over_details() {
    let (under, over, x, y, leaving, under_made, over_made) = f
    if words_over_expected_closing(words_over.file, under, over, leaving) {
      continue
    }
    let pair = "「\{under}」 under 「\{over}」"
    if words_over.pairs.contains(pair) {
      continue
    }
    words_over.pairs.add(pair)
    let bar = words_over_bars.get(words_over.file).unwrap_or(0)
    motion_known_said("words_over", words_over.file, words_over.pairs.length(), bar, pair)
    if self.motion == Count {
      println(
        "MOTION words_over \{words_over.file}: \{pair} at (\{x.round()}, \{y.round()}) at \{self.fake.time} (under: \{under_made}; over: \{over_made}) (the Tester made at \{looks_made_at.val})",
      )
      continue
    }
    if words_over.pairs.length() > bar {
      let said = "words over words while it moves (words_over.mbt), on a frame drawn \{self.w}×\{self.h} at \{self.fake.time}, the Tester made at \{looks_made_at.val}: " +
        "\{pair} at (\{x.round()}, \{y.round()}); \{words_over.pairs.length()} pairs now, \{bar} known in \{words_over.file}"
      @halt.saying(said)
    }
  }
}

///|
/// Every frame's words over words this Tester has drawn, moving or not, where it does not hold the rule
/// (`words_over_held` false), in the order they were drawn: for a test to say which it shows, frame by frame (an old
/// view's own and the same of the nodes made in its place at the same moments, no other). Where it holds the rule,
/// none: what it finds fails it.
pub fn Tester::words_over_frames(self : Tester) -> Array[WordsOverAt] {
  self.reads_own()
  ignore(self)
  words_over.frames.copy()
}

///|
/// Where what drew words was made, for a fault that names it: a node of the window's tree's, its place (or the app's
/// that holds it, past the framework's own boxes); an old view's, "old view", and the node hosting it where one does.
fn Ctx::words_over_made(self : Ctx, by : InstBy) -> String {
  match by {
    Node(id) => {
      let s = source_said(id)
      if s == "" { "a node" } else { s }
    }
    Old(i) => {
      let m = self.sizes_steady_made(i)
      // (" (…)" said bare)
      if m.length() > 3 { m.unsafe_substring(start=2, end=m.length() - 1) } else { "old view" }
    }
    Nobody => ""
  }
}

///|
/// The pairs of nodes' words the frame last drawn shows one over the other, moving or not, each once, with where they
/// meet: for a sweep of screens at rest (still.fail's words_large_wbtest.mbt), where words over words are otherwise
/// the squeeze's, which measures an old view's boxes side by side but not the window tree's words.
pub fn Tester::words_over_now(self : Tester) -> Array[String] {
  self.reads_own()
  ignore(self)
  g()
  .words_over_details()
  .map(fn(f) { "「\{f.0}」 under 「\{f.1}」 at (\{f.2.round()}, \{f.3.round()})" })
}
