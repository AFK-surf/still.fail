// ListRows' rows read by position from a source that says what changed, for a list too long to give whole each time
// (a chat's three thousand messages): what came, went or changed is worked out of those changes alone, and of a row
// only what is asked of it is read (its key and item by its place, found by its key near where it was). The rooms,
// their curve and the rows leaving in their rooms are ListRows::in_node's.

///|
/// What changed of an indexed list's rows since it was last read (ListRows::in_node_indexed's `changes`): a key that
/// came where it is now; one that went, as it last was and the key of the row it came after (None: the first); one
/// whose content changed; all of it given anew (read again: shown as it is, nothing coming or going).
pub(all) enum RowsChange[T] {
  Came(String)
  Went(String, T, String?)
  Set(String)
  Whole
}

///|
/// The rows ListRows::in_node_indexed keeps, those leaving among them: `source` for an anchored list (View::scrolls_anchored's
/// `indexed`), `item_of` a row by its key and where it is among them (one leaving as it last was), and the rooms as
/// NodeRows' are.
pub struct NodeRowsIndexed[T] {
  source : @view.AnchoredSource[String]
  item_of : (String) -> (T, Int)?
  room : (String, Double) -> @view.ListRoom
  room_now : () -> (String, Double) -> @view.ListRoom
  moving : () -> Array[String]
  lend : (@view.View, String) -> Unit
  opening : () -> Bool
}

///|
/// A row leaving where it was among an indexed list's rows: it as it last was, when it went, the key it came after, and
/// where the source's rows had that one as it went (where it is found from).
priv struct IndexedGoing[T] {
  key : String
  item : T
  at : Double
  after : String
  mut near : Int
}

///|
/// Keep the rows of `rows` in `v` with the same causes as ListRows::in_node, read by position: `item` the row at a
/// place (as `rows` is now, nothing followed), `changes` what changed since it was last read (once: what it gives is
/// gone from it then; read as `rows` says it changed), `version` a row's content by its key (followed: what reads that
/// row is told as it changes). What it reads of the rows grows with what changed and what is asked of it, never with
/// how many there are: nothing of all of them is gone through, at the first reading either (that is Whole).
pub fn[T] ListRows::in_node_indexed(
  self : ListRows[T],
  v : @view.View,
  rows : @view.AnchoredSource[String],
  item : (Int) -> T,
  changes : () -> Array[RowsChange[T]],
  version : (String) -> Int?,
  watched? : () -> Bool = fn() { true },
  ms? : (String) -> Double? = fn(_) { None },
  from? : (String) -> Double? = fn(_) { None },
  comes? : (T) -> Bool = fn(_) { true },
  middle? : (T) -> Bool = fn(_) { true },
  grown? : (T) -> Bool = fn(_) { true },
  lead? : (T, Int) -> Double = fn(_, _) { 0.0 },
  lead_in_layout? : (T, Int) -> (() -> Double),
  own? : (T) -> Bool = fn(_) { false },
) -> NodeRowsIndexed[T] {
  let ended = @signals.signal(0)
  let due : Ref[() -> Unit] = Ref(fn() { })
  let sizes : Map[String, RowSizing] = {}
  let shown : Map[String, Double] = {}
  let room_at : Ref[Double?] = Ref(None)
  let room_frame = Ref(0)
  let live = Ref(true)
  let mover = Mover::new()
  let motion = NodeRowSizes::{ causes: self.causes, live }
  v.owns(fn() { live.val = false; (due.val)() }) |> ignore
  // (those leaving, in the order they are among the rows: by where they are found from, then as they went)
  let goings : Array[IndexedGoing[T]] = []
  // (what went out of them by its revision, theirs: what an anchored list asks of what is gone since it last looked)
  let gone_log : Array[(Int, String)] = []
  let gone_from = Ref(0)
  let revision = Ref(0)
  // (the source's revision as last read: what went out of it since, not leaving in its room, gone out of them too)
  let rows_seen = Ref(-1)
  let told = @signals.signal(0)
  let given = Ref(false)
  let going_at = fn(k : String) -> Int? {
    for i, g in goings {
      if g.key == k { return Some(i) }
    }
    None
  }
  let gone = fn(k : String) {
    gone_log.push((revision.val + 1, k))
    // (the oldest let go past a few hundred: an anchored list that last looked before then reads all of it again)
    if gone_log.length() > 512 {
      gone_from.val = gone_log[0].0
      gone_log.remove(0) |> ignore
    }
  }
  // (where each one leaving is found from now: after the row it came after, found near where that one was)
  let placed = fn() {
    let n = (rows.snapshot)().1
    for g in goings {
      if g.after == "" {
        g.near = 0
      } else {
        match going_at(g.after) {
          Some(i) => g.near = goings[i].near
          None =>
            match (rows.find)(g.after, g.near - 1) {
              Some(i) => g.near = i + 1
              None => g.near = if g.near < n { g.near } else { n }
            }
        }
      }
    }
    // (those found from the same place keep the order they went in: moved back only past one found from further on)
    for i in 1..<goings.length() {
      let mut j = i
      while j > 0 && goings[j - 1].near > goings[j].near {
        let t = goings[j - 1]
        goings[j - 1] = goings[j]
        goings[j] = t
        j -= 1
      }
    }
  }
  // Read what changed as the source says it did: in one reaction with the rows' height causes it tells, as in_node.
  v.reacts(fn() {
    // (and as the rows' way ends: what left is gone from them then)
    (ended.get(), (rows.snapshot)(), watched() && !v.shown_nowhere())
  }, fn(said) {
    let (_, _, watching) = said
    let now = v.cause_at()
    let c = self.causes
    let watching = watching && given.val
    let mut moved = false
    // the rows' way over: what went out at its end, what made it forgotten
    if c.end >= 0.0 && now >= c.end - 0.001 {
      moved = moved || !goings.is_empty() || !c.by.is_empty()
      for g in goings {
        gone(g.key)
      }
      goings.clear()
      c.by.clear()
      c.start = -1.0
      c.end = -1.0
      c.own.clear()
      c.by_room.clear()
      c.opened.clear()
      c.leads.clear()
    }
    let mut began = false
    // (what came and what went in this one batch: as ListRows::rows_at has it of the rows before and after it, one come
    // and gone in it never was, one gone and come again in it is there still, neither coming nor going)
    let came_now : Set[String] = Set::new()
    let went_now : Map[String, (RowSize, Double)?] = {}
    for change in changes() {
      match change {
        Came(k) => {
          match going_at(k) {
            Some(i) => {
              goings.remove(i) |> ignore
              moved = true
            }
            None => ()
          }
          match went_now.get(k) {
            // (gone and come again in it: what moved it before, as it was)
            Some(was) => {
              went_now.remove(k)
              match was {
                Some(cause) => c.by[k] = cause
                None => c.by.remove(k) |> ignore
              }
            }
            None => {
              came_now.add(k)
              if watching {
                let it = (rows.find)(k, (rows.snapshot)().1 - 1).map(item)
                if it is Some(x) && comes(x) {
                  c.by[k] = (Comes(from(k).unwrap_or(now)), ms(k).unwrap_or(row_size_ms))
                  began = true
                }
              }
            }
          }
        }
        Went(k, it, after) =>
          if came_now.contains(k) {
            // (come and gone in it: never among them)
            came_now.remove(k)
            c.by.remove(k) |> ignore
          } else if watching {
            let at = from(k).unwrap_or(now)
            let after = after.unwrap_or("")
            let near = if after == "" { 0 } else { (rows.find)(after, (rows.snapshot)().1 - 1).map(fn(i) { i + 1 }).unwrap_or(0) }
            went_now[k] = c.by.get(k)
            goings.push({ key: k, item: it, at, after, near })
            c.by[k] = (Goes(at), ms(k).unwrap_or(row_size_ms))
            began = true
          } else {
            gone(k)
          }
        Set(k) =>
          if watching {
            match c.by.get(k) {
              // (changed as it comes: still coming, on to what it is now)
              Some((Comes(_), _)) => ()
              _ => {
                c.by[k] = (Changed(from(k).unwrap_or(now)), ms(k).unwrap_or(row_size_ms))
                began = true
              }
            }
          }
        Whole => {
          for g in goings {
            gone(g.key)
          }
          goings.clear()
          moved = moved || !c.by.is_empty()
          c.by.clear()
        }
      }
    }
    if !watching && (!goings.is_empty() || !c.by.is_empty()) {
      for g in goings {
        gone(g.key)
      }
      goings.clear()
      c.by.clear()
      moved = true
    }
    given.val = true
    // (coming or changing with another motion of its cause, told anew when and how long, as ListRows::rows_at)
    let retimed : Array[(String, RowSize, Double)] = []
    c.by.each(fn(k, cm) {
      let (cause, was) = cm
      let at = if cause.at() >= now { from(k).unwrap_or(cause.at()) } else { cause.at() }
      let now_ms = ms(k).unwrap_or(was)
      if cause is Goes(_) || (at == cause.at() && now_ms == was) {
        return
      }
      retimed.push((k, match cause { Comes(_) => Comes(at); _ => Changed(at) }, now_ms))
    })
    for r in retimed {
      c.by[r.0] = (r.1, r.2)
      moved = true
      if r.1.at() > c.start {
        c.start = r.1.at()
      }
    }
    if began {
      let mut start = now
      c.by.each(fn(_, cm) { start = dmax(start, cm.0.at()) })
      c.start = start
      moved = true
    }
    let mut end = -1.0
    c.by.each(fn(_, cm) { end = dmax(end, cm.0.at() + cm.1) })
    if c.by.is_empty() {
      c.start = -1.0
      c.own.clear()
      c.by_room.clear()
      c.opened.clear()
      c.leads.clear()
    }
    c.end = end
    // (what went out of the source not leaving in its room: offscreen, not watched, all given anew)
    let rows_now = (rows.snapshot)().0
    if rows_seen.val >= 0 && rows_now != rows_seen.val {
      match (rows.removed_since)(rows_seen.val) {
        Some(out) =>
          for k in out {
            if going_at(k) is None && !(rows.contains)(k) { gone(k) }
          }
        None => gone_from.val = revision.val + 1
      }
    }
    rows_seen.val = rows_now
    placed()
    if c.by.is_empty() { sizes.clear() }
    for k in shown.keys().collect() {
      if !c.by.contains(k) && going_at(k) is None && !(rows.contains)(k) {
        shown.remove(k)
        sizes.remove(k)
      }
    }
    self.going_said.set(goings.map(fn(g) { g.key }))
    if moved {
      c.n += 1
      c.said.set(c.n)
    }
    (due.val)()
    due.val = if c.end > v.logic_at() {
      g().moving(mover, motion as &Moving, what="a list's rows' heights, the tree's")
      v.at_moment(c.end, fn() {
        ended.set(@signals.untracked(fn() { ended.get() }) + 1)
      })
    } else {
      fn() { }
    }
    revision.val += 1
    told.set(revision.val)
  })
  // (the rows and those leaving as one: each leaving where it is found from, before the row there)
  let length = fn() { (rows.snapshot)().1 + goings.length() }
  let key = fn(i : Int) -> String {
    let mut shift = 0
    for g in goings {
      let at = g.near + shift
      if i < at { break }
      if i == at { return g.key }
      shift += 1
    }
    (rows.key)(i - shift)
  }
  // (where a row of the source is among them all, and where one there is in the source)
  let with_going = fn(s : Int) {
    let mut shift = 0
    for g in goings {
      if g.near <= s { shift += 1 } else { break }
    }
    s + shift
  }
  let find = fn(k : String, near : Int) -> Int? {
    let mut shift = 0
    for g in goings {
      if g.key == k { return Some(g.near + shift) }
      shift += 1
    }
    let mut before = 0
    for g in goings {
      if g.near + before < near { before += 1 } else { break }
    }
    (rows.find)(k, near - before).map(with_going)
  }
  let source : @view.AnchoredSource[String] = {
    snapshot: fn() {
      told.get() |> ignore
      (rows.snapshot)() |> ignore
      (revision.val, length())
    },
    key,
    find,
    removed_since: fn(rev) {
      if rev < gone_from.val { return None }
      let out = []
      for r in gone_log {
        if r.0 > rev { out.push(r.1) }
      }
      Some(out)
    },
    contains: fn(k) { going_at(k) is Some(_) || (rows.contains)(k) },
  }
  let item_of = fn(k : String) -> (T, Int)? {
    match going_at(k) {
      // (those before it in the order leaving each one more before it)
      Some(i) => Some((goings[i].item, goings[i].near + i))
      None => {
        // (that row's content followed, and no other's)
        version(k) |> ignore
        let n = @signals.untracked(fn() { (rows.snapshot)().1 })
        (rows.find)(k, n - 1).map(fn(s) { (item(s), with_going(s)) })
      }
    }
  }
  // (what of a row its room is worked out by, as in_node: whether it comes in place, the room over it, whether its
  // content grows with its room, whether its content goes on the way itself)
  let room_with = fn(now : Double, k : String, natural : Double, of : (String) -> (Bool, Double, Bool, Bool)?) -> @view.ListRoom {
    self.rooms += 1
    let c = self.causes
    guard of(k) is Some((in_middle, over, grows, owns)) else { return @view.list_room(natural) }
    let going = self.going.contains(k) || going_at(k) is Some(_)
    let by_room = going || in_middle
    if by_room {
      c.by_room.add(k)
      c.leads[k] = over
    }
    if owns {
      c.own.add(k)
    }
    if room_at.val != Some(now) {
      room_at.val = Some(now)
      room_frame.val += 1
    }
    let h = dmax(0.0, c.height(sizes, shown, k, natural, now, room_frame.val, told=false))
    shown[k] = h
    let open = c.opened.contains(k)
    let fraction = if open && natural > 0.0 { dmax(0.0, dmin(1.0, h / natural)) } else { 1.0 }
    let scaled = open && (going || grows)
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
  let of_now = fn(k : String) -> (Bool, Double, Bool, Bool)? {
    @signals.untracked(fn() { item_of(k) }).map(fn(r) { (middle(r.0), lead(r.0, r.1), grown(r.0), own(r.0)) })
  }
  let still = fn(k : String, natural : Double) -> @view.ListRoom {
    shown[k] = natural
    @view.list_room(natural)
  }
  // (the last row, where it is one whose content goes on the way itself: the composer's room under the messages)
  let own_last = fn() -> String? {
    let n = (rows.snapshot)().1
    if n == 0 { return None }
    let it = item(n - 1)
    if own(it) { Some((rows.key)(n - 1)) } else { None }
  }
  let busy = fn() { !self.causes.by.is_empty() || !goings.is_empty() }
  let room = fn(k : String, natural : Double) -> @view.ListRoom {
    told.get() |> ignore
    let c = self.causes
    c.read()
    if !busy() {
      return still(k, natural)
    }
    let now = if v.logic_at() < c.end { v.drawn_at() } else { v.logic_at() }
    room_with(now, k, natural, of_now)
  }
  // (the rooms as they are now, read before a layout that lays them out reads none of what they are worked out of)
  let room_now = fn() -> (String, Double) -> @view.ListRoom {
    told.get() |> ignore
    let c = self.causes
    c.read()
    if !busy() {
      return still
    }
    let now = if v.logic_at() < c.end { v.drawn_at() } else { v.logic_at() }
    // (what each row on its way is worked out by, read now: those on their way and the last, no other)
    let pre : Map[String, (Bool, () -> Double, Bool, Bool)] = {}
    let note = fn(k : String) {
      if pre.contains(k) { return }
      match item_of(k) {
        Some((it, i)) => {
          let over = match lead_in_layout {
            Some(f) => f(it, i)
            None => {
              let value = lead(it, i)
              fn() { value }
            }
          }
          pre[k] = (middle(it), over, grown(it), own(it))
        }
        None => ()
      }
    }
    c.by.each(fn(k, _) { note(k) })
    for g in goings {
      note(g.key)
    }
    let owned = own_last()
    fn(k, natural) {
      room_with(now, k, natural, fn(k) {
        match pre.get(k) {
          Some((in_middle, over, grows, owns)) => Some((in_middle, over(), grows, owns))
          None => Some((false, 0.0, false, owned == Some(k)))
        }
      })
    }
  }
  let lend = fn(row : @view.View, k : String) {
    row.lends(node_row_way, fn() {
      told.get() |> ignore
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
    told.get() |> ignore
    self.causes.read()
    self.causes.end > v.logic_at() && self.causes.by.values().any(fn(cm) { cm.0 is Comes(_) })
  }
  let moving = fn() -> Array[String] {
    told.get() |> ignore
    let c = self.causes
    c.read()
    if !busy() {
      return []
    }
    let seen : Set[String] = Set::new()
    let out : Array[String] = []
    let add = fn(k : String) { if !seen.contains(k) { seen.add(k); out.push(k) } }
    c.by.each(fn(k, _) { add(k) })
    for g in goings {
      add(g.key)
    }
    c.own.each(add)
    match own_last() {
      Some(k) => add(k)
      None => ()
    }
    out
  }
  { source, item_of, room, room_now, moving, lend, opening }
}
