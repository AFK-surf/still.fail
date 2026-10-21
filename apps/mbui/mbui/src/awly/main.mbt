// arewelayoutyet's shared workloads (PanGUI's layout benchmarks, from Taffy's) laid out by mbui's flex engine, timed
// the way its Criterion harness times the retained-tree engines: the tree is built once, outside timing; each pass
// lays out the whole tree again with nothing kept from the pass before (compute without reuse), as Yoga's and Taffy's
// adapters do after marking every node dirty. Prints one JSON line per workload: how long a pass took (mean, and
// the fastest and slowest of the 10 samples), the sizings it did, and the layout it came to (the root's size and the
// sums of every node's left, top, width and height), to compare with another engine's or another commit's.
//
// AWLY_ONLY=<index> runs one workload; AWLY_PROFILE=<seconds> lays it out over and over for a profiler (Studio, its
// screen locked: `xcrun xctrace record --template 'Time Profiler' --launch -- <exe>`; `sample` hangs there).
// Workloads: scripts/awly_gen.py <arewelayoutyet>/benchmarks/pangui > src/awly/workloads.mbt. Build and run:
// moon build --target native --release src/awly && _build/native/release/build/awly/awly.exe > run.jsonl; two runs
// compared: scripts/awly_compare.py before.jsonl after.jsonl.

///|
/// A size as the templates write it.
enum Sz {
  NoSize
  Px(Double)
  Fit
  Expand(Double)
  Frac(Double)
  Ratio(Double)
}

///|
fn Sz::is_expand(self : Sz) -> Bool {
  self is Expand(_)
}

///|
struct Spec {
  w : Sz
  h : Sz
  min_w : Sz
  min_h : Sz
  max_w : Sz
  max_h : Sz
  gap : Double
  pad : (Double, Double, Double, Double)
  mar : (Double, Double, Double, Double)
  wrap : Bool
  row : Bool
}

///|
fn spec(
  w? : Sz = NoSize,
  h? : Sz = NoSize,
  min_w? : Sz = NoSize,
  min_h? : Sz = NoSize,
  max_w? : Sz = NoSize,
  max_h? : Sz = NoSize,
  gap? : Double = 0.0,
  pad_l? : Double = 0.0,
  pad_t? : Double = 0.0,
  pad_r? : Double = 0.0,
  pad_b? : Double = 0.0,
  mar_l? : Double = 0.0,
  mar_t? : Double = 0.0,
  mar_r? : Double = 0.0,
  mar_b? : Double = 0.0,
  wrap? : Bool = false,
  row? : Bool = false,
) -> Spec {
  {
    w,
    h,
    min_w,
    min_h,
    max_w,
    max_h,
    gap,
    pad: (pad_l, pad_t, pad_r, pad_b),
    mar: (mar_l, mar_t, mar_r, mar_b),
    wrap,
    row,
  }
}

///|
fn dim(s : Sz) -> @flex.Dim {
  match s {
    Px(v) => Pt(v)
    Frac(v) => Pct(v * 100.0)
    _ => Auto
  }
}

///|
fn min_max(s : Sz) -> @flex.Dim {
  match s {
    Px(v) => Pt(v)
    Frac(v) => Pct(v * 100.0)
    NoSize => Auto
    _ => abort("only pixels and percentages bound a size")
  }
}

///|
/// The node of a template's node, translated as the harness translates it into a flexbox style for Taffy and Yoga
/// (benches/pangui.rs `style`): Expand along the parent's main axis shares out its space (grow by the weight, shrink
/// 1, basis 0, min 0); an Expand minimum grows from the node's own size; Expand across is stretched.
fn node(sp : Spec, parent_is_row : Bool) -> @flex.Node {
  let n = @flex.Node::new()
  let s = n.style
  let (main, main_min) = if parent_is_row {
    (sp.w, sp.min_w)
  } else {
    (sp.h, sp.min_h)
  }
  match (main, main_min) {
    (Expand(v), _) => {
      s.grow = v
      s.shrink = 1.0
      s.set_basis(Pt(0.0))
    }
    (_, Expand(v)) => {
      s.grow = v
      s.shrink = 0.0
      s.set_basis(Auto)
    }
    _ => ()
  }
  if !(parent_is_row && sp.min_w.is_expand()) {
    s.set_min_width(min_max(sp.min_w))
  }
  if !(!parent_is_row && sp.min_h.is_expand()) {
    s.set_min_height(min_max(sp.min_h))
  }
  if main.is_expand() {
    if parent_is_row && sp.min_w is NoSize {
      s.set_min_width(Pt(0.0))
    }
    if !parent_is_row && sp.min_h is NoSize {
      s.set_min_height(Pt(0.0))
    }
  }
  match (sp.w, sp.h) {
    (Ratio(v), _) => s.aspect = v
    (_, Ratio(v)) => s.aspect = 1.0 / v
    _ => ()
  }
  s.direction = if sp.row { Row } else { Column }
  s.wrap = if sp.wrap { Wrap } else { NoWrap }
  s.set_width(dim(sp.w))
  s.set_height(dim(sp.h))
  s.set_max_width(min_max(sp.max_w))
  s.set_max_height(min_max(sp.max_h))
  s.set_gap_row(Pt(sp.gap))
  s.set_gap_col(Pt(sp.gap))
  let (pl, pt, pr, pb) = sp.pad
  s.set_padding_left(Pt(pl))
  s.set_padding_top(Pt(pt))
  s.set_padding_right(Pt(pr))
  s.set_padding_bottom(Pt(pb))
  let (ml, mt, mr, mb) = sp.mar
  s.set_margin_left(Pt(ml))
  s.set_margin_top(Pt(mt))
  s.set_margin_right(Pt(mr))
  s.set_margin_bottom(Pt(mb))
  s.align_items = Stretch
  s.justify = FlexStart
  s.align_content = FlexStart
  n
}

///|
/// Node count, and the sum of every node's left, top, width and height: to check the layout against another engine's.
fn sums(n : @flex.Node, acc : Array[Double]) -> Unit {
  acc[0] = acc[0] + 1.0
  acc[1] = acc[1] + n.left
  acc[2] = acc[2] + n.top
  acc[3] = acc[3] + n.width
  acc[4] = acc[4] + n.height
  for c in n.children {
    sums(c, acc)
  }
}

///|
fn main {
  if !supported {
    println("src/awly times the native build: on the JS target there is nothing to run")
    return
  }
  // Criterion's settings in the harness (criterion_config): a 0.3 s warm-up, then 10 samples over about 1 s, the
  // same number of passes in each
  let pick = only()
  for i, w in workloads {
    if pick >= 0 && i != pick {
      continue
    }
    let (name, build, width, height) = w
    let root = build()
    let lay = fn() { @flex.compute(root, width~, height~, round=true) }
    lay()
    let c0 = [@flex.counters[0], @flex.counters[1], @flex.counters[2]]
    lay()
    let work = "\"sized\":\{@flex.counters[0] - c0[0]},\"cached\":\{@flex.counters[1] - c0[1]},"
    let secs = profile_secs()
    if secs > 0.0 {
      let end = now_ns() + secs * 1.0e9
      while now_ns() < end {
        lay()
      }
      continue
    }
    let acc = [0.0, 0.0, 0.0, 0.0, 0.0]
    sums(root, acc)
    let warm_end = now_ns() + 3.0e8
    let mut passes = 0
    let t0 = now_ns()
    while now_ns() < warm_end {
      lay()
      passes = passes + 1
    }
    let per = (now_ns() - t0) / passes.to_double()
    let each = (1.0e9 / 10.0 / per).ceil().to_int()
    let each = if each < 1 { 1 } else { each }
    let samples : Array[Double] = []
    for _ in 0..<10 {
      let s0 = now_ns()
      for _ in 0..<each {
        lay()
      }
      samples.push((now_ns() - s0) / each.to_double())
    }
    let mut mean = 0.0
    let mut lo = samples[0]
    let mut hi = samples[0]
    for x in samples {
      mean = mean + x
      if x < lo {
        lo = x
      }
      if x > hi {
        hi = x
      }
    }
    mean = mean / samples.length().to_double()
    println(
      "{\"scenario\":\"\{name}\",\"library\":\"mbui\",\"mean_ns\":\{mean},\"min_ns\":\{lo},\"max_ns\":\{hi},\"passes\":\{each}," +
      work +
      "\"nodes\":\{acc[0].to_int()},\"root\":[\{root.width},\{root.height}],\"sum\":[\{acc[1]},\{acc[2]},\{acc[3]},\{acc[4]}]}",
    )
  }
}
