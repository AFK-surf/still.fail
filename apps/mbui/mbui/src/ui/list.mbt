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
    // (laid out other than it was had: what was built from what it had, built again)
    self.learned = self.learned + 1
    self.heights_learned.set(self.learned)
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
  self.ease_v = 0.0
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
      // (scrolled at once by the hand: a trackpad's, a key's page; rows_steady's)
      st.put_at = self.clock
      self.scrolled(st)
      st.glide = false
      st.follow_item = -1
    }
    None => ()
  }
}

///|
/// A wheel's notch's ease (ms): the time constant of the follow its notches are eased in by, critically damped, as a
/// browser eases one (Chromium's smooth scroll, ~200 ms a notch): one from rest sets out slowly, half of it come by
/// 1.7 of these (71 ms), 95 in 100 by 4.7 (200 ms). A notch turned while another is coming carries on from where the
/// list is and how fast it moves then, so a wheel turned on scrolls at its pace, not in a burst a notch (an ease out of
/// 36 ms from each notch, 2026-10-26: a notch every 80 ms moved the list eight times faster at it than between).
pub let wheel_ease_ms : Double = 42.0

///|
/// A wheel's notch on list `id`, turned at `at` (the event's moment, not before the last frame): scrolled by `d` over
/// the next frames (eased: ease_come), not at once. What had not come yet carries on into it: the follow taken over at
/// `at`, where it is and as fast as it moves then (ease_state), toward all that is left of it and this notch.
fn Ctx::ease_list(self : Ctx, id : Int, d : Double, at : Double) -> Unit {
  match self.lists.get(id) {
    Some(st) => {
      // (from the notch's own moment, said once as it sets out: a list at rest since its last frame, long ago, eases
      // it in from now, not all of it at once at the next frame)
      let at = dmax(at, self.clock)
      let (came, v) = if st.easing() {
        ease_state(st.ease, st.ease_v, at - st.ease_t0)
      } else {
        (0.0, 0.0)
      }
      st.ease = st.ease - came + d
      st.ease_v = v
      // (what the last frame put on of it, from where it is taken over: short of it as far as it had come since)
      st.ease_done = st.ease_done - came
      st.ease_t0 = at
      self.scrolled(st)
      st.glide = false
      st.follow_item = -1
    }
    None => ()
  }
}

///|
/// Whether a wheel's ease is under way (its follow: a way to go, or a speed left as it was taken over just short of it).
fn ListState::easing(self : ListState) -> Bool {
  self.ease != 0.0 || self.ease_v != 0.0
}

///|
/// How much of a wheel's ease of `total` has come `t` ms after it set out at `v0` (px a ms, the way `total` goes when
/// positive): solved for the time (critically damped, wheel_ease_ms: what is left (total + (total / τ - v0) t)
/// e^(-t / τ)), in whole 1/64 px, all of it from ease_end on. The same at any time whatever frames it went by.
fn ease_come(total : Double, v0 : Double, t : Double) -> Double {
  if t >= ease_end(total, v0) {
    total
  } else {
    let left = (total + (total / wheel_ease_ms - v0) * t) * @dmath.exp(-t / wheel_ease_ms)
    ((total - left) * 64.0).round() / 64.0
  }
}

///|
/// Where an ease (ease_come) is `t` ms after it set out, and how fast it moves then (px a ms): what a notch turned then
/// takes over (Ctx::ease_list).
fn ease_state(total : Double, v0 : Double, t : Double) -> (Double, Double) {
  let t = dmax(0.0, t)
  if t >= ease_end(total, v0) {
    (total, 0.0)
  } else {
    let k = total / wheel_ease_ms - v0
    (ease_come(total, v0, t), (v0 + k * t / wheel_ease_ms) * @dmath.exp(-t / wheel_ease_ms))
  }
}

///|
/// When an ease of `total` set out at `v0` has all come (ms after it set out): what is left under 1/128 px from then on.
/// What is left is at most (|total| + |k| t) e^(-t / τ) (k = total / τ - v0), and t e^(-t / 4τ) at most 4τ / e: so at
/// most (|total| + 4 |k| τ / e) e^(-3t / 4τ), under 1/128 from the time solved here (a little after the least).
fn ease_end(total : Double, v0 : Double) -> Double {
  let k = (total / wheel_ease_ms - v0).abs()
  let most = (total.abs() + 4.0 * k * wheel_ease_ms / @dmath.exp(1.0)) * 128.0
  if most <= 1.0 {
    0.0
  } else {
    wheel_ease_ms * 4.0 / 3.0 * @dmath.ln(most)
  }
}

///|
/// When list `key` (asked where it is built) is at rest: its wheel's ease come, its fling and its overscroll over and
/// its scroll bar gone (the frames' clock; before now: it is).
pub fn Ctx::list_rest(self : Ctx, key : String) -> Double {
  match self.lists.get(self.id(key)) {
    Some(st) => {
      // (where its own motions have it at the frame's time, what that leaves to come: read so)
      self.list_step(st)
      st.rest_at(self.clock, self.frame_no)
    }
    None => -1.0
  }
}

///|
/// List `st`'s own motions (a wheel's ease, a fling, a glide to its end, an overscroll going back, what scrolls toward
/// the pointer) where they have it at the frame's time: worked out once a frame, where it is first asked (its layout,
/// Ctx::place_list; what is built asking when it rests, Ctx::list_rest), from what was said as each set out.
fn Ctx::list_step(self : Ctx, st : ListState) -> Unit {
  if st.stepped == self.frame_no {
    return
  }
  st.stepped = self.frame_no
  self.step_ease(st)
  self.step_edge(st)
  self.step_glide(st)
  self.step_scroll(st)
}

///|
/// List `st` scrolled now: its scroll bar shows (and then fades) from now, said as what moves.
fn Ctx::scrolled(self : Ctx, st : ListState) -> Unit {
  st.bar.wake(self.clock, st.shown_until())
  st.last_scroll = self.clock
  self.moving(st.ease_mover, st as &Moving, what="a list's wheel ease and scroll bar")
}

///|
/// Whether list `id` showed scrolling past its view the frame before (its bar was drawn, shown or not): moved by the
/// app now (sent to a row, to its end), it scrolls and its bar shows; else (just shown, its rows just come) it is put
/// there.
fn Ctx::list_shown(self : Ctx, id : Int) -> Bool {
  self.bar_drawn(id) is Some(_)
}

///|
/// List `id` (`st`) moved by the app (Ctx::list_scroll_to, list_to_end, a row come at the end it follows): scrolled,
/// where it showed.
fn Ctx::app_scrolled(self : Ctx, id : Int, st : ListState, put? : Bool = true) -> Unit {
  // (put elsewhere at once: what it shows moves for no row's cause, rows_steady.mbt; held at its end as rows come,
  // what is in view stays where its rows have it)
  if put {
    st.put_at = self.clock
  }
  if self.list_shown(id) {
    self.scrolled(st)
  }
}

///|
/// What moves of a list by itself: a wheel's ease (at rest at its end), its fling and its overscroll going back (at
/// their ends: scroll_path.mbt) and its scroll bar (gone once faded).
impl Moving for ListState with rest_at(self, now, frame) {
  // not built this frame: nothing shows it, at rest (shown again, it says so again: Ctx::list)
  if self.built != frame {
    return -1.0
  }
  if (self.glide && self.glide_t0 == @double.infinity) || self.edge_v != 0.0 {
    return @double.infinity
  }
  // (its own motions, and its bar's after them: a finger's list has none, its rest theirs)
  let mut t = self.bar.rest(now, self.shown_until())
  if self.easing() {
    t = dmax(t, self.ease_t0 + ease_end(self.ease, self.ease_v))
  }
  if self.fling != 0 && self.vel != 0.0 {
    t = dmax(t, self.fling_rest())
  }
  if self.over_state == 2 {
    t = dmax(t, self.back_rest())
  }
  if self.glide {
    t = dmax(t, self.glide_rest)
  }
  t
}

///|
/// When the list is at rest by itself (ListInfo's `rest`).
fn ListState::own_rest(self : ListState) -> Double {
  if self.held || (self.glide && self.glide_t0 == @double.infinity) || self.edge_v != 0.0 {
    return @double.infinity
  }
  let mut t = -1.0
  if self.fling != 0 && self.vel != 0.0 {
    t = dmax(t, self.fling_rest())
  }
  if self.over_state == 2 {
    t = dmax(t, self.back_rest())
  }
  if self.easing() {
    t = dmax(t, self.ease_t0 + ease_end(self.ease, self.ease_v))
  }
  if self.glide {
    t = dmax(t, self.glide_rest)
  }
  t
}

///|
/// Until when the list is scrolled, its scroll bar shown before it fades: its last scroll, the end of its fling or of
/// its overscroll going back while one goes on, of its glide to its end where it showed as that set out (+inf: one
/// not set out yet).
fn ListState::shown_until(self : ListState) -> Double {
  let mut t = self.last_scroll
  if self.fling != 0 && self.vel != 0.0 {
    t = dmax(t, self.fling_rest())
  }
  if self.over_state == 2 {
    t = dmax(t, self.back_rest())
  }
  if self.glide && self.glide_shows {
    t = dmax(t, if self.glide_t0 == @double.infinity { @double.infinity } else { self.glide_rest })
  }
  t
}

///|
/// What of a wheel's notches has come by this frame (Ctx::ease_list): how much the ease has come to now (ease_come,
/// solved for the time) less what had come by the last.
fn Ctx::step_ease(self : Ctx, st : ListState) -> Unit {
  if !st.easing() {
    return
  }
  let t = dmax(0.0, self.now() - st.ease_t0)
  let came = ease_come(st.ease, st.ease_v, t)
  st.pending = st.pending + (came - st.ease_done)
  st.ease_done = came
  self.scrolled(st)
  if t >= ease_end(st.ease, st.ease_v) {
    st.ease = 0.0
    st.ease_v = 0.0
    st.ease_done = 0.0
  }
}

///|
/// What it has scrolled toward the pointer since the last frame, words picked past its shown edge (Ctx::edge_scroll).
fn Ctx::step_edge(self : Ctx, st : ListState) -> Unit {
  if st.edge_v == 0.0 {
    return
  }
  st.pending = st.pending + st.edge_v * dmax(0.0, self.now() - st.edge_t)
  st.edge_t = self.clock
  self.scrolled(st)
  st.glide = false
  st.follow_item = -1
}

///|
/// List `id` scrolls toward the pointer at `v` (px a ms, the way a wheel scrolls it; 0: no more), from now
/// (Ctx::step_edge), as words are picked with the pointer held past its shown edge (desktop.mbt).
fn Ctx::edge_scroll(self : Ctx, id : Int, v : Double) -> Unit {
  match self.lists.get(id) {
    Some(st) if st.edge_v != v => {
      if st.edge_v == 0.0 {
        st.edge_t = self.clock
      }
      st.edge_v = v
      self.scrolled(st)
    }
    _ => ()
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
/// scrolled away. With `rows_read`, `row(i)` shows only what it reads (signals,
/// the core's topics, row i's own of them) and nothing else it is given: a row
/// is kept as its nodes while nothing it read changed, however what builds the
/// list is built again (kept_nodes.mbt); without, what builds the list built
/// again builds its rows anew. A Tester holds it: each frame that kept a row is
/// built again keeping none and must come out the same. `sized`: what changed
/// its rows' heights, by their keys (ListRows::sized): each laid out as tall as
/// its way to its new height has it now (list_size.mbt). `from_end`: rows short of
/// its view stand at its end, the room left over them (a chat's: what comes pushes
/// what is over it up from the first, as once it is full, never down then up).
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
  rows_read? : Bool = false,
  sized? : RowCauses,
  from_end? : Bool = false,
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
        bones: 0L,
        vis_first: -1,
        vis_last: -1,
        owner: self.owner,
        below: 1.0e9,
        glide: false,
        glide_t0: 0.0,
        glide_l0: 0.0,
        glide_rest: -1.0,
        glide_left: 0.0,
        glide_meant: -1.0,
        follow_item: -1,
        follow_margin: 0.0,
        built: -1,
        stepped: -1,
        fresh: true,
        rows_read: false,
        glide_shows: false,
        bar: Bar::new(),
        laid: -1,
        pinned_by: 0.0,
        began: (0, 0.0, 0.0, false, false),
        left: (0, 0.0, 0.0, false, false),
        glide_began: (0.0, 0.0, -1.0, 0.0, -1.0),
        scroll_asked: (-1, 0, 0.0),
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
        back: BackPath::new(),
        ease: 0.0,
        ease_v: 0.0,
        ease_t0: 0.0,
        ease_done: 0.0,
        ease_mover: Mover::new(),
        learned: 0,
        heights_learned: @signals.signal(0),
        hand_said: @signals.signal(0),
        moving_said: @signals.signal(false),
        edge_v: 0.0,
        edge_t: 0.0,
        vw: 0.0,
        vh: 0.0,
        sel: false,
        theme: self.theme,
        direction: self.direction,
        layer: self.layer_cur,
        causes: None,
        sizes: {},
        sizes_end: -1.0,
        from_end: false,
        put_at: -1.0,
        shown_h: {},
        sizes_mover: Mover::new(),
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
  // what changed its rows' heights, by their keys (list_size.mbt ListRows)
  st.causes = sized
  st.from_end = from_end
  st.seed = self.id_seed
  st.bones = self.bones
  st.owner = self.owner
  st.vw = self.width
  st.vh = self.height
  st.sel = desk.selecting
  st.theme = self.theme
  st.direction = self.direction
  st.layer = self.layer_cur
  // (rows that show only what they read are kept however what builds them was built: their own watches say when
  // they change; only a build keeping none builds them anew)
  st.rows_read = rows_read
  st.fresh = if rows_read { nodes_run.whole } else { nodes_run.fresh || nodes_run.part_fresh }
  // shown again (not built the frame before): what of it still moves says so again (where it is at the frame's time
  // is its layout's to work out: Ctx::place_list)
  let back = st.built >= 0 && st.built < self.frame_no - 1
  st.built = self.frame_no
  if back && st.rest_at(self.clock, self.frame_no) > self.clock {
    self.moving(st.ease_mover, st as &Moving, what="a list's wheel ease, glide and scroll bar")
  }
  // with `glide_on_growth`, rows come at the end while it is at its end: it glides after them from where it was
  // (still.fail's Follow), rather than being put at its end at once; put there, it scrolled all the same
  if self.list_grew(id, count) && st.stick_end && st.at_end {
    if glide_on_growth && !self.still() {
      st.at_end = false
      self.glide_to_end(id, st)
    } else {
      self.app_scrolled(id, st, put=false)
    }
  }
  let i = self.alloc_part(kind_list, true, false)
  let n = self.nodes[i]
  n.id = id
  self.id_built(i)
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
  let saved_bones = self.bones
  let (saved_w, saved_h) = (self.width, self.height)
  let saved_sel = desk.selecting
  let (saved_theme, saved_dir, saved_layer) = (self.theme, self.direction, self.layer_cur)
  desk.selecting = st.sel
  self.theme = st.theme
  self.direction = st.direction
  self.layer_cur = st.layer
  self.cur = li
  self.id_seed = st.seed
  self.owner = st.owner
  self.bones = st.bones
  // built for the size the list was given (Ctx::sized), not the window's
  if st.vw > 0.0 {
    self.width = st.vw
    self.height = st.vh
  }
  // (who it is: its item, however many rows were built before it)
  let r = self.alloc_part(kind_box, true, true, key=item_key(k))
  self.nodes[r].item = k
  let row = st.row
  // (what its content reads of its rows' way: Ctx::row_way)
  let laid_by = rows_laid_by.val
  rows_laid_by.val = st.causes.map(fn(c) { (c, k) })
  self.with_parent(r, fn() { self.scope(k, fn() { row(k) }) })
  rows_laid_by.val = laid_by
  self.id_seed = saved_seed
  self.cur = saved_cur
  self.owner = saved_owner
  self.bones = saved_bones
  self.width = saved_w
  self.height = saved_h
  desk.selecting = saved_sel
  self.theme = saved_theme
  self.direction = saved_dir
  self.layer_cur = saved_layer
  r
}

///|
/// Moves a laid-out subtree down by `dy`.
fn Ctx::shift(self : Ctx, i : Int, dy : Double) -> Unit {
  self.moved_shift(i, 0.0, dy)
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
  // (shown this frame: what its rows came, went and changed for, said from the next, ListRows::rows)
  match st.causes {
    Some(c) => c.laid = self.frame_no
    None => ()
  }
  // where its own motions have it at the frame's time (a wheel's ease, a fling, a glide to its end, an overscroll going
  // back), stepped at its first layout in a frame, and what the hand did to it between frames: read as it is laid out,
  // so that what is laid out again as they go is its layout, nothing built for them (frame_watch.mbt's layout watch)
  st.hand_said.get() |> ignore
  self.list_step(st)
  self.shows_motion(st.ease_mover, st.rest_at(self.clock, self.frame_no) > self.clock)
  self.shows_motion(st.sizes_mover, st.sizes_rest() > self.clock)
  // laid out again in the same frame (built again from what its layout read: readback.mbt), from where it stood as
  // the frame's first layout of it began, unless something moved it since its last: a row laid there for the first
  // time may have been laid at a height it does not keep (a fold's words whole until it knows how tall they are), and
  // where the list stood said from that row would move what is in view by what the row lost (to the end, past it)
  // (and gliding to its end as it was then: a glide that set out at the first, its end not yet grown, is under way
  // again, not over with the list short of its end)
  let now = (st.anchor, st.anchor_off, st.pending, st.at_end, st.glide)
  if st.laid == self.frame_no && now == st.left {
    st.anchor = st.began.0
    st.anchor_off = st.began.1
    st.pending = st.began.2
    st.at_end = st.began.3
    st.glide = st.began.4
    let (t0, l0, rest, left, meant) = st.glide_began
    st.glide_t0 = t0
    st.glide_l0 = l0
    st.glide_rest = rest
    st.glide_left = left
    st.glide_meant = meant
  } else {
    st.began = now
    st.glide_began = (st.glide_t0, st.glide_l0, st.glide_rest, st.glide_left, st.glide_meant)
  }
  st.laid = self.frame_no
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
    st.moving_said.set(st.held || st.moving() || st.glide)
    return
  }
  let nan = 0.0 / 0.0
  let top_rows : Array[Int] = [] // above the pivot, nearest first
  let rows : Array[Int] = [] // the pivot and below
  let lay = fn(k : Int, y : Double) -> (Int, Double) {
    // (kept as its nodes where nothing it shows changed: kept_nodes.mbt)
    let (r, h) = self.row_laid(li, st, k, ix, y, iw)
    // as tall as what changed its height has it now (list_size.mbt), what it holds cut there
    let shown = st.row_sized(k, h, self.clock, self.frame_no)
    // (as tall as it is laid out once there: a row kept as its nodes keeps what it was last cut to otherwise)
    let sized = (shown - h).abs() > 0.001
    // (cut there too while what is in it goes to its height on the rows' way: what leaves it is not drawn past it)
    self.nodes[r].clip = sized || st.row_own_way(k, self.clock)
    // (one coming or going where it is: what its room cuts off it fading out to its edges, ListRows::enter, leave)
    // what it holds laid out in the middle of its room, so drawn, tapped and found there; where its row lays it
    // otherwise (put there from where its row lays it, not moved on from where it was: a row kept as its nodes keeps
    // where they were put last)
    let middle = sized && st.row_by_room(k)
    if middle {
      dr.rows_soft.push((r, row_soft(shown, h)))
    }
    let by = if middle { st.row_middle(k, shown, h) } else { 0.0 }
    // (what comes and goes in it, where something in it is so: not what it is drawn on, Node's `room_held`)
    for ch in (if st.causes is Some(_) { self.room_held_in(r) } else { [] }) {
      let n = self.nodes[ch]
      let pn = self.nodes[n.parent]
      let d = pn.y + n.fl.top + n.ty + n.moved_y + by - n.y
      if d != 0.0 {
        self.shift(ch, d)
      }
    }
    let h = if sized {
      self.nodes[r].fh = shown
      self.row_slot(r, shown)
    } else {
      self.nodes[r].fh = h
      h
    }
    st.set_height(k, h)
    st.row_shown(k, h)
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
  // held at its end with a row followed from its top (Ctx::list_follow_from): laid from that row's top `follow_margin`
  // under the view's, down; short of the view, the end pass below holds it at its end all the same. Held there, not
  // past the row's top, however the list came to its end (glided, or put there at once: a row in over its end rows)
  let follows = st.follow_item >= 0 && st.follow_item < st.count
  if st.stick_end && st.at_end && st.pending >= 0.0 && follows {
    let y = iy + st.follow_margin - st.pending
    let (r, h) = lay(st.follow_item, y)
    rows.push(r)
    top = y
    bottom = y + h
    first = st.follow_item
    last = st.follow_item
  } else if st.stick_end && st.at_end && st.pending >= 0.0 {
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
  // (what the hand scrolled toward the end since the last layout: of a shortfall at the end, that much is its)
  let scrolled_down = dmax(st.pending, 0.0)
  st.pending = 0.0
  st.pinned_by = 0.0
  let mut pinned_end = false
  // down, then up, then down again if the start was reached
  for pass in 0..<2 {
    // (and down to a row followed from its top, while gliding to it: its top is where the glide goes)
    while (bottom < bottom_edge || (st.glide && st.follow_item > last)) && last + 1 < st.count {
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
      st.pinned_by = dmax(d - scrolled_down, 0.0)
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
    // (its last row's foot on the view's: laid from its end, or put there short of it)
    if top > iy && st.from_end && (bottom - bottom_edge).abs() < 0.001 {
      // short of its view, standing at its end: the room left over its rows
      hit_top = true
      break
    } else if top > iy {
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
      // (put back up as far: short of the view, it moved its rows none so)
      st.pinned_by = dmax(st.pinned_by + d, 0.0)
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
  // held at its end: where its first row in view stands said from the end (the view's bottom less the rows from it
  // down), the same however it got there, not by the float error of laying from where it was and moving back
  if pinned_end && st.vis_first >= 0 {
    let mut below_top = 0.0
    let mut from = false
    for r in order {
      let rn = self.nodes[r]
      if rn.item == st.vis_first {
        from = true
      }
      if from {
        below_top = below_top + rn.fh
      }
    }
    st.anchor_off = iy - (bottom_edge - below_top)
  }
  // (at its end where its last row's foot is at the view's, but for the float error of laying it there: one moved off it
  // by less than a point, a finger's first moves, a trackpad's, is off it, and is laid where it was moved, not put back)
  st.at_end = last == st.count - 1 && (pinned_end || bottom <= bottom_edge + 0.001)
  st.below = if last == st.count - 1 { bottom - bottom_edge } else { 1.0e9 }
  // (what the view built this frame read of how the list stood, a way back to the end, the rows in view told, is read
  // back where it was read: Ctx::list_info; a list scrolled that nothing read builds nothing again)
  if st.glide {
    // how far it is above its end: the rows not laid out by their heights as known (measured, or estimated)
    let to_end = if last == st.count - 1 {
      bottom - bottom_edge
    } else {
      st.above(st.count) - st.above(last + 1) + (bottom - bottom_edge)
    }
    // a row followed from its top: its top `follow_margin` under the view's, or the end, whichever comes first
    // (Follow.kt left)
    let mut left = to_end
    if st.follow_item >= 0 {
      for r in order {
        let rn = self.nodes[r]
        if rn.item == st.follow_item {
          left = dmin(to_end, rn.y - iy - st.follow_margin)
        }
      }
    }
    st.glide_left = left
    // its end moved since its last step (a row came or grew under it, the row it follows came nearer): it sets out
    // again from where it is, so it neither jumps the difference at its rest nor stands still till its way catches up
    let moved = st.glide_meant >= 0.0 && (left - st.glide_meant).abs() > 0.5
    if st.glide_t0 == @double.infinity || moved {
      // it sets out at its first layout: its way said once (what is left of it e^(-t/list_glide_ms), at its end once
      // under a pixel)
      st.glide_t0 = self.clock
      st.glide_l0 = left
      st.glide_rest = if left < 1.0 { self.clock } else { self.clock + (list_glide_ms * @dmath.ln(left)).ceil() }
    }
    if left < 1.0 {
      st.glide = false
      st.at_end = to_end < 1.0
      if st.glide_shows {
        st.last_scroll = dmax(st.last_scroll, self.clock)
      }
    }
  }
  st.sizes_kept(self.clock)
  // (a row's height under way, said by a row built as it was laid out: frames till it is over, each laid out again)
  if st.sizes_rest() > self.clock {
    self.moving(st.sizes_mover, (Sizes::{ st, }) as &Moving, what="a list's rows' heights")
    self.shows_motion(st.sizes_mover, true)
  }
  st.left = (st.anchor, st.anchor_off, st.pending, st.at_end, st.glide)
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
  // iOS's rubber band moves the rows past the end (as its curve has it)
  let off = st.over_offset()
  if off != 0.0 {
    for r in order {
      self.shift(r, off)
    }
  }
  // set on the device's pixels (where the list stands said above, as they are laid)
  self.rows_on_pixels(order)
  self.stick_in(li, order, iy)
  // (whether it moves, as laid out: what is built from it told as that changes, Ctx::list_moving)
  st.moving_said.set(st.held || st.moving() || st.glide)
}

///|
/// Whether a list's rows are laid on the device's pixels (Ctx::row_slot, rows_on_pixels): on a host, its rows kept or
/// not, as it draws each glyph on its pixels; in a Tester where it keeps parts as drawn (Tester::keep_parts), else as
/// every frame of a Tester's was always laid out; not while anything reads what each frame builds as it was (a test's
/// instance owners, a test lighting everything). Not with the parts kept as drawn (Ctx::rows_on): on a host with them,
/// they went off with them (#2325), and a list scrolled had its words crawl again.
fn Ctx::rows_on_grid(self : Ctx) -> Bool {
  (fake.val is None || rows_grid_test.val) && !inst_owners.on && !self.lit_every
}

///|
/// A Tester's list rows laid on the pixels as a host lays them, its rows kept as their nodes (a test of it).
// kept across runs: set by a test, put back by each Tester (Tester::new)
let rows_grid_test : Ref[Bool] = Ref(false)

///|
/// Row node `r` of a list, laid out `h` tall: where rows are laid on the pixels (Ctx::rows_on_grid), as tall as whole
/// device pixels, its room to the next row what is left of the last one (the rows' tops on the pixels together:
/// Ctx::rows_on_pixels).
fn Ctx::row_slot(self : Ctx, r : Int, h : Double) -> Double {
  if !self.rows_on_grid() {
    return h
  }
  let sc = self.scale
  let slot = (h * sc - 0.000001).ceil() / sc
  self.nodes[r].fh = slot
  slot
}

///|
/// A list's rows (`order`, top to bottom, laid where the list stands, each as tall as whole device pixels: row_slot)
/// set on the device's pixels, all moved alike, less than a pixel (where they are laid on them: Ctx::rows_on_grid).
/// Each glyph is set on the pixels where it is (Ctx::emit_text, paint_rich), so a row put a part of a pixel off them
/// has its lines set apart, one moved a pixel and the next not as the list moves it, its words crawling: so it is as
/// the list stands at its end and what is under its rows grows (words sent flying in, an agent's line coming), the
/// keyboard comes, an end stops it, it is said from another row. On the pixels, all of a row moves as one, by whole
/// pixels, and a row kept is moved as its laying out there would move it (kept_nodes.mbt).
fn Ctx::rows_on_pixels(self : Ctx, order : Array[Int]) -> Unit {
  if !self.rows_on_grid() || order.length() == 0 {
    return
  }
  let y = self.nodes[order[0]].y
  let by = on_pixels(y, self.scale) - y
  if by != 0.0 {
    for r in order {
      self.shift(r, by)
    }
  }
}

///|
/// The list node `i` is in (its nearest), or -1.
fn Ctx::list_of(self : Ctx, i : Int) -> Int {
  let mut p = self.nodes[i].parent
  while p >= 0 && self.nodes[p].kind != kind_list {
    p = self.nodes[p].parent
  }
  p
}

///|
/// Node `i` held `top` below the top of the list it is in while its row scrolls past (CSS's `position: sticky` with
/// `top`): laid out where it is, it goes down with the view's top as that passes it, never past the foot of its parent
/// (what a long row keeps in view, its picture at the top of the list). Outside a list's rows it is where it is laid out.
pub fn Ctx::stick(self : Ctx, i : Int, top : Double) -> Unit {
  if i < 0 || i >= self.count {
    return
  }
  self.nodes[i].stick = top
}

///|
/// What the rows of list `li` just placed (`rows`) hold near its top (Node's `stick`: Ctx::stick; a list in a row holds
/// its own), its content starting at `top`: each where its parent lays it, then down to `top` and its own distance, as
/// far as its parent's foot lets it.
fn Ctx::stick_in(self : Ctx, li : Int, rows : Array[Int], top : Double) -> Unit {
  let stuck : Array[Int] = []
  let walk : Array[Int] = []
  for r in rows {
    walk.push(r)
    while walk.pop() is Some(i) {
      let n = self.nodes[i]
      if n.stick == n.stick {
        stuck.push(i)
      }
      if n.kind == kind_list && i != li {
        continue
      }
      let mut ch = n.first
      while ch >= 0 {
        walk.push(ch)
        ch = self.nodes[ch].next
      }
    }
  }
  for s in stuck {
    let n = self.nodes[s]
    if n.parent < 0 {
      continue
    }
    let p = self.nodes[n.parent]
    // where its parent lays it (a subtree placed as before keeps where it was held last frame)
    self.replace(s, p.x, p.y)
    let held = top + n.stick - n.y
    let room = p.y + p.fh - p.pad_b - n.fh - n.y
    let dy = dmin(held, room)
    if dy > 0.0 {
      self.shift(s, dy)
    }
  }
}

///|
/// Scrolls list `key` (as given to Ctx::list in the same scope) so row
/// `item` is at its top (`offset` below it: its top that far above the
/// view's, or below it when negative), the end kept in view. A glide to its
/// end, and a row followed, end there: the row is where it goes.
pub fn Ctx::list_scroll_to(
  self : Ctx,
  key : String,
  item : Int,
  offset? : Double = 0.0,
) -> Unit {
  let id = self.id(key)
  match self.lists.get(id) {
    // (asked again as the frame is built again: done already)
    Some(st) if st.scroll_asked != (self.frame_no, item, offset) => {
      st.scroll_asked = (self.frame_no, item, offset)
      st.scroll_to(item)
      st.glide = false
      st.follow_item = -1
      st.anchor_off = offset
      self.app_scrolled(id, st)
      self.read_changed("a list scrolled to a row")
    }
    _ => ()
  }
}

///|
/// Back to list `key`'s end: gliding there (what is left of the way e^(-t/list_glide_ms) of it, as still.fail's lists
/// follow their newest; far from it, more than list_glide_rows rows, at once), or at once.
pub fn Ctx::list_to_end(self : Ctx, key : String, glide? : Bool = true) -> Unit {
  let id = self.id(key)
  match self.lists.get(id) {
    Some(st) => {
      st.follow_item = -1
      if glide {
        st.stop()
        self.glide_to_end(id, st)
      } else {
        st.scroll_to_end()
        self.app_scrolled(id, st)
      }
      self.read_changed("a list sent to its end")
    }
    None => ()
  }
}

///|
/// List `key` follows its row `item` from its top: gliding to the end from now on (what comes at it, Ctx::list's
/// glide_on_growth) stops once that row's top is `margin` under the view's, if the end does not come first (still.fail's
/// Follow.kt: a message arriving while the list is at its end is read from its start). -1: none. Let go by the
/// reader's scroll, or a glide asked to the end (list_to_end).
pub fn Ctx::list_follow_from(self : Ctx, key : String, item : Int, margin? : Double = 0.0) -> Unit {
  match self.lists.get(self.id(key)) {
    Some(st) => {
      st.follow_item = item
      st.follow_margin = margin
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
fn Ctx::glide_to_end(self : Ctx, id : Int, st : ListState) -> Unit {
  if st.vis_last >= 0 && st.count - 1 - st.vis_last > list_glide_rows {
    st.scroll_to_end()
    st.glide = false
    self.app_scrolled(id, st)
    return
  }
  // (its bar out from now till the glide's end, where it showed)
  st.glide_shows = self.list_shown(id)
  if st.glide_shows {
    st.bar.wake(self.clock, st.shown_until())
  }
  st.glide = true
  st.glide_t0 = @double.infinity
  st.glide_rest = -1.0
  st.glide_meant = -1.0
  self.moving(st.ease_mover, st as &Moving, what="a list gliding to its end")
}

///|
/// Where a glide to the end is at this frame: what is left of it as a function of the time since it set out, the
/// list moved by what it is further than that; at its end from its rest on.
fn Ctx::step_glide(self : Ctx, st : ListState) -> Unit {
  if !st.glide || st.glide_t0 == @double.infinity {
    return
  }
  if self.clock >= st.glide_rest {
    // a row followed: moved by what was left of its way as last laid out, the glide over only once this frame's layout
    // finds it at its goal as it is now (its end, or the row's top): its end moved since by less than sets it out
    // again (a row under it opening by parts of a point a frame), it is at its end all the same, not short of it and
    // standing still (Ctx::place_list)
    if st.follow_item >= 0 {
      st.pending = st.pending + st.glide_left
      st.glide_meant = 0.0
      return
    }
    // there: its end; its bar fades from then
    st.scroll_to_end()
    st.glide = false
    if st.glide_shows {
      st.last_scroll = dmax(st.last_scroll, st.glide_rest)
    }
    return
  }
  let want = st.glide_l0 * @dmath.exp(-(self.now() - st.glide_t0) / list_glide_ms)
  if st.glide_left > want {
    st.pending = st.pending + (st.glide_left - want)
  }
  // (where it means to be after this step: its next layout finds it there unless its end moved)
  st.glide_meant = dmin(st.glide_left, want)
}

///|
/// Scrolls list `key` by `dy` (down when positive), as a wheel does.
pub fn Ctx::list_scroll_by(self : Ctx, key : String, dy : Double) -> Unit {
  self.scroll_list(self.id(key), dy)
  self.read_changed("list_scroll_by \"\{key}\"")
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
  /// the view's height (what of the rows shows at once)
  height : Double
  /// its rows laid end to end: those built at their height, the rest at its estimate (what it would be as tall as,
  /// shown whole)
  content : Double
  /// gliding to its end (list_to_end)
  gliding : Bool
  /// a row followed from its top (Ctx::list_follow_from), not let go by the reader since
  following_row : Bool
  /// when it is at rest by itself, on the frames' clock: its fling, its overscroll going back, a wheel's ease and its
  /// glide over (its scroll bar's fading aside); inf while a finger holds it or a glide's way is not known yet (it
  /// sets out at its next layout); -1 at rest
  rest : Double
  /// when its glide after what came (to its end, to a row it follows) is over, on the frames' clock: inf while its way
  /// is not known yet, -1 none. What the reader's hand does (a finger holding it, a fling, a wheel) is not in it
  glide_rest : Double
}

///|
/// How list `key` stood after the last layout; None before its first. Read as the view builds, it is read back
/// (readback.mbt) by its rows in view and how far it is from its end: laid out otherwise this frame (a scroll that took
/// one frame, a wheel's or a key's), the frame is built again from it. What is built from less of it says what
/// (Ctx::list_info_as), and is built again only as that changes.
pub fn Ctx::list_info(self : Ctx, key : String) -> ListInfo? {
  self.list_info_as(key, rows_and_end)
}

///|
/// What Ctx::list_info is read back by: the rows in view, whether the list is at its end and how far from it.
fn rows_and_end(i : ListInfo?) -> (Int, Int, Bool, Double)? {
  match i {
    Some(i) => Some((i.first, i.last, i.at_end, i.below))
    None => None
  }
}

///|
/// How list `key` stood after the last layout, as Ctx::list_info, read back by what `made` makes of it alone: what
/// the view builds from it only by whether it is at its end, or far from it, is built again as that changes, not at
/// every step of a scroll.
pub fn[T : Eq] Ctx::list_info_as(self : Ctx, key : String, made : (ListInfo?) -> T) -> ListInfo? {
  let id = self.id(key)
  let v = self.list_info_of(id)
  if building.val {
    let was = made(v)
    self.info_reads.push((key, fn() { made(self.list_info_of(id)) != was }))
  }
  v
}

///|
/// A list, to read later as it then stands and never read back: for what a frame works out of where it is once its
/// builds are over and tells outside (Ctx::after_build: a reader's place, what they have seen whole), never for what it
/// draws (that reads Ctx::list_info, list_place and list_row_height as it builds).
pub struct ListReader {
  priv ctx : Ctx
  priv id : Int
}

///|
/// List `key`, by its id where this is said (the scope it is built in), to read later (ListReader).
pub fn Ctx::list_reader(self : Ctx, key : String) -> ListReader {
  { ctx: self, id: self.id(key) }
}

///|
/// How the list stands now (Ctx::list_info's).
pub fn ListReader::info(self : ListReader) -> ListInfo? {
  self.ctx.list_info_of(self.id)
}

///|
/// Where the list is now (Ctx::list_place's).
pub fn ListReader::place(self : ListReader) -> (Int, Double, Double)? {
  self.ctx.list_place_of(self.id)
}

///|
/// How tall row `item` is now (Ctx::list_row_height's).
pub fn ListReader::row_height(self : ListReader, item : Int) -> Double? {
  self.ctx.list_row_height_of(self.id, item)
}

///|
fn Ctx::list_info_of(self : Ctx, id : Int) -> ListInfo? {
  match self.lists.get(id) {
    Some(st) =>
      Some({
        count: st.count,
        first: st.vis_first,
        last: st.vis_last,
        at_end: st.at_end,
        below: st.below,
        height: st.vp_h,
        content: st.above(st.heights.length()),
        gliding: st.glide,
        following_row: st.follow_item >= 0,
        rest: st.own_rest(),
        glide_rest: if !st.glide {
          -1.0
        } else if st.glide_t0 == @double.infinity {
          @double.infinity
        } else {
          st.glide_rest
        },
      })
    None => None
  }
}

///|
/// Where list `key` is, after its last layout: the first row in view, how far its top is above the view's, and that
/// row's height (a reader's place inside a block taller than the window). None before its first layout. Read as the
/// view builds, it is read back (readback.mbt): laid out otherwise this frame, the frame is built again from it.
pub fn Ctx::list_place(self : Ctx, key : String) -> (Int, Double, Double)? {
  // (by its id where it is read: the scope it is built in)
  let id = self.id(key)
  let v = self.list_place_of(id)
  if building.val && !self.place_reads.contains(id) {
    self.place_reads[id] = (key, v)
  }
  v
}

///|
fn Ctx::list_place_of(self : Ctx, id : Int) -> (Int, Double, Double)? {
  match self.lists.get(id) {
    Some(st) if st.vis_first >= 0 && st.vis_first < st.heights.length() =>
      Some((st.vis_first, st.anchor_off, st.heights[st.vis_first]))
    _ => None
  }
}

///|
/// Row `item` of list `key`'s height as last laid out; None while it has not been. Read as the view builds, it is
/// read back (readback.mbt), as list_place is.
pub fn Ctx::list_row_height(self : Ctx, key : String, item : Int) -> Double? {
  let id = self.id(key)
  let v = self.list_row_height_of(id, item)
  if building.val && !self.row_reads.contains((id, item)) {
    self.row_reads[(id, item)] = (key, v)
  }
  v
}

///|
fn Ctx::list_row_height_of(self : Ctx, id : Int, item : Int) -> Double? {
  match self.lists.get(id) {
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
/// Whether list `key` (in this scope) moved as it was last laid out: a finger on it, flung, gliding or springing back from
/// an end. Its motions are worked out as it is laid out (Ctx::place_list), after what is built round it: what is built
/// from this is built again as it changes (a signal), as what reads a list as it was laid out is (Ctx::list_info).
pub fn Ctx::list_moving(self : Ctx, key : String) -> Bool {
  match self.lists.get(self.id(key)) {
    Some(st) => st.moving_said.get()
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
