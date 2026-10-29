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
}

///|
// kept across runs: begun anew by each Tester (words_over_begin)
let words_over : WordsOver = { held: true, file: "", pairs: Set::new() }

///|
/// Each file's bar: how many pairs of words over words a Tester made there may show while what it walks through
/// moves (the app's tests' known faults, falling as they are mended).
// kept across runs: said once as a test program starts (its packages' `init`)
let words_over_bars : Map[String, Int] = {}

///|
/// The words over words known in the tests of the files `bars` names (the file a Tester is made in, as its `loc`
/// says it without line and column: "src/sfapp/chat_wbtest.mbt"), each how many pairs a Tester made there may show.
/// Said by a test package as it starts (`fn init`); only falls.
pub fn words_over_known(bars : Array[(String, Int)]) -> Unit {
  for b in bars {
    words_over_bars.set(b.0, b.1)
  }
}

///|
/// A Tester made at `loc` starts finding: none found yet; `held`, whether a fault fails it.
fn words_over_begin(loc : String, held : Bool) -> Unit {
  words_over.held = held
  words_over.pairs.clear()
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
/// The pairs of nodes' words the frame just drawn shows one over the other, each once: their words, where they meet.
fn Ctx::words_over_faults(self : Ctx) -> Array[(String, String, Double, Double)] {
  let a = self.inst
  let ks : Array[Int] = []
  let rs : Array[(Double, Double, Double, Double)] = []
  let os : Array[Int] = []
  for k in 0..<self.ninst {
    let b = k * inst_size
    let kind = a[b + 5]
    if (kind != 1.0 && kind != 3.0 && kind != 7.0) || a[b + 11] < words_over_seen_least {
      continue
    }
    let o = inst_owner(k)
    if o < 0 {
      continue
    }
    // its ink, a little inside its picture and within its own cell across (a picture is made with room round its
    // ink: a full stop's spills well past its advance), cut by its clip
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
  let grid : Map[Int, Array[Int]] = {}
  let pairs : Set[Int] = Set::new()
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
          out.push((self.words_over_words(os[p]), self.words_over_words(os[q]), px, py))
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
  if !words_over.held || !(c.motion_left || c.page_in_hand) {
    return
  }
  for f in c.words_over_faults() {
    let (under, over, x, y) = f
    let pair = "「\{under}」 under 「\{over}」"
    if words_over.pairs.contains(pair) {
      continue
    }
    words_over.pairs.add(pair)
    let bar = words_over_bars.get(words_over.file).unwrap_or(0)
    if words_over.pairs.length() > bar {
      let said = "words over words while it moves (words_over.mbt), on a frame drawn \{self.w}×\{self.h} at \{self.fake.time}, the Tester made at \{looks_made_at.val}: " +
        "\{pair} at (\{x.round()}, \{y.round()}); \{words_over.pairs.length()} pairs now, \{bar} known in \{words_over.file}"
      println(said)
      abort(said)
    }
  }
}
