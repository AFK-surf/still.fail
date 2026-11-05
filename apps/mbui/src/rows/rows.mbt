// A topic's keyed list read by its index (mbui docs/retained.md, rule 12): a subscription's list at a path (a chat's
// messages, `["messages"]`) kept as its items in order, each with its key and a version of its own, and changed by the
// core's keyed ops itself (the subscription's whole value has the list only as it is read: core client.mbt's
// Sub::value). What reads it reads how many there are, row i's key and value, and the changes since it last read
// (inserted, removed, moved, one row's value set), each with what caused it (a message come, one sent from here,
// history fetched; given whole: the first value, one after an error, the list or what holds it set, an op from a core
// that says no cause). Where a key is is looked for from where it was last, outwards (Compose's nearest range), never
// from a map of places; a row read by its key tells what read it only as that row is set, comes or goes, and where it
// is is carried along as rows come and go before it. Rows come one after another for one cause (a page of history,
// put one before the other) go in at once, one change.
// The keys are the core's (core-ts collections.ts): the fields an item's key is made of, as its keyed ops name them
// (delta.mbt's key_of).

///|
/// What caused a change of a list: a message come (to anyone looking), one sent from here, history fetched (come
/// before what was there), or the list given whole (its first value, after an error, by a core that says no cause:
/// shown as it is, nothing moving in).
pub(all) enum Cause {
  Came
  Sent
  History
  Given
} derive(Eq, Show, Debug)

///|
/// A list's change, as a reader is told it, in order: where each was or went counted as the list stood just after that
/// change.
pub(all) enum ListChange {
  /// `n` rows put in from `at`
  Inserted(Int, Int, Cause)
  /// rows taken out from `at`, their keys (in their order)
  Removed(Int, Array[String], Cause)
  /// the row keyed so moved from, to
  Moved(String, Int, Int, Cause)
  /// row `at`'s value set (its version one more)
  Set(Int, Cause)
  /// all of it to be read again: given whole, or what this reader had not read let go of
  Whole(Cause)
} derive(Eq, Show, Debug)

///|
/// What a list made of an op of its subscription's (TopicList::take): not its (the op goes to the rest of the value);
/// done to it (the value's list is the list's: nothing more); or one that sets it or what holds it (applied to the
/// value, the list then given whole from it).
pub(all) enum Took {
  NotMine
  Done
  Anew
} derive(Eq, Show)

///|
/// A topic's keyed list.
pub struct TopicList {
  priv path : Array[String]
  priv fields : Array[Json]
  /// Older pages, stored in reverse so adding a page before the first item does not copy the rest.
  priv mut front_keys : Array[String]
  priv mut front_values : Array[Json]
  priv mut front_versions : Array[Int]
  priv mut keys : Array[String]
  priv mut values : Array[Json]
  priv mut versions : Array[Int]
  /// which keys it holds (not where: that is looked for, find), kept as rows come and go, so a key it does not hold
  /// is known so without looking through all of it
  priv holds : Map[String, Bool]
  /// where the last key looked for was found: the next looked for from there
  priv mut near : Int
  /// rows come one before the other for one cause, not in yet: where they go, and they (the last come first: in their
  /// order from its end), their cause
  priv mut coming_at : Int
  priv coming : Array[(String, Json)]
  priv mut coming_why : Cause
  /// what happened, from change number `base` on, kept while a reader has not read it
  priv log : Array[ListChange]
  priv mut base : Int
  priv mut count : Int
  /// how many changes there have been: what follows its length and its changes reads it
  priv told : @signals.Signal[Int]
  priv readers : Array[ListReader]
  /// the rows read by key (value_of, version_of): each where it is, carried along as rows come and go, a signal told
  /// as it is set, comes or goes; let go of as none follows it
  priv by_key : Map[String, KeyRead]
  /// rows looked at finding keys, rows copied and items taken in: for tests that count what a change costs
  priv mut work : Int
}

///|
priv struct KeyRead {
  mut at : Int
  mut n : Int
  said : @signals.Signal[Int]
}

///|
/// What reads a list's changes: those since it last read them.
pub struct ListReader {
  priv of : TopicList
  priv mut seen : Int
}

///|
/// The list at `path` of a value (fields of objects from its top), by the keys its `fields` make (core-ts
/// collections.ts: a chat's messages `["seq", "outgoing"]`), as `v` has it.
pub fn TopicList::new(path : Array[String], fields : Array[String], v : Json?) -> TopicList {
  let l : TopicList = {
    path,
    fields: fields.map(Json::string(_)),
    front_keys: [],
    front_values: [],
    front_versions: [],
    keys: [],
    values: [],
    versions: [],
    holds: {},
    near: 0,
    coming_at: -1,
    coming: [],
    coming_why: Given,
    log: [],
    base: 0,
    count: 0,
    told: @signals.signal(0, same=fn(a, b) { a == b }),
    readers: [],
    by_key: {},
    work: 0,
  }
  l.given(v)
  l
}

///|
/// Where in its subscription's value it is.
pub fn TopicList::path(self : TopicList) -> Array[String] {
  self.path
}

///|
/// How many rows it has, followed: told of each change.
pub fn TopicList::length(self : TopicList) -> Int {
  self.told.get() |> ignore
  self.length_now()
}

///|
/// How many rows it has, followed by nothing (read where no signal may be: a layout's).
pub fn TopicList::length_now(self : TopicList) -> Int {
  self.front_keys.length() + self.keys.length()
}

///|
fn TopicList::key_now(self : TopicList, i : Int) -> String {
  let front = self.front_keys.length()
  if i < front { self.front_keys[front - 1 - i] } else { self.keys[i - front] }
}

///|
fn TopicList::value_now(self : TopicList, i : Int) -> Json {
  let front = self.front_values.length()
  if i < front { self.front_values[front - 1 - i] } else { self.values[i - front] }
}

///|
fn TopicList::version_now(self : TopicList, i : Int) -> Int {
  let front = self.front_versions.length()
  if i < front { self.front_versions[front - 1 - i] } else { self.versions[i - front] }
}

///|
/// Row `i`'s key, followed by nothing (its changes are: a reader's).
pub fn TopicList::key(self : TopicList, i : Int) -> String {
  self.work += 1
  self.key_now(i)
}

///|
/// Row `i`'s value, followed by nothing.
pub fn TopicList::value(self : TopicList, i : Int) -> Json {
  self.value_now(i)
}

///|
/// Row `i`'s version: one more each time its value is set. Followed by nothing.
pub fn TopicList::version(self : TopicList, i : Int) -> Int {
  self.version_now(i)
}

///|
/// Its rows' values as one array (its subscription's whole value as it is read): all of it gone through.
pub fn TopicList::to_json(self : TopicList) -> Json {
  let n = self.length_now()
  self.work += n
  Json::array(Array::makei(n, fn(i) { self.value_now(i) }))
}

///|
/// Where the row keyed `key` is, looked for from `near` outwards (rows looked at as many as it is away), None where
/// it is not in it. Followed by nothing.
pub fn TopicList::find(self : TopicList, key : String, near~ : Int) -> Int? {
  let n = self.length_now()
  if n == 0 || !self.holds.contains(key) {
    return None
  }
  let from = if near < 0 { 0 } else if near >= n { n - 1 } else { near }
  // (where it was looked for first; then the ends: history is put before the first row, even where what was looked
  // for last came at the other end)
  self.work += 1
  if self.key_now(from) == key { return Some(from) }
  for end in [0, n - 1] {
    if end != from {
      self.work += 1
      if self.key_now(end) == key { return Some(end) }
    }
  }
  let mut d = 0
  while from - d >= 0 || from + d < n {
    let a = from - d
    if a >= 0 {
      self.work += 1
      if self.key_now(a) == key {
        return Some(a)
      }
    }
    let b = from + d
    if d > 0 && b < n {
      self.work += 1
      if self.key_now(b) == key {
        return Some(b)
      }
    }
    d += 1
  }
  None
}

///|
/// The row keyed `key`'s value, followed by it alone: what reads it is told as that row is set, comes or goes.
pub fn TopicList::value_of(self : TopicList, key : String) -> Json? {
  match self.key_read(key) {
    Some(i) => Some(self.value_now(i))
    None => None
  }
}

///|
/// The row keyed `key`'s version, followed by it alone (value_of).
pub fn TopicList::version_of(self : TopicList, key : String) -> Int? {
  match self.key_read(key) {
    Some(i) => Some(self.version_now(i))
    None => None
  }
}

///|
/// Where the row keyed `key` is, its signal read: from where it was carried to.
fn TopicList::key_read(self : TopicList, key : String) -> Int? {
  let r = match self.by_key.get(key) {
    Some(r) => r
    None => {
      let r = { at: self.near, n: 0, said: @signals.signal(0, same=fn(a, b) { a == b }) }
      self.by_key[key] = r
      r
    }
  }
  r.said.get() |> ignore
  match self.find(key, near=r.at) {
    Some(i) => {
      r.at = i
      Some(i)
    }
    None => None
  }
}

///|
/// Rows looked at, copied and taken in since it was made: for a test that counts what a change costs.
pub fn TopicList::work(self : TopicList) -> Int {
  self.work
}

///|
/// A reader of its changes, from now on.
pub fn TopicList::reader(self : TopicList) -> ListReader {
  let r = { of: self, seen: self.count }
  self.readers.push(r)
  r
}

///|
/// The changes since this reader last read them (since its making, the first time), followed: what reads them told of
/// the next. One Whole where it was given whole since, or where what this reader had not read was let go of.
pub fn ListReader::changes(self : ListReader) -> Array[ListChange] {
  let l = self.of
  let now = l.told.get()
  if self.seen == now {
    return []
  }
  let out = if self.seen < l.base {
    [Whole(Given)]
  } else {
    let from = self.seen - l.base
    Array::makei(l.log.length() - from, fn(i) { l.log[from + i] })
  }
  self.seen = now
  l.trim()
  out
}

///|
/// This reader reads no more: nothing kept for it.
pub fn ListReader::let_go(self : ListReader) -> Unit {
  let rs = self.of.readers
  match rs.search_by(fn(r) { physical_equal(r, self) }) {
    Some(i) => rs.remove(i) |> ignore
    None => ()
  }
  self.of.trim()
}

///|
/// Where the row that was at `i` before `changes` is after them (an anchor's place carried over to look for it from):
/// None where it was taken out, or the list given whole.
pub fn index_after(changes : Array[ListChange], i : Int) -> Int? {
  let mut at = i
  for c in changes {
    match shifted(c, at) {
      Some(a) => at = a
      None => return None
    }
  }
  Some(at)
}

///|
/// Where the row at `at` is after change `c`: None where it was taken out, or the list given whole.
fn shifted(c : ListChange, at : Int) -> Int? {
  match c {
    Inserted(from, n, _) => Some(if from <= at { at + n } else { at })
    Removed(from, keys, _) =>
      if at >= from + keys.length() {
        Some(at - keys.length())
      } else if at >= from {
        None
      } else {
        Some(at)
      }
    Moved(_, from, to, _) =>
      if at == from {
        Some(to)
      } else {
        let mut a = at
        if from < a {
          a = a - 1
        }
        if to <= a {
          a = a + 1
        }
        Some(a)
      }
    Set(_, _) => Some(at)
    Whole(_) => None
  }
}

///|
fn TopicList::tell(self : TopicList, c : ListChange) -> Unit {
  // (the rows read by key carried along: those few, not all of it)
  match c {
    Inserted(_, _, _) | Removed(_, _, _) | Moved(_, _, _, _) =>
      self.by_key.each(fn(_, r) {
        match shifted(c, r.at) {
          Some(a) => r.at = a
          None => ()
        }
      })
    _ => ()
  }
  self.count += 1
  if self.readers.is_empty() {
    self.base = self.count
  } else {
    self.log.push(c)
    // (a reader far behind: what it has not read let go of, it reads it whole)
    if self.log.length() > 2 * self.length_now() + 64 {
      self.base = self.count
      self.log.clear()
    }
  }
  self.told.set(self.count)
}

///|
/// What every reader has read let go of.
fn TopicList::trim(self : TopicList) -> Unit {
  let mut least = self.count
  for r in self.readers {
    if r.seen < least {
      least = r.seen
    }
  }
  if least < self.base {
    least = self.base
  }
  let n = least - self.base
  if n > 0 {
    let left = self.log.length() - n
    for i in 0..<left {
      self.log[i] = self.log[i + n]
    }
    self.log.truncate(left)
    self.base = least
  }
}

///|
/// The row keyed `key`'s readers told it changed (set, come, gone); one followed by none let go.
fn TopicList::said_of(self : TopicList, key : String) -> Unit {
  match self.by_key.get(key) {
    Some(r) =>
      if r.said.watched() {
        r.n += 1
        r.said.set(r.n)
      } else {
        self.by_key.remove(key)
      }
    None => ()
  }
}

///|
/// An item's key in a list: its key fields' values (delta.mbt's key_of), as text.
fn item_key(item : Json, fields : Array[Json]) -> String {
  key_of(item, fields).stringify()
}

///|
/// What is at `path` of `v`, through objects' fields.
pub fn value_at(v : Json?, path : Array[String]) -> Json? {
  let mut now = v
  for f in path {
    now = match now {
      Some(Object(m)) => m.get(f)
      _ => None
    }
  }
  now
}

///|
/// `v` with `list` at `path` (through objects' fields, each copied along it): `v` where there is no such place.
pub fn with_at(v : Json, path : Array[String], list : Json) -> Json {
  fn go(node : Json, d : Int) -> Json {
    if d == path.length() {
      return list
    }
    match node {
      Object(m) if m.contains(path[d]) => {
        let c = m.copy()
        c[path[d]] = go(m[path[d]], d + 1)
        Json::object(c)
      }
      _ => node
    }
  }

  go(v, 0)
}

///|
/// The list as `v` (its subscription's value; none: after an error) has it, whole: gone through once.
pub fn TopicList::given(self : TopicList, v : Json?) -> Unit {
  self.coming.clear()
  self.coming_at = -1
  let items = match value_at(v, self.path) {
    Some(Array(a)) => a
    _ => []
  }
  self.keys = []
  self.values = []
  self.versions = []
  self.front_keys = []
  self.front_values = []
  self.front_versions = []
  self.holds.clear()
  for item in items {
    self.work += 1
    let k = item_key(item, self.fields)
    self.holds[k] = true
    self.keys.push(k)
    self.values.push(item)
    self.versions.push(0)
  }
  // (what followed a row by its key told: it may have changed, come or gone; looked for from the start)
  let followed = self.by_key.keys().collect()
  for k in followed {
    match self.by_key.get(k) {
      Some(r) => r.at = 0
      None => ()
    }
    self.said_of(k)
  }
  self.log.clear()
  self.count += 1
  self.base = self.count
  self.told.set(self.count)
}

///|
/// The list as `v` has it, whole, taken as what changed from what it holds (a made-up core's value, given whole each
/// version): rows gone taken out, those come put in where they are, those moved put there, those another value set, each
/// a change of its own as an op of its subscription's would be. Gone through once.
pub fn TopicList::given_keyed(self : TopicList, v : Json?) -> Unit {
  let items = match value_at(v, self.path) {
    Some(Array(a)) => a
    _ => []
  }
  let keys = items.map(fn(item) { item_key(item, self.fields) })
  let want : Set[String] = Set::from_array(keys)
  self.come_in()
  let mut i = self.length_now() - 1
  while i >= 0 {
    self.work += 1
    if !want.contains(self.key_now(i)) {
      self.drop_at(i, Given)
    }
    i -= 1
  }
  for j, item in items {
    let k = keys[j]
    self.come_in()
    if j < self.length_now() && self.key_now(j) == k {
      self.work += 1
      let was = self.value_now(j)
      if !physical_equal(was, item) && was != item {
        self.set_at(j, item, Given)
      }
    } else {
      match self.find(k, near=j) {
        Some(from) => {
          self.drop_at(from, Given)
          self.come(j, k, item, Given)
        }
        None => self.come(j, k, item, Given)
      }
    }
  }
  self.come_in()
}

///|
/// The cause an op says (core-ts: `why`), Given where it says none (a core from before it said).
fn cause_of(op : Map[String, Json]) -> Cause {
  match op.get("why") {
    Some(String("came")) => Came
    Some(String("sent")) => Sent
    Some(String("history")) => History
    _ => Given
  }
}

///|
/// The rows come one before the other (TopicList::take's puts) put in now, at once: one change.
pub fn TopicList::come_in(self : TopicList) -> Unit {
  let n = self.coming.length()
  if n == 0 {
    return
  }
  let at = self.coming_at
  let old = self.length_now()
  if at == old {
    // (at the end: put after what is there, nothing of it copied but as the arrays grow)
    self.work += n
    for j in 0..<n {
      let (k, item) = self.coming[n - 1 - j]
      self.keys.push(k)
      self.values.push(item)
      self.versions.push(0)
    }
    let came = self.coming.map(fn(p) { p.0 })
    self.coming.clear()
    self.coming_at = -1
    self.near = at
    self.tell(Inserted(at, n, self.coming_why))
    for k in came {
      self.said_of(k)
    }
    return
  }
  if at == 0 {
    // Each new page is stacked in reverse before the earlier pages; the existing messages stay where they are.
    self.work += n
    for (k, item) in self.coming {
      self.front_keys.push(k)
      self.front_values.push(item)
      self.front_versions.push(0)
    }
    let came = self.coming.map(fn(p) { p.0 })
    self.coming.clear()
    self.coming_at = -1
    self.near = 0
    self.tell(Inserted(0, n, self.coming_why))
    for k in came { self.said_of(k) }
    return
  }
  // (before what is there: all of it copied once, with them in their place)
  self.work += old + n
  let keys = Array::makei(old + n, fn(i) {
    if i < at {
      self.key_now(i)
    } else if i < at + n {
      self.coming[n - 1 - (i - at)].0
    } else {
      self.key_now(i - n)
    }
  })
  let values = Array::makei(old + n, fn(i) {
    if i < at {
      self.value_now(i)
    } else if i < at + n {
      self.coming[n - 1 - (i - at)].1
    } else {
      self.value_now(i - n)
    }
  })
  let versions = Array::makei(old + n, fn(i) {
    if i < at {
      self.version_now(i)
    } else if i < at + n {
      0
    } else {
      self.version_now(i - n)
    }
  })
  self.keys = keys
  self.values = values
  self.versions = versions
  self.front_keys = []
  self.front_values = []
  self.front_versions = []
  let came = self.coming.map(fn(p) { p.0 })
  self.coming.clear()
  self.coming_at = -1
  self.near = at
  self.tell(Inserted(at, n, self.coming_why))
  for k in came {
    self.said_of(k)
  }
}

///|
/// Row `key` with `item` coming in at `at` for `why`: with those coming already where it goes just before them (a page
/// of history, put last first), else they put in first.
fn TopicList::come(self : TopicList, at : Int, key : String, item : Json, why : Cause) -> Unit {
  if self.coming.length() > 0 && (at != self.coming_at || why != self.coming_why) {
    self.come_in()
  }
  self.holds[key] = true
  if self.coming.is_empty() {
    self.coming_at = at
    self.coming_why = why
  }
  self.coming.push((key, item))
}

///|
fn TopicList::set_at(self : TopicList, at : Int, item : Json, why : Cause) -> Unit {
  self.work += 1
  let front = self.front_keys.length()
  if at < front {
    let i = front - 1 - at
    self.front_values[i] = item
    self.front_versions[i] += 1
  } else {
    let i = at - front
    self.values[i] = item
    self.versions[i] += 1
  }
  self.near = at
  self.tell(Set(at, why))
  self.said_of(self.key_now(at))
}

///|
/// Where an op's `before` puts a row: before the row keyed so (or before those coming in front of it), at the end
/// where it is null, absent or not there.
fn TopicList::place_before(self : TopicList, before : Json?) -> Int {
  match before {
    None | Some(Null) => self.length_now()
    Some(b) => {
      let k = b.stringify()
      if self.coming.last() is Some((first, _)) && first == k {
        return self.coming_at
      }
      self.come_in()
      self.find(k, near=self.near).unwrap_or(self.length_now())
    }
  }
}

///|
/// What `op` (one of a delta's) does to the list: NotMine where it is elsewhere in the value; Done where it was the
/// list's (a keyed op on it, an op in one of its items), Anew where it sets the list or what holds it (the caller
/// gives the list the value as the op leaves it).
pub fn TopicList::take(self : TopicList, op : Map[String, Json]) -> Took {
  guard op.get("path") is Some(Array(path)) else { return NotMine }
  let n = self.path.length()
  for i in 0..<(if n < path.length() { n } else { path.length() }) {
    guard path[i] is String(f) && f == self.path[i] else { return NotMine }
  }
  if path.length() < n || (path.length() == n && !op.contains("key")) {
    return Anew
  }
  let why = cause_of(op)
  if path.length() > n {
    // (in an item, by its place: that item set as the op leaves it)
    self.come_in()
    guard index_of(path[n]) is Some(i) && i < self.length_now() else { return Done }
    let rest = path[n + 1:].to_owned()
    let inner = op.copy()
    inner["path"] = Json::array(rest)
    let item = apply_delta(self.value_now(i), [Json::object(inner)])
    if item_key(item, self.fields) == self.key_now(i) {
      self.set_at(i, item, why)
    } else {
      // (its key changed: taken out, and in again where it was)
      self.drop_at(i, why)
      self.come(i, item_key(item, self.fields), item, why)
    }
    return Done
  }
  match (op.get("drop"), op.get("patch"), op.get("move")) {
    (Some(k), _, _) => {
      self.come_in()
      match self.find(k.stringify(), near=self.near) {
        Some(i) => self.drop_at(i, why)
        None => ()
      }
    }
    (None, Some(k), _) => {
      self.come_in()
      match (self.find(k.stringify(), near=self.near), op.get("ops")) {
        (Some(i), Some(Array(ops))) => self.set_at(i, apply_delta(self.value_now(i), ops), why)
        _ => ()
      }
    }
    (None, None, Some(k)) => {
      self.come_in()
      match self.find(k.stringify(), near=self.near) {
        Some(from) => self.moved(k.stringify(), from, op.get("before"), why)
        None => ()
      }
    }
    (None, None, None) =>
      match op.get("put") {
        Some(item) => {
          let k = item_key(item, self.fields)
          if self.holds.contains(k) {
            self.come_in()
            match self.find(k, near=self.near) {
              Some(i) => {
                self.set_at(i, item, why)
                if op.contains("before") {
                  self.moved(k, i, op.get("before"), why)
                }
              }
              None => ()
            }
          } else {
            self.come(self.place_before(op.get("before")), k, item, why)
          }
        }
        None => ()
      }
  }
  Done
}

///|
/// Remove a row from the two parts without notifying readers.
fn TopicList::remove_raw(self : TopicList, at : Int) -> (String, Json, Int) {
  let front = self.front_keys.length()
  if at < front {
    let i = front - 1 - at
    self.work += front - 1 - i
    (self.front_keys.remove(i), self.front_values.remove(i), self.front_versions.remove(i))
  } else {
    let i = at - front
    self.work += self.keys.length() - 1 - i
    (self.keys.remove(i), self.values.remove(i), self.versions.remove(i))
  }
}

///|
/// Insert a row into the two parts without notifying readers.
fn TopicList::insert_raw(self : TopicList, at : Int, key : String, item : Json, version : Int) -> Unit {
  let front = self.front_keys.length()
  if at <= front {
    let i = front - at
    self.work += front - i
    self.front_keys.insert(i, key)
    self.front_values.insert(i, item)
    self.front_versions.insert(i, version)
  } else {
    let i = at - front
    self.work += self.keys.length() - i
    self.keys.insert(i, key)
    self.values.insert(i, item)
    self.versions.insert(i, version)
  }
}

///|
fn TopicList::drop_at(self : TopicList, i : Int, why : Cause) -> Unit {
  self.work += 1
  let (k, _, _) = self.remove_raw(i)
  self.holds.remove(k)
  self.near = i
  self.tell(Removed(i, [k], why))
  self.said_of(k)
}

///|
/// The row keyed `k`, at `from`, moved before the one `before` names (the end where none).
fn TopicList::moved(self : TopicList, k : String, from : Int, before : Json?, why : Cause) -> Unit {
  if before is Some(b) && b.stringify() == k {
    return
  }
  self.work += 1
  let (_, item, version) = self.remove_raw(from)
  let to = match before {
    None | Some(Null) => self.length_now()
    Some(b) => self.find(b.stringify(), near=from).unwrap_or(self.length_now())
  }
  self.insert_raw(to, k, item, version)
  self.near = to
  if to != from {
    self.tell(Moved(k, from, to, why))
  }
}
