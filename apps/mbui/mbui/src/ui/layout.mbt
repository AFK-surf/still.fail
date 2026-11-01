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
/// How much of words cut short (`w=Cut`) their row keeps before a part of it leaves (Ctx::box `drop`): four of their
/// size, or all of them where they are fewer.
let cut_kept_ems : Double = 4.0

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
    style=self.words_style(),
  )
  self.full_cut = self.wrap && self.max_lines > 0 && tl.line_start.length() > self.max_lines
  let tl = if self.full_cut { cut_to_lines(self, tl, max_w) } else { tl }
  self.full = Some(tl)
  self.full_max = max_w
  tl
}

///|
/// The style bits a text's words are shaped in: its digits all one width where it says so (Ctx::text `tabular`).
fn Node::words_style(self : Node) -> Int {
  if self.tabular {
    @hostapi.style_tabular
  } else {
    0
  }
}

///|
/// Its words said as `s` (one of its `shorter` ways), on one line.
fn Node::worded(self : Node, s : String) -> TextLayout {
  layout_text(s, self.font_size, self.weight, 1.0e9, false, line=self.line_h, trim=self.line_trim, spacing=self.spacing, style=self.words_style())
}

///|
/// Words on one line in `w`, all of them laid out (`tl`): those where they fit, else the longest of their shorter ways
/// that fits (Ctx::text `shorter`), else the shortest cut to `w` with an ellipsis.
fn Node::one_line_in(self : Node, tl : TextLayout, w : Double) -> TextLayout {
  if tl.w <= w + 0.5 {
    return tl
  }
  said_in(self.text, tl, self.shorter, w, fn(s) { self.worded(s) })
}

///|
/// Words on one line in `w`, said `said` (laid out as `tl`) or, where that does not fit, one of their `shorter` ways
/// (each shorter than the one before; `lay` lays words out on one line as they are drawn): the first that fits whole,
/// else the last cut to `w` with an ellipsis.
fn said_in(
  said : String,
  tl : TextLayout,
  shorter : Array[String],
  w : Double,
  lay : (String) -> TextLayout,
) -> TextLayout {
  if tl.w <= w + 0.5 {
    return tl
  }
  let mut said = said
  let mut last = tl
  for s in shorter {
    said = s
    last = lay(s)
    if last.w <= w + 0.5 {
      return last
    }
  }
  ellipsized(said, last, w, lay)
}

///|
/// One-line words (`s`, laid out as `tl` by `lay`) cut to fit `w`, ending in an ellipsis.
fn ellipsized(s : String, tl : TextLayout, w : Double, lay : (String) -> TextLayout) -> TextLayout {
  let shaped = tl.shaped
  let dots = lay("…")
  let room = w - dots.w
  let mut end = 0
  while end < shaped.starts.length() && tl.xs[end] + shaped.adv[end] <= room {
    end = end + 1
  }
  // no space left before the dots
  while end > 0 && shaped.cu[end - 1] == 32 {
    end = end - 1
  }
  let cut = if end < shaped.starts.length() { shaped.starts[end] } else { shaped.len }
  lay(s.view(end_offset=cut).to_string() + "…")
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
  let dots = layout_text("…", n.font_size, n.weight, 1.0e9, false, line=n.line_h, trim=n.line_trim, spacing=n.spacing, style=n.words_style())
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
  layout_text(text, n.font_size, n.weight, w, true, line=n.line_h, trim=n.line_trim, spacing=n.spacing, style=n.words_style())
}

///|
/// Whether a node is words on one line (Ctx::text's or Ctx::rich's, `wrap` false): never laid wider than a column they
/// are in, as wide as they are in a row unless they say otherwise (docs/style.md, Short of room).
fn Node::one_line_words(self : Node) -> Bool {
  (self.kind == kind_text || self.kind == kind_rich) && !self.wrap
}

///|
/// How wide words on one line are, all of them.
fn Node::one_line_w(self : Node) -> Double {
  if self.kind == kind_rich {
    // (as it was laid out, cut or not: laid out again only for other runs)
    if rich_same(self.rl_for, self.rich) && !self.rl_whole.is_nan() {
      return self.rl_whole
    }
    match self.rich_layout(1.0e9) {
      Some(rl) => rl.w
      None => 0.0
    }
  } else {
    self.text_layout(1.0e9).w
  }
}

///|
/// How wide words on one line are at least, shown whole: the shortest way they are said (Ctx::text `shorter`).
fn Node::one_line_least_w(self : Node) -> Double {
  match self.shorter {
    [.., last] if self.kind == kind_text => self.worded(last).w
    _ => self.one_line_w()
  }
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
    // (on one line wider than it may be, said a shorter way: as wide as that is)
    let tl = if !n.wrap && wm == AtMost && n.shorter.length() > 0 && tl.w > max_w + 0.5 {
      n.one_line_in(tl, max_w)
    } else {
      tl
    }
    (if wm == Exactly || (wm == AtMost && n.wrap && soft_wrapped(tl.line_end, tl.shaped.cu)) { w } else { tl.w }, tl.h)
  } else if n.kind == kind_rich {
    // (on one line, as wide as it is, as Ctx::text's words: cut, where it is, as it is placed narrower)
    match n.rich_layout(if n.wrap { max_w } else { 1.0e9 }) {
      Some(rl) => (if wm == Exactly || (wm == AtMost && n.wrap && soft_wrapped(rl.line_end, rl.cu)) { w } else { rl.w }, rl.h)
      None => (0.0, 0.0)
    }
  } else if n.kind == kind_editor {
    // an editor takes the width it is offered
    let (tw, th) = editor_words_laid(g().editor_display(n), n.font_size, n.weight, max_w, n.wrap, n.line_h, n.line_trim)
    (if wm == Undefined { tw } else { w }, th)
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
/// A side's inset as flex_tree sets it: a layer's from its parent's top left (`layer`); one put where it is said, from
/// the edges said, on whole pixels too where they are; NaN where none.
fn Ctx::inset_of(self : Ctx, v : Double, layer : Double, over : Bool, at : Bool, whole : Bool) -> Double {
  if over {
    layer
  } else if at && !v.is_nan() {
    self.on_px(v, whole)
  } else {
    0.0 / 0.0
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
  let mut ch = n.lk_epoch != self.epoch || n.lk_kind != n.kind
  // A slot may have held another kind of leaf: an image also writes lk_text, but does not replace the text's
  // layout. Its words matching those of the next text must not keep the layout of the text before that image.
  if !layout_reuse.val || n.lk_kind != n.kind {
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
  let pad_l = self.on_px(n.pad_l, whole)
  if pt_differs(s.padding_left_kind(), s.padding_left_value(), pad_l) {
    s.set_padding_left(Pt(pad_l))
    ch = true
  }
  let pad_t = self.on_px(n.pad_t, whole)
  if pt_differs(s.padding_top_kind(), s.padding_top_value(), pad_t) {
    s.set_padding_top(Pt(pad_t))
    ch = true
  }
  let pad_r = self.on_px(n.pad_r, whole)
  if pt_differs(s.padding_right_kind(), s.padding_right_value(), pad_r) {
    s.set_padding_right(Pt(pad_r))
    ch = true
  }
  let pad_b = self.on_px(n.pad_b, whole)
  if pt_differs(s.padding_bottom_kind(), s.padding_bottom_value(), pad_b) {
    s.set_padding_bottom(Pt(pad_b))
    ch = true
  }
  // margins (CSS's: below 0 too)
  let mar_l = self.on_px(n.mar_l, whole)
  if pt_differs(s.margin_left_kind(), s.margin_left_value(), mar_l) {
    s.set_margin_left(Pt(mar_l))
    ch = true
  }
  let mar_t = self.on_px(n.mar_t, whole)
  if pt_differs(s.margin_top_kind(), s.margin_top_value(), mar_t) {
    s.set_margin_top(Pt(mar_t))
    ch = true
  }
  let mar_r = self.on_px(n.mar_r, whole)
  if pt_differs(s.margin_right_kind(), s.margin_right_value(), mar_r) {
    s.set_margin_right(Pt(mar_r))
    ch = true
  }
  let mar_b = self.on_px(n.mar_b, whole)
  if pt_differs(s.margin_bottom_kind(), s.margin_bottom_value(), mar_b) {
    s.set_margin_bottom(Pt(mar_b))
    ch = true
  }
  let gap = self.on_px(n.gap, whole)
  // (a row in lines: `line_gap` between its lines where said)
  let lines = if n.flow && n.line_gap >= 0.0 { self.on_px(n.line_gap, whole) } else { gap }
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
  let min_h = self.on_px(n.min_h, whole)
  if opt_differs(s.min_height_kind(), s.min_height_value(), has_min_h, min_h) {
    s.set_min_height(if has_min_h { Pt(min_h) } else { Auto })
    ch = true
  }
  let has_max_h = n.max_h < 1.0e9
  let max_h = self.on_px(n.max_h, whole)
  if opt_differs(s.max_height_kind(), s.max_height_value(), has_max_h, max_h) {
    s.set_max_height(if has_max_h { Pt(max_h) } else { Auto })
    ch = true
  }
  let has_max_w = n.max_w < 1.0e9
  let max_w = self.on_px(n.max_w, whole)
  // (words on one line in a column, and what is said to be cut short there: never wider than the column, cut with an
  // ellipsis where it is narrower, whatever the column's alignment; as CSS's block with its overflow hidden. A max said
  // as well is that where the column has the room and the column's where it has less, CSS's min(100%, 560px): a card
  // as wide as its words up to 560 is not 560 in a column of 360)
  let capped = pdir == 2 && (n.w is Cut || (n.one_line_words() && !(n.w is Px(_))))
  if capped {
    let (k, v) = if has_max_w { (@flex.LEN_WITHIN, max_w) } else { (@flex.LEN_PCT, 100.0) }
    if s.max_width_kind() != k || s.max_width_value() != v {
      s.set_max_width(if has_max_w { Within(max_w) } else { Pct(100.0) })
      ch = true
    }
  } else if opt_differs(s.max_width_kind(), s.max_width_value(), has_max_w, max_w) {
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
      // (a least said below it: that width where its row has it, down to the least where it has less, as CSS's width
      // in a flex row with its min-width)
      if in_row && n.min_w > 0.0 && n.min_w < p {
        shrink = 1.0
      }
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
    Cut => if in_row { shrink = 1.0 }
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
    Auto | Cut => ()
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
  // (in a row of lines, what does not fit goes on the next line; one wider than a line alone is cut to it as far as
  // what it holds may give way, never below its least: CSS's flex-wrap)
  // what scrolls in itself, kept to the room its column has left (Ctx::capped `shrinks`)
  if in_col && n.shrinks {
    shrink = 1.0
  }
  if s.shrink != shrink {
    s.shrink = shrink
    ch = true
  }
  // (stretched past its most by its row: Ctx::capped `past_most`)
  if s.stretch_past_max != n.past_most {
    s.stretch_past_max = n.past_most
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
  // (cut short, never grown: in a column that stretches what it holds, at its start as wide as what it holds; in one
  // that centres or ends them, placed as it places them)
  let als : @flex.Align = if stretch {
    Stretch
  } else if in_col && n.w is Cut && n.parent >= 0 && self.nodes[n.parent].align is AStretch {
    FlexStart
  } else {
    Auto
  }
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
    let w = self.on_px(wpx, whole)
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
    let h = self.on_px(hpx, whole)
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
  let in_l = self.inset_of(n.at_l, 0.0, over, at, whole)
  if opt_differs(s.inset_left_kind(), s.inset_left_value(), !in_l.is_nan(), in_l) {
    s.set_inset_left(if in_l.is_nan() { Auto } else { Pt(in_l) })
    ch = true
  }
  let in_t = self.inset_of(n.at_t, 0.0, over, at, whole)
  if opt_differs(s.inset_top_kind(), s.inset_top_value(), !in_t.is_nan(), in_t) {
    s.set_inset_top(if in_t.is_nan() { Auto } else { Pt(in_t) })
    ch = true
  }
  let in_r = self.inset_of(n.at_r, 0.0 / 0.0, over, at, whole)
  if opt_differs(s.inset_right_kind(), s.inset_right_value(), !in_r.is_nan(), in_r) {
    s.set_inset_right(if in_r.is_nan() { Auto } else { Pt(in_r) })
    ch = true
  }
  let in_b = self.inset_of(n.at_b, 0.0 / 0.0, over, at, whole)
  if opt_differs(s.inset_bottom_kind(), s.inset_bottom_value(), !in_b.is_nan(), in_b) {
    s.set_inset_bottom(if in_b.is_nan() { Auto } else { Pt(in_b) })
    ch = true
  }
  let mut up = 0
  // (what it holds needs across at least, Node's `least`: its row's sum and how many, the widest under it; whether
  // its row may leave something out and what its ⋯ needs)
  let mut sum = 0.0
  let mut placed_in = 0
  let mut widest = 0.0
  let mut droppable = false
  let mut more_need = -1.0
  let mut fits = false
  // (the same, what it holds keeping what its row's fit keeps of it: Node's `fit_least`)
  let mut fsum = 0.0
  let mut fwidest = 0.0
  // (and what it comes to as a last resort: Node's `soft_least`)
  let mut ssum = 0.0
  let mut swidest = 0.0
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
        n.lk_shorter != n.shorter ||
        n.lk_size != n.font_size ||
        n.lk_weight != n.weight ||
        n.lk_line != n.line_h ||
        n.lk_trim != n.line_trim ||
        n.lk_wrap != n.wrap ||
        n.lk_spacing != n.spacing ||
        n.lk_tabular != n.tabular ||
        n.lk_max_lines != n.max_lines ||
        n.lk_shaped != words_shaped_in.val {
        n.lk_text = n.text
        n.lk_shorter = n.shorter
        n.lk_size = n.font_size
        n.lk_weight = n.weight
        n.lk_line = n.line_h
        n.lk_trim = n.line_trim
        n.lk_wrap = n.wrap
        n.lk_spacing = n.spacing
        n.lk_tabular = n.tabular
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
    let along = n.dir == Row && !n.flow
    let mut j = 0
    let mut c = n.first
    while c >= 0 {
      let cn = self.nodes[c]
      let r = self.flex_tree(c, pd)
      // what it needs across at least, with what is beside it in its row (all of it) or under it (the widest): what it
      // may leave out apart, its ⋯ with it where it may
      if !(cn.layer || cn.portal || cn.pager != 0 || cn.placed_at()) {
        let margins = self.on_px(cn.mar_l, whole) + self.on_px(cn.mar_r, whole)
        let need = cn.least + margins
        let fneed = cn.fit_least + margins
        let sneed = cn.soft_least + margins
        if along && n.one_of {
          // (ways of saying one thing, one of them shown: at least what the last, the shortest, needs)
          sum = need
          fsum = fneed
          ssum = sneed
          placed_in = 1
        } else if along && cn.drop > 0 {
          droppable = true
        } else if along && cn.drop == -1 {
          more_need = need
        } else if along {
          if placed_in > 0 {
            sum = sum + gap
            fsum = fsum + gap
            ssum = ssum + gap
          }
          sum = sum + need
          fsum = fsum + fneed
          ssum = ssum + sneed
          placed_in = placed_in + 1
        } else {
          widest = dmax(widest, need)
          fwidest = dmax(fwidest, fneed)
          swidest = dmax(swidest, sneed)
        }
        if cn.drop != 0 {
          fits = true
        }
      }
      if (r & 1) != 0 {
        ch = true
      }
      if (r & 2) != 0 ||
        cn.place is Some(_) ||
        cn.tx != cn.otx ||
        cn.ty != cn.oty ||
        cn.moved_by is Some(_) {
        up = 2
      }
      if j < kids.length() {
        // another node in this slot (one before it holds more or fewer than it did, or the slot holds another node
        // than it did: a list's row kept as its nodes put back elsewhere, kept_nodes.mbt): what it lays out changed
        if !physical_equal(kids[j], cn.fl) {
          kids[j] = cn.fl
          ch = true
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
  // left out of its row where it has not the room (Ctx::box `drop`), and a row that leaves something out
  if s.drop != n.drop {
    s.drop = n.drop
    ch = true
  }
  let one_of = n.one_of && n.dir == Row && !n.flow
  if s.one_of != one_of {
    s.one_of = one_of
    ch = true
  }
  // (what it leaves out left out as a row's are: drawn, pressed and read out nowhere)
  let fits = (fits || one_of) && n.dir == Row && !n.flow
  if s.fits != fits {
    s.fits = fits
    ch = true
  }
  // the least it is laid out across in a row: what it holds needs, where it is sized by that (a box with no width of
  // its own, words on one line in a row); one sized by the room it is given (Fill, a share) or cut by it (`clip`,
  // `sideways`) takes what it is given, what it holds squeezed in it where that is too little (Tester::squeeze_faults)
  let mut least = match n.w {
    // (giving way down to a least said below it: that)
    Px(p) => if n.min_w > 0.0 && n.min_w < p { 0.0 } else { self.on_px(p, whole) }
    Pct(_) | Cut => 0.0
    // (one said to keep what it holds: never less than that needs, the rest of its row squeezed first)
    Fill(_) if !(n.keep && k == kind_box) => 0.0
    Fill(_) | Auto =>
      if k == kind_box {
        if n.clip || n.sideways {
          0.0
        } else {
          // (one said to keep what it holds: what its row's fit keeps of it, words cut short in it four of their size,
          // so what is beside it gives way before they are cut further)
          let kept = n.w is Fill(_) && n.keep
          let (held, widest_held) = if kept { (fsum, fwidest) } else { (sum, widest) }
          let row = if more_need >= 0.0 && droppable {
            held + (if placed_in > 0 { gap } else { 0.0 }) + more_need
          } else {
            held
          }
          dmax(row, widest_held) + pad_l + pad_r
        }
      } else if pdir == 1 && n.one_line_words() {
        // (in a row, said its shortest way; in a column, cut to the column's width)
        n.one_line_least_w() + pad_l + pad_r
      } else {
        0.0
      }
  }
  let said_min = self.on_px(n.min_w, whole)
  // (a least that gives way to the parent's room is not what it needs: how much room that is, the layout knows)
  if n.min_w > 0.0 && !n.min_w_within {
    least = dmax(least, said_min)
  }
  if n.max_w < 1.0e9 {
    least = dmin(least, self.on_px(n.max_w, whole))
  }
  n.least = least
  // what its row's fit (Ctx::box drop) keeps of it before a part of the row leaves: words cut short four of their size
  // (all of them, fewer; all of them said to be kept: Ctx::text `keep`), what holds them as it holds them; else its
  // least
  let mut fit_least = if n.w is Cut && n.one_line_words() {
    let whole = n.one_line_least_w()
    (if n.keep { whole } else { dmin(whole, cut_kept_ems * n.font_size) }) + pad_l + pad_r
  } else if k == kind_box && (n.w is Auto || (n.w is Fill(_) && n.keep)) && !(n.clip || n.sideways) {
    let row = if more_need >= 0.0 && droppable {
      fsum + (if placed_in > 0 { gap } else { 0.0 }) + more_need
    } else {
      fsum
    }
    dmax(row, fwidest) + pad_l + pad_r
  } else {
    least
  }
  if n.min_w > 0.0 && !n.min_w_within {
    fit_least = dmax(fit_least, said_min)
  }
  if n.max_w < 1.0e9 {
    fit_least = dmin(fit_least, self.on_px(n.max_w, whole))
  }
  fit_least = dmax(fit_least, least)
  n.fit_least = fit_least
  // what it comes to as a last resort where its row has not the room for every least (docs/style.md, Short of room):
  // words on one line in a row that say not how they give, none of them; what holds such words, as it holds them,
  // but for what is pressed (a button, a chip: a control is never cut); else its least
  let mut soft_least = if k == kind_box &&
    (n.w is Auto || (n.w is Fill(_) && n.keep)) &&
    !(n.clip || n.sideways) &&
    !(n.id != 0 && n.hit) {
    let row = if more_need >= 0.0 && droppable {
      ssum + (if placed_in > 0 { gap } else { 0.0 }) + more_need
    } else {
      ssum
    }
    dmax(row, swidest) + pad_l + pad_r
  } else if n.w is Auto && pdir == 1 && n.one_line_words() {
    pad_l + pad_r
  } else {
    least
  }
  if n.min_w > 0.0 && !n.min_w_within {
    soft_least = dmax(soft_least, said_min)
  }
  soft_least = dmin(soft_least, least)
  n.soft_least = soft_least
  let fit_need = if fit_least > least + 0.01 { fit_least } else { 0.0 / 0.0 }
  if !(s.fit_need == fit_need || (s.fit_need.is_nan() && fit_need.is_nan())) {
    s.fit_need = fit_need
    ch = true
  }
  // in a row, sized by what it holds: never narrower than that needs (CSS's min-width: auto); else as said
  let within = n.min_w > 0.0 && n.min_w_within
  let min_w = if in_row && !over && !at && (n.w is Auto || (n.w is Fill(_) && n.keep)) {
    if within {
      dmax(least, said_min)
    } else {
      least
    }
  } else if n.min_w > 0.0 {
    said_min
  } else {
    0.0
  }
  let has_min_w = min_w > 0.0
  // less than that as a last resort, where it has some of it to give and its row is not one to scroll sideways nor
  // one that leaves it out (flex's soft_min, last_resort)
  let soft_min = if in_row &&
    !over &&
    !at &&
    !within &&
    n.drop == 0 &&
    !n.in_sideways &&
    !(n.parent >= 0 && self.nodes[n.parent].sideways) &&
    (n.w is Auto || (n.w is Fill(_) && n.keep)) &&
    soft_least < min_w - 0.01 {
    soft_least
  } else {
    0.0 / 0.0
  }
  if !(s.soft_min == soft_min || (s.soft_min.is_nan() && soft_min.is_nan())) {
    s.soft_min = soft_min
    ch = true
  }
  // (said to give way to the parent's room: that much where the parent has it, all of the parent's where it has less)
  if within {
    if s.min_width_kind() != @flex.LEN_WITHIN || s.min_width_value() != min_w {
      s.set_min_width(Within(min_w))
      ch = true
    }
  } else if opt_differs(s.min_width_kind(), s.min_width_value(), has_min_w, min_w) {
    s.set_min_width(if has_min_w { Pt(min_w) } else { Auto })
    ch = true
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
  // (placed on whole device pixels where the host sets things on them, as its lengths: whole_px_layout)
  @flex.compute(root, width=w, height=h, round=false, reuse=true, grid=if self.whole_px { self.scale } else { 0.0 })
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
/// Node `i` (built this frame) placed off where its parent lays it by what `f` gives from its size (w, h) at the
/// frame's time (a page sliding in: across by a share of its width), it and all it holds: laid out there, so drawn,
/// tapped and found there. Read as it is laid out, not followed, and again as the frame is painted, followed there:
/// what `f` reads (where a motion is: the clock) places it again as the next frame is painted, nothing built nor laid
/// out (Ctx::moved_place, frame_watch.mbt). `f` gives the same for the same state and time, however often asked.
pub fn Ctx::moved_by(self : Ctx, i : Int, f : (Double, Double) -> (Double, Double)) -> Unit {
  self.nodes[i].moved_by = Some(f)
  // (a motion, whatever said it before: Ctx::moved_carries)
  self.nodes[i].moved_carries = false
}

///|
/// Node `i` moved by `f` as Ctx::moved_by moves it, where that only carries it from where it is laid out to where it is
/// drawn (an old view's box, laid out once where its layout puts it, drawn where the window's tree draws it:
/// view_host.mbt old_frame): what measures the frame (gaps.mbt's shown_whole, squeeze's aside) takes where it is drawn
/// for its place, as it took the box placed there, not as a thing on its way.
fn Ctx::moved_carries(self : Ctx, i : Int, f : (Double, Double) -> (Double, Double)) -> Unit {
  self.nodes[i].moved_by = Some(f)
  self.nodes[i].moved_carries = true
}

///|
/// Where node `n`, `w` by `h`, is moved off its place by what moves it (Ctx::moved_by) at the frame's time: on the
/// device's pixels, so that what it holds moves by whole pixels (its words as crisp as at rest, as a look's move is:
/// draw.mbt), and a part kept in it is drawn again there as building it there draws it (kept_part.mbt). Read as it is
/// laid out, not followed: what moves it is read again, followed, as the frame is painted (Ctx::moved_place).
fn Ctx::moved_now(self : Ctx, n : Node, w : Double, h : Double) -> Unit {
  match n.moved_by {
    Some(f) => {
      let (dx, dy) = @signals.untracked(fn() { f(w, h) })
      n.moved_x = self.moved_on_pixels(n, dx)
      n.moved_y = self.moved_on_pixels(n, dy)
    }
    None => {
      n.moved_x = 0.0
      n.moved_y = 0.0
    }
  }
}

///|
/// How far node `n` is moved across or down by what moves it, `d` as that says: on the device's pixels (Ctx::moved_now);
/// what only carries it to where it is drawn (Ctx::moved_carries: an old view hosted in a node) as it says, which says
/// itself where that is on them (island_on_pixels: not where it is drawn bigger or smaller).
fn Ctx::moved_on_pixels(self : Ctx, n : Node, d : Double) -> Double {
  if n.moved_carries {
    d
  } else {
    on_pixels(d, self.scale)
  }
}

///|
/// How many times something drawn was moved off where it was by what moves it (Ctx::moved_shift), so far.
// kept across runs: only ever counted on
let moves_said : Ref[Int] = Ref(0)

///|
/// As the frame is painted (frame_paint), before anything of it: each node moved by what moves it (Ctx::moved_by) where
/// that has it at the frame's time, it and all it holds placed there as laid out: what that reads followed by the
/// paint, so that a frame where only it changed is painted again so, nothing built nor laid out (frame_watch.mbt). As
/// the frame is laid out where it is built whole, so nothing moves then.
fn Ctx::moved_place(self : Ctx) -> Unit {
  for i in 0..<self.count {
    let n = self.nodes[i]
    match n.moved_by {
      Some(f) => {
        let (dx, dy) = f(n.fw, n.fh)
        let mx = self.moved_on_pixels(n, dx)
        let my = self.moved_on_pixels(n, dy)
        if mx != n.moved_x || my != n.moved_y {
          self.moved_shift(i, mx - n.moved_x, my - n.moved_y)
          n.moved_x = mx
          n.moved_y = my
        }
      }
      None => ()
    }
  }
}

///|
/// Node `i` and all it holds, as laid out, placed `dx` across and `dy` down from where they are: what is placed with them
/// as they are laid out too (a field's words, where they start: layout.mbt's commit).
fn Ctx::moved_shift(self : Ctx, i : Int, dx : Double, dy : Double) -> Unit {
  // (what is where moved: the frame's targets found again, Ctx::view_targets)
  moves_said.val = moves_said.val + 1
  let n = self.nodes[i]
  n.x = n.x + dx
  n.y = n.y + dy
  if n.kind == kind_editor {
    match self.editors.get(n.id) {
      Some(st) => {
        // The node may have been restored from a kept layout, while its Field still holds the last placement.
        // Place the words from the node, rather than accumulating that placement's shift again.
        st.ox = n.x + n.pad_l - st.scroll_x
        st.oy = n.y + n.pad_t - st.scroll
      }
      None => ()
    }
  }
  let mut c = n.first
  while c >= 0 {
    self.moved_shift(c, dx, dy)
    c = self.nodes[c].next
  }
}

///|
/// Places a subtree laid out as before under its parent's new origin
/// (px, py): what commit would make of it, without its leaves' layouts.
fn Ctx::replace(self : Ctx, i : Int, px : Double, py : Double) -> Unit {
  let n = self.nodes[i]
  let f = n.fl
  n.by_size(f.width, f.height)
  self.moved_now(n, f.width, f.height)
  n.x = px + f.left + n.tx + n.moved_x
  n.y = py + f.top + n.ty + n.moved_y
  if n.kind == kind_editor {
    match self.editors.get(n.id) {
      Some(st) => {
        st.ox = n.x + n.pad_l - st.scroll_x
        st.oy = n.y + n.pad_t - st.scroll
      }
      None => ()
    }
  }
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
  // (an old view's box: what its rows make as they are laid out is that old view's own, let go with it, and built in
  // it, as what it builds is: view_host.mbt)
  if !old_box_owners.is_empty() && old_box_owners.get(i) is Some((o, island)) {
    let was = @signals.set_owner(o)
    let was_island = island_building.val
    island_building.val = Some(island)
    self.commit_at(i, px, py, gen)
    island_building.val = was_island
    @signals.set_owner(was) |> ignore
  } else {
    self.commit_at(i, px, py, gen)
  }
}

///|
fn Ctx::commit_at(self : Ctx, i : Int, px : Double, py : Double, gen : Int) -> Unit {
  let n = self.nodes[i]
  let f = n.fl
  if n.same && f.laid_out_at() != gen {
    n.by_size(f.width, f.height)
    self.moved_now(n, f.width, f.height)
    let x = px + f.left + n.tx + n.moved_x
    let y = py + f.top + n.ty + n.moved_y
    n.otx = n.tx
    n.oty = n.ty
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
  self.moved_now(n, f.width, f.height)
  n.x = px + f.left + n.tx + n.moved_x
  n.y = py + f.top + n.ty + n.moved_y
  n.fw = f.width
  n.fh = f.height
  let ix = n.x + n.pad_l
  let iy = n.y + n.pad_t
  let iw = dmax(n.fw - n.pad_l - n.pad_r, 0.0)
  let ih = dmax(n.fh - n.pad_t - n.pad_b, 0.0)
  if n.kind == kind_text {
    let tl = n.text_layout(iw)
    n.tl = Some(if n.wrap { tl } else { n.one_line_in(tl, iw) })
  } else if n.kind == kind_rich {
    n.rich_layout(iw) |> ignore
  } else if n.kind == kind_editor {
    match self.editors.get(n.id) {
      Some(st) => {
        let tl = layout_text(st.shown(), n.font_size, n.weight, iw, n.wrap, line=n.line_h, trim=n.line_trim, style=faces_style(st.words, 0))
        st.tl = Some(tl)
        // taller than the field: scrolled so that the caret's line shows; a field of more lines, where it was scrolled
        // to (the wheel, a finger, its bar: Ctx::editor) until the caret or the words change
        let (cx, cl) = st.place_of(tl, st.caret + st.marked.length())
        if n.wrap {
          st.scroll_x = 0.0
        } else {
          let room = dmax(0.0, iw - caret_w)
          if cx < st.scroll_x {
            st.scroll_x = cx
          } else if cx > st.scroll_x + room {
            st.scroll_x = cx - room
          }
          st.scroll_x = dmax(0.0, dmin(st.scroll_x, dmax(0.0, tl.w - room)))
        }
        let top = cl.to_double() * tl.line_h
        let most = dmax(0.0, tl.h - ih)
        let sw = sideways.get(n.id)
        let was = match sw {
          Some(s) => s.x
          None => st.scroll
        }
        let now = (st.caret, st.anchor, st.text.length() + st.marked.length())
        st.scroll = was
        if sw is None || now != st.followed {
          st.followed = now
          if top - st.scroll < 0.0 {
            st.scroll = top
          } else if top + tl.line_h - st.scroll > ih {
            st.scroll = top + tl.line_h - ih
          }
        }
        st.scroll = dmax(0.0, dmin(st.scroll, most))
        match sw {
          Some(s) => {
            s.max = most
            s.x = st.scroll
            // (brought to the caret where its bar was drawn: it scrolled)
            if st.scroll != was && self.bar_drawn(n.id) is Some(_) {
              self.sideways_scrolled(s)
            }
          }
          None => ()
        }
        st.ox = ix - st.scroll_x
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
