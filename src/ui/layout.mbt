// Layout: the tree goes to the flexbox engine in mbui/flex (checked against
// Yoga's tests) as a tree of flex nodes, one kept on each node of the pool.
// Text, editors and lists are its measured leaves; a list lays out its own
// rows, each as a tree of its own.

///|
fn Ctx::editor_display(self : Ctx, n : Node) -> String {
  match self.editors.get(n.id) {
    Some(st) => st.display()
    None => ""
  }
}

///|
/// The text laid out in `max_w`. The engine asks for a few widths per frame;
/// greedy wrapping gives the same lines for any width from the widest line
/// up to the one it was laid out in, so one layout serves them all.
fn Node::text_layout(self : Node, max_w : Double) -> TextLayout {
  match self.tl {
    Some(tl) if !self.wrap || (tl.w <= max_w + 0.01 && max_w <= self.tl_max) =>
      return tl
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
  self.tl = Some(tl)
  self.tl_max = max_w
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
  } else if n.kind == kind_editor {
    // an editor takes the width it is offered
    let s = g.editor_display(n)
    let tl = layout_text(s, n.font_size, n.weight, max_w, true)
    (if wm == Undefined { tl.w } else { w }, tl.h)
  } else if n.kind == kind_image {
    image_leaf_size(n, w, wm, h, hm)
  } else {
    // a list fills what it is given, and has no height of its own
    (if wm == Undefined { 0.0 } else { w }, if hm == Exactly { h } else { 0.0 })
  }
}

///|
/// The flex node for node `i` and its subtree, styled from the builder's
/// sizes: Fill along the parent's direction grows from nothing, across it
/// stretches; content-sized children of a row may shrink (and wrap), except
/// text that must stay on one line.
fn Ctx::flex_tree(self : Ctx, i : Int, parent : Dir?) -> @flex.Node {
  let n = self.nodes[i]
  let f = n.fl
  let s = f.style
  s.reset()
  f.children.clear()
  f.measure = None
  s.direction = if n.dir == Row { Row } else { Column }
  s.padding.left = Pt(n.pad_l)
  s.padding.top = Pt(n.pad_t)
  s.padding.right = Pt(n.pad_r)
  s.padding.bottom = Pt(n.pad_b)
  s.gap_row = Pt(n.gap)
  s.gap_col = Pt(n.gap)
  s.align_items = match n.align {
    AStart => FlexStart
    ACenter => Center
    AEnd => FlexEnd
    AStretch => Stretch
  }
  s.justify = match n.justify {
    JStart => FlexStart
    JCenter => Center
    JEnd => FlexEnd
    JBetween => SpaceBetween
  }
  if n.min_h > 0.0 {
    s.min_height = Pt(n.min_h)
  }
  if n.max_h < 1.0e9 {
    s.max_height = Pt(n.max_h)
  }
  if n.min_w > 0.0 {
    s.min_width = Pt(n.min_w)
  }
  if n.max_w < 1.0e9 {
    s.max_width = Pt(n.max_w)
  }
  let in_row = parent == Some(Row)
  let in_col = parent == Some(Column)
  match n.w {
    Px(p) => s.width = Pt(p)
    Fill(k) =>
      if in_row {
        s.grow = k
        s.shrink = 1.0
        s.basis = Pt(0.0)
      } else if in_col {
        s.align_self = Stretch
      }
    Auto =>
      if in_row && !(n.kind == kind_text && !n.wrap) {
        s.shrink = 1.0
      }
  }
  if n.pager != 0 || n.layer {
    // a pager's pages lie over each other, moved sideways as they turn
    s.position = Absolute
    s.inset.left = Pt(0.0)
    s.inset.top = Pt(0.0)
    s.width = Pct(100.0)
    s.height = Pct(100.0)
  }
  match n.h {
    Px(p) => s.height = Pt(p)
    Fill(k) =>
      if in_col {
        s.grow = k
        s.shrink = 1.0
        s.basis = Pt(0.0)
      } else if in_row {
        s.align_self = Stretch
      }
    Auto => ()
  }
  if n.kind == kind_text ||
    n.kind == kind_editor ||
    n.kind == kind_list ||
    n.kind == kind_image {
    f.measure = n.leaf
  } else {
    let mut c = n.first
    while c >= 0 {
      f.children.push(self.flex_tree(c, Some(n.dir)))
      c = self.nodes[c].next
    }
  }
  f
}

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
  let root = self.flex_tree(i, None)
  @flex.compute(root, width=w, height=h, round=false)
  self.commit(i, x, y)
  root.height
}

///|
/// Copies the flex engine's results back as absolute rectangles (with each
/// node's visual offset, which its subtree follows), and lays out what is
/// inside the leaves.
fn Ctx::commit(self : Ctx, i : Int, px : Double, py : Double) -> Unit {
  let n = self.nodes[i]
  if n.pager != 0 {
    self.place_pager_slot(i)
  }
  let f = n.fl
  n.x = px + f.left + n.tx
  n.y = py + f.top + n.ty
  n.fw = f.width
  n.fh = f.height
  let ix = n.x + n.pad_l
  let iy = n.y + n.pad_t
  let iw = dmax(n.fw - n.pad_l - n.pad_r, 0.0)
  let ih = dmax(n.fh - n.pad_t - n.pad_b, 0.0)
  if n.kind == kind_text {
    let tl = n.text_layout(iw)
    if !n.wrap && tl.w > iw + 0.5 {
      n.tl = Some(ellipsized(n, tl, iw))
    }
  } else if n.kind == kind_editor {
    match self.editors.get(n.id) {
      Some(st) => {
        st.tl = Some(layout_text(st.display(), n.font_size, n.weight, iw, true))
        st.ox = ix
        st.oy = iy
      }
      None => ()
    }
  } else if n.kind == kind_list {
    self.place_list(i, ix, iy, iw, ih)
  } else {
    let mut c = n.first
    while c >= 0 {
      self.commit(c, n.x, n.y)
      c = self.nodes[c].next
    }
  }
}
