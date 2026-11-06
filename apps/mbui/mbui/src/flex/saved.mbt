///|
/// What a compute writes of a node, kept whole (its sizes, its place, its caches, what it was asked: every field a
/// compute sets, the arrays it writes into copied), to be put back by Node::restore: a layout worked out for another
/// moment and let go, the node as it was. Its style, its children and what measures it are not a compute's and are not
/// kept.
pub fn Node::saved(self : Node) -> Node {
  {
    style: self.style,
    children: self.children,
    measure: self.measure,
    layout_children: self.layout_children,
    sized_by_children: self.sized_by_children,
    on_room: self.on_room,
    room_said: self.room_said,
    room_w: self.room_w,
    room_h: self.room_h,
    sizing: self.sizing,
    sizing_w: self.sizing_w,
    sizing_h: self.sizing_h,
    left: self.left,
    top: self.top,
    width: self.width,
    height: self.height,
    line: self.line,
    cache: self.cache.copy(),
    cache_n: self.cache_n,
    cache_gen: self.cache_gen,
    box_cbw: self.box_cbw,
    box_cbh: self.box_cbh,
    box_memo: self.box_memo,
    box_ver: self.box_ver,
    dirty: self.dirty,
    p_ok: self.p_ok,
    laid_grid: self.laid_grid,
    p_gen: self.p_gen,
    p_kw: self.p_kw,
    p_kh: self.p_kh,
    p_cbw: self.p_cbw,
    p_cbh: self.p_cbh,
    p_w: self.p_w,
    p_h: self.p_h,
    laid_gen: self.laid_gen,
    pre_gen: self.pre_gen,
    pre: if self.pre.length() == 0 { self.pre } else { self.pre.copy() },
    skip_gen: self.skip_gen,
  }
}

///|
/// The node put back as Node::saved kept it (what a compute writes; its style, children and measuring left as they are).
pub fn Node::restore(self : Node, s : Node) -> Unit {
  self.room_said = s.room_said
  self.room_w = s.room_w
  self.room_h = s.room_h
  self.sizing = s.sizing
  self.sizing_w = s.sizing_w
  self.sizing_h = s.sizing_h
  self.left = s.left
  self.top = s.top
  self.width = s.width
  self.height = s.height
  self.line = s.line
  self.cache = s.cache
  self.cache_n = s.cache_n
  self.cache_gen = s.cache_gen
  self.box_cbw = s.box_cbw
  self.box_cbh = s.box_cbh
  self.box_memo = s.box_memo
  self.box_ver = s.box_ver
  self.dirty = s.dirty
  self.p_ok = s.p_ok
  self.laid_grid = s.laid_grid
  self.p_gen = s.p_gen
  self.p_kw = s.p_kw
  self.p_kh = s.p_kh
  self.p_cbw = s.p_cbw
  self.p_cbh = s.p_cbh
  self.p_w = s.p_w
  self.p_h = s.p_h
  self.laid_gen = s.laid_gen
  self.pre_gen = s.pre_gen
  self.pre = s.pre
  self.skip_gen = s.skip_gen
}
