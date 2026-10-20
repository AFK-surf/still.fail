// Layout: the tree goes to the flexbox engine in mbui/flex (checked against
// Yoga's tests) as a tree of flex nodes, one kept on each node of the pool.
// Text, editors and lists are its measured leaves; a list lays out its own
// rows, each as a tree of its own.

///|
fn Ctx::editor_display(self : Ctx, n : Node) -> String {
  match self.editors.get(n.id) {
    Some(st) => st.shown()
    None => ""
  }
}

///|
/// The text laid out in `max_w`. The engine asks for a few widths per frame;
/// greedy wrapping gives the same lines for any width from the widest line
/// up to the one it was laid out in, so one layout serves them all, frame
/// after frame while the text stays (Ctx::flex_tree forgets it when not).
fn Node::text_layout(self : Node, max_w : Double) -> TextLayout {
  match self.full {
    Some(tl) if !self.wrap ||
      (tl.w <= max_w + 0.01 && max_w <= self.full_max) => return tl
    _ => ()
  }
  let tl = layout_text(
    self.text,
    self.font_size,
    self.weight,
    max_w,
    self.wrap,
    line=self.line_h,
  )
  self.full = Some(tl)
  self.full_max = max_w
  tl
}

///|
/// One-line text cut to fit `w`, ending in an ellipsis.
fn ellipsized(n : Node, tl : TextLayout, w : Double) -> TextLayout {
  let s = tl.shaped
  let dots = layout_text("…", n.font_size, n.weight, 1.0e9, false, line=n.line_h)
  let room = w - dots.w
  let mut end = 0
  while end < s.starts.length() && tl.xs[end] + s.adv[end] <= room {
    end = end + 1
  }
  // no space left before the dots
  while end > 0 && s.cu[end - 1] == 32 {
    end = end - 1
  }
  let cut = if end < s.starts.length() { s.starts[end] } else { s.len }
  let text = n.text.view(end_offset=cut).to_string() + "…"
  layout_text(text, n.font_size, n.weight, 1.0e9, false, line=n.line_h)
}

///|
/// The content size of a leaf for the flex engine.
fn leaf_size(
  n : Node,
  w : Double,
  wm : @flex.MeasureMode,
  h : Double,
  hm : @flex.MeasureMode,
) -> (Double, Double) {
  let max_w = if wm == Undefined { 1.0e9 } else { w }
  if n.kind == kind_text {
    let tl = n.text_layout(max_w)
    (if wm == Exactly { w } else { tl.w }, tl.h)
  } else if n.kind == kind_rich {
    match n.rich_layout(max_w) {
      Some(rl) => (if wm == Exactly { w } else { rl.w }, rl.h)
      None => (0.0, 0.0)
    }
  } else if n.kind == kind_editor {
    // an editor takes the width it is offered
    let s = g().editor_display(n)
    let tl = layout_text(s, n.font_size, n.weight, max_w, true, line=n.line_h)
    (if wm == Undefined { tl.w } else { w }, tl.h)
  } else if n.kind == kind_image {
    image_leaf_size(n, w, wm, h, hm)
  } else {
    // a list fills what it is given, and has no height of its own
    (if wm == Undefined { 0.0 } else { w }, if hm == Exactly { h } else { 0.0 })
  }
}

///|
/// A length for the flex engine; zero, the most common, is not made anew.
fn pt(v : Double) -> @flex.Dim {
  if v == 0.0 {
    @flex.pt_zero
  } else {
    Pt(v)
  }
}

///|
/// What `d` must become to be `Pt(v)`; None when it is.
fn pt_change(d : @flex.Dim, v : Double) -> @flex.Dim? {
  match d {
    Pt(x) if x == v => None
    _ => Some(pt(v))
  }
}

///|
/// What `d` must become to be `Pt(v)` when `has`, else Auto; None when it
/// is.
fn opt_change(d : @flex.Dim, has : Bool, v : Double) -> @flex.Dim? {
  if has {
    pt_change(d, v)
  } else if is_auto(d) {
    None
  } else {
    Some(Auto)
  }
}

///|
fn is_pct100(d : @flex.Dim) -> Bool {
  match d {
    Pct(p) => p == 100.0
    _ => false
  }
}

///|
fn is_auto(d : @flex.Dim) -> Bool {
  match d {
    Auto => true
    _ => false
  }
}

///|
/// The parts of a rich paragraph its layout depends on are the same.
fn rich_same(a : Rich?, b : Rich?) -> Bool {
  match (a, b) {
    (Some(a), Some(b)) =>
      a.size == b.size &&
      a.weight == b.weight &&
      a.line == b.line &&
      a.wrap == b.wrap &&
      a.code_scale == b.code_scale &&
      a.code_bg == b.code_bg &&
      (physical_equal(a.runs, b.runs) || a.runs == b.runs)
    (None, None) => true
    _ => false
  }
}

///|
/// The flex node for node `i` (laid out in direction `pdir`: 0 none, 1
/// row, 2 column) and its subtree,
/// styled from the builder's sizes: Fill along the parent's direction
/// grows from nothing, across it stretches; content-sized children of a
/// row may shrink (and wrap), except text that must stay on one line.
///
/// Styles, children and what leaves measure are compared with what the
/// flex node was given last frame, and only what differs is set: a flex
/// node that changed, and every one above it, is marked dirty, and the
/// engine keeps the layout of the rest (@flex.compute's reuse). Returns
/// for the parent: 1 when it must lay out again (this subtree changed), 2
/// when it is not to be moved as a whole (Ctx::commit): something in it
/// changed, moved by itself, or is placed anew every frame (lists,
/// editors, pager pages).
///
/// A child changes parents only with both parents' children changing (a
/// slot is taken before the slots of what it holds, and every slot in use
/// is reached here), so the parents lay out again as the engine needs.
fn Ctx::flex_tree(self : Ctx, i : Int, pdir : Int) -> Int {
  let n = self.nodes[i]
  let f = n.fl
  let s = f.style
  let mut ch = n.lk_epoch != self.epoch || n.lk_kind != n.kind
  if !layout_reuse.val {
    n.full = None
    n.rl = None
  }
  n.lk_epoch = self.epoch
  n.lk_kind = n.kind
  let dir : @flex.FlexDirection = if n.dir == Row {
    if n.rtl {
      RowReverse
    } else {
      Row
    }
  } else {
    Column
  }
  if s.direction != dir {
    s.direction = dir
    ch = true
  }
  match pt_change(s.padding.left, n.pad_l) {
    Some(d) => {
      s.padding.left = d
      ch = true
    }
    None => ()
  }
  match pt_change(s.padding.top, n.pad_t) {
    Some(d) => {
      s.padding.top = d
      ch = true
    }
    None => ()
  }
  match pt_change(s.padding.right, n.pad_r) {
    Some(d) => {
      s.padding.right = d
      ch = true
    }
    None => ()
  }
  match pt_change(s.padding.bottom, n.pad_b) {
    Some(d) => {
      s.padding.bottom = d
      ch = true
    }
    None => ()
  }
  match pt_change(s.gap_row, n.gap) {
    Some(d) => {
      s.gap_row = d
      s.gap_col = d
      ch = true
    }
    None => ()
  }
  if s.aspect != n.aspect {
    s.aspect = n.aspect
    ch = true
  }
  let ai : @flex.Align = match n.align {
    AStart => FlexStart
    ACenter => Center
    AEnd => FlexEnd
    AStretch => Stretch
  }
  if s.align_items != ai {
    s.align_items = ai
    ch = true
  }
  let ju : @flex.Align = match n.justify {
    JStart => FlexStart
    JCenter => Center
    JEnd => FlexEnd
    JBetween => SpaceBetween
  }
  if s.justify != ju {
    s.justify = ju
    ch = true
  }
  // 0 and 1e9: none (Auto)
  match opt_change(s.min_height, n.min_h > 0.0, n.min_h) {
    Some(d) => {
      s.min_height = d
      ch = true
    }
    None => ()
  }
  match opt_change(s.max_height, n.max_h < 1.0e9, n.max_h) {
    Some(d) => {
      s.max_height = d
      ch = true
    }
    None => ()
  }
  match opt_change(s.min_width, n.min_w > 0.0, n.min_w) {
    Some(d) => {
      s.min_width = d
      ch = true
    }
    None => ()
  }
  match opt_change(s.max_width, n.max_w < 1.0e9, n.max_w) {
    Some(d) => {
      s.max_width = d
      ch = true
    }
    None => ()
  }
  let in_row = pdir == 1
  let in_col = pdir == 2
  let mut grow = 0.0
  let mut shrink = 0.0
  let mut basis0 = false
  let mut stretch = false
  // the width (and height) said in points
  let mut wpx = 0.0
  let mut hpx = 0.0
  let mut has_w = false
  let mut has_h = false
  match n.w {
    Px(p) => {
      wpx = p
      has_w = true
    }
    Fill(k) =>
      if in_row {
        grow = k
        shrink = 1.0
        basis0 = true
      } else if in_col {
        stretch = true
      }
    Auto =>
      if in_row && !((n.kind == kind_text || n.kind == kind_rich) && !n.wrap) {
        shrink = 1.0
      }
  }
  // a pager's pages lie over each other, moved sideways as they turn
  let over = n.pager != 0 || n.layer
  match n.h {
    Px(p) => {
      hpx = p
      has_h = true
    }
    Fill(k) =>
      if in_col {
        grow = k
        shrink = 1.0
        basis0 = true
      } else if in_row {
        stretch = true
      }
    Auto => ()
  }
  if s.grow != grow {
    s.grow = grow
    ch = true
  }
  // (shrink never changes alone: with the width said another way, which
  // changes the width, grow, basis or alignment; with the parent's
  // direction, which changes the parent; with a text's wrapping or kind.
  // A node's own size does not depend on it, only its parent's layout)
  // in what scrolls sideways, as wide as it is (Ctx::sideways)
  if (in_row || in_col) && n.parent >= 0 && self.nodes[n.parent].sideways {
    shrink = 0.0
  }
  if s.shrink != shrink {
    s.shrink = shrink
    ch = true
  }
  let flow : @flex.Overflow = if n.sideways { Scroll } else { Visible }
  if s.overflow != flow {
    s.overflow = flow
    ch = true
  }
  if is_auto(s.basis) == basis0 {
    s.basis = if basis0 { @flex.pt_zero } else { Auto }
    ch = true
  }
  let als : @flex.Align = if stretch { Stretch } else { Auto }
  if s.align_self != als {
    s.align_self = als
    ch = true
  }
  if over {
    // (only when it has just become a layer: its position changes too)
    if !is_pct100(s.width) {
      s.width = Pct(100.0)
    }
  } else {
    match opt_change(s.width, has_w, wpx) {
      Some(d) => {
        s.width = d
        ch = true
      }
      None => ()
    }
  }
  if !has_h && over {
    if !is_pct100(s.height) {
      s.height = Pct(100.0)
      ch = true
    }
  } else {
    match opt_change(s.height, has_h, hpx) {
      Some(d) => {
        s.height = d
        ch = true
      }
      None => ()
    }
  }
  let pos : @flex.PositionType = if over { Absolute } else { Relative }
  if s.position != pos {
    s.position = pos
    s.inset.left = if over { @flex.pt_zero } else { Auto }
    s.inset.top = if over { @flex.pt_zero } else { Auto }
    ch = true
  }
  let mut up = 0
  let k = n.kind
  if k == kind_text ||
    k == kind_rich ||
    k == kind_editor ||
    k == kind_list ||
    k == kind_image {
    // (measured or not goes with its kind, compared above)
    if f.measure is None {
      f.measure = n.leaf
    }
    if f.children.length() > 0 {
      f.children.clear()
      ch = true
    }
    if k == kind_text {
      if n.lk_text != n.text ||
        n.lk_size != n.font_size ||
        n.lk_weight != n.weight ||
        n.lk_line != n.line_h ||
        n.lk_wrap != n.wrap {
        n.lk_text = n.text
        n.lk_size = n.font_size
        n.lk_weight = n.weight
        n.lk_line = n.line_h
        n.lk_wrap = n.wrap
        n.full = None
        ch = true
      }
    } else if k == kind_rich {
      if !rich_same(n.lk_rich, n.rich) {
        n.lk_rich = n.rich
        n.rl = None
        ch = true
      }
    } else if k == kind_image {
      let (iw, ih) = match image_size(n.text) {
        Some(sz) => sz
        None => (-1.0, -1.0)
      }
      if n.lk_text != n.text || n.lk_iw != iw || n.lk_ih != ih {
        n.lk_text = n.text
        n.lk_iw = iw
        n.lk_ih = ih
        ch = true
      }
    } else if k == kind_editor {
      // what it shows changes as it is typed in: measured (and placed)
      // every frame
      ch = true
    }
    if k == kind_list {
      up = 2
    }
  } else {
    if f.measure is Some(_) {
      f.measure = None
    }
    let kids = f.children
    let pd = if n.dir == Row { 1 } else { 2 }
    let mut j = 0
    let mut c = n.first
    while c >= 0 {
      let cn = self.nodes[c]
      let r = self.flex_tree(c, pd)
      if (r & 1) != 0 {
        ch = true
      }
      if (r & 2) != 0 ||
        cn.tx != cn.otx ||
        cn.ty != cn.oty ||
        cn.slide != cn.oslide {
        up = 2
      }
      if j < kids.length() {
        // another slot here only when one before it holds more or fewer
        // than it did (slots are taken in order): that one changed
        // already, and this one says so if it differs
        if !physical_equal(kids[j], cn.fl) {
          kids[j] = cn.fl
        }
      } else {
        kids.push(cn.fl)
        ch = true
      }
      j = j + 1
      c = cn.next
    }
    if j < kids.length() {
      kids.truncate(j)
      ch = true
    }
  }
  if n.pager != 0 {
    up = 2
  }
  if ch {
    f.dirty = true
    up = 3
  }
  n.same = up == 0
  up
}

///|
/// Work done by commits so far: nodes placed, subtrees moved as a whole,
/// subtrees left where they were. For tests and benchmarks.
let commit_counts : FixedArray[Int] = FixedArray::make(3, 0)

///|
/// Off (tests only): every frame laid out from nothing, as before layouts
/// were kept, to compare with.
// kept across runs: a test sets it around the Testers it makes, and puts it back (layout_wbtest's same_both_ways)
let layout_reuse : Ref[Bool] = Ref::new(true)

///|
/// Lays out node `i` and its subtree at (x, y), `w` wide and `h` high (NaN:
/// as high as its content); returns its height.
fn Ctx::layout(
  self : Ctx,
  i : Int,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> Double {
  self.flex_tree(i, 0) |> ignore
  let root = self.nodes[i].fl
  @flex.compute(root, width=w, height=h, round=false, reuse=true)
  // (lists lay out their rows as they are placed: computes of their own)
  self.commit(i, x, y, @flex.computes())
  root.height
}

///|
/// Places a subtree laid out as before under its parent's new origin
/// (px, py): what commit would make of it, without its leaves' layouts.
fn Ctx::replace(self : Ctx, i : Int, px : Double, py : Double) -> Unit {
  let n = self.nodes[i]
  let f = n.fl
  n.x = px + f.left + n.tx + n.slide * f.width
  n.y = py + f.top + n.ty
  let mut c = n.first
  while c >= 0 {
    self.replace(c, n.x, n.y)
    c = self.nodes[c].next
  }
}

///|
/// Copies the flex engine's results back as absolute rectangles (with each
/// node's visual offset, which its subtree follows), and lays out what is
/// inside the leaves. A subtree the same as when it was placed last, that
/// the engine did not lay out again in compute `gen` (so nothing in it
/// moved or changed size), is put where it now goes instead: every slot in
/// use is placed every frame, so what it holds was placed as it is.
fn Ctx::commit(self : Ctx, i : Int, px : Double, py : Double, gen : Int) -> Unit {
  let n = self.nodes[i]
  let f = n.fl
  if n.same && f.laid_out_at() != gen {
    let x = px + f.left + n.tx + n.slide * f.width
    let y = py + f.top + n.ty
    n.otx = n.tx
    n.oty = n.ty
    n.oslide = n.slide
    if x != n.x || y != n.y {
      commit_counts[1] = commit_counts[1] + 1
      self.replace(i, px, py)
    } else {
      // where it was, and so is all of it
      commit_counts[2] = commit_counts[2] + 1
    }
    return
  }
  if n.pager != 0 {
    self.place_pager_slot(i)
  }
  commit_counts[0] = commit_counts[0] + 1
  n.otx = n.tx
  n.oty = n.ty
  n.oslide = n.slide
  n.x = px + f.left + n.tx + n.slide * f.width
  n.y = py + f.top + n.ty
  n.fw = f.width
  n.fh = f.height
  let ix = n.x + n.pad_l
  let iy = n.y + n.pad_t
  let iw = dmax(n.fw - n.pad_l - n.pad_r, 0.0)
  let ih = dmax(n.fh - n.pad_t - n.pad_b, 0.0)
  if n.kind == kind_text {
    let tl = n.text_layout(iw)
    n.tl = Some(if !n.wrap && tl.w > iw + 0.5 { ellipsized(n, tl, iw) } else { tl })
  } else if n.kind == kind_rich {
    n.rich_layout(iw) |> ignore
  } else if n.kind == kind_editor {
    match self.editors.get(n.id) {
      Some(st) => {
        let tl = layout_text(st.shown(), n.font_size, n.weight, iw, true, line=n.line_h)
        st.tl = Some(tl)
        // taller than the field: scrolled so that the caret's line shows
        let (_, cl) = tl.caret(st.caret + st.marked.length())
        let top = cl.to_double() * tl.line_h
        if top - st.scroll < 0.0 {
          st.scroll = top
        } else if top + tl.line_h - st.scroll > ih {
          st.scroll = top + tl.line_h - ih
        }
        st.scroll = dmax(0.0, dmin(st.scroll, tl.h - ih))
        st.ox = ix
        st.oy = iy - st.scroll
      }
      None => ()
    }
  } else if n.kind == kind_list {
    self.place_list(i, ix, iy, iw, ih)
  } else {
    let mut c = n.first
    while c >= 0 {
      self.commit(c, n.x, n.y, gen)
      c = self.nodes[c].next
    }
  }
}
