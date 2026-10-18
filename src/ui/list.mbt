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
fn ListState::normalize(self : ListState) -> Unit {
  if self.count == 0 {
    self.anchor = 0
    self.anchor_off = 0.0
    self.at_end = true
    return
  }
  if self.anchor >= self.count {
    self.anchor = self.count - 1
  }
  while self.anchor_off < 0.0 && self.anchor > 0 {
    self.anchor = self.anchor - 1
    self.anchor_off = self.anchor_off + self.height(self.anchor)
  }
  if self.anchor_off < 0.0 {
    self.anchor_off = 0.0
    if self.vel < 0.0 {
      self.vel = 0.0
    }
  }
  while self.anchor < self.count - 1 &&
        self.anchor_off >= self.height(self.anchor) {
    self.anchor_off = self.anchor_off - self.height(self.anchor)
    self.anchor = self.anchor + 1
  }
  // never scroll past the end
  let mut rem = -self.anchor_off
  let mut i = self.anchor
  while i < self.count && rem < self.vp_h {
    rem = rem + self.height(i)
    i = i + 1
  }
  if rem < self.vp_h {
    self.anchor_off = self.anchor_off - (self.vp_h - rem)
    if self.vel > 0.0 {
      self.vel = 0.0
    }
    while self.anchor_off < 0.0 && self.anchor > 0 {
      self.anchor = self.anchor - 1
      self.anchor_off = self.anchor_off + self.height(self.anchor)
    }
    if self.anchor_off < 0.0 {
      self.anchor_off = 0.0
    }
    self.at_end = true
  } else {
    self.at_end = i >= self.count && rem <= self.vp_h + 1.0
  }
}

///|
fn Ctx::scroll_list(self : Ctx, id : Int, d : Double) -> Unit {
  match self.lists.get(id) {
    Some(st) => {
      st.pending = st.pending + d
      st.last_scroll = self.now
    }
    None => ()
  }
}

///|
/// A list of `count` rows; `row(i)` builds row i. Rows are estimated at
/// `est` pixels until they have been laid out once.
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
        anchor: if stick_end && count > 0 { count - 1 } else { 0 },
        anchor_off: if stick_end { 1.0e9 } else { 0.0 },
        heights: [],
        est,
        count: 0,
        vp_h: 600.0,
        vel: 0.0,
        at_end: stick_end,
        stick_end,
        last_scroll: -1.0e9,
        pending: 0.0,
        first_built: 0,
        last_built: 0,
      }
      self.lists[id] = s
      s
    }
  }
  if self.bench_list == 0 {
    self.bench_list = id
  }
  while st.heights.length() < count {
    st.heights.push(-1.0)
  }
  if count > st.count && st.stick_end && st.at_end && st.count > 0 {
    st.anchor = count - 1
    st.anchor_off = 1.0e9
  }
  st.count = count
  if st.vel != 0.0 {
    st.pending = st.pending + st.vel * self.dt
    st.vel = st.vel * 0.997.pow(self.dt)
    st.last_scroll = self.now
    if st.vel.abs() < 0.02 {
      st.vel = 0.0
    } else {
      self.wants_frame = true
    }
  }
  st.anchor_off = st.anchor_off + st.pending
  st.pending = 0.0
  st.normalize()
  let i = self.alloc(kind_list)
  let n = self.nodes[i]
  n.id = id
  n.w = w
  n.h = h
  n.clip = true
  n.bg = bg
  self.with_parent(i, fn() {
    let mut acc = -st.anchor_off
    let mut k = st.anchor
    st.first_built = k
    while k < count && acc < st.vp_h + 64.0 {
      let r = self.alloc(kind_box)
      self.nodes[r].item = k
      let item = k
      self.with_parent(r, fn() { self.scope(item, fn() { row(item) }) })
      acc = acc + st.height(k)
      k = k + 1
    }
    st.last_built = k
  })
  if self.now - st.last_scroll < 900.0 {
    self.wake_at_time(st.last_scroll + 900.0)
  }
  i
}

///|
fn Ctx::place_list(
  self : Ctx,
  n : Node,
  ix : Double,
  iy : Double,
  iw : Double,
  ih : Double,
) -> Unit {
  match self.lists.get(n.id) {
    Some(st) => {
      let vp_changed = (st.vp_h - ih).abs() > 0.5
      st.vp_h = ih
      let mut y = iy - st.anchor_off
      let mut c = n.first
      let mut changed = false
      while c >= 0 {
        let row = self.nodes[c]
        let (_, h) = self.measure(c, iw)
        self.place(c, ix, y, iw, h)
        let old = st.heights[row.item]
        if (old - h).abs() > 0.5 {
          changed = true
        }
        st.heights[row.item] = h
        y = y + h
        c = row.next
      }
      // a list pinned to its end stays there when rows turn out taller
      // or shorter than estimated
      if (changed || vp_changed) && st.stick_end && st.at_end {
        st.anchor = imax(st.count - 1, 0)
        st.anchor_off = 1.0e9
      }
      // rows measured for the first time, or a resized viewport, can
      // leave a gap: build again next frame with the real heights.
      if (changed || vp_changed) &&
         (y < iy + ih || (st.stick_end && st.at_end)) {
        self.wants_frame = true
      }
    }
    None => ()
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
