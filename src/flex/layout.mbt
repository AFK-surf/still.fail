// A flexbox layout engine following the CSS Flexible Box algorithm with
// Yoga's defaults and rounding, checked against Yoga's tests (generated
// from Chrome). Sizes are border-box; NaN means "not known".

///|
let undef : Double = 0.0 / 0.0

///|
fn known(x : Double) -> Bool {
  x == x
}

///|
fn or_else(x : Double, y : Double) -> Double {
  if known(x) {
    x
  } else {
    y
  }
}

///|
fn fmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn fmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// A dimension against a reference length (NaN when it can't be resolved).
fn resolve(d : Dim, base : Double) -> Double {
  match d {
    Auto => undef
    Pt(v) => v
    Pct(p) => if known(base) { base * p / 100.0 } else { undef }
  }
}

///|
/// An edge length (margin, padding, border): auto and unresolved are 0.
fn edge(d : Dim, base : Double) -> Double {
  let v = resolve(d, base)
  if known(v) {
    v
  } else {
    0.0
  }
}

///|
fn clamp_size(v : Double, lo : Double, hi : Double) -> Double {
  let mut r = v
  if known(hi) && r > hi {
    r = hi
  }
  if known(lo) && r < lo {
    r = lo
  }
  r
}

///|
fn is_row(d : FlexDirection) -> Bool {
  d == Row || d == RowReverse
}

///|
fn is_reverse(d : FlexDirection) -> Bool {
  d == RowReverse || d == ColumnReverse
}

///|
/// What a node's own style says about its box, against its containing
/// block (cb_w, cb_h: the parent's content box).
priv struct Box {
  pad_l : Double
  pad_t : Double
  pad_r : Double
  pad_b : Double
  bor_l : Double
  bor_t : Double
  bor_r : Double
  bor_b : Double
  mar_l : Double
  mar_t : Double
  mar_r : Double
  mar_b : Double
  // size from style, border-box, NaN when auto
  w : Double
  h : Double
  min_w : Double
  min_h : Double
  max_w : Double
  max_h : Double
}

///|
fn box_of(s : Style, cb_w : Double, cb_h : Double) -> Box {
  ignore(cb_h)
  let pad_l = edge(s.padding.left, cb_w)
  let pad_r = edge(s.padding.right, cb_w)
  let pad_t = edge(s.padding.top, cb_w)
  let pad_b = edge(s.padding.bottom, cb_w)
  let bor_l = edge(s.border.left, cb_w)
  let bor_r = edge(s.border.right, cb_w)
  let bor_t = edge(s.border.top, cb_w)
  let bor_b = edge(s.border.bottom, cb_w)
  let pbw = pad_l + pad_r + bor_l + bor_r
  let pbh = pad_t + pad_b + bor_t + bor_b
  // content-box sizes grow by the padding and border (NaN stays NaN)
  let (adj_w, adj_h) = if s.box_sizing == ContentBox {
    (pbw, pbh)
  } else {
    (0.0, 0.0)
  }
  let mut min_w = resolve(s.min_width, cb_w) + adj_w
  let mut min_h = resolve(s.min_height, cb_h) + adj_h
  // a box is never smaller than its padding and border
  min_w = if known(min_w) { fmax(min_w, pbw) } else { pbw }
  min_h = if known(min_h) { fmax(min_h, pbh) } else { pbh }
  {
    pad_l,
    pad_t,
    pad_r,
    pad_b,
    bor_l,
    bor_t,
    bor_r,
    bor_b,
    mar_l: edge(s.margin.left, cb_w),
    mar_t: edge(s.margin.top, cb_w),
    mar_r: edge(s.margin.right, cb_w),
    mar_b: edge(s.margin.bottom, cb_w),
    w: resolve(s.width, cb_w) + adj_w,
    h: resolve(s.height, cb_h) + adj_h,
    min_w,
    min_h,
    max_w: resolve(s.max_width, cb_w) + adj_w,
    max_h: resolve(s.max_height, cb_h) + adj_h,
  }
}

///|
fn Box::pbw(self : Box) -> Double {
  self.pad_l + self.pad_r + self.bor_l + self.bor_r
}

///|
fn Box::pbh(self : Box) -> Double {
  self.pad_t + self.pad_b + self.bor_t + self.bor_b
}

///|
/// Lays out `root` and everything under it. Positions are relative to the
/// parent's border box and rounded to whole pixels, as Yoga does.
///|
/// Lays out the tree under `root` in a space of `width` × `height` (NaN:
/// unbounded), as Yoga's calculateLayout does. Results are relative to the
/// parent's border box; with `round` they snap to whole units.
pub fn compute(
  root : Node,
  width? : Double = undef,
  height? : Double = undef,
  round? : Bool = true,
) -> Unit {
  generation.val = generation.val + 1
  let b = box_of(root.style, width, height)
  let w = or_else(b.w, if root.style.position == Absolute { undef } else { width })
  let h = or_else(b.h, if root.style.position == Absolute { undef } else { height })
  // without a size, the root may grow up to its max size (Yoga)
  let aw = if known(w) { w } else if known(b.max_w) { b.max_w } else { width }
  let ah = if known(h) { h } else if known(b.max_h) { b.max_h } else { height }
  let (fw, fh) = size_node(root, w, h, aw, ah, aw, ah, true)
  root.width = fw
  root.height = fh
  let s = root.style
  let dx = if s.position == Relative || s.position == Absolute {
    let l = resolve(s.inset.left, width)
    let r = resolve(s.inset.right, width)
    if known(l) { l } else if known(r) { -r } else { 0.0 }
  } else {
    0.0
  }
  let dy = if s.position == Relative || s.position == Absolute {
    let t = resolve(s.inset.top, height)
    let bt = resolve(s.inset.bottom, height)
    if known(t) { t } else if known(bt) { -bt } else { 0.0 }
  } else {
    0.0
  }
  root.left = b.mar_l + dx
  root.top = b.mar_t + dy
  layout_static_absolute(root, root, 0.0, 0.0)
  if round {
    round_layout(root, 0.0, 0.0)
  }
}

///|
/// The offset of a relatively positioned box from its insets.
fn inset_offset(s : Style, cb_w : Double, cb_h : Double, horizontal : Bool) -> Double {
  if s.position != Relative {
    return 0.0
  }
  if horizontal {
    let l = resolve(s.inset.left, cb_w)
    if known(l) {
      return l
    }
    let r = resolve(s.inset.right, cb_w)
    if known(r) {
      -r
    } else {
      0.0
    }
  } else {
    let t = resolve(s.inset.top, cb_h)
    if known(t) {
      return t
    }
    let b = resolve(s.inset.bottom, cb_h)
    if known(b) {
      -b
    } else {
      0.0
    }
  }
}

///|
/// Bumped by every compute(): sizes cached on nodes are only good within one.
let generation : Ref[Int] = { val: 0 }

///|
/// Work done so far: sizes computed, sizes found in the cache, leaves
/// measured. For benchmarks.
pub let counters : FixedArray[Int] = FixedArray::make(3, 0)

///|
fn same(a : Double, b : Double) -> Bool {
  a == b || (!known(a) && !known(b))
}

///|
/// Whether a size found along one axis for (old_k, old_a) — known size,
/// available space — is the one (k, a) would give, as Yoga's
/// canUseCachedMeasurement decides: a box asked for exactly the size it
/// came out at before, or offered at least the room its content took
/// when it was offered unlimited or more room.
fn reusable(
  k : Double,
  a : Double,
  old_k : Double,
  old_a : Double,
  result : Double,
) -> Bool {
  if known(k) {
    return (known(old_k) && old_k == k) || (result - k).abs() < 0.0001
  }
  if known(old_k) {
    return false
  }
  if known(a) {
    if !known(old_a) {
      return result <= a + 0.0001
    }
    return old_a == a || (old_a > a && result <= a + 0.0001)
  }
  !known(old_a)
}

///|
/// The border-box size of `node`. `kw`/`kh`: sizes already decided by the
/// parent (NaN if not). `aw`/`ah`: the space available (NaN: unbounded).
/// `cb_w`/`cb_h`: the containing block, for percentages. With `perform`,
/// also places its children.
///
/// A container sizes each child for its basis, its cross size and then
/// for real, and each of those sizes the grandchildren again: without the
/// cache below that is exponential in the depth of the tree.
fn size_node(
  node : Node,
  kw : Double,
  kh : Double,
  aw : Double,
  ah : Double,
  cb_w : Double,
  cb_h : Double,
  perform : Bool,
) -> (Double, Double) {
  if node.cache_gen != generation.val {
    node.cache.clear()
    node.cache_gen = generation.val
  }
  let c = node.cache
  if !perform {
    let mut k = 0
    while k < c.length() {
      if same(c[k + 4], cb_w) &&
        same(c[k + 5], cb_h) &&
        reusable(kw, aw, c[k], c[k + 2], c[k + 6]) &&
        reusable(kh, ah, c[k + 1], c[k + 3], c[k + 7]) {
        counters[1] = counters[1] + 1
        return (c[k + 6], c[k + 7])
      }
      k = k + 8
    }
  }
  counters[0] = counters[0] + 1
  let (w, h) = size_uncached(node, kw, kh, aw, ah, cb_w, cb_h, perform)
  if c.length() >= 8 * 16 {
    c.clear()
  }
  c.push(kw)
  c.push(kh)
  c.push(aw)
  c.push(ah)
  c.push(cb_w)
  c.push(cb_h)
  c.push(w)
  c.push(h)
  (w, h)
}

///|
fn size_uncached(
  node : Node,
  kw : Double,
  kh : Double,
  aw : Double,
  ah : Double,
  cb_w : Double,
  cb_h : Double,
  perform : Bool,
) -> (Double, Double) {
  let s = node.style
  let b = box_of(s, cb_w, cb_h)
  let mut w = if known(kw) { kw } else { b.w }
  let mut h = if known(kh) { kh } else { b.h }
  // a min equal to the max is a size (Chrome resolves percentages of it)
  if !known(w) && known(b.min_w) && b.min_w == b.max_w {
    w = b.min_w
  }
  if !known(h) && known(b.min_h) && b.min_h == b.max_h {
    h = b.min_h
  }
  // aspect ratio fills in the missing side
  if s.aspect > 0.0 {
    if known(w) && !known(h) {
      h = w / s.aspect
    } else if known(h) && !known(w) {
      w = h * s.aspect
    }
  }
  if known(w) {
    w = clamp_size(w, b.min_w, b.max_w)
  }
  if known(h) {
    h = clamp_size(h, b.min_h, b.max_h)
  }
  let pbw = b.pbw()
  let pbh = b.pbh()
  // leaves measured from their content
  match node.measure {
    Some(m) =>
      if node.children.length() == 0 {
        if known(w) && known(h) {
          return (w, h)
        }
        let iw = if known(w) {
          w - pbw
        } else if known(aw) {
          fmax(clamp_size(aw, b.min_w, b.max_w) - pbw, 0.0)
        } else {
          undef
        }
        let ih = if known(h) {
          h - pbh
        } else if known(ah) {
          fmax(clamp_size(ah, b.min_h, b.max_h) - pbh, 0.0)
        } else {
          undef
        }
        let wm = if known(w) {
          Exactly
        } else if known(iw) {
          AtMost
        } else {
          Undefined
        }
        let hm = if known(h) {
          Exactly
        } else if known(ih) {
          AtMost
        } else {
          Undefined
        }
        counters[2] = counters[2] + 1
        let (mw, mh) = m(
          if known(iw) { iw } else { 0.0 },
          wm,
          if known(ih) { ih } else { 0.0 },
          hm,
        )
        let fw = if known(w) { w } else { clamp_size(mw + pbw, b.min_w, b.max_w) }
        let fh = if known(h) { h } else { clamp_size(mh + pbh, b.min_h, b.max_h) }
        return (fw, fh)
      }
    None => ()
  }
  layout_flex(node, b, w, h, aw, ah, perform)
}

///|
priv struct Item {
  node : Node
  b : Box
  auto_l : Bool
  auto_t : Bool
  auto_r : Bool
  auto_b : Bool
  mut basis : Double
  mut hyp : Double // hypothetical main size (clamped basis)
  mut main : Double
  mut cross : Double
  mut frozen : Bool
  mut target : Double
  mut line : Int
  mut main_pos : Double
  mut cross_pos : Double
  min_main : Double
  max_main : Double
  min_cross : Double
  max_cross : Double
  margin_main : Double
  margin_cross : Double
  stretch : Bool
  align : Align
  row : Bool
  mut ascent : Double
}

///|
priv struct Line {
  start : Int
  end : Int
  mut cross : Double
  mut pos : Double
  mut ascent : Double
}

///|
fn item_align(container : Style, s : Style) -> Align {
  if s.align_self == Auto {
    container.align_items
  } else {
    s.align_self
  }
}

///|
fn layout_flex(
  node : Node,
  b : Box,
  w0 : Double,
  h0 : Double,
  aw : Double,
  ah : Double,
  perform : Bool,
) -> (Double, Double) {
  let s = node.style
  let row = is_row(s.direction)
  let pbw = b.pbw()
  let pbh = b.pbh()
  // the content box, when known
  let inner_w = if known(w0) { fmax(w0 - pbw, 0.0) } else { undef }
  let inner_h = if known(h0) { fmax(h0 - pbh, 0.0) } else { undef }
  // the space children can use when the size isn't known
  let avail_inner_w = if known(inner_w) {
    inner_w
  } else if known(aw) {
    fmax(clamp_size(aw, b.min_w, b.max_w) - pbw, 0.0)
  } else {
    undef
  }
  let avail_inner_h = if known(inner_h) {
    inner_h
  } else if known(ah) {
    fmax(clamp_size(ah, b.min_h, b.max_h) - pbh, 0.0)
  } else {
    undef
  }
  let inner_main = if row { inner_w } else { inner_h }
  let inner_cross = if row { inner_h } else { inner_w }
  let avail_main = if row { avail_inner_w } else { avail_inner_h }
  let avail_cross = if row { avail_inner_h } else { avail_inner_w }
  let gap_main = edge(if row { s.gap_col } else { s.gap_row }, inner_main)
  let gap_cross = edge(if row { s.gap_row } else { s.gap_col }, inner_cross)
  // percentages of children resolve against this content box
  let cb_w = inner_w
  let cb_h = inner_h
  // flex items
  let items : Array[Item] = []
  let flow = flow_children(node)
  for c in flow {
    let cs = c.style
    if cs.position == Absolute {
      continue
    }
    let cb = box_of(cs, cb_w, cb_h)
    let al = item_align(s, cs)
    let margin_main = if row { cb.mar_l + cb.mar_r } else { cb.mar_t + cb.mar_b }
    let margin_cross = if row { cb.mar_t + cb.mar_b } else { cb.mar_l + cb.mar_r }
    let cross_style = if row { cb.h } else { cb.w }
    let auto_cross_margin = if row {
      cs.margin.top == Auto || cs.margin.bottom == Auto
    } else {
      cs.margin.left == Auto || cs.margin.right == Auto
    }
    let item = {
      node: c,
      b: cb,
      auto_l: cs.margin.left == Auto,
      auto_t: cs.margin.top == Auto,
      auto_r: cs.margin.right == Auto,
      auto_b: cs.margin.bottom == Auto,
      basis: 0.0,
      hyp: 0.0,
      main: 0.0,
      cross: 0.0,
      frozen: false,
      target: 0.0,
      line: 0,
      main_pos: 0.0,
      cross_pos: 0.0,
      min_main: if row { cb.min_w } else { cb.min_h },
      max_main: if row { cb.max_w } else { cb.max_h },
      min_cross: if row { cb.min_h } else { cb.min_w },
      max_cross: if row { cb.max_h } else { cb.max_w },
      margin_main,
      margin_cross,
      stretch: al == Stretch && !known(cross_style) && !auto_cross_margin,
      align: al,
      row,
      ascent: 0.0,
    }
    // flex base size
    let basis_style = resolve(cs.basis, inner_main)
    let main_style = if row { cb.w } else { cb.h }
    let mut basis = if known(basis_style) && cs.basis != Auto {
      if cs.box_sizing == ContentBox {
        basis_style + (if row { cb.pbw() } else { cb.pbh() })
      } else {
        basis_style
      }
    } else if known(main_style) {
      main_style
    } else {
      undef
    }
    if !known(basis) {
      // size from content: cross known if fixed or stretched in a known line
      let mut kc = cross_style
      if !known(kc) && item.stretch && known(inner_cross) && s.wrap == NoWrap {
        kc = fmax(inner_cross - margin_cross, 0.0)
      }
      let (cw, ch) = if row {
        size_node(
          c,
          undef,
          kc,
          if known(avail_main) { avail_main - margin_main } else { undef },
          if known(avail_cross) { avail_cross - margin_cross } else { undef },
          cb_w,
          cb_h,
          false,
        )
      } else {
        size_node(
          c,
          kc,
          undef,
          if known(avail_cross) { avail_cross - margin_cross } else { undef },
          if known(avail_main) { avail_main - margin_main } else { undef },
          cb_w,
          cb_h,
          false,
        )
      }
      basis = if row { cw } else { ch }
    }
    let pb_main = if row { cb.pbw() } else { cb.pbh() }
    basis = fmax(basis, pb_main)
    item.basis = basis
    item.hyp = clamp_size(basis, item.min_main, item.max_main)
    items.push(item)
  }
  // lines
  let lines : Array[Line] = []
  let wrap = s.wrap != NoWrap
  let line_limit = if known(inner_main) { inner_main } else { avail_main }
  let mut start = 0
  let mut sum = 0.0
  for i, it in items {
    let outer = it.hyp + it.margin_main
    if wrap &&
      i > start &&
      known(line_limit) &&
      sum + gap_main + outer > line_limit + 0.0001 {
      lines.push({ start, end: i, cross: 0.0, pos: 0.0, ascent: 0.0 })
      start = i
      sum = outer
    } else {
      sum = if i == start { outer } else { sum + gap_main + outer }
    }
  }
  if items.length() > 0 || lines.length() == 0 {
    lines.push({ start, end: items.length(), cross: 0.0, pos: 0.0, ascent: 0.0 })
  }
  // resolve flexible lengths, line by line
  let mut max_line_main = 0.0
  for ln in lines {
    let n = ln.end - ln.start
    let gaps = if n > 1 { gap_main * (n - 1).to_double() } else { 0.0 }
    let mut sum_hyp = gaps
    for k in ln.start..<ln.end {
      sum_hyp = sum_hyp + items[k].hyp + items[k].margin_main
    }
    // the main size to fill: the container's, or the space available when
    // the content would overflow it
    let mut space = inner_main
    if !known(space) {
      let lo = if row { b.min_w - pbw } else { b.min_h - pbh }
      let hi = if row { b.max_w - pbw } else { b.max_h - pbh }
      if known(avail_main) && sum_hyp > avail_main {
        space = avail_main
      } else if known(hi) && sum_hyp > hi {
        space = hi
      } else if known(lo) && sum_hyp < lo {
        space = lo
      }
    }
    if known(space) {
      resolve_flexible(items, ln.start, ln.end, space - gaps)
    } else {
      for k in ln.start..<ln.end {
        items[k].main = items[k].hyp
      }
    }
    let mut used = gaps
    for k in ln.start..<ln.end {
      used = used + items[k].main + items[k].margin_main
    }
    max_line_main = fmax(max_line_main, used)
  }
  // container main size
  let main_size = if known(inner_main) {
    inner_main
  } else if wrap && known(avail_main) && lines.length() > 1 {
    // a container that wraps takes all the space it was given (Yoga)
    avail_main
  } else {
    let pb = if row { pbw } else { pbh }
    let lo = if row { b.min_w } else { b.min_h }
    let hi = if row { b.max_w } else { b.max_h }
    clamp_size(max_line_main + pb, lo, hi) - pb
  }
  // hypothetical cross sizes
  for it in items {
    let cs = it.node.style
    let cross_style = if row { it.b.h } else { it.b.w }
    if known(cross_style) {
      it.cross = clamp_size(cross_style, it.min_cross, it.max_cross)
    } else {
      // stretched items in a single line of known cross size take it
      let kc = if it.stretch && known(inner_cross) && !wrap {
        fmax(inner_cross - it.margin_cross, 0.0)
      } else {
        undef
      }
      if known(kc) {
        // what sizing it would return, without laying out its subtree
        it.cross = clamp_size(kc, it.min_cross, it.max_cross)
        continue
      }
      let ac = if known(avail_cross) { avail_cross - it.margin_cross } else { undef }
      let (cw, ch) = if row {
        size_node(it.node, it.main, kc, it.main, ac, cb_w, cb_h, false)
      } else {
        size_node(it.node, kc, it.main, ac, it.main, cb_w, cb_h, false)
      }
      ignore(cs)
      it.cross = clamp_size(if row { ch } else { cw }, it.min_cross, it.max_cross)
    }
  }
  // line cross sizes; items aligned by baseline share the line's baseline
  for li, ln in lines {
    let mut c = 0.0
    let mut asc = 0.0
    let mut desc = 0.0
    for k in ln.start..<ln.end {
      let it = items[k]
      it.line = li
      if it.align == Baseline && row {
        let (iw, ih) = (it.main, it.cross)
        let (rw, rh) = size_node(it.node, iw, ih, iw, ih, cb_w, cb_h, true)
        it.node.width = rw
        it.node.height = rh
        it.ascent = node_baseline(it.node) + it.b.mar_t
        asc = fmax(asc, it.ascent)
        desc = fmax(desc, it.cross + it.margin_cross - it.ascent)
      } else {
        c = fmax(c, it.cross + it.margin_cross)
      }
    }
    ln.ascent = asc
    ln.cross = fmax(c, asc + desc)
  }
  if !wrap && known(inner_cross) && lines.length() == 1 {
    lines[0].cross = inner_cross
  }
  // container cross size
  let nl = lines.length()
  let mut lines_cross = if nl > 1 { gap_cross * (nl - 1).to_double() } else { 0.0 }
  for ln in lines {
    lines_cross = lines_cross + ln.cross
  }
  let cross_size = if known(inner_cross) {
    inner_cross
  } else {
    let pb = if row { pbh } else { pbw }
    let lo = if row { b.min_h } else { b.min_w }
    let hi = if row { b.max_h } else { b.max_w }
    clamp_size(lines_cross + pb, lo, hi) - pb
  }
  // align-content: stretch lines when the container is taller than them
  if wrap {
    let free = cross_size - lines_cross
    if s.align_content == Stretch && free > 0.0 && nl > 0 {
      let extra = free / nl.to_double()
      for ln in lines {
        ln.cross = ln.cross + extra
      }
    }
  } else if nl == 1 {
    lines[0].cross = cross_size
  }
  // stretch items to their line
  for ln in lines {
    for k in ln.start..<ln.end {
      let it = items[k]
      if it.stretch {
        it.cross = clamp_size(
          fmax(ln.cross - it.margin_cross, 0.0),
          it.min_cross,
          it.max_cross,
        )
      }
    }
  }
  // position lines along the cross axis
  let mut total_cross = if nl > 1 { gap_cross * (nl - 1).to_double() } else { 0.0 }
  for ln in lines {
    total_cross = total_cross + ln.cross
  }
  let free_cross = cross_size - total_cross
  let (lead, between) = distribute(
    if wrap { s.align_content } else { FlexStart },
    free_cross,
    nl,
    true,
  )
  let mut cp = lead
  for ln in lines {
    ln.pos = cp
    cp = cp + ln.cross + gap_cross + between
  }
  // place items in each line
  let reverse = is_reverse(s.direction)
  for ln in lines {
    let n = ln.end - ln.start
    let gaps = if n > 1 { gap_main * (n - 1).to_double() } else { 0.0 }
    let mut used = gaps
    let mut auto_margins = 0
    for k in ln.start..<ln.end {
      let it = items[k]
      used = used + it.main + it.margin_main
      if row {
        if it.auto_l {
          auto_margins = auto_margins + 1
        }
        if it.auto_r {
          auto_margins = auto_margins + 1
        }
      } else {
        if it.auto_t {
          auto_margins = auto_margins + 1
        }
        if it.auto_b {
          auto_margins = auto_margins + 1
        }
      }
    }
    let free = main_size - used
    let per_auto = if auto_margins > 0 && free > 0.0 {
      free / auto_margins.to_double()
    } else {
      0.0
    }
    let (lead, between) = if auto_margins > 0 {
      (0.0, 0.0)
    } else {
      distribute(s.justify, free, n, false)
    }
    let mut p = lead
    for k in ln.start..<ln.end {
      let it = items[k]
      let (m_start, m_end, a_start, a_end) = if row {
        (it.b.mar_l, it.b.mar_r, it.auto_l, it.auto_r)
      } else {
        (it.b.mar_t, it.b.mar_b, it.auto_t, it.auto_b)
      }
      let ms = m_start + (if a_start { per_auto } else { 0.0 })
      let me = m_end + (if a_end { per_auto } else { 0.0 })
      if reverse {
        it.main_pos = main_size - (p + ms) - it.main
      } else {
        it.main_pos = p + ms
      }
      p = p + ms + it.main + me + gap_main + between
      // cross axis within the line
      let (c_start, c_end, ca_start, ca_end) = if row {
        (it.b.mar_t, it.b.mar_b, it.auto_t, it.auto_b)
      } else {
        (it.b.mar_l, it.b.mar_r, it.auto_l, it.auto_r)
      }
      let free_c = ln.cross - it.cross - c_start - c_end
      let off = if ca_start && ca_end {
        fmax(free_c, 0.0) / 2.0
      } else if ca_start {
        fmax(free_c, 0.0)
      } else if ca_end {
        0.0
      } else {
        match it.align {
          FlexEnd => free_c
          Center => free_c / 2.0
          _ => 0.0
        }
      }
      it.cross_pos = ln.pos + c_start + off
      if it.align == Baseline && row && !(ca_start || ca_end) {
        it.cross_pos = ln.pos + ln.ascent - it.ascent + c_start
      }
      if s.wrap == WrapReverse {
        it.cross_pos = cross_size - it.cross_pos - it.cross
      }
      it.node.line = it.line
    }
  }
  let fw = if row { main_size + pbw } else { cross_size + pbw }
  let fh = if row { cross_size + pbh } else { main_size + pbh }
  if perform {
    let ox = b.bor_l + b.pad_l
    let oy = b.bor_t + b.pad_t
    for it in items {
      let (iw, ih) = if row { (it.main, it.cross) } else { (it.cross, it.main) }
      let (rw, rh) = size_node(it.node, iw, ih, iw, ih, cb_w, cb_h, true)
      it.node.width = rw
      it.node.height = rh
      let (x, y) = if row {
        (it.main_pos, it.cross_pos)
      } else {
        (it.cross_pos, it.main_pos)
      }
      it.node.left = ox + x + inset_offset(it.node.style, fw - pbw, fh - pbh, true)
      it.node.top = oy + y + inset_offset(it.node.style, fw - pbw, fh - pbh, false)
    }
    ignore(flow)
    for c in node.children {
      if c.style.display == DisplayNone {
        zero(c)
      }
    }
  }
  (fw, fh)
}

///|
/// Children taking part in layout: display: contents lifts its children up.
fn flow_children(node : Node) -> Array[Node] {
  let mut plain = true
  for c in node.children {
    if c.style.display != Flex {
      plain = false
      break
    }
  }
  if plain {
    return node.children
  }
  let out = []
  for c in node.children {
    match c.style.display {
      DisplayNone => ()
      Contents => {
        zero(c)
        for g in flow_children(c) {
          out.push(g)
        }
      }
      Flex => out.push(c)
    }
  }
  out
}

///|
fn zero(n : Node) -> Unit {
  n.left = 0.0
  n.top = 0.0
  n.width = 0.0
  n.height = 0.0
  for c in n.children {
    zero(c)
  }
}

///|
/// Leading space and space between items for justify / align-content.
fn distribute(a : Align, free : Double, n : Int, content : Bool) -> (Double, Double) {
  ignore(content)
  if n <= 0 {
    return (0.0, 0.0)
  }
  let nd = n.to_double()
  match a {
    FlexEnd => (free, 0.0)
    Center => (free / 2.0, 0.0)
    SpaceBetween =>
      if n > 1 && free > 0.0 {
        (0.0, free / (nd - 1.0))
      } else {
        (0.0, 0.0)
      }
    SpaceAround =>
      if free > 0.0 {
        (free / nd / 2.0, free / nd)
      } else {
        (0.0, 0.0)
      }
    SpaceEvenly =>
      if free > 0.0 {
        (free / (nd + 1.0), free / (nd + 1.0))
      } else {
        (0.0, 0.0)
      }
    _ => (0.0, 0.0)
  }
}

///|
/// CSS flexbox §9.7: grow or shrink the items of one line to fill `space`.
fn resolve_flexible(items : Array[Item], a : Int, b : Int, space : Double) -> Unit {
  let mut sum_hyp = 0.0
  for k in a..<b {
    sum_hyp = sum_hyp + items[k].hyp + items[k].margin_main
  }
  let grow = sum_hyp < space
  // freeze inflexible items
  for k in a..<b {
    let it = items[k]
    it.target = it.hyp
    let factor = if grow { it.node.style.grow } else { it.node.style.shrink }
    if factor == 0.0 ||
      (grow && it.basis > it.hyp) ||
      (!grow && it.basis < it.hyp) {
      it.frozen = true
    } else {
      it.frozen = false
    }
  }
  let mut initial_free = space
  for k in a..<b {
    let it = items[k]
    initial_free = initial_free -
      it.margin_main -
      (if it.frozen { it.target } else { it.basis })
  }
  let mut rounds = 0
  while rounds < 64 {
    rounds = rounds + 1
    let mut unfrozen = 0
    let mut sum_factors = 0.0
    let mut free = space
    for k in a..<b {
      let it = items[k]
      free = free - it.margin_main - (if it.frozen { it.target } else { it.basis })
      if !it.frozen {
        unfrozen = unfrozen + 1
        sum_factors = sum_factors +
          (if grow { it.node.style.grow } else { it.node.style.shrink })
      }
    }
    if unfrozen == 0 {
      break
    }
    if sum_factors < 1.0 {
      let scaled = initial_free * sum_factors
      if scaled.abs() < free.abs() {
        free = scaled
      }
    }
    if grow {
      for k in a..<b {
        let it = items[k]
        if !it.frozen {
          it.target = it.basis + free * it.node.style.grow / sum_factors
        }
      }
    } else {
      let mut sum_scaled = 0.0
      for k in a..<b {
        let it = items[k]
        if !it.frozen {
          sum_scaled = sum_scaled + it.node.style.shrink * it.basis
        }
      }
      for k in a..<b {
        let it = items[k]
        if !it.frozen {
          let scaled = it.node.style.shrink * it.basis
          it.target = if sum_scaled > 0.0 {
            it.basis + free * scaled / sum_scaled
          } else {
            it.basis
          }
        }
      }
    }
    // clamp and freeze violators
    let mut total = 0.0
    let clamped = Array::make(b - a, 0.0)
    for k in a..<b {
      let it = items[k]
      if it.frozen {
        continue
      }
      let pb = if it.row { it.b.pbw() } else { it.b.pbh() }
      let lo = fmax(or_else(it.min_main, 0.0), pb)
      let c = clamp_size(it.target, lo, it.max_main)
      clamped[k - a] = c - it.target
      total = total + (c - it.target)
      it.target = c
    }
    for k in a..<b {
      let it = items[k]
      if it.frozen {
        continue
      }
      let v = clamped[k - a]
      if total == 0.0 ||
        (total > 0.0 && v > 0.0) ||
        (total < 0.0 && v < 0.0) {
        it.frozen = true
      }
    }
  }
  for k in a..<b {
    items[k].main = items[k].target
  }
}

///|
/// Absolutely positioned boxes, once everything else is placed: each one
/// against the padding box of its nearest positioned ancestor `cb` (static
/// boxes in between pass their absolute children up), and at its static
/// position in its parent when it has no insets. (ox, oy): the parent's
/// border box in cb's.
fn layout_static_absolute(cb : Node, node : Node, ox : Double, oy : Double) -> Unit {
  for c in node.children {
    let cs = c.style
    if cs.display == DisplayNone {
      continue
    }
    if cs.display == Contents {
      layout_static_absolute(cb, c, ox, oy)
      continue
    }
    if cs.position == Absolute {
      place_absolute(cb, node, c, ox, oy)
      layout_static_absolute(c, c, 0.0, 0.0)
    } else if cs.position == Static {
      layout_static_absolute(cb, c, ox + c.left, oy + c.top)
    } else {
      layout_static_absolute(c, c, 0.0, 0.0)
    }
  }
}

///|
fn place_absolute(cb : Node, parent : Node, c : Node, ox : Double, oy : Double) -> Unit {
  let cbb = box_of(cb.style, undef, undef)
  let pb = box_of(parent.style, undef, undef)
  let ps = parent.style
  let cs = c.style
  // the containing block: cb's padding box
  let cw = cb.width - cbb.bor_l - cbb.bor_r
  let ch = cb.height - cbb.bor_t - cbb.bor_b
  let b = box_of(cs, cw, ch)
  let l = resolve(cs.inset.left, cw)
  let r = resolve(cs.inset.right, cw)
  let t = resolve(cs.inset.top, ch)
  let bt = resolve(cs.inset.bottom, ch)
  let mut w = b.w
  let mut h = b.h
  if !known(w) && known(l) && known(r) {
    w = fmax(cw - l - r - b.mar_l - b.mar_r, 0.0)
  }
  if !known(h) && known(t) && known(bt) {
    h = fmax(ch - t - bt - b.mar_t - b.mar_b, 0.0)
  }
  if known(w) {
    w = clamp_size(w, b.min_w, b.max_w)
  }
  if known(h) {
    h = clamp_size(h, b.min_h, b.max_h)
  }
  let (fw, fh) = size_node(
    c,
    w,
    h,
    if known(w) { w } else { cw },
    if known(h) { h } else { ch },
    cw,
    ch,
    false,
  )
  let (rw, rh) = size_node(c, fw, fh, fw, fh, cw, ch, true)
  c.width = rw
  c.height = rh
  // static position: where it would sit in its parent's content box
  let row = is_row(ps.direction)
  let inner_w = parent.width - pb.pbw()
  let inner_h = parent.height - pb.pbh()
  let free_w = inner_w - rw - b.mar_l - b.mar_r
  let free_h = inner_h - rh - b.mar_t - b.mar_b
  let static_x = pb.bor_l +
    pb.pad_l +
    b.mar_l +
    (if row {
      static_offset(ps.justify, free_w, is_reverse(ps.direction))
    } else {
      static_offset(item_align(ps, cs), free_w, ps.wrap == WrapReverse)
    })
  let static_y = pb.bor_t +
    pb.pad_t +
    b.mar_t +
    (if row {
      static_offset(item_align(ps, cs), free_h, ps.wrap == WrapReverse)
    } else {
      static_offset(ps.justify, free_h, is_reverse(ps.direction))
    })
  c.left = if known(l) {
    cbb.bor_l + l + b.mar_l - ox
  } else if known(r) {
    cb.width - cbb.bor_r - r - rw - b.mar_r - ox
  } else {
    static_x
  }
  c.top = if known(t) {
    cbb.bor_t + t + b.mar_t - oy
  } else if known(bt) {
    cb.height - cbb.bor_b - bt - rh - b.mar_b - oy
  } else {
    static_y
  }
}

///|
fn static_offset(a : Align, free : Double, reverse : Bool) -> Double {
  let o = match a {
    FlexEnd => free
    Center | SpaceAround | SpaceEvenly => free / 2.0
    _ => 0.0
  }
  if reverse {
    free - o
  } else {
    o
  }
}

///|
/// Yoga's rounding: positions and sizes snap to whole pixels by their
/// absolute edges, so neighbours never overlap or leave gaps.
fn round_layout(n : Node, abs_x : Double, abs_y : Double) -> Unit {
  let x = abs_x + n.left
  let y = abs_y + n.top
  let l = n.left.round()
  let t = n.top.round()
  let w = (x + n.width).round() - x.round()
  let h = (y + n.height).round() - y.round()
  for c in n.children {
    round_layout(c, x, y)
  }
  n.left = l
  n.top = t
  n.width = w
  n.height = h
}

///|
/// The distance from a node's top to its first baseline: that of its first
/// child on the first line (preferring one aligned by baseline), or its
/// bottom when it has none (Yoga).
fn node_baseline(n : Node) -> Double {
  let mut pick : Node? = None
  for c in n.children {
    if c.line > 0 {
      break
    }
    if c.style.position == Absolute || c.style.display == DisplayNone {
      continue
    }
    let al = item_align(n.style, c.style)
    if al == Baseline {
      pick = Some(c)
      break
    }
    if pick is None {
      pick = Some(c)
    }
  }
  match pick {
    Some(c) => node_baseline(c) + c.top
    None => n.height
  }
}
