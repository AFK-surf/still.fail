// tiny-skia's scan conversion (src/blitter.rs, src/alpha_runs.rs, src/scan/mod.rs, path.rs, path_aa.rs; after
// Skia's SkScan_Path.cpp, SkScan_AntiPath.cpp, SkAlphaRuns.cpp): a path's edges walked down the scanlines, spans
// handed to a blitter; anti-aliased by 4x4 supersampling into runs of alpha.

///|
/// What scan conversion draws with (Blitter): spans, runs of alpha, columns, pairs, rects and masks. A blitter
/// implements what its callers use.
trait Blitter {
  blit_h(Self, x : Int, y : Int, width : Int) -> Unit
  blit_anti_h(Self, x : Int, y : Int, alpha : FixedArray[Int], runs : FixedArray[Int]) -> Unit
  blit_v(Self, x : Int, y : Int, height : Int, alpha : Int) -> Unit
  blit_anti_h2(Self, x : Int, y : Int, alpha0 : Int, alpha1 : Int) -> Unit
  blit_anti_v2(Self, x : Int, y : Int, alpha0 : Int, alpha1 : Int) -> Unit
  blit_rect(Self, rect : ScreenIntRect) -> Unit
}

///|
pub(all) enum FillRule {
  Winding
  EvenOdd
} derive(Eq, Show, Debug)

///|
fn fill_rect_nonaa(rect : Rect, clip : ScreenIntRect, blitter : &Blitter) -> Unit {
  match rect.round() {
    Some(r) =>
      match r.intersect(clip.to_int_rect()) {
        Some(r) =>
          match r.to_screen_int_rect() {
            Some(r) => blitter.blit_rect(r)
            None => ()
          }
        None => ()
      }
    None => ()
  }
}

// ── alpha runs ────────────────────────────────────────────────────────

///|
/// A row's coverage as runs: runs[i] the length of the run at i (0 where none: Rust's None), alpha[i] its alpha.
priv struct AlphaRuns {
  runs : FixedArray[Int]
  alpha : FixedArray[Int]
}

///|
fn AlphaRuns::new(width : Int) -> AlphaRuns {
  let r = { runs: FixedArray::make(width + 1, 0), alpha: FixedArray::make(width + 1, 0) }
  r.reset(width)
  r
}

///|
fn catch_overflow(alpha : Int) -> Int {
  (alpha - (alpha >> 8)) & 0xFF
}

///|
fn AlphaRuns::is_empty(self : AlphaRuns) -> Bool {
  let run = self.runs[0]
  if run != 0 {
    self.alpha[0] == 0 && self.runs[run] == 0
  } else {
    true
  }
}

///|
fn AlphaRuns::reset(self : AlphaRuns, width : Int) -> Unit {
  self.runs[0] = width & 0xFFFF
  self.runs[width] = 0
  self.alpha[0] = 0
}

///|
fn AlphaRuns::add(
  self : AlphaRuns,
  x : Int,
  start_alpha : Int,
  middle_count : Int,
  stop_alpha : Int,
  max_value : Int,
  offset_x : Int,
) -> Int {
  let mut x = x
  let mut middle_count = middle_count
  let mut runs_offset = offset_x
  let mut alpha_offset = offset_x
  let mut last_alpha_offset = offset_x
  x -= offset_x
  if start_alpha != 0 {
    break_run(self.runs, runs_offset, self.alpha, alpha_offset, x, 1)
    let tmp = self.alpha[alpha_offset + x] + start_alpha
    self.alpha[alpha_offset + x] = (tmp - (tmp >> 8)) & 0xFF
    runs_offset += x + 1
    alpha_offset += x + 1
    x = 0
  }
  if middle_count != 0 {
    break_run(self.runs, runs_offset, self.alpha, alpha_offset, x, middle_count)
    alpha_offset += x
    runs_offset += x
    x = 0
    while true {
      let a = catch_overflow(self.alpha[alpha_offset] + max_value)
      self.alpha[alpha_offset] = a
      let n = self.runs[runs_offset]
      alpha_offset += n
      runs_offset += n
      middle_count -= n
      if middle_count == 0 {
        break
      }
    }
    last_alpha_offset = alpha_offset
  }
  if stop_alpha != 0 {
    break_run(self.runs, runs_offset, self.alpha, alpha_offset, x, 1)
    alpha_offset += x
    self.alpha[alpha_offset] = (self.alpha[alpha_offset] + stop_alpha) & 0xFF
    last_alpha_offset = alpha_offset
  }
  last_alpha_offset
}

///|
fn break_run(runs : FixedArray[Int], ro : Int, alpha : FixedArray[Int], ao : Int, x : Int, count : Int) -> Unit {
  let orig_x = x
  let mut x = x
  let mut runs_offset = ro
  let mut alpha_offset = ao
  while x > 0 {
    let n = runs[runs_offset]
    if x < n {
      alpha[alpha_offset + x] = alpha[alpha_offset]
      runs[runs_offset] = x & 0xFFFF
      runs[runs_offset + x] = (n - x) & 0xFFFF
      break
    }
    runs_offset += n
    alpha_offset += n
    x -= n
  }
  runs_offset = ro + orig_x
  alpha_offset = ao + orig_x
  x = count
  while true {
    let n = runs[runs_offset]
    if x < n {
      alpha[alpha_offset + x] = alpha[alpha_offset]
      runs[runs_offset] = x & 0xFFFF
      runs[runs_offset + x] = (n - x) & 0xFFFF
      break
    }
    x -= n
    if x == 0 {
      break
    }
    runs_offset += n
    alpha_offset += n
  }
}

///|
/// AlphaRuns::break_at (as tiny-skia has it: its runs written from the first).
fn break_at(alpha : FixedArray[Int], ao : Int, runs : FixedArray[Int], ro : Int, x : Int) -> Unit {
  let mut x = x
  let mut alpha_i = ao
  let mut run_i = ro
  while x > 0 {
    let n = runs[run_i]
    if x < n {
      alpha[alpha_i + x] = alpha[alpha_i]
      runs[ro] = x & 0xFFFF
      runs[ro + x] = (n - x) & 0xFFFF
      break
    }
    run_i += n
    alpha_i += n
    x -= n
  }
}

// ── filling a path ────────────────────────────────────────────────────

///|
fn fill_path_nonaa(path : Path, fill_rule : FillRule, clip : ScreenIntRect, blitter : &Blitter) -> Unit {
  let ir = match conservative_round_to_int(path.bounds) {
    Some(v) => v
    None => return
  }
  let contained = match ir.to_screen_int_rect() {
    Some(b) => clip.contains(b)
    None => false
  }
  fill_path_impl(path, fill_rule, clip, ir.y, ir.bottom(), 0, contained, blitter)
}

///|
fn conservative_round_to_int(src : Rect) -> IntRect? {
  IntRect::from_ltrb(
    round_down_to_int(src.left),
    round_down_to_int(src.top),
    round_up_to_int(src.right),
    round_up_to_int(src.bottom),
  )
}

///|
let conservative_round_bias : Double = 0.5 + 1.5 / 64.0

///|
/// i32::saturate_from(f64)
fn saturate_i32_d(x : Double) -> Int {
  let x = if x < 2147483647.0 { x } else { 2147483647.0 }
  let x = if x > -2147483648.0 { x } else { -2147483648.0 }
  d2i(x)
}

///|
fn round_down_to_int(x : Float) -> Int {
  saturate_i32_d((x.to_double() - conservative_round_bias).ceil())
}

///|
fn round_up_to_int(x : Float) -> Int {
  saturate_i32_d((x.to_double() + conservative_round_bias).floor())
}

///|
/// Stable sort of the edges by first y, then x (Rust's sort_by is stable).
fn sort_edges(edges : Array[Edge]) -> Array[Edge] {
  let key_lt = fn(a : Edge, b : Edge) {
    if a.first_y == b.first_y {
      a.x < b.x
    } else {
      a.first_y < b.first_y
    }
  }
  // (a merge sort: stable)
  let n = edges.length()
  let mut src = edges.copy()
  let mut dst = edges.copy()
  let mut width = 1
  while width < n {
    let mut lo = 0
    while lo < n {
      let mid = if lo + width < n { lo + width } else { n }
      let hi = if lo + 2 * width < n { lo + 2 * width } else { n }
      let mut i = lo
      let mut j = mid
      let mut k = lo
      while i < mid && j < hi {
        if key_lt(src[j], src[i]) {
          dst[k] = src[j]
          j += 1
        } else {
          dst[k] = src[i]
          i += 1
        }
        k += 1
      }
      while i < mid {
        dst[k] = src[i]
        i += 1
        k += 1
      }
      while j < hi {
        dst[k] = src[j]
        j += 1
        k += 1
      }
      lo += 2 * width
    }
    let t = src
    src = dst
    dst = t
    width *= 2
  }
  src
}

///|
fn sentinel_edge(prev : Int, next : Int, x : Int, first_y : Int) -> Edge {
  {
    kind: ELine,
    prev,
    next,
    x,
    dx: 0,
    first_y,
    last_y: 0,
    winding: 0,
    curve_count: 0,
    curve_shift: 0,
    dshift: 0,
    cx: 0,
    cy: 0,
    cdx: 0,
    cdy: 0,
    cddx: 0,
    cddy: 0,
    cdddx: 0,
    cdddy: 0,
    c_last_x: 0,
    c_last_y: 0,
  }
}

///|
fn fill_path_impl(
  path : Path,
  fill_rule : FillRule,
  clip_rect : ScreenIntRect,
  start_y : Int,
  stop_y : Int,
  shift_edges_up : Int,
  path_contained_in_clip : Bool,
  blitter : &Blitter,
) -> Unit {
  let shifted_clip = match ShiftedIntRect::new(clip_rect, shift_edges_up) {
    Some(v) => v
    None => return
  }
  let clip = if path_contained_in_clip { None } else { Some(shifted_clip) }
  let built = match build_edges(path, clip, shift_edges_up) {
    Some(v) => v
    None => return
  }
  let sorted = sort_edges(built)
  for i, e in sorted {
    e.prev = i
    e.next = i + 2
  }
  let edges : Array[Edge] = [sentinel_edge(-1, 1, -2147483648, -2147483648)]
  edges.append(sorted)
  edges.push(sentinel_edge(edges.length() - 1, -1, 0, 2147483647))
  let mut start_y = start_y << shift_edges_up
  let mut stop_y = stop_y << shift_edges_up
  let top = shifted_clip.shifted.y
  if !path_contained_in_clip && start_y < top {
    start_y = top
  }
  let bottom = shifted_clip.shifted.bottom()
  if !path_contained_in_clip && stop_y > bottom {
    stop_y = bottom
  }
  if start_y < 0 || stop_y < 0 {
    return
  }
  walk_edges(fill_rule, start_y, stop_y, shifted_clip.shifted.right(), edges, blitter)
}

///|
fn walk_edges(
  fill_rule : FillRule,
  start_y : Int,
  stop_y : Int,
  right_clip : Int,
  edges : Array[Edge],
  blitter : &Blitter,
) -> Unit {
  let mut curr_y = start_y
  let winding_mask = if fill_rule == EvenOdd { 1 } else { -1 }
  while true {
    let mut w = 0
    let mut left = 0
    let mut prev_x = edges[0].x
    let mut curr_idx = edges[0].next
    while edges[curr_idx].first_y <= curr_y {
      let e = edges[curr_idx]
      let x = fdot16_round_to_i32(e.x)
      if (w & winding_mask) == 0 {
        left = x
      }
      w += e.winding
      if (w & winding_mask) == 0 {
        let width = x - left
        if width != 0 {
          blitter.blit_h(left, curr_y, width)
        }
      }
      let next_idx = e.next
      if e.last_y == curr_y {
        match e.kind {
          ELine => remove_edge(curr_idx, edges)
          EQuad =>
            if e.curve_count > 0 && e.update() {
              let new_x = e.x
              if new_x < prev_x {
                backward_insert_edge_based_on_x(curr_idx, edges)
              } else {
                prev_x = new_x
              }
            } else {
              remove_edge(curr_idx, edges)
            }
          ECubic =>
            if e.curve_count < 0 && e.update() {
              let new_x = e.x
              if new_x < prev_x {
                backward_insert_edge_based_on_x(curr_idx, edges)
              } else {
                prev_x = new_x
              }
            } else {
              remove_edge(curr_idx, edges)
            }
        }
      } else {
        let new_x = e.x + e.dx
        e.x = new_x
        if new_x < prev_x {
          backward_insert_edge_based_on_x(curr_idx, edges)
        } else {
          prev_x = new_x
        }
      }
      curr_idx = next_idx
    }
    if (w & winding_mask) != 0 {
      let width = right_clip - left
      if width != 0 {
        blitter.blit_h(left, curr_y, width)
      }
    }
    curr_y += 1
    if curr_y >= stop_y {
      break
    }
    insert_new_edges(curr_idx, curr_y, edges)
  }
}

///|
fn remove_edge(curr_idx : Int, edges : Array[Edge]) -> Unit {
  let prev = edges[curr_idx].prev
  let next = edges[curr_idx].next
  edges[prev].next = next
  edges[next].prev = prev
}

///|
fn backward_insert_edge_based_on_x(curr_idx : Int, edges : Array[Edge]) -> Unit {
  let x = edges[curr_idx].x
  let mut prev_idx = edges[curr_idx].prev
  while prev_idx != 0 {
    if edges[prev_idx].x > x {
      prev_idx = edges[prev_idx].prev
    } else {
      break
    }
  }
  let next_idx = edges[prev_idx].next
  if next_idx != curr_idx {
    remove_edge(curr_idx, edges)
    insert_edge_after(curr_idx, prev_idx, edges)
  }
}

///|
fn insert_edge_after(curr_idx : Int, after_idx : Int, edges : Array[Edge]) -> Unit {
  edges[curr_idx].prev = after_idx
  edges[curr_idx].next = edges[after_idx].next
  let after_next_idx = edges[after_idx].next
  edges[after_next_idx].prev = curr_idx
  edges[after_idx].next = curr_idx
}

///|
fn backward_insert_start(prev_idx : Int, x : Int, edges : Array[Edge]) -> Int {
  let mut prev_idx = prev_idx
  while edges[prev_idx].prev != -1 {
    prev_idx = edges[prev_idx].prev
    if edges[prev_idx].x <= x {
      break
    }
  }
  prev_idx
}

///|
fn insert_new_edges(new_idx : Int, curr_y : Int, edges : Array[Edge]) -> Unit {
  let mut new_idx = new_idx
  if edges[new_idx].first_y != curr_y {
    return
  }
  let prev_idx = edges[new_idx].prev
  if edges[prev_idx].x <= edges[new_idx].x {
    return
  }
  let mut start_idx = backward_insert_start(prev_idx, edges[new_idx].x, edges)
  while true {
    let next_idx = edges[new_idx].next
    let mut keep_edge = false
    while true {
      let after_idx = edges[start_idx].next
      if after_idx == new_idx {
        keep_edge = true
        break
      }
      if edges[after_idx].x >= edges[new_idx].x {
        break
      }
      start_idx = after_idx
    }
    if !keep_edge {
      remove_edge(new_idx, edges)
      insert_edge_after(new_idx, start_idx, edges)
    }
    start_idx = new_idx
    new_idx = next_idx
    if edges[new_idx].first_y != curr_y {
      break
    }
  }
}

// ── anti-aliased filling ──────────────────────────────────────────────

///|
let supersample_shift : Int = 2

///|
let ss_scale : Int = 1 << 2

///|
let ss_mask : Int = (1 << 2) - 1

///|
fn fill_path_aa(path : Path, fill_rule : FillRule, clip : ScreenIntRect, blitter : &Blitter) -> Unit {
  let b = path.bounds
  let ir = match Rect::from_ltrb(b.left.floor(), b.top.floor(), b.right.ceil(), b.bottom.ceil()) {
    Some(r) => r.round_out()
    None => None
  }
  let ir = match ir {
    Some(v) => v
    None => return
  }
  let clipped_ir = match ir.intersect(clip.to_int_rect()) {
    Some(v) => v
    None => return
  }
  if rect_overflows_short_shift(clipped_ir, supersample_shift) != 0 {
    fill_path_nonaa(path, fill_rule, clip, blitter)
    return
  }
  if clip.right() > 32767 || clip.bottom() > 32767 {
    return
  }
  let sb = match SuperBlitter::new(ir, clip, blitter) {
    Some(v) => v
    None => return
  }
  let contained = match ir.to_screen_int_rect() {
    Some(bounds) => clip.contains(bounds)
    None => false
  }
  fill_path_impl(path, fill_rule, clip, ir.y, ir.bottom(), supersample_shift, contained, sb)
  // (Drop)
  sb.flush()
}

///|
fn rect_overflows_short_shift(rect : IntRect, shift : Int) -> Int {
  overflows_short_shift(rect.left(), shift) |
  overflows_short_shift(rect.top(), shift) |
  overflows_short_shift(rect.right(), shift) |
  overflows_short_shift(rect.bottom(), shift)
}

///|
fn overflows_short_shift(value : Int, shift : Int) -> Int {
  let s = 16 + shift
  (left_shift(value, s) >> s) - value
}

///|
/// The supersampling blitter: 4 subscanlines summed into a row of alpha runs, handed on to the real blitter.
priv struct SuperBlitter {
  real_blitter : &Blitter
  mut curr_iy : Int
  width : Int
  left : Int
  super_left : Int
  mut curr_y : Int
  top : Int
  runs : AlphaRuns
  mut offset_x : Int
}

///|
fn SuperBlitter::new(bounds : IntRect, clip_rect : ScreenIntRect, blitter : &Blitter) -> SuperBlitter? {
  let sect = match bounds.intersect(clip_rect.to_int_rect()) {
    Some(r) =>
      match r.to_screen_int_rect() {
        Some(s) => s
        None => return None
      }
    None => return None
  }
  Some({
    real_blitter: blitter,
    curr_iy: sect.y - 1,
    width: sect.width,
    left: sect.x,
    super_left: sect.x << supersample_shift,
    curr_y: (sect.y << supersample_shift) - 1,
    top: sect.y,
    runs: AlphaRuns::new(sect.width),
    offset_x: 0,
  })
}

///|
fn SuperBlitter::flush(self : SuperBlitter) -> Unit {
  if self.curr_iy >= self.top {
    if !self.runs.is_empty() {
      self.real_blitter.blit_anti_h(self.left, self.curr_iy, self.runs.alpha, self.runs.runs)
      self.runs.reset(self.width)
      self.offset_x = 0
    }
    self.curr_iy = self.top - 1
  }
}

///|
impl Blitter for SuperBlitter with blit_h(self, x, y, width) {
  let iy = y >> supersample_shift
  let mut x = x
  let mut width = width
  if x >= self.super_left {
    x = x - self.super_left
  } else {
    width = x + width
    x = 0
  }
  if self.curr_y != y {
    self.offset_x = 0
    self.curr_y = y
  }
  if iy != self.curr_iy {
    self.flush()
    self.curr_iy = iy
  }
  let start = x
  let stop = x + width
  let mut fb = start & ss_mask
  let mut fe = stop & ss_mask
  let mut n = (stop >> supersample_shift) - (start >> supersample_shift) - 1
  if n < 0 {
    fb = fe - fb
    n = 0
    fe = 0
  } else if fb == 0 {
    n += 1
  } else {
    fb = ss_scale - fb
  }
  let max_value = (1 << (8 - supersample_shift)) - (((y & ss_mask) + 1) >> supersample_shift)
  self.offset_x = self.runs.add(
    x >> supersample_shift,
    coverage_to_partial_alpha(fb),
    n,
    coverage_to_partial_alpha(fe),
    max_value,
    self.offset_x,
  )
}

///|
impl Blitter for SuperBlitter with blit_anti_h(_self, _x, _y, _alpha, _runs) {
  abort("SuperBlitter: blit_anti_h")
}

///|
impl Blitter for SuperBlitter with blit_v(_self, _x, _y, _height, _alpha) {
  abort("SuperBlitter: blit_v")
}

///|
impl Blitter for SuperBlitter with blit_anti_h2(_self, _x, _y, _a0, _a1) {
  abort("SuperBlitter: blit_anti_h2")
}

///|
impl Blitter for SuperBlitter with blit_anti_v2(_self, _x, _y, _a0, _a1) {
  abort("SuperBlitter: blit_anti_v2")
}

///|
impl Blitter for SuperBlitter with blit_rect(_self, _rect) {
  abort("SuperBlitter: blit_rect")
}

///|
fn coverage_to_partial_alpha(aa : Int) -> Int {
  (aa << (8 - 2 * supersample_shift)) & 0xFF
}
