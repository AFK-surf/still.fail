// The hand's change to a list is followed apart from layout's other reads. That lets a small scroll which keeps the
// same rows and changes nothing else move those rows without running flex again. Other cases use the ordinary layout.

///|
// kept across runs: stopped when the run is reset or the list is no longer laid out
let list_hand_watches : Map[Int, @signals.Watch] = Map([])

///|
// kept across runs: what the hand told since each list was last laid out
let list_hand_dirty : Map[Int, Bool] = Map([])

///|
// kept across runs: the last build's readbacks, so a scroll may skip layout only if each projection stays the same
let list_fast_info_reads : Array[(String, () -> Bool)] = []

///|
// kept across runs: the last build's exact position reads
let list_fast_place_reads : Map[Int, (String, (Int, Double, Double)?)] = Map([])

///|
// kept across runs: the ids of what is told after a build that follows where lists stand (Ctx::after_build_or_scroll)
let tells_follow_lists : Map[Int, Bool] = Map([])

///|
// kept across runs: those the last build said, told again as a list moves with nothing built
let list_fast_tells : Array[() -> Unit] = []

///|
fn Ctx::list_fast_reads(self : Ctx) -> Unit {
  list_fast_info_reads.clear()
  list_fast_info_reads.append(self.info_reads)
  list_fast_place_reads.clear()
  self.place_reads.each(fn(id, read) { list_fast_place_reads[id] = read })
}

///|
fn Ctx::list_hand_follow(self : Ctx, id : Int, st : ListState, at : Double) -> Unit {
  let w = match list_hand_watches.get(id) {
    Some(w) if !w.gone() => w
    _ => {
      let w = @signals.watch(fn() {
        list_hand_dirty[id] = true
        // (moved after the frame was drawn, a scripted run's step: drive_frame, as between frames)
        if !in_frame.val {
          h_frame_owed()
        } else if !frame_built.val || (layout_coming.val && !laying.val) {
          ()
        } else {
          layout_said.val = "a list moved as the frame was laid out"
        }
      })
      list_hand_watches[id] = w
      w
    }
  }
  list_hand_dirty.remove(id)
  w.read(fn() {
    st.hand_said.get() |> ignore
    // The scrollbar's clock belongs to this list too. Keep it separate from other layout reads; an active wheel
    // ease, fling or glide still reads time while stepped by layout and takes the ordinary path.
    self.shows_motion(st.ease_mover, Moving::rest_at(st, at, self.frame_no) > at)
  })
}

///|
fn list_hand_forget() -> Unit {
  for _, w in list_hand_watches {
    w.stop()
  }
  list_hand_watches.clear()
  list_hand_dirty.clear()
  list_fast_info_reads.clear()
  list_fast_place_reads.clear()
  list_fast_tells.clear()
  tells_follow_lists.clear()
}

///|
fn Ctx::list_hand_end(self : Ctx) -> Unit {
  let gone : Array[Int] = []
  for id, _ in list_hand_watches {
    match self.lists.get(id) {
      Some(st) if st.laid == self.frame_no => ()
      _ => gone.push(id)
    }
  }
  for id in gone {
    match list_hand_watches.get(id) {
      Some(w) => w.stop()
      None => ()
    }
    list_hand_watches.remove(id)
    list_hand_dirty.remove(id)
  }
}

///|
/// Advance a simple list only while all of its visible rows stay visible. Complex rows, other layout dependencies,
/// motion at an edge and changes to the window take the ordinary path instead.
fn Ctx::list_hand_move(self : Ctx, at : Double) -> String {
  let blocked = if list_hand_dirty.length() != 1 {
    "lists"
  } else if !nodes_run.on {
    "nodes off"
  } else if !self.laid_watch.is_empty() {
    "laid watch"
  } else if !self.shown_watch.is_empty() {
    "shown watch"
  } else if reads_out() {
    "reads out"
  } else if !self.layers.is_empty() {
    "layers"
  } else if !picked.spans.is_empty() {
    "picked"
  } else if !words_sel.is_empty() {
    "words sel"
  } else {
    ""
  }
  if blocked != "" {
    return blocked
  }
  let mut id = 0
  for k, _ in list_hand_dirty {
    id = k
  }
  let st = match self.lists.get(id) {
    Some(s) => s
    None => return "gate 2"
  }
  if st.pending == 0.0 || st.at_end || st.glide || st.fling != 0 || st.vel != 0.0 ||
    st.easing() || st.over_state != 0 || st.edge_v != 0.0 || st.sizes_rest() > at ||
    st.moving_said.untracked() != (st.held || st.moving() || st.glide) {
    return "moving"
  }
  let mut li = -1
  for i in 0..<self.count {
    if self.nodes[i].id == id && self.nodes[i].kind == kind_list {
      if li >= 0 {
        return "gate 4"
      }
      li = i
    }
  }
  if li < 0 {
    return "gate 5"
  }
  let list = self.nodes[li]
  if list.first < 0 || list.last < 0 {
    return "gate 6"
  }
  let first = self.nodes[list.first]
  let last = self.nodes[list.last]
  if first.item != st.anchor || first.item != st.vis_first || last.item != st.vis_last {
    return "rows in view"
  }
  // Do not move a row with layout-dependent side effects, an editor or a nested coordinate system. An editor outside
  // these rows stays in place and need not force their layout.
  let stops : Map[String, Bool] = Map([])
  let mut r = list.first
  while r >= 0 {
    let row = self.nodes[r]
    let rn = match kept_nodes.get((id, row.item)) {
      Some(rn) => rn
      None => return "a row not kept"
    }
    if !rn.ok { stops["row not ok"] = true }
    if !rn.in_pool { stops["row not in pool"] = true }
    if rn.base != r { stops["row base"] = true }
    if rn.watch.is_stale() { stops["row stale"] = true }
    if !rn.laid.is_empty() { stops["row laid"] = true }
    if !rn.info.is_empty() { stops["row info"] = true }
    for j in r..<(r + rn.n) {
      let n = self.nodes[j]
      if n.kind != kind_box && n.kind != kind_text && n.kind != kind_rich && n.kind != kind_image {
        stops["kind \{n.kind}"] = true
      }
      if n.portal { stops["portal"] = true }
      if n.shot { stops["shot"] = true }
      if n.floats { stops["floats"] = true }
      // (a box scrolled across: where it is scrolled to is no matter of how far down it is; one scrolled up and down
      // is a list of its own)
      if n.scroller != 0 && (match sideways.get(n.scroller) { Some(sw) => sw.vertical; None => true }) {
        stops["scroller"] = true
      }
      if n.moved_by is Some(_) { stops["moved_by"] = true }
      if n.place is Some(_) { stops["place"] = true }
      if n.stick == n.stick { stops["stick"] = true }
    }
    r = row.next
  }
  if !stops.is_empty() {
    let said : Array[String] = []
    for k, _ in stops {
      said.push(k)
    }
    return said.join(",")
  }
  let top = list.y + list.pad_t
  let foot = top + st.vp_h
  let want = top - st.anchor_off - st.pending
  let y = if self.rows_on_grid() { on_pixels(want, self.scale) } else { want }
  let dy = y - first.y
  // (where a layout lays them, before it sets them on the pixels: what it says of where the list stands is said of
  // that, Ctx::place_list, list.mbt's rows_on_pixels after it)
  let laid = want - first.y
  // The same set of rows must cover the view and every current row must remain visible. A row comes in where the
  // layout would lay one (place_list: one above while the first's top is below the view's, `top > iy`; one below while
  // the last's foot is above the view's, `bottom < bottom_edge`), by as little as it is: a first row 0.0002 under the
  // view's top was moved there with nothing built over it, where the layout lays the row before it.
  if first.y + laid > top || first.y + first.fh + laid <= top + 0.001 ||
    last.y + last.fh + laid < foot || last.y + laid >= foot - 0.001 {
    return "past an edge"
  }
  // ListInfo may be read through a projection (for example, only whether the list is at its end). Ask exactly those
  // projections against the proposed logical position before committing it. A precise place read must also match.
  // No row is entering or leaving, this is not the last row, and no height changes, so the other ListInfo fields are
  // the same as after an ordinary layout. If a projection changes, leave the pending scroll for that layout.
  // (how far its last row's foot is below the view's, where it is laid: ListInfo's `below`, `at_end`, Ctx::place_list)
  let below = if last.item == st.count - 1 { last.y + last.fh + laid - foot } else { 1.0e9 }
  let at_end = last.item == st.count - 1 && below <= 0.001
  let was = (st.anchor_off, st.below, st.at_end)
  st.anchor_off = was.0 + st.pending
  st.below = below
  st.at_end = at_end
  let changed = @signals.untracked(fn() {
    let mut different = false
    for read in list_fast_info_reads {
      if (read.1)() { different = true }
    }
    list_fast_place_reads.each(fn(list_id, read) {
      if self.list_place_of(list_id) != read.1 { different = true }
    })
    different
  })
  st.anchor_off = was.0
  st.below = was.1
  st.at_end = was.2
  if changed || frame_watch_of().is_stale() || layout_watch_of().is_stale() ||
    nodes_run.told || watch_said.val != "" || layout_said.val != "" {
    return "what was read of it"
  }
  st.anchor_off = st.anchor_off + st.pending
  st.below = below
  st.at_end = at_end
  st.pending = 0.0
  st.pinned_by = 0.0
  st.drag_pending = 0.0
  st.on_pixels_by = y - want
  st.left = (st.anchor, st.anchor_off, st.pending, st.at_end, st.glide)
  // (its rows kept as they are, moved: what the frame kept, Tester::rows_kept)
  let parts = nodes_run.kept_at.filter(fn(k) { k.1 < 0 })
  nodes_run.kept_at.clear()
  nodes_run.kept_at.append(parts)
  r = list.first
  while r >= 0 {
    let next = self.nodes[r].next
    if dy != 0.0 {
      self.shift(r, dy)
    }
    nodes_run.kept_at.push((id, self.nodes[r].item))
    r = next
  }
  self.list_hand_follow(id, st, at)
  // (what is worked out of the nodes where they are laid out, worked out again where they are now)
  self.drawing_after_layout()
  self.words_after_layout()
  scroll_paint_uncompared.val = true
  lists_scrolled.push(id)
  ""
}
