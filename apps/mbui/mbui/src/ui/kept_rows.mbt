// What the Tester asks of a list's rows kept (kept_nodes.mbt), and a clip as what is in it is cut (said.mbt's Moved).

///|
/// How many of the last frame's list rows were kept as their nodes (kept_nodes.mbt), not built.
pub fn Tester::rows_kept(self : Tester) -> Int {
  ignore(self)
  nodes_run.kept_at.iter().filter(fn(k) { k.1 >= 0 }).count()
}

///|
/// Whether parts kept and a list's rows kept are kept as their nodes (true, as on a host) or built every frame
/// (false): a test's, to hold what is kept to what building it draws.
pub fn Tester::drawn_again(self : Tester, on : Bool) -> Unit {
  ignore(self)
  if nodes_run.on != on {
    test_stepped()
  }
  nodes_run.on = on
}

///|
/// The clip being painted in, as what is drawn in it shows: its rect, its corners' radii. What is put outside the
/// drawing where it shows (a native view, put in the window by the host) reads this.
fn clip_shown() -> ((Double, Double, Double, Double), (Double, Double, Double, Double)) {
  let k = clip_top()
  let s = clip_stack
  ((s[k], s[k + 1], s[k + 2], s[k + 3]), (s[k + 4], s[k + 5], s[k + 6], s[k + 7]))
}

///|
/// A clip's 24 numbers, worked on in place (Moved::clip).
// kept across runs: scratch, written before it is read
let clip_scratch : FixedArray[Double] = FixedArray::make(24, 0.0)

///|
/// A clip `c` (a level's 24 numbers: its rect, its corners' radii, how smooth they are, its outer's 12) as what is in
/// the clip at `k` (in `clip_stack`) is cut where they meet, by the rule a clip pushed in it is (push_round_clip,
/// push_clip_r): their rects' intersection; each corner its own where it is still its own (the rounder where it is also
/// the outer clip's), else the outer clip's where it is that one's, else square; its outer, of its own, that clip and
/// that clip's outer, the one whose curves cut into it (push_clip_r's rule), none where none does. One that holds that clip's rect whole, square and
/// with no outer (what a row draws in nothing of its own that cuts) is that clip.
fn clip_into(k : Int, c : FixedArray[Double]) -> Unit {
  let s = clip_stack
  let (ox0, oy0, ox1, oy1) = (c[0], c[1], c[2], c[3])
  if ox0 <= s[k] &&
    oy0 <= s[k + 1] &&
    ox1 >= s[k + 2] &&
    oy1 >= s[k + 3] &&
    c[4] <= 0.0 &&
    c[5] <= 0.0 &&
    c[6] <= 0.0 &&
    c[7] <= 0.0 &&
    c[16] <= 0.0 &&
    c[17] <= 0.0 &&
    c[18] <= 0.0 &&
    c[19] <= 0.0 {
    for m in 0..<24 {
      c[m] = s[k + m]
    }
    return
  }
  let x0 = dmax(ox0, s[k])
  let y0 = dmax(oy0, s[k + 1])
  let x1 = dmin(ox1, s[k + 2])
  let y1 = dmin(oy1, s[k + 3])
  for j in 0..<4 {
    let left = j == 0 || j == 3
    let top = j < 2
    let px = if left { x0 } else { x1 }
    let py = if top { y0 } else { y1 }
    let own = px == (if left { ox0 } else { ox1 }) && py == (if top { oy0 } else { oy1 })
    let (lr, ls) = clip_corner_r(k, j, px, py)
    if !(own && c[4 + j] > 0.0 && c[4 + j] >= lr) {
      c[4 + j] = lr
      c[8 + j] = ls
    }
  }
  c[0] = x0
  c[1] = y0
  c[2] = x1
  c[3] = y1
  // its outer: of its own, that clip and that clip's outer, the one whose curves cut into it (push_clip_r's rule)
  let r = (c[4], c[5], c[6], c[7])
  let sm = (c[8], c[9], c[10], c[11])
  let beyond = clip_has_outer(k)
  let apart = beyond && clip_is_apart(k)
  let own = if c[16] > 0.0 || c[17] > 0.0 || c[18] > 0.0 || c[19] > 0.0 {
    clip_cut_depth(c, 12, x0, y0, x1, y1, r, sm)
  } else {
    -1.0e9
  }
  let mut most = dmax(own, clip_cut_least)
  let mut from = if own > clip_cut_least { -2 } else { -1 }
  for o in if beyond && !apart { [k, k + 12] } else { [k] } {
    let d = clip_cut_depth(s, o, x0, y0, x1, y1, r, sm)
    if d > most {
      most = d
      from = o
    }
  }
  if from >= 0 || (from == -1 && apart) {
    let from = if from >= 0 { from } else { k + 12 }
    for m in 0..<12 {
      c[12 + m] = s[from + m]
    }
  } else if from == -1 {
    for m in 12..<24 {
      c[m] = 0.0
    }
  }
}
