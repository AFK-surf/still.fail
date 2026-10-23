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
    trim=self.line_trim,
    spacing=self.spacing,
  )
  let tl = if self.wrap && self.max_lines > 0 && tl.line_start.length() > self.max_lines {
    cut_to_lines(self, tl, max_w)
  } else {
    tl
  }
  self.full = Some(tl)
  self.full_max = max_w
  tl
}

///|
/// One-line text cut to fit `w`, ending in an ellipsis.
fn ellipsized(n : Node, tl : TextLayout, w : Double) -> TextLayout {
  let s = tl.shaped
  let dots = layout_text("…", n.font_size, n.weight, 1.0e9, false, line=n.line_h, trim=n.line_trim, spacing=n.spacing)
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
  layout_text(text, n.font_size, n.weight, 1.0e9, false, line=n.line_h, trim=n.line_trim, spacing=n.spacing)
}

///|
/// Wrapped text cut after its `max_lines`th line in `w`, as Android's maxLines with an ellipsis: the last line has
/// what follows of the paragraph up to what fits with the ellipsis after it. The lines before stay as they were
/// (greedy wrapping makes each of what precedes it). Like a whole layout, the cut serves every width from its widest
/// line up to the one it was made in (Node::text_layout): the lines before are the same in any of them, and what did
/// not fit the last line in the widest does not in a narrower one, what did still does.
fn cut_to_lines(n : Node, tl : TextLayout, w : Double) -> TextLayout {
  let s = tl.shaped
  let count = s.starts.length()
  let a = tl.line_start[n.max_lines - 1]
  let dots = layout_text("…", n.font_size, n.weight, 1.0e9, false, line=n.line_h, trim=n.line_trim, spacing=n.spacing)
  let room = w - dots.w
  let mut x = 0.0
  let mut end = a
  while end < count && !is_nl(s.cu[end]) && x + s.adv[end] <= room + 0.01 {
    x = x + s.adv[end]
    end = end + 1
  }
  // no space left before the dots
  while end > a && s.cu[end - 1] == 32 {
    end = end - 1
  }
  let cut = if end < count { s.starts[end] } else { s.len }
  let text = n.text.view(end_offset=cut).to_string() + "…"
  layout_text(text, n.font_size, n.weight, w, true, line=n.line_h, trim=n.line_trim, spacing=n.spacing)
}

///|
/// Whether lines ending at `line_end` (clusters, whose first code units are `cu`) were broken where the width ran out,
/// not only at the words' own new lines.
fn soft_wrapped(line_end : Array[Int], cu : Array[Int]) -> Bool {
  for l in 0..<(line_end.length() - 1) {
    let e = line_end[l]
    if e <= 0 || e > cu.length() || !is_nl(cu[e - 1]) {
      return true
    }
  }
  false
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
  // words broken onto more lines than their own take all the width they may (Compose's Text: a paragraph wrapped is
  // as wide as its constraint, not its widest line), as a message's bubble is
  if n.kind == kind_text {
    let tl = n.text_layout(max_w)
    (if wm == Exactly || (wm == AtMost && n.wrap && soft_wrapped(tl.line_end, tl.shaped.cu)) { w } else { tl.w }, tl.h)
  } else if n.kind == kind_rich {
    match n.rich_layout(max_w) {
      Some(rl) => (if wm == Exactly || (wm == AtMost && n.wrap && soft_wrapped(rl.line_end, rl.cu)) { w } else { rl.w }, rl.h)
      None => (0.0, 0.0)
    }
  } else if n.kind == kind_editor {
    // an editor takes the width it is offered
    let s = g().editor_display(n)
    let tl = layout_text(s, n.font_size, n.weight, max_w, true, line=n.line_h, trim=n.line_trim)
    (if wm == Undefined { tl.w } else { w }, tl.h)
  } else if n.kind == kind_image {
    image_leaf_size(n, w, wm, h, hm)
  } else {
    // a list fills what it is given, and has no height of its own
    (if wm == Undefined { 0.0 } else { w }, if hm == Exactly { h } else { 0.0 })
  }
}

///|
/// `v` points on the device's whole pixels when `whole` (Compose's Dp.roundToPx: the pixels rounded, half up), else as
/// it is: a padding, a gap, a size said in points is laid out as Android's layout lays it out, each on its own, so what
/// is placed after several of them falls where Android's does (still.fail's share sheet: its grabber's 25 points 66
/// pixels there at 2.625, not 65.625).
fn Ctx::on_px(self : Ctx, v : Double, whole : Bool) -> Double {
  if !whole || v == 0.0 || v >= 1.0e9 {
    v
  } else {
    (v * self.scale + 0.5).floor() / self.scale
  }
}

///|
/// Whether the host sets things on whole device pixels, its lengths as its lines (Android's: Compose rounds each
/// length to pixels, StaticLayout each line; whole_pixel_lines, as the host says of its fonts).
fn whole_px_layout() -> Bool {
  match fake.val {
    // a Tester over a host's kept text: as that host said of its fonts (any of them), asked of nothing new
    Some(_) =>
      match text_table.val {
        Some(t) => t.metrics.values().any(fn(r) { r.length() > 5 && r[5] == 1.0 })
        None => false
      }
    None => whole_pixel_lines(15.0, 400)
  }
}

///|
/// Whether a style's length (its kind and number: @flex.Style's `<name>_k`, `<name>_v`) is not `v` points.
fn pt_differs(k : Int, cur : Double, v : Double) -> Bool {
  k != @flex.LEN_PT || cur != v
}

///|
/// Whether a style's length is not what it is to be: `v` points when `has`, else Auto.
fn opt_differs(k : Int, cur : Double, has : Bool, v : Double) -> Bool {
  if has {
    pt_differs(k, cur, v)
  } else {
    k != @flex.LEN_AUTO
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
      a.spacing == b.spacing &&
      a.code_bg == b.code_bg &&
      a.max_lines == b.max_lines &&
      a.faces == b.faces &&
      a.shaped_in == b.shaped_in &&
      (physical_equal(a.runs, b.runs) || a.runs == b.runs)
    (None, None) => true
    _ => false
  }
}

///|
/// The flex node for node `i` (laid out in direction `pdir`: 0 none, 1
/// row, 2 column) and its subtree,
/// styled from the builder's sizes: Fill along the parent's direction
/// grows from nothing, across it stretches (held to a max across in a
/// parent that centres or ends, placed as the parent places what it
/// holds); content-sized children of a
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
  // (each length said in points on whole device pixels where the host sets things on them: whole_px_layout)
  let whole = self.whole_px
  let len = fn(v : Double) { self.on_px(v, whole) }
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
  let pad_l = len(n.pad_l)
  if pt_differs(s.padding_left_kind(), s.padding_left_value(), pad_l) {
    s.set_padding_left(Pt(pad_l))
    ch = true
  }
  let pad_t = len(n.pad_t)
  if pt_differs(s.padding_top_kind(), s.padding_top_value(), pad_t) {
    s.set_padding_top(Pt(pad_t))
    ch = true
  }
  let pad_r = len(n.pad_r)
  if pt_differs(s.padding_right_kind(), s.padding_right_value(), pad_r) {
    s.set_padding_right(Pt(pad_r))
    ch = true
  }
  let pad_b = len(n.pad_b)
  if pt_differs(s.padding_bottom_kind(), s.padding_bottom_value(), pad_b) {
    s.set_padding_bottom(Pt(pad_b))
    ch = true
  }
  // margins (CSS's: below 0 too)
  let mar_l = len(n.mar_l)
  if pt_differs(s.margin_left_kind(), s.margin_left_value(), mar_l) {
    s.set_margin_left(Pt(mar_l))
    ch = true
  }
  let mar_t = len(n.mar_t)
  if pt_differs(s.margin_top_kind(), s.margin_top_value(), mar_t) {
    s.set_margin_top(Pt(mar_t))
    ch = true
  }
  let mar_r = len(n.mar_r)
  if pt_differs(s.margin_right_kind(), s.margin_right_value(), mar_r) {
    s.set_margin_right(Pt(mar_r))
    ch = true
  }
  let mar_b = len(n.mar_b)
  if pt_differs(s.margin_bottom_kind(), s.margin_bottom_value(), mar_b) {
    s.set_margin_bottom(Pt(mar_b))
    ch = true
  }
  let gap = len(n.gap)
  // (a row in lines: `line_gap` between its lines where said)
  let lines = if n.flow && n.line_gap >= 0.0 { len(n.line_gap) } else { gap }
  if pt_differs(s.gap_col_kind(), s.gap_col_value(), gap) || pt_differs(s.gap_row_kind(), s.gap_row_value(), lines) {
    s.set_gap_row(Pt(lines))
    s.set_gap_col(Pt(gap))
    ch = true
  }
  // a row in lines (Ctx::box `flow`)
  let fw : @flex.FlexWrap = if n.flow { Wrap } else { NoWrap }
  if s.wrap != fw {
    s.wrap = fw
    ch = true
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
  let has_min_h = n.min_h > 0.0
  let min_h = len(n.min_h)
  if opt_differs(s.min_height_kind(), s.min_height_value(), has_min_h, min_h) {
    s.set_min_height(if has_min_h { Pt(min_h) } else { Auto })
    ch = true
  }
  let has_max_h = n.max_h < 1.0e9
  let max_h = len(n.max_h)
  if opt_differs(s.max_height_kind(), s.max_height_value(), has_max_h, max_h) {
    s.set_max_height(if has_max_h { Pt(max_h) } else { Auto })
    ch = true
  }
  let has_min_w = n.min_w > 0.0
  let min_w = len(n.min_w)
  if opt_differs(s.min_width_kind(), s.min_width_value(), has_min_w, min_w) {
    s.set_min_width(if has_min_w { Pt(min_w) } else { Auto })
    ch = true
  }
  let has_max_w = n.max_w < 1.0e9
  let max_w = len(n.max_w)
  if opt_differs(s.max_width_kind(), s.max_width_value(), has_max_w, max_w) {
    s.set_max_width(if has_max_w { Pt(max_w) } else { Auto })
    ch = true
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
  // the width (and height) said as a share of the parent's (NaN: not)
  let mut wpct = 0.0 / 0.0
  let mut hpct = 0.0 / 0.0
  match n.w {
    Px(p) => {
      wpx = p
      has_w = true
    }
    Pct(p) => wpct = p
    Fill(k) =>
      if in_row {
        grow = k
        shrink = 1.0
        basis0 = true
      } else if in_col {
        stretch = true
      }
    Auto =>
      if in_row && !n.keep && !((n.kind == kind_text || n.kind == kind_rich) && !n.wrap) {
        shrink = 1.0
      }
  }
  // a pager's pages lie over each other, moved sideways as they turn
  let over = n.pager != 0 || n.layer
  // put where it is said in its parent (CSS's position: absolute), out of the flow
  let at = !over && n.placed_at()
  match n.h {
    Px(p) => {
      hpx = p
      has_h = true
    }
    Pct(p) => hpct = p
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
  // Fill across, held to a max there, in what centres or ends what it holds: as wide (high) as that up to its max, and
  // placed as the parent places its children, as Compose's fillMaxWidth().widthIn(max) in a centred Column; stretched
  // it would sit at the start (a flex item stretched short of its line)
  let placed = n.parent >= 0 && self.nodes[n.parent].align is (ACenter | AEnd)
  let fill_w = in_col && n.w is Fill(_) && has_max_w && placed
  let fill_h = in_row && n.h is Fill(_) && has_max_h && placed
  if fill_w || fill_h {
    stretch = false
  }
  if s.grow != grow {
    s.grow = grow
    ch = true
  }
  // (shrink never changes alone: with the width said another way, which
  // changes the width, grow, basis or alignment; with the parent's
  // direction, which changes the parent; with a text's wrapping or kind.
  // A node's own size does not depend on it, only its parent's layout)
  // in what scrolls sideways, as wide as it is (Ctx::sideways): what it holds directly, and in its rows at any depth
  // what is as wide as its content (a row of chips, a table's cells), not squeezed to the box's width
  if (in_row || in_col) && n.parent >= 0 && self.nodes[n.parent].sideways {
    shrink = 0.0
  }
  if in_row && n.in_sideways && n.w is Auto {
    shrink = 0.0
  }
  // in a row of lines, as wide as it is: what does not fit goes on the next line
  if in_row && n.parent >= 0 && self.nodes[n.parent].flow {
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
  if (s.basis_kind() == @flex.LEN_AUTO) == basis0 {
    s.set_basis(if basis0 { Pt(0.0) } else { Auto })
    ch = true
  }
  let als : @flex.Align = if stretch { Stretch } else { Auto }
  if s.align_self != als {
    s.align_self = als
    ch = true
  }
  if over {
    // (only when it has just become a layer: its position changes too)
    if !(s.width_kind() == @flex.LEN_PCT && s.width_value() == 100.0) {
      s.set_width(Pct(100.0))
    }
  } else if fill_w {
    if !(s.width_kind() == @flex.LEN_PCT && s.width_value() == 100.0) {
      s.set_width(Pct(100.0))
      ch = true
    }
  } else if !wpct.is_nan() {
    if !(s.width_kind() == @flex.LEN_PCT && s.width_value() == wpct) {
      s.set_width(Pct(wpct))
      ch = true
    }
  } else {
    let w = len(wpx)
    if opt_differs(s.width_kind(), s.width_value(), has_w, w) {
      s.set_width(if has_w { Pt(w) } else { Auto })
      ch = true
    }
  }
  if (!has_h && over) || fill_h {
    if !(s.height_kind() == @flex.LEN_PCT && s.height_value() == 100.0) {
      s.set_height(Pct(100.0))
      ch = true
    }
  } else if !hpct.is_nan() {
    if !(s.height_kind() == @flex.LEN_PCT && s.height_value() == hpct) {
      s.set_height(Pct(hpct))
      ch = true
    }
  } else {
    let h = len(hpx)
    if opt_differs(s.height_kind(), s.height_value(), has_h, h) {
      s.set_height(if has_h { Pt(h) } else { Auto })
      ch = true
    }
  }
  let pos : @flex.PositionType = if over || at { Absolute } else { Relative }
  if s.position != pos {
    s.position = pos
    ch = true
  }
  // a layer from its parent's top left; one put where it is said, from the edges said (len: on whole pixels too)
  let inset = fn(v : Double, layer : Double) -> Double {
    if over {
      layer
    } else if at && !v.is_nan() {
      len(v)
    } else {
      0.0 / 0.0
    }
  }
  let in_l = inset(n.at_l, 0.0)
  if opt_differs(s.inset_left_kind(), s.inset_left_value(), !in_l.is_nan(), in_l) {
    s.set_inset_left(if in_l.is_nan() { Auto } else { Pt(in_l) })
    ch = true
  }
  let in_t = inset(n.at_t, 0.0)
  if opt_differs(s.inset_top_kind(), s.inset_top_value(), !in_t.is_nan(), in_t) {
    s.set_inset_top(if in_t.is_nan() { Auto } else { Pt(in_t) })
    ch = true
  }
  let in_r = inset(n.at_r, 0.0 / 0.0)
  if opt_differs(s.inset_right_kind(), s.inset_right_value(), !in_r.is_nan(), in_r) {
    s.set_inset_right(if in_r.is_nan() { Auto } else { Pt(in_r) })
    ch = true
  }
  let in_b = inset(n.at_b, 0.0 / 0.0)
  if opt_differs(s.inset_bottom_kind(), s.inset_bottom_value(), !in_b.is_nan(), in_b) {
    s.set_inset_bottom(if in_b.is_nan() { Auto } else { Pt(in_b) })
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
        n.lk_trim != n.line_trim ||
        n.lk_wrap != n.wrap ||
        n.lk_spacing != n.spacing ||
        n.lk_max_lines != n.max_lines ||
        n.lk_shaped != words_shaped_in.val {
        n.lk_text = n.text
        n.lk_size = n.font_size
        n.lk_weight = n.weight
        n.lk_line = n.line_h
        n.lk_trim = n.line_trim
        n.lk_wrap = n.wrap
        n.lk_spacing = n.spacing
        n.lk_max_lines = n.max_lines
        n.lk_shaped = words_shaped_in.val
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
        cn.place is Some(_) ||
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
/// A node placed by its own size (Ctx::place_by_size): its offset worked out from the size it is laid out at.
fn Node::by_size(self : Node, w : Double, h : Double) -> Unit {
  match self.place {
    Some(p) => {
      let (tx, ty) = p(w, h)
      self.tx = tx
      self.ty = ty
    }
    None => ()
  }
}

///|
/// Places a subtree laid out as before under its parent's new origin
/// (px, py): what commit would make of it, without its leaves' layouts.
fn Ctx::replace(self : Ctx, i : Int, px : Double, py : Double) -> Unit {
  let n = self.nodes[i]
  let f = n.fl
  n.by_size(f.width, f.height)
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
    n.by_size(f.width, f.height)
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
  n.by_size(f.width, f.height)
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
        let tl = layout_text(st.shown(), n.font_size, n.weight, iw, true, line=n.line_h, trim=n.line_trim, style=faces_style(st.words, 0))
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
