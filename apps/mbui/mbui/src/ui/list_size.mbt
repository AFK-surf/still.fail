// A list's rows' heights as they change (still.fail's docs/list-motion.md, 2026-10-30 the user: 「那些会变长或缩短的消息
// 列表内容的动效协同起来的效果，需要系统性设计一下」「为啥每个改动都要自己处理一遍」). The page gives its list its rows
// each build, each by its key and its version (ListRows): from one build to the next the list itself works out what
// came (a key new to it: its room opening from nothing), what went (a key gone: kept in the list as it last was while
// its room closes) and what changed (another version: from the height it had to the new one), each from that moment,
// on a move's curve, the row laid out that tall and cut there. Every row stands where the rows before it end, so rows
// never lie over one another nor leave a gap, however many change at once, and nothing waits for another; what is in
// view stays where the list's own rule has it. A row's height going is its layout's alone: what is kept of a row's
// build is kept (its height looked up by its key as it is laid out), nothing is built again for it.

///|
/// What changed a row's height, and when (the frames' clock): it came into the list (from nothing), it goes from it
/// (to nothing: the row stays in the list till then, Ctx::row_gone), or what it holds changed (from the height it had
/// then).
pub(all) enum RowSize {
  Comes(Double)
  Goes(Double)
  Changed(Double)
} derive(Eq)

///|
fn RowSize::at(self : RowSize) -> Double {
  match self {
    Comes(t) | Goes(t) | Changed(t) => t
  }
}

///|
/// A row's way from one height to another: from `from` at `start` (its cause's moment, or later where what it is
/// laid out at changed on its way), over `ms`, to what it is laid out at (none, going); `last` the height it was last
/// laid out at, `to` the one it went to then.
priv struct RowSizing {
  mut cause : RowSize
  mut from : Double
  mut start : Double
  mut ms : Double
  mut last : Double
  mut to : Double
  /// the frame it was last laid out in, and its way as that frame found it (a frame laid out twice, built again from
  /// what it read, lays it out the same: from there each time)
  mut frame : Int
  mut was : (Double, Double, Double)
}

///|
/// How long a row's height takes to go to its new one: a near Move's (docs/motion.md Curves). Not yet as long as its
/// way is far, as every other move is: a row's height is worked out by its key as the list is laid out (ListRows),
/// its way's length to come with that.
pub let row_size_ms : Double = 300.0

///|
/// Whether the row `key` of list `list` is gone (its way to nothing over by `now`): what keeps it in the list till
/// then drops it (its declared end, never whether it moves: docs/motion.md rule 3).
pub fn row_gone(at : Double, now : Double) -> Bool {
  // (a hair short of it, a sum of ms rounded off, is there)
  now >= at + row_size_ms - 0.001
}

///|
/// Row `k`, laid out `natural` tall, as tall as what changed it has it at `now` (its list's ListRows, by its key): its
/// way set out the first time it is laid out with it (from the height it was had at, nothing for one coming), and again
/// from where it is for a new one.
fn ListState::row_sized(self : ListState, k : Int, natural : Double, now : Double, frame : Int) -> Double {
  let (key, cause, ms) = match self.causes {
    Some(c) if k < c.keys.length() => {
      c.read()
      match c.by.get(c.keys[k]) {
        Some((cause, ms)) => (c.keys[k], cause, ms)
        None => return natural
      }
    }
    _ => return natural
  }
  let r = match self.sizes.get(key) {
    Some(r) => r
    // (its way over before it was ever laid out: as tall as it is)
    None if now >= cause.at() + ms => return if cause is Goes(_) { 0.0 } else { natural }
    None => {
      let from = match cause {
        Comes(_) => 0.0
        _ => if self.heights[k] >= 0.0 { self.heights[k] } else { natural }
      }
      let r = { cause, from, start: cause.at(), ms, last: from, to: -1.0, frame: -1, was: (from, from, -1.0) }
      self.sizes[key] = r
      r
    }
  }
  if r.frame == frame {
    let (from, last, to) = r.was
    r.from = from
    r.last = last
    r.to = to
  } else {
    r.frame = frame
    r.was = (r.from, r.last, r.to)
  }
  if r.cause != cause {
    // set out again from where it is (as last laid out: the way it was on gives way to the new one)
    r.from = match cause {
      Comes(_) if r.cause is Goes(_) => r.last
      Comes(_) => 0.0
      _ => r.last
    }
    r.cause = cause
    r.start = cause.at()
    r.ms = ms
    r.to = -1.0
  }
  // (told again as long as another, by the same cause: what it goes with timed anew once it knows its way, words sent
  // flying to it; from the same moment, on the same way)
  if ms != r.ms {
    r.ms = ms
  }
  let to = match cause {
    Goes(_) => 0.0
    _ => natural
  }
  // (what it is laid out at changed on its way, a picture in it come to its size: on from where it is to that, as a
  // move's way given another end goes on, never a step)
  // (not for what lays it out a hair otherwise: on the device's pixels or not, a frame built again)
  // (its end kept where its cause put it: the way from where it is now to the new end in what is left of it)
  let p = Ease::Move.at((now - r.start) / r.ms)
  if r.to >= 0.0 && (to - r.to).abs() > 0.5 && p < 0.9 {
    r.from = (r.last - to * p) / (1.0 - p)
  }
  r.to = to
  let h = if p >= 1.0 { to } else { r.from + (to - r.from) * p }
  r.last = h
  h
}

///|
/// When the last of a list's rows' ways to their heights is over (-1: none under way).
fn ListState::sizes_rest(self : ListState) -> Double {
  let mut t = -1.0
  self.sizes.each(fn(_, r) { t = dmax(t, r.start + r.ms) })
  t
}

///|
/// What is over of the rows' ways forgotten once its row is no longer in the list's last build (the keys said this
/// time), the causes of rows past its end with them.
fn ListState::sizes_kept(self : ListState, now : Double) -> Unit {
  let past : Array[String] = []
  self.sizes.each(fn(k, r) {
    // (one going kept a while past its end: its row out of the list by then, Ctx::row_gone)
    if now >= r.start + r.ms + (if r.cause is Goes(_) { row_size_ms } else { 0.0 }) {
      past.push(k)
    }
  })
  for k in past {
    self.sizes.remove(k)
  }
}

///|
/// A list's rows' ways to their heights as what moves (frames till the last is over, the list laid out again each).
priv struct Sizes {
  st : ListState
}

///|
impl Moving for Sizes with rest_at(self, now, frame) {
  ignore(frame)
  // (over: at rest, whatever is kept of a way gone by)
  // (a hair past now, a sum of ms rounded off: at rest, as at its end)
  let t = self.st.sizes_rest()
  if t > now + 0.001 {
    t
  } else {
    -1.0
  }
}


///|
/// Why each row of a list goes to another height, by its key, and the keys of its rows in order as last given (its
/// ListRows' answer, for its layout: Ctx::list's `sized`).
pub struct RowCauses {
  by : Map[String, (RowSize, Double)]
  mut keys : Array[String]
  /// told as any of it changes: what its layout reads it by (Ctx::list), and what a row reads of it (ListRows::came,
  /// went)
  priv said : @signals.Signal[Int]
  priv mut n : Int
}

///|
/// Its rows' keys now (`keys`), and whether why any goes to another height changed (`moved`): what reads it told if
/// either did (not for the same keys given anew).
fn RowCauses::told(self : RowCauses, keys : Array[String], moved : Bool) -> Unit {
  let was = self.keys
  self.keys = keys
  if moved || !(physical_equal(was, keys) || was == keys) {
    self.n += 1
    self.said.set(self.n)
  }
}

///|
/// What reads it is told as it changes from now.
fn RowCauses::read(self : RowCauses) -> Unit {
  self.said.get() |> ignore
}

///|
/// A row gone from a list, in it still as it last was while its room closes: it, when it went, the row it came after.
priv struct GoingRow[T] {
  item : T
  at : Double
  after : String
}

///|
/// A list's rows as the page gives them each build (ListRows::rows), and what the list made of them.
pub struct ListRows[T] {
  priv was : Map[String, String]
  priv mut order : Array[(String, T)]
  priv going : Map[String, GoingRow[T]]
  priv causes : RowCauses
  priv mut given : Bool
  priv mut last_keys : Array[String]
  priv mut last_items : Array[T]
  /// the keys going, read by each row as whether it is one
  priv going_said : @signals.Keyed[String]
}

///|
pub fn[T] ListRows::new() -> ListRows[T] {
  { was: {}, order: [], going: {}, causes: { by: {}, keys: [], said: @signals.signal(0), n: 0 }, given: false, last_keys: [], last_items: [], going_said: @signals.keyed() }
}

///|
/// The rows of a list as they are now (`keys`, `items` by the same index, `version` of each: what it shows), with what
/// went from them still among them (after the row each came after) while its room closes, and their keys. What changed
/// since they were last given is said from now: a key new comes, one gone goes, another version changes. Not
/// `watched` (the list not followed, its page another's, a page of it read anew): what changed is so at once.
/// `ms`: how long a row's coming takes where it goes with another motion of its cause (words flying to it), a row's
/// move otherwise. `comes`: whether a row new to the list comes now (false: it was there before, only brought now, as
/// what was caught up on), there at once.
pub fn[T] ListRows::rows(
  self : ListRows[T],
  c : Ctx,
  keys : Array[String],
  items : Array[T],
  version : (T) -> String,
  watched? : Bool = true,
  ms? : (String) -> Double? = fn(_) { None },
  comes? : (T) -> Bool = fn(_) { true },
) -> (Array[T], Array[String]) {
  let now = c.moment()
  // (the same arrays as last given: nothing of them changed, nothing to look over)
  let same = self.given &&
    physical_equal(keys, self.last_keys) &&
    physical_equal(items, self.last_items)
  self.last_keys = keys
  self.last_items = items
  let here : Map[String, Bool] = {}
  if !same {
    for k in keys {
      here[k] = true
    }
  }
  // (whether any of what the list and its rows read of it changed: told them as it did)
  let mut moved = false
  if same && watched {
    ()
  } else if self.given && watched {
    for i, k in keys {
      let v = version(items[i])
      match self.was.get(k) {
        None =>
          if comes(items[i]) {
            self.causes.by[k] = (Comes(now), ms(k).unwrap_or(row_size_ms))
            moved = true
          }
        // (changed as it comes: still coming, on to what it is now)
        Some(w) if w != v =>
          match self.causes.by.get(k) {
            Some((Comes(at), ms)) if now < at + ms => ()
            _ => {
              self.causes.by[k] = (Changed(now), row_size_ms)
              moved = true
            }
          }
        _ => ()
      }
      if self.going.contains(k) {
        self.going.remove(k)
        moved = true
      }
    }
    let mut prev = ""
    for r in self.order {
      let (k, item) = r
      if !here.contains(k) && !self.going.contains(k) {
        self.going[k] = { item, at: now, after: prev }
        self.causes.by[k] = (Goes(now), row_size_ms)
        moved = true
      }
      if here.contains(k) || self.going.contains(k) {
        prev = k
      }
    }
  } else if !self.going.is_empty() || !self.causes.by.is_empty() {
    self.going.clear()
    self.causes.by.clear()
    moved = true
  }
  // (coming as long as another motion of its cause, told anew how long: words sent, timed once they know their way)
  let retimed : Array[(String, Double, Double)] = []
  self.causes.by.each(fn(k, cm) {
    match (cm, ms(k)) {
      ((Comes(at), was), Some(now_ms)) if now_ms != was => retimed.push((k, at, now_ms))
      _ => ()
    }
  })
  for r in retimed {
    self.causes.by[r.0] = (Comes(r.1), r.2)
    moved = true
  }
  self.given = true
  // what is over of it forgotten: what went, out of the list at its declared end
  let over : Array[String] = []
  self.going.each(fn(k, g) { if row_gone(g.at, now) { over.push(k) } })
  for k in over {
    self.going.remove(k) |> ignore
    moved = true
  }
  let past : Array[String] = []
  self.causes.by.each(fn(k, cm) {
    let (cause, ms) = cm
    if !self.going.contains(k) && (now >= cause.at() + ms || cause is Goes(_)) {
      past.push(k)
    }
  })
  for k in past {
    self.causes.by.remove(k)
    moved = true
  }

  // (built again at the end of the first of them to go: out of the list then)
  let mut next = @double.infinity
  // (at the moment row_gone says it is out, a hair short of its sum)
  self.going.each(fn(_, g) { next = dmin(next, g.at + row_size_ms - 0.001) })
  if next < @double.infinity {
    c.shows_until(next)
  }
  if !same {
    self.was.clear()
    for i, k in keys {
      self.was[k] = version(items[i])
    }
    self.order = keys.mapi(fn(i, k) { (k, items[i]) })
  }
  self.going_said.set(self.going.keys().collect())
  // (nothing going: the arrays as given, the same ones while they are, so what is worked out of them is kept)
  if self.going.is_empty() {
    self.causes.told(keys, moved)
    return (items, keys)
  }
  // the rows going among them, each after the row it came after (the first, before all)
  let all_keys = keys.copy()
  let all_items = items.copy()
  {
    let order = self.going.to_array()
    order.sort_by(fn(a, b) { a.1.at.compare(b.1.at) })
    for g in order {
      let (k, go) = g
      let mut at = 0
      if go.after != "" {
        for i, kk in all_keys {
          if kk == go.after {
            at = i + 1
          }
        }
      }
      all_keys.insert(at, k)
      all_items.insert(at, go.item)
    }
  }
  self.causes.told(all_keys, moved)
  (all_items, all_keys)
}

///|
/// What changed its rows' heights, for the list's layout (Ctx::list's `sized`).
pub fn[T] ListRows::sized(self : ListRows[T]) -> RowCauses {
  self.causes
}

///|
/// When row `key` came into the list as it was watched, while it opens its room (None: it did not, or it is open).
pub fn[T] ListRows::came(self : ListRows[T], key : String) -> Double? {
  self.causes.read()
  match self.causes.by.get(key) {
    Some((Comes(at), _)) => Some(at)
    _ => None
  }
}

///|
/// When row `key` went from the list, while its room closes (None: it is in it).
pub fn[T] ListRows::went(self : ListRows[T], key : String) -> Double? {
  if !self.going_said.has(key) {
    return None
  }
  self.going.get(key).map(fn(g) { g.at })
}

///|
/// Whether a row come into the list still opens its room: built again as the last of them is open.
pub fn[T] ListRows::opening(self : ListRows[T], c : Ctx) -> Bool {
  let now = c.moment()
  let mut last = -1.0
  self.causes.by.each(fn(_, cm) {
    match cm {
      (Comes(at), ms) if at + ms > now => last = dmax(last, at + ms)
      _ => ()
    }
  })
  if last > now {
    c.shows_until(last)
    true
  } else {
    false
  }
}
