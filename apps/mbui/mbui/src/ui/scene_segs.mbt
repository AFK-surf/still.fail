// A frame as its layers' blocks and where each run of them is put (a Tester's, while it checks what it draws:
// looks_check): each run of a block in the frame, the moves it was put with (insts_moved_by) and the place of its own
// it was put where the window has it from (scene_origin_put). What a host given the blocks once and the runs each frame
// would draw: put together again of them alone (scene_segs_put), every instance of the frame a run is the same
// (scene_segs_check). The handing over of layers to a host (docs: layers-on-hosts), proved enough before a host does it.

///|
/// A run of layer `layer`'s block (`n` from `from`) at instance `k` of the frame; its levels as drawn told from `lvl` (the
/// level it begins in where it was put: scene_block_put's), the moves it was put with, and where it was put where the
/// window has it, and in what (o, b, clip, outer_from: scene_origin_put's).
priv struct SceneSeg {
  layer : SceneLayer
  from : Int
  n : Int
  k : Int
  lvl : Int
  moves : Array[(Double, Double, Int, Bool)]
  mut put : ((Double, Double), Int, FixedArray[Double], Int)?
  /// its layer's tops (what it drew over everything, Ctx::scene_tops_out) rather than its block
  tops : Bool
}

///|
/// The runs of the frame being drawn (SceneSeg), in the order they are said.
// kept across runs: cleared as each frame begins
let scene_segs : Array[SceneSeg] = []

///|
/// Whether the frame is being put together again of the runs (scene_segs_drawn): nothing told the runs then.
// kept across runs: set while it is
let scene_segs_composing : Ref[Bool] = Ref(false)

///|
/// Whether the runs are said: a Tester's, checking what it draws.
fn scene_segs_on() -> Bool {
  looks_check.val
}

///|
/// A run of layer `l`'s block said (scene_segs_on).
fn scene_seg_said(l : SceneLayer, from : Int, n : Int, k : Int, lvl : Int) -> Unit {
  if scene_segs_on() && n > 0 {
    scene_segs.push({ layer: l, from, n, k, lvl, moves: [], put: None, tops: false })
  }
}

///|
/// Layer `l`'s tops put at instance `k` of the frame (Ctx::scene_tops_out): a run of them.
fn scene_seg_tops(l : SceneLayer, k : Int) -> Unit {
  let n = l.tops.length() / inst_size
  if scene_segs_on() && n > 0 {
    scene_segs.push({ layer: l, from: 0, n, k, lvl: 0, moves: [], put: None, tops: true })
  }
}

///|
/// The run said last moved by (`dx`, `dy`), `depth` and `soft` as insts_moved_by moves it.
fn scene_seg_moved(dx : Double, dy : Double, depth : Int, soft : Bool) -> Unit {
  if scene_segs_on() && scene_segs.length() > 0 {
    scene_segs[scene_segs.length() - 1].moves.push((dx, dy, depth, soft))
  }
}

///|
/// Instances `k0` to `k1` put where the window has them (scene_origin_put's): each run among them not so already told so.
fn scene_segs_put(k0 : Int, k1 : Int, o : (Double, Double), b : Int, clip : FixedArray[Double], outer_from : Int) -> Unit {
  if !scene_segs_on() {
    return
  }
  for s in scene_segs {
    if s.put is None && s.k >= k0 && s.k + s.n <= k1 {
      s.put = Some((o, b, clip.copy(), outer_from))
    }
  }
}

///|
/// The runs from instance `k` on let go (what they are in left out after it was drawn); one cut there cut short.
fn scene_segs_cut(k : Int) -> Unit {
  if !scene_segs_on() {
    return
  }
  let kept = scene_segs.filter(fn(s) { s.k < k })
  scene_segs.clear()
  for s in kept {
    if s.k + s.n > k {
      scene_segs.push({ ..s, n: k - s.k })
    } else {
      scene_segs.push(s)
    }
  }
}

///|
/// The runs where they are now, what of the frame was in `ranges` moved after the rest (Ctx::raise_ranges, `moved_to`
/// where each instance goes): each cut where those begin and end.
fn scene_segs_raised(ranges : Array[(Int, Int)], moved_to : (Int) -> Int) -> Unit {
  if !scene_segs_on() {
    return
  }
  let now : Array[SceneSeg] = []
  for s in scene_segs {
    let mut at = s.k
    let end = s.k + s.n
    let piece = fn(a : Int, e : Int) {
      now.push({ ..s, from: s.from + a - s.k, n: e - a, k: moved_to(a), moves: s.moves })
    }
    for g in ranges {
      for edge in [g.0, g.1] {
        if edge > at && edge < end {
          piece(at, edge)
          at = edge
        }
      }
    }
    if end > at {
      piece(at, end)
    }
  }
  scene_segs.clear()
  scene_segs.append(now)
}

///|
/// The frame as a host given the blocks and the runs would draw it, on `base` (what no run is: drawn each frame as it
/// is, handed over so): each run its block's, moved as it was, put where the window has it as it was, at scale `sc`.
fn scene_segs_drawn(base : FixedArray[Double], sc : Double) -> FixedArray[Double] {
  let a = base.copy()
  // (the frame's levels and what is left to set on the pixels, as the frame had them: put back after)
  let levels = inst_levels.copy()
  let froms = inst_froms.copy()
  let glyphs = scene_glyphs.copy()
  let done = scene_own_done.copy()
  let work = scene_work.origin_insts
  let cuts = scene_work.origin_cuts
  scene_segs_composing.val = true
  for s in scene_segs {
    let l = s.layer
    let k = s.k
    if s.tops {
      for q in 0..<(s.n * inst_size) {
        a[k * inst_size + q] = l.tops[s.from * inst_size + q]
      }
      continue
    }
    l.block.blit_to(a, len=s.n * inst_size, src_offset=s.from * inst_size, dst_offset=k * inst_size)
    for m in s.moves {
      insts_moved_by(a, k, k + s.n, m.0, m.1, l, s.from, m.2, m.3)
    }
    match s.put {
      Some((o, b, clip, outer_from)) => {
        while inst_levels.length() < k + s.n {
          inst_levels.push(0)
          inst_froms.push(-1)
        }
        for i in 0..<s.n {
          inst_levels[k + i] = l.block_own[s.from + i] - l.clip_lvl + s.lvl
          let f = l.block_from[s.from + i]
          inst_froms[k + i] = if f < 0 { -1 } else { f - l.clip_lvl + s.lvl }
        }
        scene_glyphs.clear()
        for gl in l.block_glyphs {
          if gl.0 >= s.from && gl.0 < s.from + s.n {
            scene_glyphs.push((k + gl.0 - s.from, gl.1))
          }
        }
        scene_own_done.clear()
        scene_origin_put(a, k, k + s.n, o, b, clip, sc, outer_from~)
      }
      None => ()
    }
  }
  inst_levels.clear()
  inst_levels.append(levels)
  inst_froms.clear()
  inst_froms.append(froms)
  scene_glyphs.clear()
  scene_glyphs.append(glyphs)
  scene_own_done.clear()
  scene_own_done.append(done)
  scene_work.origin_insts = work
  scene_work.origin_cuts = cuts
  scene_segs_composing.val = false
  a
}

///|
/// Whether the frame drawn (`a`, its `n` instances) is what a host given the blocks and the runs would draw
/// (scene_segs_drawn): every instance of it in one run and in no other (the root's, what is raised after it, all), and
/// the same as put together of the runs alone, each of what no run put taken for one not drawn (a number no instance
/// has). None where so; else where the first is not, how.
fn scene_segs_check(a : FixedArray[Double], n : Int, sc : Double) -> String? {
  // (all of the frame: what is in it but by a run is found, whatever drew it, the root's or after)
  let (r0, r1) = (0, n)
  // (each instance of the root's in one run, no more)
  let runs = FixedArray::make(n, 0)
  for s in scene_segs {
    if s.k < 0 || s.k + s.n > n {
      return Some("run of layer \{s.layer.id.at} at \{s.k}+\{s.n} past the frame's \{n}")
    }
    for k in s.k..<(s.k + s.n) {
      runs[k] = runs[k] + 1
    }
  }
  for k in r0..<r1 {
    if runs[k] != 1 {
      return Some("instance \{k} (kind \{a[k * inst_size + 5]}) of the root's \{r0}..\{r1} in \{runs[k]} runs")
    }
  }
  // (put together of the runs alone, on nothing where the root drew: what no run put there not what was drawn)
  let base = a.copy()
  for q in (r0 * inst_size)..<(r1 * inst_size) {
    base[q] = scene_seg_none
  }
  let drawn = scene_segs_drawn(base, sc)
  for k in 0..<n {
    for j in 0..<inst_size {
      let (x, y) = (drawn[k * inst_size + j], a[k * inst_size + j])
      if x != y && !(x != x && y != y) {
        let who = scene_segs.iter().find_first(fn(s) { k >= s.k && k < s.k + s.n })
        let of = match who {
          Some(s) =>
            "run of layer \{s.layer.id.at} (\{if s.tops { "its tops" } else { "its block" }} from \{s.from}, \{s.n}, at \{s.k}, moved \{s.moves.length()} times, put \{s.put is Some(_)})"
          None => "no run"
        }
        return Some("\{of}: instance \{k} slot \{j}: \{x} put together of the runs, \{y} drawn")
      }
    }
  }
  None
}

///|
/// What an instance of the root's no run put is taken for: a number no instance has.
let scene_seg_none : Double = -7.0e33
