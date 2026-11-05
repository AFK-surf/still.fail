// ListRows' identities, versions and common height curve used by a windowed list of retained nodes. Measuring a
// row records its natural height; the room it is given follows the same RowSizing as an old Ctx::list. A departing
// row stays in that room until it closes. Neither its contents nor its list are built again as its height moves.

///|
/// Rows kept by a node, including those whose rooms are closing. `room` is the layout of their windowed list;
/// `lend` gives each row's contents the common way for changes of height within the row.
pub struct NodeRows[T] {
  read : () -> (Array[T], Array[String])
  room : (String, Double) -> @view.ListRoom
  /// the keys whose rooms are on their way now (those with a cause, those leaving, those moved on the same curve by
  /// their contents while anything is): what a windowed list asks `room` of again as it moves, the rest as they were
  moving : () -> Array[String]
  lend : (@view.View, String) -> Unit
  opening : () -> Bool
}

///|
// kept across runs: the kind of value lent; each lender removes its value when the node or tree is released
let node_row_way : @view.Lent[() -> (Double, Double)?] = @view.Lent::new()

///|
priv struct NodeRowsChange[T] {
  rows : (Array[T], Array[String])
  revision : Int
}

///|
impl[T] Eq for NodeRowsChange[T] with equal(a, b) {
  physical_equal(a.rows.0, b.rows.0) && a.rows.1 == b.rows.1 && a.revision == b.revision
}

///|
priv struct NodeRowSizes {
  causes : RowCauses
  live : Ref[Bool]
}

///|
impl Moving for NodeRowSizes with rest_at(self, now, _frame) {
  if self.live.val && self.causes.end > now + 0.001 { self.causes.end } else { -1.0 }
}

///|
/// The list's common height curve for a change within a retained row, as Ctx::row_way is for an old row. Reading it
/// declares that the contents already change height on this curve; the list adds only the displacement at its start.
pub fn row_way_node(v : @view.View) -> (Double, Double)? {
  v.lent(node_row_way).bind(fn(f) { f() })
}

///|
/// Keep these rows in `v` by their keys and versions, with the same causes as ListRows::rows. `middle` marks rows
/// coming in place (no flight brings them), `grown` whether their content scales and fades with their opening room,
/// and `lead` the gap over their content. A departing row always closes in place. `own` is for a room already moved
/// on this same curve by its contents, such as a composer's room under the messages.
pub fn[T] ListRows::in_node(
  self : ListRows[T],
  v : @view.View,
  items : () -> Array[T],
  key : (T) -> String,
  version : (T) -> String,
  watched? : () -> Bool = fn() { true },
  ms? : (String) -> Double? = fn(_) { None },
  from? : (String) -> Double? = fn(_) { None },
  comes? : (T) -> Bool = fn(_) { true },
  moves? : (T) -> Bool = fn(_) { false },
  middle? : (T) -> Bool = fn(_) { true },
  grown? : (T) -> Bool = fn(_) { true },
  lead? : (T, Int) -> Double = fn(_, _) { 0.0 },
  own? : (T) -> Bool = fn(_) { false },
) -> NodeRows[T] {
  let ended = @signals.signal(0)
  let due : Ref[() -> Unit] = Ref(fn() { })
  let sizes : Map[String, RowSizing] = {}
  let shown : Map[String, Double] = {}
  // A retained list is measured before the old frame is built, and keeps moving when that frame is only painted.
  // Its measurement pass belongs to the moment being drawn, not to the old frame's build counter. Rebuilding the
  // old frame at that same moment must not advance the shared row curve a second time.
  let room_at : Ref[Double?] = Ref(None)
  let room_frame = Ref(0)
  let live = Ref(true)
  let mover = Mover::new()
  let motion = NodeRowSizes::{ causes: self.causes, live }
  v.owns(fn() { live.val = false; (due.val)() }) |> ignore
  let all : @signals.Signal[(Array[T], Array[String])] = @signals.signal(([], []))
  // Model inputs have their own dependencies. Completing a motion reads the same inputs, rather than asking the
  // page for its rows again and turning a newly allocated, identical array into a change of the whole list.
  let input : @signals.Computed[(Array[T], Array[String])] = @signals.computed(fn(was) {
    let given = items()
    let keys = given.map(key)
    let keys = match was {
      Some((_, before)) if before == keys => before
      _ => keys
    }
    (given, keys)
  })
  // Versions may read state independently of items. Keep those reads subscribed even when a timer takes the
  // unchanged-input path in rows_at; a later edit must still start its own change at its own cause.
  let versions : @signals.Computed[Array[String]] = @signals.computed(fn(was) {
    let next = input.get().0.map(version)
    match was {
      Some(before) if before == next => before
      _ => next
    }
  })
  // Changing the row set also tells its height causes. Publish the rows after that change has been worked out,
  // in one reaction; a lazy computed would tell readers of its causes while it was still replacing its value.
  v.reacts(fn() {
    ended.get() |> ignore
    let (given, keys) = input.get()
    let rows = self.rows_at(v.cause_at(), keys, given, version, versions=versions.get(),
      watched=watched() && !v.shown_nowhere(), ms~, from~, comes~, moves~)
    NodeRowsChange::{ rows, revision: self.causes.n }
  }, fn(change) {
    let rows = change.rows
    // A completed way is no longer a source position. Its last measured height is: a row first estimated tall
    // may have ended shorter. Keeping the completed way would make its next departure start from the estimate.
    if self.causes.by.is_empty() { sizes.clear() }
    if !physical_equal(all.get().1, rows.1) {
      let here = Set::from_array(rows.1)
      for k in shown.keys().collect() {
        if !here.contains(k) { shown.remove(k); sizes.remove(k) }
      }
    }
    (due.val)()
    due.val = if self.causes.end > v.logic_at() {
      g().moving(mover, motion as &Moving, what="a list's rows' heights, the tree's")
      v.at_moment(self.causes.end, fn() {
        ended.set(@signals.untracked(fn() { ended.get() }) + 1)
      })
    } else {
      fn() { }
    }
    all.set(rows)
  })
  // (where each row is among them, by its key: what a row's room reads, not looked for among all of them, the room of
  // each of a long chat's three thousand counted as its windowed list lays them out)
  let keys = @signals.computed(fn(_) { all.get().1 })
  let key_at = @signals.computed(fn(_) {
    let m : Map[String, Int] = {}
    for i, k in keys.get() {
      m[k] = i
    }
    m
  })
  let room = fn(k : String, natural : Double) -> @view.ListRoom {
    let (items, _) = all.get()
    let c = self.causes
    c.read()
    // (nothing of the list on its way, nothing leaving: each row as tall as it is, its height kept for a way that may
    // start from it; nothing more asked of each of a long chat's three thousand as their list is laid out, 2026-11-04)
    if c.by.is_empty() && self.going.is_empty() {
      shown[k] = natural
      return @view.list_room(natural)
    }
    let i = key_at.get().get(k).unwrap_or(-1)
    guard i >= 0 else { return @view.list_room(natural) }
    let going = self.going.contains(k)
    let by_room = going || middle(items[i])
    if by_room {
      c.by_room.add(k)
      c.leads[k] = lead(items[i], i)
    }
    if own(items[i]) {
      c.own.add(k)
    }
    let now = if v.logic_at() < c.end { v.drawn_at() } else { v.logic_at() }
    if room_at.val != Some(now) {
      room_at.val = Some(now)
      room_frame.val += 1
    }
    let h = dmax(0.0, c.height(sizes, shown, k, natural, now, room_frame.val))
    shown[k] = h
    let open = c.opened.contains(k)
    let fraction = if open && natural > 0.0 { dmax(0.0, dmin(1.0, h / natural)) } else { 1.0 }
    let scaled = open && (going || grown(items[i]))
    let clipped = (h - natural).abs() > 0.001 || (now < c.end && c.own.contains(k))
    {
      height: h,
      offset: if open && natural > 0.0 { (h - natural) / 2.0 * (natural + c.leads.get(k).unwrap_or(0.0)) / natural } else { 0.0 },
      clip: clipped,
      soft: clipped && open,
      scale: if scaled { fraction } else { 1.0 },
      alpha: if scaled { dmax(0.0, (fraction - row_gone_at) / (1.0 - row_gone_at)) } else { 1.0 },
      presses: !going,
    }
  }
  let lend = fn(row : @view.View, k : String) {
    row.lends(node_row_way, fn() {
      // Resolve a pending content version before a child changes its own height.
      all.get() |> ignore
      let c = self.causes
      c.read()
      if c.end > row.logic_at() && c.start >= 0.0 {
        c.own.add(k)
        Some((c.start, c.end - c.start))
      } else {
        None
      }
    }) |> ignore
  }
  let opening = fn() {
    all.get() |> ignore
    self.causes.read()
    self.causes.end > v.logic_at() && self.causes.by.values().any(fn(cm) { cm.0 is Comes(_) })
  }
  // (those moved by their contents, by the rows as they are now)
  let own_keys = @signals.computed(fn(_) {
    let (items, keys) = all.get()
    let out = []
    for i, it in items {
      if own(it) && i < keys.length() {
        out.push(keys[i])
      }
    }
    out
  })
  let moving = fn() -> Array[String] {
    all.get() |> ignore
    let c = self.causes
    c.read()
    if c.by.is_empty() && self.going.is_empty() {
      return []
    }
    let out : Array[String] = c.by.keys().collect()
    for k, _ in self.going {
      out.push(k)
    }
    // (and those whose content went on the way itself as it was laid out, row_way: clipped while it goes)
    c.own.each(fn(k) { out.push(k) })
    out.append(own_keys.get())
    out
  }
  { read: fn() { all.get() }, room, moving, lend, opening }
}
