// A chat's list read by its index (mbui docs/retained.md, rule 12), as the windowed list lays it out from its anchor
// (rule 11; mbui view's ListSource: how many rows, row i's key, a key looked for from where it was, a count of the
// changes of its rows' set or order): one row for each message, what goes with a message (the unread line over it,
// where it was sent elsewhere under it) drawn in its own row, so a message's index is its row's past those at the head.
// The rows that are no message's are at the two ends: the head (Top, Older, Empty), the tail (Newer, what is still
// going out, where the chat stands, the agents at work, Foot: Foot always the last). A message come, set, gone or moved
// is that row's change alone (the messages' list's own: ChatMessages); the two ends are a few rows, made again as the
// chat changes and compared by key. What a row shows is told by its key alone (version_of): a message set, or what goes
// with it, its row's version one more; nothing worked out for one row goes through all of them.

///|
/// A chat's rows (see above).
pub struct ChatRows {
  /// the messages, one row each
  messages : ChatMessages
  /// their changes since the rows last took them
  priv reader : @rows.ListReader
  /// a message's row's key (as the page keys it: the key it was sent as from here, else `m:` and its ts)
  priv key_of : (Message) -> String
  priv mut head : Array[Entry]
  priv mut tail : Array[Entry]
  /// each tail row's sign as last made (shown_sign): another, its version one more
  priv tail_signs : Map[String, String]
  /// the unread line as last made: over the message of this seq
  priv mut line : Double?
  /// how many times its rows' set or order changed, followed
  priv shape : @signals.Signal[Int]
  priv mut shapes : Int
  /// the rows read by key (version_of): each where it was last found, a signal told as what it shows changes
  priv read : Map[String, RowRead]
  /// rows looked at and made: for tests that count what a change costs
  priv mut work : Int
}

///|
priv struct RowRead {
  mut at : Int
  mut n : Int
  said : @signals.Signal[Int]
}

///|
/// The rows of a chat whose messages are `messages`, each message's row keyed by `key_of`.
pub fn ChatRows::new(messages : ChatMessages, key_of : (Message) -> String) -> ChatRows {
  {
    messages,
    reader: messages.rows.reader(),
    key_of,
    head: [Top],
    tail: [Foot],
    tail_signs: {},
    line: None,
    shape: @signals.signal(0, same=fn(a, b) { a == b }),
    shapes: 0,
    read: {},
    work: 0,
  }
}

///|
/// How many rows, followed: told as rows come, go or move.
pub fn ChatRows::length(self : ChatRows) -> Int {
  self.shape.get() |> ignore
  self.head.length() + self.count() + self.tail.length()
}

///|
/// How many times its rows' set or order changed, followed (ListSource's `changed`).
pub fn ChatRows::changed(self : ChatRows) -> Int {
  self.shape.get()
}

///|
/// Row `i`, followed by nothing.
pub fn ChatRows::entry(self : ChatRows, i : Int) -> Entry {
  let h = self.head.length()
  let n = self.count()
  if i < h {
    self.head[i]
  } else if i < h + n {
    Said(self.messages[i - h])
  } else {
    self.tail[i - h - n]
  }
}

///|
/// Row `i`'s key, followed by nothing.
pub fn ChatRows::key(self : ChatRows, i : Int) -> String {
  match self.entry(i) {
    Said(m) => (self.key_of)(m)
    e => e.id()
  }
}

///|
/// Where the row keyed `key` is, looked for from `near` outwards (rows looked at as many as it is away), None where it
/// is not one. Followed by nothing.
pub fn ChatRows::find(self : ChatRows, key : String, near : Int) -> Int? {
  let n = self.head.length() + self.count() + self.tail.length()
  if n == 0 {
    return None
  }
  let from = if near < 0 { 0 } else if near >= n { n - 1 } else { near }
  let mut d = 0
  while from - d >= 0 || from + d < n {
    let a = from - d
    if a >= 0 {
      self.work += 1
      if self.key(a) == key {
        return Some(a)
      }
    }
    let b = from + d
    if d > 0 && b < n {
      self.work += 1
      if self.key(b) == key {
        return Some(b)
      }
    }
    d += 1
  }
  None
}

///|
/// What the row keyed `key` shows, as a version, followed by it alone: one more as its message is set or what goes
/// with it (the unread line, where it was sent) changes, as a row at the ends shows otherwise; None where it is not one.
pub fn ChatRows::version_of(self : ChatRows, key : String) -> Int? {
  let r = match self.read.get(key) {
    Some(r) => r
    None => {
      let r = { at: self.length_now() - 1, n: 0, said: @signals.signal(0, same=fn(a, b) { a == b }) }
      self.read[key] = r
      r
    }
  }
  let v = r.said.get()
  match self.find(key, r.at) {
    Some(i) => {
      r.at = i
      Some(v)
    }
    None => None
  }
}

///|
/// Rows looked at and made since it was made: for a test that counts what a change costs.
pub fn ChatRows::work(self : ChatRows) -> Int {
  self.work + self.messages.rows.work()
}

///|
/// How many messages, followed by nothing (what follows the rows follows `shape`).
fn ChatRows::count(self : ChatRows) -> Int {
  @signals.untracked(fn() { self.messages.rows.length() })
}

///|
fn ChatRows::length_now(self : ChatRows) -> Int {
  self.head.length() + self.count() + self.tail.length()
}

///|
/// The row keyed `key`'s readers told what it shows changed; one read by none let go.
fn ChatRows::said_of(self : ChatRows, key : String) -> Unit {
  match self.read.get(key) {
    Some(r) =>
      if r.said.watched() {
        r.n += 1
        r.said.set(r.n)
      } else {
        self.read.remove(key)
      }
    None => ()
  }
}

///|
/// The row of message `at` (by its index among them) told it shows otherwise.
fn ChatRows::said_at(self : ChatRows, at : Int) -> Unit {
  if at >= 0 && at < self.count() {
    self.said_of((self.key_of)(self.messages[at]))
  }
}

///|
/// The rows read by key carried along a change of the messages' (at the rows' place `h` on).
fn ChatRows::carry(self : ChatRows, c : @rows.ListChange, h : Int) -> Unit {
  self.read.each(fn(_, r) {
    if r.at >= h {
      match @rows.index_after([c], r.at - h) {
        Some(a) => r.at = a + h
        None => ()
      }
    }
  })
}

///|
/// The rows as chat view `v` has them now, `tail` its last rows (what goes out, where it stands, the agents at work,
/// Foot: as the page makes them, sent_rows_taken's and with_lingering's): the messages' changes since taken (theirs
/// alone), the ends compared by key; what changed told by key, its set or order counted once if it changed.
pub fn ChatRows::take(self : ChatRows, v : ChatView, tail : Array[Entry]) -> Unit {
  let mut shaped = false
  let h0 = self.head.length()
  for c in self.reader.changes() {
    self.carry(c, h0)
    match c {
      Set(at, _) => self.said_at(at)
      Whole(_) => {
        shaped = true
        let keys = self.read.keys().collect()
        for k in keys {
          self.said_of(k)
        }
      }
      _ => shaped = true
    }
  }
  // (the head: Top, then the way to older ones, or that there is nothing)
  let head : Array[Entry] = [Top]
  if v.more {
    head.push(Older)
  }
  if v.messages.length() == 0 && v.outbox.length() == 0 && v.elsewhere.length() == 0 && !v.more {
    head.push(Empty)
  }
  if head.map(fn(e) { e.id() }) != self.head.map(fn(e) { e.id() }) {
    shaped = true
    let d = head.length() - self.head.length()
    if d != 0 {
      self.read.each(fn(_, r) { if r.at >= self.head.length() { r.at = r.at + d } })
    }
    self.head = head
  }
  // (the unread line moved: the rows it left and came to show otherwise; its message looked for from the end, where
  // what is new is)
  if v.unread_line != self.line {
    for seq in [self.line, v.unread_line] {
      match seq {
        Some(s) => self.said_at(self.message_at(s))
        None => ()
      }
    }
    self.line = v.unread_line
  }
  // (the tail: a few rows, compared by key; one showing otherwise told by its sign)
  let keys = tail.map(fn(e) { e.id() })
  if keys != self.tail.map(fn(e) { e.id() }) {
    shaped = true
  }
  for i, e in tail {
    self.work += 1
    let sign = shown_sign(e)
    if self.tail_signs.get(keys[i]) != Some(sign) {
      self.tail_signs[keys[i]] = sign
      self.said_of(keys[i])
    }
  }
  self.tail = tail
  if shaped {
    self.shapes += 1
    self.shape.set(self.shapes)
  }
}

///|
/// Where the message `seq` is among them, looked for from the end (the unread line is under what is new), -1 where it is
/// none of them.
fn ChatRows::message_at(self : ChatRows, seq : Double) -> Int {
  let mut i = self.count() - 1
  while i >= 0 {
    self.work += 1
    let m = self.messages[i]
    if m.seq == seq {
      return i
    }
    if m.seq < seq {
      return -1
    }
    i -= 1
  }
  -1
}
