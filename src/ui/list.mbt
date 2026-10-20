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
/// Rows `0..<k` laid end to end: how far row k's top is below row 0's.
fn ListState::above(self : ListState, k : Int) -> Double {
  let mut i = imin(k, self.sums.length() - 1)
  let mut t = 0.0
  while i > 0 {
    t = t + self.sums[i]
    i = i - (i & -i)
  }
  t
}

///|
/// A row more at the end, not measured yet.
fn ListState::add_row(self : ListState) -> Unit {
  self.heights.push(-1.0)
  if self.sums.length() == 0 {
    self.sums.push(0.0)
  }
  // node i holds rows i - lowbit(i) until i (1-based)
  let i = self.sums.length()
  self.sums.push(self.est + self.above(i - 1) - self.above(i - (i & -i)))
}

///|
/// Row `k` measured at `h`.
fn ListState::set_height(self : ListState, k : Int, h : Double) -> Unit {
  let d = h - self.height(k)
  self.heights[k] = h
  if d != 0.0 {
    let mut i = k + 1
    while i < self.sums.length() {
      self.sums[i] = self.sums[i] + d
      i = i + (i & -i)
    }
  }
}

///|
/// The sums again from the heights (rows came or went in the middle).
fn ListState::resum(self : ListState) -> Unit {
  self.sums.clear()
  self.sums.push(0.0)
  for k in 0..<self.heights.length() {
    self.sums.push(self.height(k))
  }
  // each node passes what it holds on to the one above it
  let n = self.sums.length()
  for i in 1..<n {
    let j = i + (i & -i)
    if j < n {
      self.sums[j] = self.sums[j] + self.sums[i]
    }
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
  self.ease = 0.0
  self.ease_done = 0.0
  self.stop()
  self.unstretch()
  self.at_end = true
}

///|
fn Ctx::scroll_list(self : Ctx, id : Int, d : Double) -> Unit {
  match self.lists.get(id) {
    Some(st) => {
      st.pending = st.pending + d
      self.scrolled(st)
      st.glide = false
    }
    None => ()
  }
}

///|
/// A wheel's notch's ease out (ms): its time constant, 1 - 1/e of the notch come by then.
pub let wheel_ease_ms : Double = 36.0

///|
/// A wheel's notch on list `id`: scrolled by `d` over the next frames (eased out, as a browser eases one), not at
/// once.
fn Ctx::ease_list(self : Ctx, id : Int, d : Double) -> Unit {
  match self.lists.get(id) {
    Some(st) => {
      // what had not come yet, and this notch: eased in from now (said once, as it sets out)
      st.ease = st.ease - st.ease_done + d
      st.ease_done = 0.0
      st.ease_t0 = self.now
      self.scrolled(st)
      st.glide = false
    }
    None => ()
  }
}

///|
/// How much of a wheel's ease of `total` has come `t` ms after it set out: solved for the time (an ease out of
/// wheel_ease_ms), in whole 1/64 px, all of it from ease_end on. The same at any time whatever frames it went by.
fn ease_come(total : Double, t : Double) -> Double {
  if t >= ease_end(total) {
    total
  } else {
    (total * (1.0 - @math.exp(-t / wheel_ease_ms)) * 64.0).round() / 64.0
  }
}

///|
/// When an ease of `total` has all come (ms after it set out): what is left under 1/128 px.
fn ease_end(total : Double) -> Double {
  if total.abs() * 128.0 <= 1.0 {
    0.0
  } else {
    wheel_ease_ms * @math.ln(total.abs() * 128.0)
  }
}

///|
/// How long a list's scroll bar shows after it was last scrolled (ms), then how long it fades out.
pub let scrollbar_hold_ms : Double = 600.0

///|
pub let scrollbar_fade_ms : Double = 300.0

///|
/// When list `key` (asked where it is built) is at rest: its wheel's ease come and its scroll bar gone (the frames'
/// clock; before now: it is).
pub fn Ctx::list_rest(self : Ctx, key : String) -> Double {
  match self.lists.get(self.id(key)) {
    Some(st) => st.rest_at(self.now, self.frame_no)
    None => -1.0
  }
}

///|
/// List `st` scrolled now: its scroll bar shows (and then fades) from now, said as what moves.
fn Ctx::scrolled(self : Ctx, st : ListState) -> Unit {
  st.last_scroll = self.now
  self.moving(st.ease_mover, st as &Moving, what="a list's wheel ease and scroll bar")
}

///|
/// What moves of a list by itself: a wheel's ease (at rest at its end) and its scroll bar (gone once faded).
impl Moving for ListState with rest_at(self, now, frame) {
  ignore(now)
  // not built this frame: nothing shows it, at rest (shown again, it says so again: Ctx::list)
  if self.built != frame {
    return -1.0
  }
  if self.glide && self.glide_t0 == @double.infinity {
    return @double.infinity
  }
  let bar = self.last_scroll + scrollbar_hold_ms + scrollbar_fade_ms
  let eased = if self.ease == 0.0 { -1.0 } else { self.ease_t0 + ease_end(self.ease) }
  let glided = if self.glide { self.glide_rest } else { -1.0 }
  dmax(bar, dmax(eased, glided))
}

///|
/// What of a wheel's notches has come by this frame (Ctx::ease_list): how much the ease has come to now (ease_come,
/// solved for the time) less what had come by the last.
fn Ctx::step_ease(self : Ctx, st : ListState) -> Unit {
  if st.ease == 0.0 {
    return
  }
  let came = ease_come(st.ease, self.now - st.ease_t0)
  st.pending = st.pending + (came - st.ease_done)
  st.ease_done = came
  self.scrolled(st)
  if came == st.ease {
    st.ease = 0.0
    st.ease_done = 0.0
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
      self.scrolled(st)
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
  glide_on_growth? : Bool = false,
) -> Int {
  let id = self.id(key)
  let st = match self.lists.get(id) {
    Some(s) => s
    None => {
      let s = {
        anchor: 0,
        anchor_off: 0.0,
        heights: [],
        sums: [],
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
        glide_t0: 0.0,
        glide_l0: 0.0,
        glide_rest: -1.0,
        glide_left: 0.0,
        built: -1,
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
        ease: 0.0,
        ease_t0: 0.0,
        ease_done: 0.0,
        ease_mover: Mover::new(),
        vw: 0.0,
        vh: 0.0,
        sel: false,
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
    st.add_row()
  }
  st.count = count
  st.row = row
  st.seed = self.id_seed
  st.owner = self.owner
  st.vw = self.width
  st.vh = self.height
  st.sel = desk.selecting
  // shown again (not built the frame before): what of it still moves says so again
  let back = st.built >= 0 && st.built < self.frame_no - 1
  st.built = self.frame_no
  if back && st.rest_at(self.now, self.frame_no) > self.now {
    self.moving(st.ease_mover, st as &Moving, what="a list's wheel ease, glide and scroll bar")
  }
  self.step_ease(st)
  self.step_glide(st)
  self.step_scroll(st)
  // with `glide_on_growth`, rows come at the end while it is at its end: it glides after them from where it was
  // (still.fail's Follow), rather than being put at its end at once
  if self.list_grew(id, count) && glide_on_growth && st.stick_end && st.at_end && !self.still() {
    st.at_end = false
    self.glide_to_end(st)
  }
  let i = self.alloc_part(kind_list, true, false)
  let n = self.nodes[i]
  n.id = id
  n.w = w
  n.h = h
  n.clip = true
  n.bg = bg
  i
}

///|
/// Builds row `k` of list node `li` (appended to its children).
fn Ctx::build_row(self : Ctx, li : Int, st : ListState, k : Int) -> Int {
  let saved_cur = self.cur
  let saved_seed = self.id_seed
  let saved_owner = self.owner
  let (saved_w, saved_h) = (self.width, self.height)
  let saved_sel = desk.selecting
  desk.selecting = st.sel
  self.cur = li
  self.id_seed = st.seed
  self.owner = st.owner
  // built for the size the list was given (Ctx::sized), not the window's
  if st.vw > 0.0 {
    self.width = st.vw
    self.height = st.vh
  }
  let r = self.alloc(kind_box)
  self.nodes[r].item = k
  let row = st.row
  self.with_parent(r, fn() { self.scope(k, fn() { row(k) }) })
  self.id_seed = saved_seed
  self.cur = saved_cur
  self.owner = saved_owner
  self.width = saved_w
  self.height = saved_h
  desk.selecting = saved_sel
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
  // how it stood after the last layout (Ctx::list_info): what was built from that is drawn again if this one moves it
  let was = (st.vis_first, st.vis_last, st.at_end, st.below)
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
    st.set_height(k, h)
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
  // what the view built this frame read from the list as it stood (a way back to the end, the rows in view told): a
  // frame more where this layout changed that (a scroll that took one frame, a wheel's or a key's, would otherwise
  // leave it drawn as before the scroll until something else asked for a frame)
  if was != (st.vis_first, st.vis_last, st.at_end, st.below) {
    self.request_frame()
  }
  if st.glide {
    // how far it is above its end: the rows not laid out by their heights as known (measured, or estimated)
    let left = if last == st.count - 1 {
      bottom - bottom_edge
    } else {
      st.above(st.count) - st.above(last + 1) + (bottom - bottom_edge)
    }
    st.glide_left = left
    if st.glide_t0 == @double.infinity {
      // it sets out at its first layout: its way said once (what is left of it e^(-t/list_glide_ms), at its end once
      // under a pixel)
      st.glide_t0 = self.now
      st.glide_l0 = left
      st.glide_rest = if left < 1.0 { self.now } else { self.now + (list_glide_ms * @math.ln(left)).ceil() }
    }
    if left < 1.0 {
      st.glide = false
      st.at_end = true
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
      if age > scrollbar_hold_ms + scrollbar_fade_ms || st.count == 0 {
        return
      }
      let fade = if age < scrollbar_hold_ms { 1.0 } else { 1.0 - (age - scrollbar_hold_ms) / scrollbar_fade_ms }
      let total = st.above(st.count)
      let before = st.above(imin(st.anchor, st.count))
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
      self.request_frame()
    }
    None => ()
  }
}

///|
/// Back to list `key`'s end: gliding there (what is left of the way e^(-t/list_glide_ms) of it, as still.fail's lists
/// follow their newest; far from it, more than list_glide_rows rows, at once), or at once.
pub fn Ctx::list_to_end(self : Ctx, key : String, glide? : Bool = true) -> Unit {
  match self.lists.get(self.id(key)) {
    Some(st) => {
      if glide {
        st.stop()
        self.glide_to_end(st)
      } else {
        st.scroll_to_end()
      }
      self.request_frame()
    }
    None => ()
  }
}

///|
/// A glide to the end's time constant (ms): 1 - 1/e of the way left gone by then.
pub let list_glide_ms : Double = 100.0

///|
/// Further than this many rows from its end (as last laid out), a glide to it goes at once.
let list_glide_rows : Int = 12

///|
/// List `st` sets out for its end (Ctx::list_to_end, a row come at its end): said once, as it sets out; its way is
/// solved at its next layout, where it knows how far it is (step_glide).
fn Ctx::glide_to_end(self : Ctx, st : ListState) -> Unit {
  if st.vis_last >= 0 && st.count - 1 - st.vis_last > list_glide_rows {
    st.scroll_to_end()
    st.glide = false
    return
  }
  st.glide = true
  st.glide_t0 = @double.infinity
  st.glide_rest = -1.0
  self.moving(st.ease_mover, st as &Moving, what="a list gliding to its end")
}

///|
/// Where a glide to the end is at this frame: what is left of it as a function of the time since it set out, the
/// list moved by what it is further than that; at its end from its rest on.
fn Ctx::step_glide(self : Ctx, st : ListState) -> Unit {
  if !st.glide || st.glide_t0 == @double.infinity {
    return
  }
  if self.now >= st.glide_rest {
    st.scroll_to_end()
    st.glide = false
    return
  }
  let want = st.glide_l0 * @math.exp(-(self.now - st.glide_t0) / list_glide_ms)
  if st.glide_left > want {
    st.pending = st.pending + (st.glide_left - want)
  }
}

///|
/// Scrolls list `key` by `dy` (down when positive), as a wheel does.
pub fn Ctx::list_scroll_by(self : Ctx, key : String, dy : Double) -> Unit {
  self.scroll_list(self.id(key), dy)
  self.request_frame()
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
/// Where list `key` is, after its last layout: the first row in view, how far its top is above the view's, and that
/// row's height (a reader's place inside a block taller than the window). None before its first layout.
pub fn Ctx::list_place(self : Ctx, key : String) -> (Int, Double, Double)? {
  match self.lists.get(self.id(key)) {
    Some(st) if st.vis_first >= 0 && st.vis_first < st.heights.length() =>
      Some((st.vis_first, st.anchor_off, st.heights[st.vis_first]))
    _ => None
  }
}

///|
/// Row `item` of list `key`'s height as last laid out; None while it has not been.
pub fn Ctx::list_row_height(self : Ctx, key : String, item : Int) -> Double? {
  match self.lists.get(self.id(key)) {
    Some(st) if item >= 0 && item < st.heights.length() && st.heights[item] >= 0.0 =>
      Some(st.heights[item])
    _ => None
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
  self.resum()
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

///|
/// Whether list `key` (in this scope) moves: a finger on it, flung, gliding or springing back from an end.
pub fn Ctx::list_moving(self : Ctx, key : String) -> Bool {
  match self.lists.get(self.id(key)) {
    Some(st) => st.held || st.moving() || st.glide
    None => false
  }
}

///|
/// How many rows each list had (Ctx::list_grew).
let list_counts : Map[Int, Int] = {}

///|
/// Whether list `id` has more rows than when it was last built.
fn Ctx::list_grew(self : Ctx, id : Int, count : Int) -> Bool {
  ignore(self)
  let was = list_counts.get(id)
  list_counts[id] = count
  match was {
    Some(n) => count > n && n > 0
    None => false
  }
}
