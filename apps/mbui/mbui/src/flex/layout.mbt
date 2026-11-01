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
/// `p` percent of a reference length (NaN when it can't be resolved).
fn pct(p : Double, base : Double) -> Double {
  if known(base) {
    base * p / 100.0
  } else {
    undef
  }
}

///|
/// `p` percent of a reference length as an edge: 0 when unresolved.
fn edge_pct(p : Double, base : Double) -> Double {
  let v = pct(p, base)
  if known(v) {
    v
  } else {
    0.0
  }
}

///|
/// A length of a style (its kind and number: Style's `<name>_k` and
/// `<name>_v`) against a reference length (NaN when it can't be resolved).
fn resolve_of(k : Int, v : Double, base : Double) -> Double {
  if k == LEN_PT {
    v
  } else if k == LEN_PCT {
    pct(v, base)
  } else if k == LEN_WITHIN {
    if known(base) && base < v {
      base
    } else {
      v
    }
  } else {
    undef
  }
}

///|
/// An edge length (margin, padding, border): auto and unresolved are 0.
fn edge_of(k : Int, v : Double, base : Double) -> Double {
  if k == LEN_PT {
    if known(v) {
      v
    } else {
      0.0
    }
  } else if k == LEN_PCT {
    edge_pct(v, base)
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
struct Box {
  mut pad_l : Double
  mut pad_t : Double
  mut pad_r : Double
  mut pad_b : Double
  mut bor_l : Double
  mut bor_t : Double
  mut bor_r : Double
  mut bor_b : Double
  mut mar_l : Double
  mut mar_t : Double
  mut mar_r : Double
  mut mar_b : Double
  // size from style, border-box, NaN when auto
  mut w : Double
  mut h : Double
  mut min_w : Double
  mut min_h : Double
  mut max_w : Double
  mut max_h : Double
  // whether any of these is a percentage of the containing block's width,
  // or of its height: without one, the box (and so the node's size) is the
  // same in any containing block
  mut of_cb_w : Bool
  mut of_cb_h : Bool
}

///|
/// With `into`, fills that box in instead of making one.
fn box_of(
  s : Style,
  cb_w : Double,
  cb_h : Double,
  into? : Box? = None,
) -> Box {
  ignore(cb_h)
  let pad_l = edge_of(s.padding_left_k, s.padding_left_v, cb_w)
  let pad_r = edge_of(s.padding_right_k, s.padding_right_v, cb_w)
  let pad_t = edge_of(s.padding_top_k, s.padding_top_v, cb_w)
  let pad_b = edge_of(s.padding_bottom_k, s.padding_bottom_v, cb_w)
  let bor_l = edge_of(s.border_left_k, s.border_left_v, cb_w)
  let bor_r = edge_of(s.border_right_k, s.border_right_v, cb_w)
  let bor_t = edge_of(s.border_top_k, s.border_top_v, cb_w)
  let bor_b = edge_of(s.border_bottom_k, s.border_bottom_v, cb_w)
  let pbw = pad_l + pad_r + bor_l + bor_r
  let pbh = pad_t + pad_b + bor_t + bor_b
  // content-box sizes grow by the padding and border (NaN stays NaN)
  let content_box = s.box_sizing == ContentBox
  let adj_w = if content_box { pbw } else { 0.0 }
  let adj_h = if content_box { pbh } else { 0.0 }
  let mut min_w = resolve_of(s.min_width_k, s.min_width_v, cb_w) + adj_w
  let mut min_h = resolve_of(s.min_height_k, s.min_height_v, cb_h) + adj_h
  // a box is never smaller than its padding and border
  min_w = if known(min_w) { fmax(min_w, pbw) } else { pbw }
  min_h = if known(min_h) { fmax(min_h, pbh) } else { pbh }
  let mar_l = edge_of(s.margin_left_k, s.margin_left_v, cb_w)
  let mar_t = edge_of(s.margin_top_k, s.margin_top_v, cb_w)
  let mar_r = edge_of(s.margin_right_k, s.margin_right_v, cb_w)
  let mar_b = edge_of(s.margin_bottom_k, s.margin_bottom_v, cb_w)
  let w = resolve_of(s.width_k, s.width_v, cb_w) + adj_w
  let h = resolve_of(s.height_k, s.height_v, cb_h) + adj_h
  let max_w = resolve_of(s.max_width_k, s.max_width_v, cb_w) + adj_w
  let max_h = resolve_of(s.max_height_k, s.max_height_v, cb_h) + adj_h
  let of_cb_w = s.padding_left_k == LEN_PCT ||
    s.padding_right_k == LEN_PCT ||
    s.padding_top_k == LEN_PCT ||
    s.padding_bottom_k == LEN_PCT ||
    s.border_left_k == LEN_PCT ||
    s.border_right_k == LEN_PCT ||
    s.border_top_k == LEN_PCT ||
    s.border_bottom_k == LEN_PCT ||
    s.margin_left_k == LEN_PCT ||
    s.margin_right_k == LEN_PCT ||
    s.margin_top_k == LEN_PCT ||
    s.margin_bottom_k == LEN_PCT ||
    s.width_k >= LEN_PCT ||
    s.min_width_k >= LEN_PCT ||
    s.max_width_k >= LEN_PCT
  let of_cb_h = s.height_k >= LEN_PCT ||
    s.min_height_k >= LEN_PCT ||
    s.max_height_k >= LEN_PCT
  match into {
    Some(o) => {
      o.pad_l = pad_l
      o.pad_t = pad_t
      o.pad_r = pad_r
      o.pad_b = pad_b
      o.bor_l = bor_l
      o.bor_t = bor_t
      o.bor_r = bor_r
      o.bor_b = bor_b
      o.mar_l = mar_l
      o.mar_t = mar_t
      o.mar_r = mar_r
      o.mar_b = mar_b
      o.w = w
      o.h = h
      o.min_w = min_w
      o.min_h = min_h
      o.max_w = max_w
      o.max_h = max_h
      o.of_cb_w = of_cb_w
      o.of_cb_h = of_cb_h
      o
    }
    None => {
      pad_l,
      pad_t,
      pad_r,
      pad_b,
      bor_l,
      bor_t,
      bor_r,
      bor_b,
      mar_l,
      mar_t,
      mar_r,
      mar_b,
      w,
      h,
      min_w,
      min_h,
      max_w,
      max_h,
      of_cb_w,
      of_cb_h,
    }
  }
}

///|
/// box_of for a node, kept on it while its style says the same (Style's
/// ver, which every setter of a length or the box sizing bumps) and so does
/// the containing block, as far as the box takes anything from it (of_cb_w,
/// of_cb_h): from one compute to the next too, reusing or not, as the box
/// is the style's and that alone. A node is sized several times (its basis,
/// its cross size, for real), each time against the same containing block.
///
/// The box is the node's own, made once and filled in again when it no
/// longer holds: a node is sized against one containing block, its
/// parent's, so an item holding it sees no other.
fn box_for(node : Node, cb_w : Double, cb_h : Double) -> Box {
  touch(node)
  match node.box_memo {
    Some(b) if node.box_ver == node.style.ver &&
      (!b.of_cb_w || same(node.box_cbw, cb_w)) &&
      (!b.of_cb_h || same(node.box_cbh, cb_h)) => return b
    _ => ()
  }
  let b = box_of(node.style, cb_w, cb_h, into=node.box_memo)
  node.box_cbw = cb_w
  node.box_cbh = cb_h
  node.box_memo = Some(b)
  node.box_ver = node.style.ver
  b
}

///|
/// A node's first visit in a compute(): what it kept from before is
/// forgotten unless the compute reuses it and the node is not dirty.
/// (Written out where every item of a container is set up: layout_flex.)
fn touch(node : Node) -> Unit {
  if node.cache_gen != generation.val {
    node.cache_gen = generation.val
    if !reusing.val || node.dirty {
      node.cache_n = 0
      node.p_ok = false
      node.dirty = false
    }
  }
}

///|
/// The height size_node (size_uncached, layout_flex) found, beside the
/// width it returns: read at once, before sizing anything else.
let out_h : Ref[Double] = { val: 0.0 }

///|
/// The space between items distribute found, beside the lead it returns.
let out_b : Ref[Double] = { val: 0.0 }

///|
/// Whether the current compute() reuses what nodes kept from the last.
let reusing : Ref[Bool] = { val: false }

///|
/// Device pixels a point the current compute() places nodes on (its `grid`), 0: anywhere; the last one's, before.
let placing_grid : Ref[Double] = { val: 0.0 }

///|
/// `v` (a node's place from its parent) on the current compute()'s grid: the nearest whole pixel, half up (Compose's
/// roundToInt).
fn on_grid(v : Double) -> Double {
  let g = placing_grid.val
  if g > 0.0 {
    (v * g + 0.5).floor() / g
  } else {
    v
  }
}

///|
/// Whether a container laid out in the current compute() has an absolutely
/// positioned child: without one, layout_static_absolute has nothing to
/// place.
let absolute_seen : Ref[Bool] = { val: false }

///|
/// Whether `n`'s layout in this compute() is the one it had (its subtree
/// untouched). (A node is laid out at most once in a compute but for
/// baselines, which reuse does not take.)
fn kept(n : Node) -> Bool {
  n.skip_gen == generation.val
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
///
/// With `reuse` (and without `round`), what nodes found in the last
/// compute is kept: sizes a node was measured at, and its last layout,
/// which stands (with its whole subtree) when it is asked for the same
/// again. The caller marks `dirty` every node whose style, measure
/// function (or what it measures) or children changed, and every node
/// above one; a node moved under another parent dirties both parents.
/// Nothing may be aligned by baseline (finding one lays items out while
/// only measuring their container): reuse aborts on it.
///
/// With `grid` (device pixels a point), each node is placed on whole device
/// pixels from its parent, as Compose places a child (its alignment's and
/// arrangement's offsets rounded to whole pixels, half up): a tree whose
/// lengths are whole pixels comes out on them however far its root is moved
/// by whole pixels. What was kept from a compute on another grid is not.
pub fn compute(
  root : Node,
  width? : Double = undef,
  height? : Double = undef,
  round? : Bool = true,
  reuse? : Bool = false,
  grid? : Double = 0.0,
) -> Unit {
  generation.val = generation.val + 1
  reusing.val = reuse && !round && grid == placing_grid.val
  placing_grid.val = grid
  absolute_seen.val = false
  let b = box_of(root.style, width, height)
  let w = or_else(b.w, if root.style.position == Absolute { undef } else { width })
  let h = or_else(b.h, if root.style.position == Absolute { undef } else { height })
  // without a size, the root may grow up to its max size (Yoga)
  let aw = if known(w) { w } else if known(b.max_w) { b.max_w } else { width }
  let ah = if known(h) { h } else if known(b.max_h) { b.max_h } else { height }
  let fw = size_node(root, w, h, aw, ah, aw, ah, true)
  let fh = out_h.val
  root.width = fw
  root.height = fh
  let s = root.style
  let dx = if s.position == Relative || s.position == Absolute {
    let l = resolve_of(s.inset_left_k, s.inset_left_v, width)
    let r = resolve_of(s.inset_right_k, s.inset_right_v, width)
    if known(l) { l } else if known(r) { -r } else { 0.0 }
  } else {
    0.0
  }
  let dy = if s.position == Relative || s.position == Absolute {
    let t = resolve_of(s.inset_top_k, s.inset_top_v, height)
    let bt = resolve_of(s.inset_bottom_k, s.inset_bottom_v, height)
    if known(t) { t } else if known(bt) { -bt } else { 0.0 }
  } else {
    0.0
  }
  root.left = on_grid(b.mar_l + dx)
  root.top = on_grid(b.mar_t + dy)
  if absolute_seen.val && !(kept(root) && s.position != Static) {
    layout_static_absolute(root, root, 0.0, 0.0)
  }
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
    let l = resolve_of(s.inset_left_k, s.inset_left_v, cb_w)
    if known(l) {
      return l
    }
    let r = resolve_of(s.inset_right_k, s.inset_right_v, cb_w)
    if known(r) {
      -r
    } else {
      0.0
    }
  } else {
    let t = resolve_of(s.inset_top_k, s.inset_top_v, cb_h)
    if known(t) {
      return t
    }
    let b = resolve_of(s.inset_bottom_k, s.inset_bottom_v, cb_h)
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
/// The border-box width of `node` (its height in out_h). `kw`/`kh`: sizes already decided by the
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
) -> Double {
  touch(node)
  if perform {
    // laid out before as now asked, nothing under it changed since: it
    // stands as it is. (A layout is always asked with the space available
    // the size it is to have, or for a root, its containing block: those
    // two say it all.)
    if reusing.val &&
      node.p_ok &&
      same(node.p_kw, kw) &&
      same(node.p_kh, kh) &&
      same(node.p_cbw, cb_w) &&
      same(node.p_cbh, cb_h) {
      node.skip_gen = generation.val
      counters[1] = counters[1] + 1
      out_h.val = node.p_h
      return node.p_w
    }
  } else {
    let c = node.cache
    let n = node.cache_n
    // a size found in another containing block holds in this one when the
    // node's box takes nothing from it (what is inside it is laid out in
    // the node's own content box), and the node was asked for the same
    // known sizes: not when it is now asked for the size it came out at,
    // which its content (percentages of it) may not have had then
    let mut any_w = false
    let mut any_h = false
    if n > 0 {
      let bx = box_for(node, cb_w, cb_h)
      any_w = !bx.of_cb_w
      any_h = !bx.of_cb_h
    }
    let mut k = 0
    while k < n {
      let same_cb = same(c[k + 4], cb_w) && same(c[k + 5], cb_h)
      if (
          same_cb ||
          (
            (any_w || same(c[k + 4], cb_w)) &&
            (any_h || same(c[k + 5], cb_h)) &&
            same(c[k], kw) &&
            same(c[k + 1], kh)
          )
        ) &&
        reusable(kw, aw, c[k], c[k + 2], c[k + 6]) &&
        reusable(kh, ah, c[k + 1], c[k + 3], c[k + 7]) {
        counters[1] = counters[1] + 1
        out_h.val = c[k + 7]
        return c[k + 6]
      }
      k = k + 8
    }
  }
  counters[0] = counters[0] + 1
  let w = size_uncached(node, kw, kh, aw, ah, cb_w, cb_h, perform)
  let h = out_h.val
  if perform {
    node.p_ok = true
    node.p_kw = kw
    node.p_kh = kh
    node.p_cbw = cb_w
    node.p_cbh = cb_h
    node.p_w = w
    node.p_h = h
    node.laid_gen = generation.val
    // (the size it was laid out at is looked for again only by a compute
    // that reuses: in one that does not, nothing measures it after its
    // layout, and the next forgets its sizes first)
    if !reusing.val {
      out_h.val = h
      return w
    }
  }
  let mut n = node.cache_n
  if n >= 8 * 16 {
    n = 0
  }
  let mut c = node.cache
  if n + 8 > c.length() {
    let more = FixedArray::make(if n == 0 { 16 } else { n * 2 }, 0.0)
    for i in 0..<n {
      more[i] = c[i]
    }
    node.cache = more
    c = more
  }
  c[n] = kw
  c[n + 1] = kh
  c[n + 2] = aw
  c[n + 3] = ah
  c[n + 4] = cb_w
  c[n + 5] = cb_h
  c[n + 6] = w
  c[n + 7] = h
  node.cache_n = n + 8
  out_h.val = h
  w
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
) -> Double {
  let s = node.style
  let b = box_for(node, cb_w, cb_h)
  // (its max-sizes only what it asks: given a size, it takes it; Style's stretch_past_max)
  let b = if s.stretch_past_max && ((known(kw) && known(b.max_w)) || (known(kh) && known(b.max_h))) {
    { ..b, max_w: if known(kw) { undef } else { b.max_w }, max_h: if known(kh) { undef } else { b.max_h } }
  } else {
    b
  }
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
    w = clamp_size(w, soft_floor(node.style, b.min_w), b.max_w)
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
          out_h.val = h
          return w
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
        out_h.val = fh
        return fw
      }
    None =>
      // a box with nothing in it: what layout_flex comes to with no items
      // (its padding and border, its own size where it has one), without
      // setting up a line for nothing
      if node.children.length() == 0 {
        out_h.val = if known(h) {
          fmax(h - pbh, 0.0) + pbh
        } else {
          clamp_size(pbh, b.min_h, b.max_h) - pbh + pbh
        }
        return if known(w) {
          fmax(w - pbw, 0.0) + pbw
        } else {
          clamp_size(pbw, b.min_w, b.max_w) - pbw + pbw
        }
      }
  }
  // as tall as its share of what it holds comes to at its width, what it holds laid out whole in that (Style's
  // content_share): what it holds sized first, then laid out in the height that comes to
  if known(s.content_share) && !known(h) {
    let fw = layout_flex(node, b, w, h, aw, ah, false)
    let natural = out_h.val
    let share = fmax(fmin(s.content_share, 1.0), 0.0)
    let sized = clamp_size(pbh + (natural - pbh) * share, b.min_h, b.max_h)
    return layout_flex(node, b, if known(w) { w } else { fw }, sized, aw, ah, perform)
  }
  layout_flex(node, b, w, h, aw, ah, perform)
}

///|
/// A flex item's numbers while its container is laid out, ITEM of them per
/// item side by side in its pool's `f` (item k's at k * ITEM): read pass
/// after pass over the items, they are kept together, not as an object
/// each, which its node and box would also be reached through.
const ITEM : Int = 26

///|
const BASIS : Int = 0

///|
/// the hypothetical main size (the basis, clamped)
const HYP : Int = 1

///|
const MAIN : Int = 2

///|
const CROSS : Int = 3

///|
const TARGET : Int = 4

///|
const MAIN_POS : Int = 5

///|
const CROSS_POS : Int = 6

///|
const MIN_MAIN : Int = 7

///|
/// the least it comes to as a last resort along a row (Style's soft_min; NaN: none)
const SOFT_MIN : Int = 25

///|
const MAX_MAIN : Int = 8

///|
const MIN_CROSS : Int = 9

///|
const MAX_CROSS : Int = 10

///|
const MARGIN_MAIN : Int = 11

///|
const MARGIN_CROSS : Int = 12

///|
const ASCENT : Int = 13

///|
/// how far resolve_flexible's clamping moved it this round
const CLAMPED : Int = 14

///|
/// resolve_flexible's: its flex factor (grow or shrink, as the line goes),
/// and the least it may come to
const FACTOR : Int = 15

///|
const LO_MAIN : Int = 16

///|
/// its cross size from its style (border-box, NaN when auto)
const CROSS_STYLE : Int = 17

///|
/// its style's flex-grow and flex-shrink, and its padding and border along
/// the main axis
const GROW : Int = 18

///|
const SHRINK : Int = 19

///|
const PB_MAIN : Int = 20

///|
/// Its margins at the start and the end of the main axis, and of the cross
/// axis.
const MAR_MAIN_START : Int = 21

///|
const MAR_MAIN_END : Int = 22

///|
const MAR_CROSS_START : Int = 23

///|
const MAR_CROSS_END : Int = 24

///|
/// An item's flags, in its pool's `flags`: its auto margins,
const AUTO_L : Int = 1

///|
const AUTO_T : Int = 2

///|
const AUTO_R : Int = 4

///|
const AUTO_B : Int = 8

///|
/// whether resolve_flexible has frozen it,
const FROZEN : Int = 16

///|
/// whether it is stretched across its line,
const STRETCH : Int = 32

///|
/// and whether its insets move it (inset_offset), relatively positioned.
const INSET : Int = 64

///|
/// and whether it is a row that leaves out what it has not the room for (Style's `fits`), as wide as what it keeps of
/// what it holds (its basis its content's): measured again in what the rest of its line leaves it, where that line
/// has not the room for all of them (layout_flex).
const FITS : Int = 128

///|
/// and whether its line stretches it past its cross max-size (Style's `stretch_past_max`).
const PAST_MAX : Int = 256

///|
priv struct Line {
  mut start : Int
  mut end : Int
  // its items' main sizes, margins and gaps
  mut used : Double
  mut cross : Double
  mut pos : Double
  mut ascent : Double
}

///|
/// Per depth of containers being laid out (each lays out its children,
/// one level down, before it is done): its items (which of the container's
/// children each is, its alignment, numbers, flags and line), and the lines
/// in use and made so far to take them from. (It holds no node or box: one
/// put in an array and taken out again is counted in and out each time.)
priv struct Pool {
  // the items in use (count of them: the rest is what is left from before)
  mut count : Int
  // where in flow_children(container) each is
  mut at : Array[Int]
  mut aligns : Array[Align]
  mut f : Array[Double]
  mut flags : Array[Int]
  mut line_of : Array[Int]
  lines : Array[Line]
  line_store : Array[Line]
}

///|
let pools : Array[Pool] = []

///|
let depth : Ref[Int] = { val: 0 }

///|
/// The next item of the pool, child `at` of flow_children(container), with
/// its alignment: its index.
/// (Its numbers are not cleared: each is set before it is read.)
fn Pool::add(self : Pool, at : Int, al : Align) -> Int {
  let k = self.count
  if k >= self.flags.length() {
    self.grow()
  }
  self.at.unsafe_set(k, at)
  self.aligns.unsafe_set(k, al)
  self.count = k + 1
  k
}

///|
/// Room for twice as many items as the pool has: what is read and written of
/// them is past the checks of the arrays' bounds, unsafe_get and unsafe_set,
/// below the count.
fn Pool::grow(self : Pool) -> Unit {
  let k = self.count
  let n = if k < 8 { 16 } else { k * 2 }
  let f = Array::make(n * ITEM, 0.0)
  for i in 0..<(k * ITEM) {
    f[i] = self.f[i]
  }
  let flags = Array::make(n, 0)
  let line_of = Array::make(n, 0)
  let at = Array::make(n, 0)
  let aligns : Array[Align] = Array::make(n, Auto)
  for i in 0..<k {
    flags[i] = self.flags[i]
    line_of[i] = self.line_of[i]
    at[i] = self.at[i]
    aligns[i] = self.aligns[i]
  }
  self.f = f
  self.flags = flags
  self.line_of = line_of
  self.at = at
  self.aligns = aligns
}

///|
/// The box of a node that has none yet.
let no_box : Box = box_of(Style::new(), undef, undef)

///|
/// The box set up for an item of the container being laid out.
fn item_box(n : Node) -> Box {
  match n.box_memo {
    Some(b) => b
    None => no_box
  }
}

///|
fn Pool::line(self : Pool, start : Int, end : Int) -> Unit {
  let k = self.lines.length()
  let ln = if k < self.line_store.length() {
    self.line_store[k]
  } else {
    let ln = { start: 0, end: 0, used: 0.0, cross: 0.0, pos: 0.0, ascent: 0.0 }
    self.line_store.push(ln)
    ln
  }
  ln.start = start
  ln.end = end
  ln.used = 0.0
  ln.cross = 0.0
  ln.pos = 0.0
  ln.ascent = 0.0
  self.lines.push(ln)
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
) -> Double {
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
  let gap_main = if row {
    edge_of(s.gap_col_k, s.gap_col_v, inner_main)
  } else {
    edge_of(s.gap_row_k, s.gap_row_v, inner_main)
  }
  let gap_cross = if row {
    edge_of(s.gap_row_k, s.gap_row_v, inner_cross)
  } else {
    edge_of(s.gap_col_k, s.gap_col_v, inner_cross)
  }
  // percentages of children resolve against this content box
  let cb_w = inner_w
  let cb_h = inner_h
  // flex items, from the pool of this depth
  let d = depth.val
  depth.val = d + 1
  if d >= pools.length() {
    pools.push({
      count: 0,
      at: [],
      aligns: [],
      f: [],
      flags: [],
      line_of: [],
      lines: [],
      line_store: [],
    })
  }
  let pool = pools[d]
  pool.count = 0
  pool.lines.clear()
  let flow = flow_children(node)
  // a row that leaves out what it has not the room for (Style's `drop`), as it is in this room
  let all = flow
  let flow = if s.one_of && row {
    first_fit(flow, if known(avail_main) { avail_main } else { 1.0e9 }, cb_w, cb_h)
  } else if s.fits && row && known(avail_main) {
    fit_flow(flow, avail_main, gap_main, cb_w, cb_h)
  } else {
    flow
  }
  // laid out at the height it was measured to come to before that height
  // was known (in this compute, at this width), nothing in it depending on
  // it: its items where that measure put them
  let pre = node.pre
  let fast = perform &&
    node.pre_gen == generation.val &&
    known(w0) &&
    w0 == pre.unsafe_get(0) &&
    known(h0) &&
    h0 == pre.unsafe_get(2)
  let mut fh = 0.0
  let fw = if fast {
    for j, c in flow {
      let cs = c.style
      if cs.position == Absolute {
        continue
      }
      // (pool.add written out: called from here too, it is not inlined
      // where every container's items are set up)
      let k = pool.count
      if k >= pool.flags.length() {
        pool.grow()
      }
      pool.at.unsafe_set(k, j)
      pool.aligns.unsafe_set(k, Auto)
      pool.count = k + 1
      let i = k * ITEM
      let p = 3 + k * 4
      let f = pool.f
      f.unsafe_set(i + MAIN, pre.unsafe_get(p))
      f.unsafe_set(i + CROSS, pre.unsafe_get(p + 1))
      f.unsafe_set(i + MAIN_POS, pre.unsafe_get(p + 2))
      f.unsafe_set(i + CROSS_POS, pre.unsafe_get(p + 3))
      pool.flags.unsafe_set(
        k,
        if cs.position == Relative &&
          !(cs.inset_left_k == LEN_AUTO &&
          cs.inset_right_k == LEN_AUTO &&
          cs.inset_top_k == LEN_AUTO &&
          cs.inset_bottom_k == LEN_AUTO) {
          INSET
        } else {
          0
        },
      )
    }
    fh = pre.unsafe_get(2)
    pre.unsafe_get(1)
  } else {
    // what some item has, for the passes below that only it needs
    let mut any_auto = false
    let mut any_stretch = false
    // (and whether an item's cross size is not its style's, or its box takes
    // anything from this one's height: then it may come out otherwise once
    // that height is known)
    let mut cross_by_height = false
    let mut any_baseline = false
    let mut any_fits = false
    for j, c in flow {
      let cs = c.style
      if cs.position == Absolute {
        absolute_seen.val = true
        continue
      }
      // box_for(c, cb_w, cb_h), its calls written out (this runs for every
      // item of every container)
      if c.cache_gen != generation.val {
        c.cache_gen = generation.val
        if !reusing.val || c.dirty {
          c.cache_n = 0
          c.p_ok = false
          c.dirty = false
        }
      }
      let cb = match c.box_memo {
        Some(memo) if c.box_ver == cs.ver &&
          (!memo.of_cb_w || same(c.box_cbw, cb_w)) &&
          (!memo.of_cb_h || same(c.box_cbh, cb_h)) =>
          memo
        _ => {
          let nb = box_of(cs, cb_w, cb_h, into=c.box_memo)
          c.box_cbw = cb_w
          c.box_cbh = cb_h
          c.box_memo = Some(nb)
          c.box_ver = cs.ver
          nb
        }
      }
      let al = item_align(s, cs)
      let margin_main = if row { cb.mar_l + cb.mar_r } else { cb.mar_t + cb.mar_b }
      let margin_cross = if row { cb.mar_t + cb.mar_b } else { cb.mar_l + cb.mar_r }
      let cross_style = if row { cb.h } else { cb.w }
      let auto_cross_margin = if row {
        cs.margin_top_k == LEN_AUTO || cs.margin_bottom_k == LEN_AUTO
      } else {
        cs.margin_left_k == LEN_AUTO || cs.margin_right_k == LEN_AUTO
      }
      let k = pool.add(j, al)
      let f = pool.f
      let i = k * ITEM
      let stretch = al == Stretch && !known(cross_style) && !auto_cross_margin
      let mut fl = 0
      if cs.margin_left_k == LEN_AUTO {
        fl = fl | AUTO_L
      }
      if cs.margin_top_k == LEN_AUTO {
        fl = fl | AUTO_T
      }
      if cs.margin_right_k == LEN_AUTO {
        fl = fl | AUTO_R
      }
      if cs.margin_bottom_k == LEN_AUTO {
        fl = fl | AUTO_B
      }
      if fl != 0 {
        any_auto = true
      }
      if stretch {
        fl = fl | STRETCH
        any_stretch = true
        if cs.stretch_past_max {
          fl = fl | PAST_MAX
        }
      }
      if cs.position == Relative &&
        !(cs.inset_left_k == LEN_AUTO &&
        cs.inset_right_k == LEN_AUTO &&
        cs.inset_top_k == LEN_AUTO &&
        cs.inset_bottom_k == LEN_AUTO) {
        fl = fl | INSET
      }
      pool.flags.unsafe_set(k, fl)
      pool.line_of.unsafe_set(k, 0)
      if al == Baseline {
        any_baseline = true
      }
      if !known(cross_style) || cb.of_cb_h {
        cross_by_height = true
      }
      let min_main = if row { cb.min_w } else { cb.min_h }
      // (one never narrower than what it holds: at least as wide as that comes to, measured here, as a basis of auto
      // would be: what changes in it makes it so again, as anything it holds changing lays its line out again)
      let min_main = if row && cs.min_held {
        let held = size_node(c, undef, undef, undef, undef, cb_w, cb_h, false)
        if known(min_main) {
          fmax(min_main, held)
        } else {
          held
        }
      } else {
        min_main
      }
      let max_main = if row { cb.max_w } else { cb.max_h }
      f.unsafe_set(i + MIN_MAIN, min_main)
      f.unsafe_set(i + SOFT_MIN, if row && !(s.fits && cs.drop != 0) { cs.soft_min } else { undef })
      f.unsafe_set(i + MAX_MAIN, max_main)
      f.unsafe_set(i + MIN_CROSS, if row { cb.min_h } else { cb.min_w })
      f.unsafe_set(i + MAX_CROSS, if row { cb.max_h } else { cb.max_w })
      f.unsafe_set(i + MARGIN_MAIN, margin_main)
      f.unsafe_set(i + MARGIN_CROSS, margin_cross)
      f.unsafe_set(i + MAR_MAIN_START, if row { cb.mar_l } else { cb.mar_t })
      f.unsafe_set(i + MAR_MAIN_END, if row { cb.mar_r } else { cb.mar_b })
      f.unsafe_set(i + MAR_CROSS_START, if row { cb.mar_t } else { cb.mar_l })
      f.unsafe_set(i + MAR_CROSS_END, if row { cb.mar_b } else { cb.mar_r })
      f.unsafe_set(i + CROSS_STYLE, cross_style)
      f.unsafe_set(i + ASCENT, 0.0)
      f.unsafe_set(i + GROW, cs.grow)
      // (what a row may leave out is kept whole while it is there)
      f.unsafe_set(i + SHRINK, if s.fits && cs.drop != 0 { 0.0 } else { cs.shrink })
      // flex base size
      let basis_style = resolve_of(cs.basis_k, cs.basis_v, inner_main)
      let main_style = if row { cb.w } else { cb.h }
      // (a container sized by what it holds counts a growing item at the more of its flex basis and what it holds, as
      // Chrome sizes one: flex: 1 1 0 words in a fit-content card are as wide as they are, not nothing; flex: 1 1 200
      // with nothing in it still 200)
      let grows_in_unknown = cs.grow > 0.0 && !known(inner_main)
      let mut declared = undef
      let mut basis = if known(basis_style) && cs.basis_k != LEN_AUTO {
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
      if grows_in_unknown && known(basis_style) && cs.basis_k != LEN_AUTO {
        declared = basis
        basis = undef
      }
      if !known(basis) {
        // size from content: cross known if fixed or stretched in a known line
        let mut kc = cross_style
        if !known(kc) && stretch && known(inner_cross) && s.wrap == NoWrap {
          kc = fmax(inner_cross - margin_cross, 0.0)
        }
        let cw = if row {
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
        let ch = out_h.val
        basis = if row { cw } else { ch }
        if known(declared) {
          basis = fmax(basis, declared)
        } else if row && cs.fits && is_row(cs.direction) {
          pool.flags.unsafe_set(k, pool.flags.unsafe_get(k) | FITS)
          any_fits = true
        }
      }
      let pb_main = if row { cb.pbw() } else { cb.pbh() }
      f.unsafe_set(i + PB_MAIN, pb_main)
      basis = fmax(basis, pb_main)
      f.unsafe_set(i + BASIS, basis)
      f.unsafe_set(i + HYP, clamp_size(basis, min_main, max_main))
    }
    // (no more items: their numbers stay where they are)
    let f = pool.f
    let flags = pool.flags
    let count = pool.count
    let at = pool.at
    let aligns = pool.aligns
    // lines
    let lines = pool.lines
    let wrap = s.wrap != NoWrap
    let line_limit = if known(inner_main) { inner_main } else { avail_main }
    let mut start = 0
    let mut sum = 0.0
    // (without wrapping, all are on one line)
    if wrap {
      for k in 0..<count {
        let outer = f.unsafe_get(k * ITEM + HYP) + f.unsafe_get(k * ITEM + MARGIN_MAIN)
        if k > start &&
          known(line_limit) &&
          sum + gap_main + outer > line_limit + 0.0001 {
          pool.line(start, k)
          start = k
          sum = outer
        } else {
          sum = if k == start { outer } else { sum + gap_main + outer }
        }
      }
    }
    if count > 0 || lines.length() == 0 {
      pool.line(start, count)
    }
    // resolve flexible lengths, line by line
    let mut max_line_main = 0.0
    for ln in lines {
      let n = ln.end - ln.start
      let gaps = if n > 1 { gap_main * (n - 1).to_double() } else { 0.0 }
      let mut sum_hyp = gaps
      // (and without them, for resolve_flexible)
      let mut items_hyp = 0.0
      for k in ln.start..<ln.end {
        let hyp = f.unsafe_get(k * ITEM + HYP)
        let margin = f.unsafe_get(k * ITEM + MARGIN_MAIN)
        sum_hyp = sum_hyp + hyp + margin
        items_hyp = items_hyp + hyp + margin
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
      // rows in it that leave out what they have not the room for, each as wide as what it keeps, where the line has
      // not the room for all it holds: what they leave out chosen across the line (fit_line), not measured each in all
      // of the line's room and squeezed with the rest (then it would leave out more in the room it is squeezed to and
      // keep what that frees empty, what is beside it squeezed for nothing)
      if any_fits && !wrap && known(space) && sum_hyp > space + 0.01 {
        let was = items_hyp
        items_hyp = fit_line(pool, flow, ln.start, ln.end, space - gaps, cb_w, cb_h)
        sum_hyp = sum_hyp + items_hyp - was
      }
      if known(space) {
        resolve_flexible(pool, ln.start, ln.end, items_hyp, space - gaps)
        if row && !wrap {
          last_resort(pool, ln.start, ln.end, space - gaps)
        }
      } else {
        for k in ln.start..<ln.end {
          f.unsafe_set(k * ITEM + MAIN, f.unsafe_get(k * ITEM + HYP))
        }
      }
      let mut used = gaps
      for k in ln.start..<ln.end {
        used = used + f.unsafe_get(k * ITEM + MAIN) + f.unsafe_get(k * ITEM + MARGIN_MAIN)
      }
      ln.used = used
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
    for k in 0..<count {
      let i = k * ITEM
      let cross_style = f.unsafe_get(i + CROSS_STYLE)
      if known(cross_style) {
        f.unsafe_set(i + CROSS, clamp_size(cross_style, f.unsafe_get(i + MIN_CROSS), f.unsafe_get(i + MAX_CROSS)))
      } else {
        // stretched items in a single line of known cross size take it
        let kc = if (flags.unsafe_get(k) & STRETCH) != 0 && known(inner_cross) && !wrap {
          fmax(inner_cross - f.unsafe_get(i + MARGIN_CROSS), 0.0)
        } else {
          undef
        }
        if known(kc) {
          // what sizing it would return, without laying out its subtree
          let hi = if (flags.unsafe_get(k) & PAST_MAX) != 0 { undef } else { f.unsafe_get(i + MAX_CROSS) }
          f.unsafe_set(i + CROSS, clamp_size(kc, f.unsafe_get(i + MIN_CROSS), hi))
          continue
        }
        let ac = if known(avail_cross) {
          avail_cross - f.unsafe_get(i + MARGIN_CROSS)
        } else {
          undef
        }
        let main = f.unsafe_get(i + MAIN)
        let cw = if row {
          size_node(flow.unsafe_get(at.unsafe_get(k)), main, kc, main, ac, cb_w, cb_h, false)
        } else {
          size_node(flow.unsafe_get(at.unsafe_get(k)), kc, main, ac, main, cb_w, cb_h, false)
        }
        let ch = out_h.val
        f.unsafe_set(
          i + CROSS,
          clamp_size(
            if row { ch } else { cw },
            f.unsafe_get(i + MIN_CROSS),
            f.unsafe_get(i + MAX_CROSS),
          ),
        )
      }
    }
    // line cross sizes; items aligned by baseline share the line's baseline
    // (one line of a known cross size is that size: below)
    let one_known_line = !wrap && known(inner_cross) && lines.length() == 1
    for li, ln in lines {
      if one_known_line && !(any_baseline && row) {
        break
      }
      let mut c = 0.0
      let mut asc = 0.0
      let mut desc = 0.0
      for k in ln.start..<ln.end {
        let i = k * ITEM
        pool.line_of.unsafe_set(k, li)
        if aligns.unsafe_get(k) == Baseline && row {
          // its baseline is found by laying it out, while this one may be
          // only measured: a layout kept above it could hold that one
          if reusing.val {
            abort("flex: compute(reuse=true) with an item aligned by baseline")
          }
          let iw = f.unsafe_get(i + MAIN)
          let ih = f.unsafe_get(i + CROSS)
          let n = flow.unsafe_get(at.unsafe_get(k))
          let rw = size_node(n, iw, ih, iw, ih, cb_w, cb_h, true)
          let rh = out_h.val
          n.width = rw
          n.height = rh
          let ascent = node_baseline(n) + f.unsafe_get(i + MAR_CROSS_START)
          f.unsafe_set(i + ASCENT, ascent)
          asc = fmax(asc, ascent)
          desc = fmax(desc, f.unsafe_get(i + CROSS) + f.unsafe_get(i + MARGIN_CROSS) - ascent)
        } else {
          c = fmax(c, f.unsafe_get(i + CROSS) + f.unsafe_get(i + MARGIN_CROSS))
        }
      }
      ln.ascent = asc
      ln.cross = fmax(c, asc + desc)
    }
    if one_known_line {
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
      if !any_stretch {
        break
      }
      for k in ln.start..<ln.end {
        if (flags.unsafe_get(k) & STRETCH) != 0 {
          let i = k * ITEM
          // (past its most where it says so: its most bounded what it asked of the line only)
          let hi = if (flags.unsafe_get(k) & PAST_MAX) != 0 { undef } else { f.unsafe_get(i + MAX_CROSS) }
          f.unsafe_set(
            i + CROSS,
            clamp_size(fmax(ln.cross - f.unsafe_get(i + MARGIN_CROSS), 0.0), f.unsafe_get(i + MIN_CROSS), hi),
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
    let lead = distribute(
      if wrap { s.align_content } else { FlexStart },
      free_cross,
      nl,
      true,
    )
    let between = out_b.val
    let mut cp = lead
    for ln in lines {
      ln.pos = cp
      cp = cp + ln.cross + gap_cross + between
    }
    // place items in each line
    let reverse = is_reverse(s.direction)
    let wrap_reverse = s.wrap == WrapReverse
    // the flags of an item's auto margins at the start and end of each axis
    let a_start_bit = if row { AUTO_L } else { AUTO_T }
    let a_end_bit = if row { AUTO_R } else { AUTO_B }
    let ca_start_bit = if row { AUTO_T } else { AUTO_L }
    let ca_end_bit = if row { AUTO_B } else { AUTO_R }
    for ln in lines {
      let n = ln.end - ln.start
      // (what its items take, found with their main sizes)
      let used = ln.used
      let mut auto_margins = 0
      for k in ln.start..<ln.end {
        if !any_auto {
          break
        }
        if (flags.unsafe_get(k) & a_start_bit) != 0 {
          auto_margins = auto_margins + 1
        }
        if (flags.unsafe_get(k) & a_end_bit) != 0 {
          auto_margins = auto_margins + 1
        }
      }
      let free = main_size - used
      let per_auto = if auto_margins > 0 && free > 0.0 {
        free / auto_margins.to_double()
      } else {
        0.0
      }
      let lead = if auto_margins > 0 {
        out_b.val = 0.0
        0.0
      } else {
        distribute(s.justify, free, n, false)
      }
      let between = out_b.val
      let mut p = lead
      for k in ln.start..<ln.end {
        let i = k * ITEM
        let fl = flags.unsafe_get(k)
        let m_start = f.unsafe_get(i + MAR_MAIN_START)
        let m_end = f.unsafe_get(i + MAR_MAIN_END)
        let ms = m_start + (if (fl & a_start_bit) != 0 { per_auto } else { 0.0 })
        let me = m_end + (if (fl & a_end_bit) != 0 { per_auto } else { 0.0 })
        let main = f.unsafe_get(i + MAIN)
        if reverse {
          f.unsafe_set(i + MAIN_POS, main_size - (p + ms) - main)
        } else {
          f.unsafe_set(i + MAIN_POS, p + ms)
        }
        p = p + ms + main + me + gap_main + between
        // cross axis within the line
        let c_start = f.unsafe_get(i + MAR_CROSS_START)
        let c_end = f.unsafe_get(i + MAR_CROSS_END)
        let ca_start = (fl & ca_start_bit) != 0
        let ca_end = (fl & ca_end_bit) != 0
        let cross = f.unsafe_get(i + CROSS)
        let free_c = ln.cross - cross - c_start - c_end
        let al = aligns.unsafe_get(k)
        let off = if ca_start && ca_end {
          fmax(free_c, 0.0) / 2.0
        } else if ca_start {
          fmax(free_c, 0.0)
        } else if ca_end {
          0.0
        } else {
          match al {
            FlexEnd => free_c
            Center => free_c / 2.0
            _ => 0.0
          }
        }
        let mut cross_pos = ln.pos + c_start + off
        if al == Baseline && row && !(ca_start || ca_end) {
          cross_pos = ln.pos + ln.ascent - f.unsafe_get(i + ASCENT) + c_start
        }
        if wrap_reverse {
          cross_pos = cross_size - cross_pos - cross
        }
        f.unsafe_set(i + CROSS_POS, cross_pos)
        // (for baselines only, which reuse does not take: measuring may
        // write them too)
        flow.unsafe_get(at.unsafe_get(k)).line = pool.line_of.unsafe_get(k)
      }
    }
    let fw = if row { main_size + pbw } else { cross_size + pbw }
    fh = if row { cross_size + pbh } else { main_size + pbh }
    if !perform &&
      row &&
      s.wrap == NoWrap &&
      known(w0) &&
      !known(h0) &&
      !cross_by_height &&
      !any_baseline &&
      !b.of_cb_w &&
      !b.of_cb_h &&
      fmax(fh - pbh, 0.0) == cross_size {
      // measured before its height was known, and nothing in it depends on
      // that height: laid out at the height it came to, its items come out
      // where they are now (lines, sizes and positions alike: its one line's
      // cross size is that height's content box, as here), so they are kept
      // for that layout (the fast path above)
      // (its unsafe_get / unsafe_set within the 3 + 4 × count it has)
      let pre = if pre.length() >= 3 + count * 4 {
        pre
      } else {
        let a = Array::make(3 + count * 4, 0.0)
        node.pre = a
        a
      }
      pre.unsafe_set(0, w0)
      pre.unsafe_set(1, fw)
      pre.unsafe_set(2, fh)
      for k in 0..<count {
        let i = k * ITEM
        let j = 3 + k * 4
        pre.unsafe_set(j, f.unsafe_get(i + MAIN))
        pre.unsafe_set(j + 1, f.unsafe_get(i + CROSS))
        pre.unsafe_set(j + 2, f.unsafe_get(i + MAIN_POS))
        pre.unsafe_set(j + 3, f.unsafe_get(i + CROSS_POS))
      }
      node.pre_gen = generation.val
    } else if !perform {
      node.pre_gen = -1
    }
    fw
  }
  if perform {
    let count = pool.count
    let at = pool.at
    let f = pool.f
    let flags = pool.flags
    let ox = b.bor_l + b.pad_l
    let oy = b.bor_t + b.pad_t
    for k in 0..<count {
      let i = k * ITEM
      let n = flow.unsafe_get(at.unsafe_get(k))
      let iw = if row { f.unsafe_get(i + MAIN) } else { f.unsafe_get(i + CROSS) }
      let ih = if row { f.unsafe_get(i + CROSS) } else { f.unsafe_get(i + MAIN) }
      if !reusing.val &&
        n.children.length() == 0 &&
        n.measure is None &&
        known(iw) &&
        known(ih) {
        // a box with nothing in it, its size given: what size_node comes
        // to (its box the one set up above, its caches already started in
        // this compute, nothing kept for a compute that reuses), without
        // the calls
        let ib = item_box(n)
        let w = clamp_size(iw, soft_floor(n.style, ib.min_w), ib.max_w)
        let h = clamp_size(ih, ib.min_h, ib.max_h)
        let ipbw = ib.pbw()
        let ipbh = ib.pbh()
        let rw = fmax(w - ipbw, 0.0) + ipbw
        let rh = fmax(h - ipbh, 0.0) + ipbh
        counters[0] = counters[0] + 1
        n.p_ok = true
        n.p_kw = iw
        n.p_kh = ih
        n.p_cbw = cb_w
        n.p_cbh = cb_h
        n.p_w = rw
        n.p_h = rh
        n.laid_gen = generation.val
        n.width = rw
        n.height = rh
      } else {
        let rw = size_node(n, iw, ih, iw, ih, cb_w, cb_h, true)
        let rh = out_h.val
        n.width = rw
        n.height = rh
      }
      let x = if row { f.unsafe_get(i + MAIN_POS) } else { f.unsafe_get(i + CROSS_POS) }
      let y = if row { f.unsafe_get(i + CROSS_POS) } else { f.unsafe_get(i + MAIN_POS) }
      // (insets that are all auto move it by 0)
      let inset = (flags.unsafe_get(k) & INSET) != 0
      let dx = if inset {
        inset_offset(n.style, fw - pbw, fh - pbh, true)
      } else {
        0.0
      }
      let dy = if inset {
        inset_offset(n.style, fw - pbw, fh - pbh, false)
      } else {
        0.0
      }
      n.left = on_grid(ox + x + dx)
      n.top = on_grid(oy + y + dy)
    }
    // (one laid out nowhere: left out as one its row has not the room for is, its last layout forgotten, what it holds
    // of no size)
    for c in node.children {
      if c.style.display == DisplayNone {
        left_out(c)
        zero(c)
      }
    }
    // what its row left out, nowhere (its line said so), the rest on theirs
    if s.fits {
      let mut j = 0
      for c in all {
        if j < flow.length() && physical_equal(flow[j], c) {
          j = j + 1
          if c.line < 0 {
            c.line = 0
          }
        } else {
          left_out(c)
        }
      }
    }
  }
  pool.count = 0
  depth.val = d
  out_h.val = fh
  fw
}

///|
/// What of a row's items `flow` it keeps in `room` along it (its content box's width, `gap` between items): all of
/// them but its ⋯ (Style's `drop` -1) where all take no more than that (what may leave as wide as what it holds, whole
/// or not at all; the rest at least their width, else their min-width; with their margins); else its ⋯ too, and what
/// it may leave out (`drop` k > 0) left out, the lowest k first (of the same k the last first), until the rest takes no
/// more. What is put where it is said is kept, taking no room.
fn fit_flow(flow : Array[Node], room : Double, gap : Double, cb_w : Double, cb_h : Double) -> Array[Node] {
  let n = flow.length()
  let (need, more) = fit_needs(flow, cb_w, cb_h)
  let mut total = 0.0
  let mut count = 0
  for j, c in flow {
    if c.style.position != Absolute && j != more {
      total = total + need[j]
      count = count + 1
    }
  }
  let out = Array::make(n, true)
  if more >= 0 {
    out[more] = false
  }
  if total + gap * (count - 1).to_double() > room + 0.01 {
    if more >= 0 {
      out[more] = true
      total = total + need[more]
      count = count + 1
    }
    let mut left = 0
    while total + gap * (count - 1).to_double() > room + 0.01 {
      // the next to leave: the lowest k, the last of it
      let mut pick = -1
      for j, c in flow {
        let k = c.style.drop
        if out[j] && k > 0 && c.style.position != Absolute && (pick < 0 || k <= flow[pick].style.drop) {
          pick = j
        }
      }
      if pick < 0 {
        break
      }
      out[pick] = false
      total = total - need[pick]
      count = count - 1
      left = left + 1
    }
    // nothing it may leave out: no ⋯
    if more >= 0 && left == 0 {
      out[more] = false
    }
  }
  let kept = []
  for j, c in flow {
    if out[j] {
      kept.push(c)
    }
  }
  kept
}

///|
/// Of a row's items `flow` (Style's `one_of`: ways of saying one thing, each shorter than the one before), the first
/// that fits `room` whole (as wide as what it holds, with its margins), else the last; what is put where it is said
/// kept too, taking no room.
fn first_fit(flow : Array[Node], room : Double, cb_w : Double, cb_h : Double) -> Array[Node] {
  let ways = []
  for j, c in flow {
    if c.style.position != Absolute {
      ways.push(j)
    }
  }
  let mut pick = -1
  for j in ways {
    let c = flow[j]
    let b = box_for(c, cb_w, cb_h)
    let w = size_node(c, undef, undef, undef, undef, cb_w, cb_h, false) + b.mar_l + b.mar_r
    pick = j
    if w <= room + 0.01 {
      break
    }
  }
  let kept = []
  for j, c in flow {
    if j == pick || c.style.position == Absolute {
      kept.push(c)
    }
  }
  kept
}

///|
/// What each of a row's items `flow` takes along it as fit_flow measures it, with its margins (0 for what is put where
/// it is said): what may leave is there whole or not at all, and what never gives way (shrink 0: kept as wide as what
/// it holds) is never narrower: each as wide as what it holds; the rest at least their least, or what the row keeps
/// of them (fit_need: words cut short keep some of them). And which is its ⋯ (Style's `drop` -1; -1 none).
fn fit_needs(flow : Array[Node], cb_w : Double, cb_h : Double) -> (Array[Double], Int) {
  let need = Array::make(flow.length(), 0.0)
  let mut more = -1
  for j, c in flow {
    if c.style.position == Absolute {
      continue
    }
    let b = box_for(c, cb_w, cb_h)
    let least = if known(b.min_w) { b.min_w } else { 0.0 }
    let w = if c.style.drop != 0 || (c.style.shrink == 0.0 && !known(b.w)) {
      size_node(c, undef, undef, undef, undef, cb_w, cb_h, false)
    } else if known(b.w) {
      b.w
    } else if known(c.style.fit_need) {
      fmax(least, c.style.fit_need)
    } else {
      least
    }
    need[j] = w + b.mar_l + b.mar_r
    if c.style.drop == -1 {
      more = j
    }
  }
  (need, more)
}

///|
/// A line's items `start`..`end` (pool's) with rows among them that leave out what they have not the room for, each as
/// wide as what it keeps (FITS), where the line has not the room for all it holds (`room`, its gaps out): what those
/// rows leave out chosen across the line as though their parts were one row's (fit_flow: the lowest `drop` first, of
/// the same the last in the line first), until the line takes no more than the room with the rest of it given way as
/// far as such a row would have them (each down to the least it needs, words cut short to four of their size:
/// fit_needs). Each of those rows then as wide as what it keeps (its flex basis), and where all of the line is in the
/// room so, not squeezed further: what is beside it gives way, by no more than said. What the line's items' bases come
/// to (with their margins).
fn fit_line(
  pool : Pool,
  flow : Array[Node],
  start : Int,
  end : Int,
  room : Double,
  cb_w : Double,
  cb_h : Double,
) -> Double {
  let f = pool.f
  // the rest of the line as far as it gives way, and each row's parts: its own measure (fit_needs), its padding and
  // gap, which of its parts it has left out
  let mut total = 0.0
  let rows : Array[(Int, Array[Node], Array[Double], Int, Double, Double, Array[Bool])] = []
  for k in start..<end {
    let i = k * ITEM
    total = total + f.unsafe_get(i + MARGIN_MAIN)
    if (pool.flags.unsafe_get(k) & FITS) == 0 {
      let hyp = f.unsafe_get(i + HYP)
      total = total +
        (if f.unsafe_get(i + SHRINK) == 0.0 {
          hyp
        } else {
          let least = or_else(f.unsafe_get(i + MIN_MAIN), 0.0)
          let fit = flow.unsafe_get(pool.at.unsafe_get(k)).style.fit_need
          fmin(hyp, if known(fit) { fmax(least, fit) } else { least })
        })
    } else {
      let c = flow.unsafe_get(pool.at.unsafe_get(k))
      let parts = flow_children(c)
      let (need, more) = fit_needs(parts, undef, undef)
      let pb = box_for(c, cb_w, cb_h).pbw()
      let gap = edge_of(c.style.gap_col_k, c.style.gap_col_v, undef)
      rows.push((k, parts, need, more, pb, gap, Array::make(parts.length(), false)))
    }
  }
  // a row as wide as what it keeps of its parts (its ⋯ with them once one is left out), within its least and most
  let width = fn(r : (Int, Array[Node], Array[Double], Int, Double, Double, Array[Bool])) -> Double {
    let (k, parts, need, more, pb, gap, out) = r
    let mut w = 0.0
    let mut n = 0
    let mut left = false
    for j, c in parts {
      if c.style.position == Absolute || j == more {
        continue
      }
      if out[j] {
        left = true
      } else {
        w = w + need[j]
        n = n + 1
      }
    }
    if left && more >= 0 {
      w = w + need[more]
      n = n + 1
    }
    let i = k * ITEM
    let at = pb + w + (if n > 1 { gap * (n - 1).to_double() } else { 0.0 })
    fmin(clamp_size(at, f.unsafe_get(i + MIN_MAIN), f.unsafe_get(i + MAX_MAIN)), f.unsafe_get(i + HYP))
  }
  let widths = rows.map(width)
  for w in widths {
    total = total + w
  }
  // what may leave, across the line in the order it leaves: the lowest drop first, of the same the last first
  let parts : Array[(Int, Int, Int)] = []
  for ri, r in rows {
    let (_, kids, _, _, _, _, _) = r
    for j, c in kids {
      if c.style.drop > 0 && c.style.position != Absolute {
        parts.push((ri, j, c.style.drop))
      }
    }
  }
  parts.sort_by(fn(a, b) {
    if a.2 != b.2 {
      a.2 - b.2
    } else if a.0 != b.0 {
      b.0 - a.0
    } else {
      b.1 - a.1
    }
  })
  let mut p = 0
  while total > room + 0.01 && p < parts.length() {
    let (ri, j, _) = parts[p]
    p = p + 1
    let (_, _, _, _, _, _, out) = rows[ri]
    out[j] = true
    let now = width(rows[ri])
    total = total + now - widths[ri]
    widths[ri] = now
  }
  let fits = total <= room + 0.01
  let mut sum = 0.0
  for k in start..<end {
    sum = sum + f.unsafe_get(k * ITEM + HYP) + f.unsafe_get(k * ITEM + MARGIN_MAIN)
  }
  for ri, r in rows {
    let (k, _, _, _, _, _, _) = r
    let i = k * ITEM
    let now = widths[ri]
    sum = sum + now - f.unsafe_get(i + HYP)
    f.unsafe_set(i + BASIS, now)
    f.unsafe_set(i + HYP, now)
    if fits {
      f.unsafe_set(i + SHRINK, 0.0)
    }
  }
  sum
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
/// Node `n` left out of its row (fit_flow): laid out nowhere, of no size, as this compute's layout of it and all it
/// holds (what reads the results places it so), its last layout forgotten (laid out again as it comes back, where its
/// positions were let go).
fn left_out(n : Node) -> Unit {
  n.line = -1
  forget(n)
}

///|
fn forget(n : Node) -> Unit {
  n.left = 0.0
  n.top = 0.0
  n.width = 0.0
  n.height = 0.0
  n.p_ok = false
  n.laid_gen = generation.val
  for c in n.children {
    forget(c)
  }
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
/// Leading space for justify / align-content; the space between items in
/// out_b.
fn distribute(a : Align, free : Double, n : Int, content : Bool) -> Double {
  ignore(content)
  out_b.val = 0.0
  if n <= 0 {
    return 0.0
  }
  let nd = n.to_double()
  match a {
    FlexEnd => free
    Center => free / 2.0
    SpaceBetween => {
      if n > 1 && free > 0.0 {
        out_b.val = free / (nd - 1.0)
      }
      0.0
    }
    SpaceAround =>
      if free > 0.0 {
        out_b.val = free / nd
        free / nd / 2.0
      } else {
        0.0
      }
    SpaceEvenly =>
      if free > 0.0 {
        out_b.val = free / (nd + 1.0)
        free / (nd + 1.0)
      } else {
        0.0
      }
    _ => 0.0
  }
}

///|
/// CSS flexbox §9.7: grow or shrink the items of one line to fill `space`.
fn resolve_flexible(
  pool : Pool,
  a : Int,
  b : Int,
  sum_hyp : Double,
  space : Double,
) -> Unit {
  let f = pool.f
  let flags = pool.flags
  let grow = sum_hyp < space
  // freeze inflexible items, at the size they are to have unless some are
  // flexible after all. A frozen item's main size is its target from then
  // on.
  let mut initial_free = space
  let mut flexible = false
  let factor_at = if grow { GROW } else { SHRINK }
  for k in a..<b {
    let i = k * ITEM
    let hyp = f.unsafe_get(i + HYP)
    let basis = f.unsafe_get(i + BASIS)
    f.unsafe_set(i + TARGET, hyp)
    f.unsafe_set(i + MAIN, hyp)
    let factor = f.unsafe_get(i + factor_at)
    let frozen = factor == 0.0 ||
      (grow && basis > hyp) ||
      (!grow && basis < hyp)
    if frozen {
      flags.unsafe_set(k, flags.unsafe_get(k) | FROZEN)
    } else {
      flags.unsafe_set(k, flags.unsafe_get(k) & FROZEN.lnot())
      f.unsafe_set(i + FACTOR, factor)
      f.unsafe_set(i + LO_MAIN, fmax(or_else(f.unsafe_get(i + MIN_MAIN), 0.0), f.unsafe_get(i + PB_MAIN)))
      flexible = true
    }
    initial_free = initial_free -
      f.unsafe_get(i + MARGIN_MAIN) -
      (if frozen { hyp } else { basis })
  }
  if !flexible {
    return
  }
  let mut rounds = 0
  let mut left = true
  while rounds < 64 && left {
    rounds = rounds + 1
    let mut sum_factors = 0.0
    let mut free = space
    let mut sum_scaled = 0.0
    for k in a..<b {
      let i = k * ITEM
      let frozen = (flags.unsafe_get(k) & FROZEN) != 0
      free = free -
        f.unsafe_get(i + MARGIN_MAIN) -
        (if frozen { f.unsafe_get(i + TARGET) } else { f.unsafe_get(i + BASIS) })
      if !frozen {
        sum_factors = sum_factors + f.unsafe_get(i + FACTOR)
        sum_scaled = sum_scaled + f.unsafe_get(i + FACTOR) * f.unsafe_get(i + BASIS)
      }
    }
    if sum_factors < 1.0 {
      let scaled = initial_free * sum_factors
      if scaled.abs() < free.abs() {
        free = scaled
      }
    }
    // each unfrozen item's share, clamped
    let mut total = 0.0
    for k in a..<b {
      if (flags.unsafe_get(k) & FROZEN) != 0 {
        continue
      }
      let i = k * ITEM
      let basis = f.unsafe_get(i + BASIS)
      let t = if grow {
        basis + free * f.unsafe_get(i + FACTOR) / sum_factors
      } else {
        let scaled = f.unsafe_get(i + FACTOR) * basis
        if sum_scaled > 0.0 {
          basis + free * scaled / sum_scaled
        } else {
          basis
        }
      }
      let c = clamp_size(t, f.unsafe_get(i + LO_MAIN), f.unsafe_get(i + MAX_MAIN))
      f.unsafe_set(i + CLAMPED, c - t)
      total = total + (c - t)
      f.unsafe_set(i + TARGET, c)
    }
    // freeze the violators (all, when none)
    left = false
    for k in a..<b {
      if (flags.unsafe_get(k) & FROZEN) != 0 {
        continue
      }
      let i = k * ITEM
      let v = f.unsafe_get(i + CLAMPED)
      if total == 0.0 ||
        (total > 0.0 && v > 0.0) ||
        (total < 0.0 && v < 0.0) {
        flags.unsafe_set(k, flags.unsafe_get(k) | FROZEN)
        f.unsafe_set(i + MAIN, f.unsafe_get(i + TARGET))
      } else {
        left = true
      }
    }
  }
  if left {
    for k in a..<b {
      f.unsafe_set(k * ITEM + MAIN, f.unsafe_get(k * ITEM + TARGET))
    }
  }
}

///|
/// The least width a node takes when it is given one: its min-width, or less down to its least as a last resort
/// (Style's soft_min), which only a row's last_resort gives it.
fn soft_floor(s : Style, min_w : Double) -> Double {
  if known(s.soft_min) && (!known(min_w) || s.soft_min < min_w) {
    s.soft_min
  } else {
    min_w
  }
}

///|
/// Not CSS's: a row's items `a` until `b` still wider than `space` once resolve_flexible has given them their sizes
/// (what never gives way kept at its min-width): those with a least of their own as a last resort (SOFT_MIN, below
/// their size: words on one line that say not how they give, what holds them) come down to it, the widest first, all
/// to one width where that is enough (each no less than its least), so that the row is no wider than its room; where
/// they cannot make it so, none (what never gives way runs past it: a fault the squeeze check says). Never one wider
/// than it was.
fn last_resort(pool : Pool, a : Int, b : Int, space : Double) -> Unit {
  let f = pool.f
  let mut used = 0.0
  let mut room = 0.0
  let mut widest = 0.0
  for k in a..<b {
    let i = k * ITEM
    let main = f.unsafe_get(i + MAIN)
    used = used + main + f.unsafe_get(i + MARGIN_MAIN)
    let lo = f.unsafe_get(i + SOFT_MIN)
    if known(lo) && lo < main {
      room = room + (main - lo)
      widest = fmax(widest, main)
    }
  }
  // (none cut in vain: where all of them at their least still leave the row wider than its room, what never gives
  // way is what runs past it, and they stay as they are)
  let over = used - space
  if over <= 0.01 || room < over - 0.01 {
    return
  }
  // what comes down at a width `cap`: each above it to it, no lower than its least
  let given = fn(cap : Double) {
    let mut g = 0.0
    for k in a..<b {
      let i = k * ITEM
      let main = f.unsafe_get(i + MAIN)
      let lo = f.unsafe_get(i + SOFT_MIN)
      if known(lo) && lo < main && main > cap {
        g = g + main - fmax(cap, lo)
      }
    }
    g
  }
  // the widest the items may be, halved towards it
  let mut lo = 0.0
  let mut hi = widest
  for _ in 0..<60 {
    let mid = (lo + hi) / 2.0
    if given(mid) > over {
      lo = mid
    } else {
      hi = mid
    }
  }
  let cap = hi
  for k in a..<b {
    let i = k * ITEM
    let main = f.unsafe_get(i + MAIN)
    let lo = f.unsafe_get(i + SOFT_MIN)
    if known(lo) && lo < main && main > cap {
      f.unsafe_set(i + MAIN, fmax(cap, lo))
    }
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
    // a box whose layout was reused holds its absolute boxes as they were
    // (and one with no children has none to place)
    if cs.position == Absolute {
      place_absolute(cb, node, c, ox, oy)
      if !kept(c) && c.children.length() > 0 {
        layout_static_absolute(c, c, 0.0, 0.0)
      }
    } else if c.children.length() == 0 {
      ()
    } else if cs.position == Static {
      layout_static_absolute(cb, c, ox + c.left, oy + c.top)
    } else if !kept(c) {
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
  let l = resolve_of(cs.inset_left_k, cs.inset_left_v, cw)
  let r = resolve_of(cs.inset_right_k, cs.inset_right_v, cw)
  let t = resolve_of(cs.inset_top_k, cs.inset_top_v, ch)
  let bt = resolve_of(cs.inset_bottom_k, cs.inset_bottom_v, ch)
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
  let fw = size_node(
    c,
    w,
    h,
    if known(w) { w } else { cw },
    if known(h) { h } else { ch },
    cw,
    ch,
    false,
  )
  let fh = out_h.val
  let rw = size_node(c, fw, fh, fw, fh, cw, ch, true)
  let rh = out_h.val
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
  c.left = on_grid(
    if known(l) {
      cbb.bor_l + l + b.mar_l - ox
    } else if known(r) {
      cb.width - cbb.bor_r - r - rw - b.mar_r - ox
    } else {
      static_x
    },
  )
  c.top = on_grid(
    if known(t) {
      cbb.bor_t + t + b.mar_t - oy
    } else if known(bt) {
      cb.height - cbb.bor_b - bt - rh - b.mar_b - oy
    } else {
      static_y
    },
  )
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
