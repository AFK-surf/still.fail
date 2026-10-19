// A virtualized list of rows of different heights. Only the rows on screen
// are built. The scroll position is an anchor (an item and an offset into
// it), so rows measured for the first time never make the content jump.

///|
fn ListState::height(self : ListState, i : Int) -> Double {
  let h = self.heights[i]
  if h >= 0.0 {
    h
  } else {
    self.est
  }
}

///|
fn ListState::scroll_to(self : ListState, item : Int) -> Unit {
  self.anchor = item
  self.anchor_off = 0.0
  self.pending = 0.0
  self.stop()
  self.unstretch()
  self.at_end = false
}

///|
fn ListState::unstretch(self : ListState) -> Unit {
  self.over = 0.0
  self.over_edge = 0
  self.over_state = 0
  self.over_v = 0.0
}

///|
fn ListState::scroll_to_end(self : ListState) -> Unit {
  // the last row, scrolled past further than it can be: laid out, it
  // comes back to end at the bottom
  self.anchor = 1 << 30
  self.anchor_off = 1.0e9
  self.pending = 0.0
  self.stop()
  self.unstretch()
  self.at_end = true
}

///|
fn Ctx::scroll_list(self : Ctx, id : Int, d : Double) -> Unit {
  match self.lists.get(id) {
    Some(st) => {
      st.pending = st.pending + d
      st.last_scroll = self.now
      st.glide = false
    }
    None => ()
  }
}

///|
/// Home, End, Page Up and Page Down, and the arrows by a line, for the
/// list under the pointer.
fn Ctx::list_key(self : Ctx, id : Int, code : Int) -> Bool {
  match self.lists.get(id) {
    Some(st) => {
      if code == key_home {
        st.scroll_to(0)
      } else if code == key_end {
        st.scroll_to_end()
      } else if code == key_page_up {
        self.scroll_list(id, -(st.vp_h - 40.0))
      } else if code == key_page_down {
        self.scroll_list(id, st.vp_h - 40.0)
      } else if code == key_up {
        self.scroll_list(id, -40.0)
      } else if code == key_down {
        self.scroll_list(id, 40.0)
      } else {
        return false
      }
      st.last_scroll = self.now
      true
    }
    None => false
  }
}

///|
/// A list of `count` rows; `row(i)` builds row i. Only rows in view are
/// built, while the list is laid out, so it knows their real heights;
/// rows not built yet count as `est` pixels (for the scroll bar). With
/// `stick_end` it starts at its end and stays there as rows come, until
/// scrolled away.
pub fn Ctx::list(
  self : Ctx,
  key : String,
  count : Int,
  est : Double,
  row : (Int) -> Unit,
  w? : Size = Fill(1.0),
  h? : Size = Fill(1.0),
  stick_end? : Bool = false,
  bg? : Int64 = 0L,
) -> Int {
  let id = self.id(key)
  let st = match self.lists.get(id) {
    Some(s) => s
    None => {
      let s = {
        anchor: 0,
        anchor_off: 0.0,
        heights: [],
        est,
        count: 0,
        vp_h: 600.0,
        vel: 0.0,
        at_end: stick_end,
        stick_end,
        last_scroll: -1.0e9,
        pending: 0.0,
        row,
        seed: 0,
        vis_first: -1,
        vis_last: -1,
        owner: self.owner,
        below: 1.0e9,
        glide: false,
        fling: 0,
        fling_v: 0.0,
        fling_t0: -1.0,
        fling_dist: 0.0,
        fling_dur: 0.0,
        fling_done: 0.0,
        drag_pending: 0.0,
        held: false,
        over: 0.0,
        over_edge: 0,
        over_state: 0,
        over_v: 0.0,
        over_t: -1.0,
      }
      self.lists[id] = s
      self.own(id)
      s
    }
  }
  if self.bench_list == 0 {
    self.bench_list = id
  }
  while st.heights.length() < count {
    st.heights.push(-1.0)
  }
  st.count = count
  st.row = row
  st.seed = self.id_seed
  st.owner = self.owner
  self.step_scroll(st)
  let i = self.alloc_part(kind_list, true, false)
  let n = self.nodes[i]
  n.id = id
  n.w = w
  n.h = h
  n.clip = true
  n.bg = bg
  if self.now - st.last_scroll < 900.0 {
    self.wake_at_time(st.last_scroll + 900.0)
  }
  i
}

///|
/// Builds row `k` of list node `li` (appended to its children).
fn Ctx::build_row(self : Ctx, li : Int, st : ListState, k : Int) -> Int {
  let saved_cur = self.cur
  let saved_seed = self.id_seed
  let saved_owner = self.owner
  self.cur = li
  self.id_seed = st.seed
  self.owner = st.owner
  let r = self.alloc(kind_box)
  self.nodes[r].item = k
  let row = st.row
  self.with_parent(r, fn() { self.scope(k, fn() { row(k) }) })
  self.id_seed = saved_seed
  self.cur = saved_cur
  self.owner = saved_owner
  r
}

///|
/// Moves a laid-out subtree down by `dy`.
fn Ctx::shift(self : Ctx, i : Int, dy : Double) -> Unit {
  let n = self.nodes[i]
  n.y = n.y + dy
  if n.kind == kind_editor {
    match self.editors.get(n.id) {
      Some(st) => st.oy = st.oy + dy
      None => ()
    }
  }
  let mut c = n.first
  while c >= 0 {
    self.shift(c, dy)
    c = self.nodes[c].next
  }
}

///|
/// Lays out the list in its content box: builds rows from the one the
/// scroll position is anchored to (or the last, when it sticks to its
/// end), downward and then upward until the view is full, never past
/// either end. Positions come from the rows' real heights, so scrolling
/// moves rows by exactly what was scrolled, measured or not.
fn Ctx::place_list(
  self : Ctx,
  li : Int,
  ix : Double,
  iy : Double,
  iw : Double,
  ih : Double,
) -> Unit {
  let n = self.nodes[li]
  let st = match self.lists.get(n.id) {
    Some(st) => st
    None => return
  }
  st.vp_h = ih
  // rows built in the build phase (none, normally) are not shown
  n.first = -1
  n.last = -1
  if st.count == 0 {
    st.anchor = 0
    st.anchor_off = 0.0
    st.pending = 0.0
    st.at_end = true
    st.vis_first = -1
    st.vis_last = -1
    st.drag_pending = 0.0
    return
  }
  let nan = 0.0 / 0.0
  let top_rows : Array[Int] = [] // above the pivot, nearest first
  let rows : Array[Int] = [] // the pivot and below
  let lay = fn(k : Int, y : Double) -> (Int, Double) {
    let r = self.build_row(li, st, k)
    let h = self.layout(r, ix, y, iw, nan)
    st.heights[k] = h
    (r, h)
  }
  let bottom_edge = iy + ih
  let mut top = 0.0
  let mut bottom = 0.0
  let mut first = 0
  let mut last = 0
  // how far what was scrolled went past the end and the start, and whether
  // it did (a finger pulls with it, a fling stops there)
  let mut blocked_end = 0.0
  let mut blocked_top = 0.0
  let mut hit_end = false
  let mut hit_top = false
  if st.stick_end && st.at_end && st.pending >= 0.0 {
    blocked_end = st.pending
    hit_end = st.pending > 0.0
    // the last row's bottom on the view's
    let (r, h) = lay(st.count - 1, 0.0)
    self.shift(r, bottom_edge - h)
    rows.push(r)
    top = bottom_edge - h
    bottom = bottom_edge
    first = st.count - 1
    last = st.count - 1
  } else {
    let a = imax(imin(st.anchor, st.count - 1), 0)
    let y = iy - st.anchor_off - st.pending
    let (r, h) = lay(a, y)
    rows.push(r)
    top = y
    bottom = y + h
    first = a
    last = a
  }
  st.pending = 0.0
  let mut pinned_end = false
  // down, then up, then down again if the start was reached
  for pass in 0..<2 {
    while bottom < bottom_edge && last + 1 < st.count {
      last = last + 1
      let (r, h) = lay(last, bottom)
      rows.push(r)
      bottom = bottom + h
    }
    if bottom < bottom_edge && pass == 0 {
      // the end: no space after it
      let d = bottom_edge - bottom
      for r in rows {
        self.shift(r, d)
      }
      for r in top_rows {
        self.shift(r, d)
      }
      top = top + d
      bottom = bottom_edge
      pinned_end = true
      blocked_end = blocked_end + d
      hit_end = true
    }
    while top > iy && first > 0 {
      first = first - 1
      let (r, h) = lay(first, 0.0)
      self.shift(r, top - h)
      top_rows.push(r)
      top = top - h
    }
    if top > iy {
      // the start: no space before it
      let d = iy - top
      for r in rows {
        self.shift(r, d)
      }
      for r in top_rows {
        self.shift(r, d)
      }
      blocked_top = blocked_top - d
      hit_top = true
      top = iy
      bottom = bottom + d
      pinned_end = false
    } else {
      break
    }
  }
  // the children, top to bottom
  let order : Array[Int] = []
  for j = top_rows.length() - 1; j >= 0; j = j - 1 {
    order.push(top_rows[j])
  }
  for r in rows {
    order.push(r)
  }
  let mut prev = -1
  for r in order {
    if prev >= 0 {
      self.nodes[prev].next = r
    } else {
      n.first = r
    }
    self.nodes[r].next = -1
    prev = r
  }
  n.last = prev
  // the new scroll position: the first row in view, and how far it is
  // scrolled past
  st.vis_first = -1
  st.vis_last = -1
  for r in order {
    let rn = self.nodes[r]
    if rn.y + rn.fh > iy + 0.001 && rn.y < bottom_edge - 0.001 {
      if st.vis_first < 0 {
        st.vis_first = rn.item
        st.anchor = rn.item
        st.anchor_off = iy - rn.y
      }
      st.vis_last = rn.item
    }
  }
  st.at_end = last == st.count - 1 && (pinned_end || bottom <= bottom_edge + 0.5)
  st.below = if last == st.count - 1 { bottom - bottom_edge } else { 1.0e9 }
  if st.glide {
    // each frame the same share of what is left (1 - e^(-dt/100ms)), at
    // least a pixel; far below what is laid out, most of the way at once
    if last == st.count - 1 {
      let left = bottom - bottom_edge
      if left < 1.0 {
        st.glide = false
        st.at_end = true
      } else {
        let step = left * (1.0 - 2.718281828459045.pow(-self.dt / 100.0))
        st.pending = if step < 1.0 { dmin(left, 1.0) } else { step }
        self.wants_frame = true
      }
    } else if st.count - 1 - last > 12 {
      st.scroll_to_end()
      self.wants_frame = true
    } else {
      st.pending = ih
      self.wants_frame = true
    }
  }
  // a finger pulls past the end it reached; a fling stops there
  let drag = st.drag_pending
  st.drag_pending = 0.0
  if st.held {
    if drag > 0.0 && blocked_end > 0.0 {
      self.pull(st, -1, dmin(blocked_end, drag))
    } else if drag < 0.0 && blocked_top > 0.0 {
      self.pull(st, 1, dmin(blocked_top, -drag))
    }
  } else if st.vel > 0.0 && hit_end {
    self.absorb(st, -1, st.vel)
  } else if st.vel < 0.0 && hit_top {
    self.absorb(st, 1, st.vel)
  }
  // iOS's rubber band moves the rows past the end
  let off = st.over_offset()
  if off != 0.0 {
    for r in order {
      self.shift(r, off)
    }
  }
}

///|
fn Ctx::paint_scrollbar(self : Ctx, n : Node, alpha : Double) -> Unit {
  match self.lists.get(n.id) {
    Some(st) => {
      let age = self.now - st.last_scroll
      if age > 900.0 || st.count == 0 {
        return
      }
      let fade = if age < 600.0 { 1.0 } else { 1.0 - (age - 600.0) / 300.0 }
      let mut total = 0.0
      let mut before = 0.0
      for i in 0..<st.count {
        let h = st.height(i)
        if i < st.anchor {
          before = before + h
        }
        total = total + h
      }
      let vp = n.fh
      if total <= vp + 1.0 {
        return
      }
      let off = before + st.anchor_off
      let th = dmax(28.0, vp * vp / total)
      let ty = n.y + (off / (total - vp)) * (vp - th)
      let a = (0.45 * fade * alpha * 255.0).to_int().to_int64()
      self.emit_rect(
        n.x + n.fw - 8.0,
        dclamp(ty, n.y, n.y + vp - th),
        5.0,
        th,
        2.5,
        0x00000000L | a,
        0.0,
        0L,
        0.0,
      )
    }
    None => ()
  }
}

///|
/// Scrolls list `key` (as given to Ctx::list in the same scope) so row
/// `item` is at its top (`offset` below it: its top that far above the
/// view's, or below it when negative), the end kept in view.
pub fn Ctx::list_scroll_to(
  self : Ctx,
  key : String,
  item : Int,
  offset? : Double = 0.0,
) -> Unit {
  match self.lists.get(self.id(key)) {
    Some(st) => {
      st.scroll_to(item)
      st.anchor_off = offset
      self.wants_frame = true
    }
    None => ()
  }
}

///|
/// Back to list `key`'s end: gliding there (each frame a share of the way
/// left, as still.fail's lists follow their newest), or at once.
pub fn Ctx::list_to_end(self : Ctx, key : String, glide? : Bool = true) -> Unit {
  match self.lists.get(self.id(key)) {
    Some(st) => {
      if glide {
        st.stop()
        st.glide = true
      } else {
        st.scroll_to_end()
      }
      self.wants_frame = true
    }
    None => ()
  }
}

///|
/// Scrolls list `key` by `dy` (down when positive), as a wheel does.
pub fn Ctx::list_scroll_by(self : Ctx, key : String, dy : Double) -> Unit {
  self.scroll_list(self.id(key), dy)
  self.wants_frame = true
}

///|
/// How a list stood when it was last laid out.
pub(all) struct ListInfo {
  count : Int
  /// the first and the last row in view (-1 when none)
  first : Int
  last : Int
  /// at its end, nothing below the view
  at_end : Bool
  /// how far the last row's bottom is below the view's (1e9 when the last
  /// row was not laid out)
  below : Double
  /// gliding to its end (list_to_end)
  gliding : Bool
}

///|
/// How list `key` stood after the last layout; None before its first.
pub fn Ctx::list_info(self : Ctx, key : String) -> ListInfo? {
  match self.lists.get(self.id(key)) {
    Some(st) =>
      Some({
        count: st.count,
        first: st.vis_first,
        last: st.vis_last,
        at_end: st.at_end,
        below: st.below,
        gliding: st.glide,
      })
    None => None
  }
}

///|
/// Rows came (`n` > 0) or went (`n` < 0) before row `at` of list `key`
/// since it was last laid out: what is in view stays where it is. Where
/// the first row in view is above `at` (a spinner over the rows, say), the
/// row that was at `at` is kept in place instead, the new rows coming in
/// above it. Call before the list is laid out (while building).
pub fn Ctx::list_moved(self : Ctx, key : String, at : Int, n : Int) -> Unit {
  match self.lists.get(self.id(key)) {
    Some(st) => st.moved(at, n)
    None => ()
  }
}

///|
fn ListState::moved(self : ListState, at : Int, n : Int) -> Unit {
  if n == 0 || at < 0 {
    return
  }
  let was = self.heights.copy()
  self.heights.clear()
  for i in 0..<imin(at, was.length()) {
    self.heights.push(was[i])
  }
  if n > 0 {
    for _ in 0..<n {
      self.heights.push(-1.0)
    }
  }
  let from = if n < 0 { at - n } else { at }
  for i in from..<was.length() {
    self.heights.push(was[i])
  }
  if self.stick_end && self.at_end {
    return
  }
  if self.anchor >= at {
    self.anchor = imax(at, self.anchor + n)
  } else if n > 0 {
    let mut off = self.anchor_off
    for i in self.anchor..<at {
      off = off - self.height(i)
    }
    self.anchor = at + n
    self.anchor_off = off
  }
}
