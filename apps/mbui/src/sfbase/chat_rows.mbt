// A chat's list read by its index (mbui docs/retained.md, rule 12), as the windowed list lays it out from its anchor
// (rule 11; mbui view's AnchoredSource: how many rows and how many times their set or order changed, row i's key, a
// key looked for from where it was, the keys gone since): one row for each message, what goes with a message (the
// unread line over it, where it was sent elsewhere under it) drawn in its own row, so a message's index is its row's
// past those at the head. The rows that are no message's are at the two ends: the head (Top, Older, Empty, what was
// sent elsewhere before the first message), the tail (Newer, what is still going out, where the chat stands, the
// agents at work, Foot: Foot always the last). A message come, set, gone or moved is that row's change alone (the
// messages' list's own: ChatMessages); the two ends are a few rows, made again as the chat changes and compared by
// key. What a row shows is told by its key alone (version_of): a message set, or what goes with it, its row's version
// one more; nothing worked out for one row goes through all of them.

///|
/// A change of a chat's rows, as its list takes them (changes): a row come in at its place, one gone (what it showed,
/// the row it came after), one showing otherwise, or all of them to be taken as they are.
pub(all) enum ChatRowChange {
  Came(String)
  Went(String, Entry, String?)
  Set(String)
  Whole
}

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
  /// the messages not in the list yet (waiting their turn to come out of an avatar: emit_held), by their index among
  /// the messages, in order: a few, the newest
  priv mut hidden : Array[Int]
  /// how many times its rows' set or order changed, followed
  priv shape : @signals.Signal[Int]
  priv mut shapes : Int
  /// the key of the row after Top (the first under the bar: no gap over it), followed
  priv lead : @signals.Signal[String]
  /// the rows read by key (version_of): each where it was last found, a signal told as what it shows changes
  priv read : Map[String, RowRead]
  /// the messages the list drew (item), by their key among the messages: what a row gone showed
  priv drawn : Map[String, Message]
  /// the changes since the list last took them (changes)
  priv mut told : Array[ChatRowChange]
  /// the keys gone, each with the shape it went at (removed_since); those before `gone_from` let go of
  priv gone : Array[(Int, String)]
  priv mut gone_from : Int
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
/// How many keys gone are kept for removed_since.
let chat_rows_gone_kept = 512

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
    hidden: [],
    shape: @signals.signal(0, same=fn(a, b) { a == b }),
    shapes: 0,
    lead: @signals.signal("", same=fn(a, b) { a == b }),
    read: {},
    drawn: {},
    told: [Whole],
    gone: [],
    gone_from: 0,
    work: 0,
  }
}

///|
/// It reads its messages' changes no more.
pub fn ChatRows::let_go(self : ChatRows) -> Unit {
  self.reader.let_go()
}

///|
/// How many rows, followed: told as rows come, go or move.
pub fn ChatRows::length(self : ChatRows) -> Int {
  self.shape.get() |> ignore
  self.length_now()
}

///|
/// How many times its rows' set or order changed, followed (AnchoredSource's revision).
pub fn ChatRows::changed(self : ChatRows) -> Int {
  self.shape.get()
}

///|
/// Its shape and length, followed (AnchoredSource's snapshot).
pub fn ChatRows::snapshot(self : ChatRows) -> (Int, Int) {
  (self.shape.get(), self.length_now())
}

///|
/// The key of the row right after Top, followed: the first row under the bar, no gap over it.
pub fn ChatRows::lead(self : ChatRows) -> String {
  self.lead.get()
}

///|
/// How many rows at the head, before the first message's.
pub fn ChatRows::head_length(self : ChatRows) -> Int {
  self.head.length()
}

///|
/// The rows at the tail, after the last message's, as last taken.
pub fn ChatRows::tail(self : ChatRows) -> Array[Entry] {
  self.tail
}

///|
/// Row `i`, followed by nothing.
pub fn ChatRows::entry(self : ChatRows, i : Int) -> Entry {
  let h = self.head.length()
  let n = self.count()
  if i < h {
    self.head[i]
  } else if i < h + n {
    Said(self.messages[self.message_of_row(i - h)])
  } else {
    self.tail[i - h - n]
  }
}

///|
/// Row `i` as the list draws it, followed by nothing: a message's kept to say what its row showed should it go.
pub fn ChatRows::item(self : ChatRows, i : Int) -> Entry {
  let h = self.head.length()
  let n = self.count()
  if i >= h && i < h + n {
    let at = self.message_of_row(i - h)
    let m = self.messages[at]
    self.drawn[self.messages.rows.key(at)] = m
    Said(m)
  } else {
    self.entry(i)
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
  let n = self.length_now()
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
/// Where the row keyed `key` is, looked for from where it was last found (version_of's), else from the end; and that
/// row. Followed by what the row shows (version_of).
pub fn ChatRows::row_of(self : ChatRows, key : String) -> (Entry, Int)? {
  self.version_of(key).map(fn(_) {
    let i = self.read.get(key).unwrap().at
    (self.item(i), i)
  })
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
/// The changes since they were last taken (the first time: Whole), now taken.
pub fn ChatRows::changes(self : ChatRows) -> Array[ChatRowChange] {
  let out = self.told
  self.told = []
  out
}

///|
/// The keys gone since its shape was `since` (AnchoredSource's removed_since), None where those are let go of.
pub fn ChatRows::removed_since(self : ChatRows, since : Int) -> Array[String]? {
  if since < self.gone_from {
    return None
  }
  let out = []
  for g in self.gone {
    if g.0 > since {
      out.push(g.1)
    }
  }
  Some(out)
}

///|
/// Whether the row keyed `key` is one, of those removed_since says went (AnchoredSource's contains): one gone and come
/// again is.
pub fn ChatRows::contains(self : ChatRows, key : String) -> Bool {
  match self.read.get(key) {
    Some(r) => self.find(key, r.at) is Some(_)
    None => self.find(key, self.length_now() - 1) is Some(_)
  }
}

///|
/// Rows looked at and made since it was made: for a test that counts what a change costs.
pub fn ChatRows::work(self : ChatRows) -> Int {
  self.work + self.messages.rows.work()
}

///|
/// How many messages in the list (those waiting their turn not), followed by nothing (what follows the rows follows
/// `shape`).
fn ChatRows::count(self : ChatRows) -> Int {
  self.all_count() - self.hidden.length()
}

///|
/// How many messages, those waiting their turn too, followed by nothing.
fn ChatRows::all_count(self : ChatRows) -> Int {
  self.messages.rows.length_now()
}

///|
/// The index among the messages of the `r`th of them in the list (past those waiting their turn before it).
fn ChatRows::message_of_row(self : ChatRows, r : Int) -> Int {
  let mut at = r
  for h in self.hidden {
    if h <= at {
      at += 1
    } else {
      break
    }
  }
  at
}

///|
/// The place in the list among the messages of message `at` (those waiting their turn before it not counted), None
/// where it waits its turn.
fn ChatRows::row_of_message(self : ChatRows, at : Int) -> Int? {
  let mut before = 0
  for h in self.hidden {
    if h == at {
      return None
    }
    if h < at {
      before += 1
    }
  }
  Some(at - before)
}

///|
fn ChatRows::length_now(self : ChatRows) -> Int {
  self.head.length() + self.count() + self.tail.length()
}

///|
/// The row keyed `key`'s readers told what it shows changed; one read by none let go.
fn ChatRows::said_of(self : ChatRows, key : String, sized? : Bool = true) -> Unit {
  if sized {
    self.told.push(Set(key))
  }
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
/// The row of message `at` (by its index among them) told it shows otherwise; its list told so (its room may be
/// another) where it was drawn and `sized`, or what it shows differs in what makes its height (shown_sign).
fn ChatRows::said_at(self : ChatRows, at : Int, sized? : Bool = false) -> Unit {
  if at >= 0 && at < self.all_count() && !self.hidden.contains(at) {
    let tk = self.messages.rows.key(at)
    let m = self.messages[at]
    let sized = match self.drawn.get(tk) {
      Some(was) => {
        self.drawn[tk] = m
        sized || shown_sign(Said(was)) != shown_sign(Said(m))
      }
      None => false
    }
    self.said_of((self.key_of)(m), sized~)
  }
}

///|
/// The row keyed `key` shows otherwise in what makes its height (the room under the last row, Foot's, its sign at the
/// page's): its readers and its list told at once.
pub fn ChatRows::said(self : ChatRows, key : String) -> Unit {
  self.said_of(key)
  self.shapes += 1
  self.shape.set(self.shapes)
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
/// Key `k` gone, as it is now (its shape's next).
fn ChatRows::went(self : ChatRows, k : String, e : Entry, after : String?) -> Unit {
  self.told.push(Went(k, e, after))
  self.gone.push((self.shapes + 1, k))
}

///|
/// An end's rows (the head's or the tail's) as they were, `was`, and are, `now`, `before` the key of the row before
/// them (None at the start): those gone and come told, those showing otherwise by their sign. Whether its keys changed.
fn ChatRows::end_taken(self : ChatRows, was : Array[Entry], now : Array[Entry], before : String?) -> Bool {
  let was_keys = was.map(fn(e) { e.id() })
  let keys = now.map(fn(e) { e.id() })
  for i, e in now {
    self.work += 1
    let sign = shown_sign(e)
    if !was_keys.contains(keys[i]) {
      self.told.push(Came(keys[i]))
      self.tail_signs[keys[i]] = sign
    } else if self.tail_signs.get(keys[i]) != Some(sign) {
      self.tail_signs[keys[i]] = sign
      self.said_of(keys[i])
    }
  }
  for i, e in was {
    if !keys.contains(was_keys[i]) {
      self.tail_signs.remove(was_keys[i])
      self.went(was_keys[i], e, if i > 0 { Some(was_keys[i - 1]) } else { before })
    }
  }
  keys != was_keys
}

///|
/// The rows as chat view `v` has them now, `tail` its last rows (what goes out, where it stands, the agents at work,
/// Foot: as the page makes them, sent_rows_taken's and with_lingering's), `empty` whether a chat with nothing in it says
/// so (not the one a new chat became: fresh_view): the messages' changes since taken (theirs alone), the ends compared
/// by key; what changed told by key, its set or order counted once if it changed.
pub fn ChatRows::take(
  self : ChatRows,
  v : ChatView,
  tail : Array[Entry],
  empty? : Bool = true,
  held? : Array[Double] = [],
) -> Unit {
  let mut shaped = false
  let h0 = self.head.length()
  // (the messages come in this take, where they are once all of it is: none of them gone from the list)
  let came_in : Set[Int] = Set::new()
  let held_now : Set[Double] = Set::from_array(held)
  let told_from = self.told.length()
  let gone_from = self.gone.length()
  let cs = self.reader.changes()
  for ci, c in cs {
    self.carry(c, h0)
    // (those waiting their turn carried along: one taken out waits no more)
    let hidden = []
    for h in self.hidden {
      match @rows.index_after([c], h) {
        Some(a) => hidden.push(a)
        None => ()
      }
    }
    self.hidden = hidden
    // (where a row of this change is once all of them are taken: where it is looked at)
    let later = cs[ci + 1:].to_array()
    let now_at = fn(at : Int) { @rows.index_after(later, at) }
    match c {
      Set(at, _) =>
        match now_at(at) {
          Some(a) => self.said_at(a)
          None => ()
        }
      Inserted(at, n, _) => {
        shaped = true
        for j in 0..<n {
          match now_at(at + j) {
            Some(a) => {
              came_in.add(a)
              let m = self.messages[a]
              if !held_now.contains(m.seq) {
                self.told.push(Came((self.key_of)(m)))
              }
            }
            None => ()
          }
        }
      }
      Removed(at, keys, _) => {
        shaped = true
        // (the row before them, as it is now: none of the messages, the head's last)
        let after = if at > 0 {
          now_at(at - 1).map(fn(a) { (self.key_of)(self.messages[a]) })
        } else {
          self.head.last().map(fn(e) { e.id() })
        }
        for k in keys {
          match self.drawn.get(k) {
            Some(m) => {
              self.drawn.remove(k)
              self.went((self.key_of)(m), Said(m), after)
            }
            // (never drawn: nothing of it to go, but that it went)
            None => ()
          }
        }
      }
      Moved(_, _, to, _) => {
        shaped = true
        match now_at(to) {
          Some(a) => self.told.push(Came((self.key_of)(self.messages[a])))
          None => ()
        }
      }
      Whole(_) => {
        shaped = true
        self.told.push(Whole)
        self.drawn.clear()
        self.hidden = []
        let keys = self.read.keys().collect()
        for k in keys {
          self.said_of(k, sized=false)
        }
      }
    }
  }
  // (those waiting their turn now: found from the end, where they are; one let out comes, one held from the list goes)
  let hidden : Array[Int] = []
  for seq in held {
    let at = self.message_at(seq)
    if at >= 0 && !hidden.contains(at) {
      hidden.push(at)
    }
  }
  hidden.sort()
  if hidden != self.hidden {
    shaped = true
    let was = self.hidden
    for at in was {
      if !hidden.contains(at) {
        self.told.push(Came((self.key_of)(self.messages[at])))
      }
    }
    self.hidden = hidden
    for at in hidden {
      if !was.contains(at) && !came_in.contains(at) {
        let m = self.messages[at]
        let after = match self.row_of_message(at - 1) {
          Some(r) if at > 0 => Some(self.key(self.head.length() + r))
          _ => self.head.last().map(fn(e) { e.id() })
        }
        self.drawn.remove(self.messages.rows.key(at))
        self.went((self.key_of)(m), Said(m), after)
      }
    }
  }
  // (the head: Top, then the way to older ones, or that there is nothing, then what was sent elsewhere before the
  // first message)
  let head : Array[Entry] = [Top]
  if v.more {
    head.push(Older)
  }
  if empty && v.messages.length() == 0 && v.outbox.length() == 0 && v.elsewhere.length() == 0 && !v.more {
    head.push(Empty)
  }
  for e in v.elsewhere {
    head.push(Sent(e))
  }
  let was_head = self.head
  let d = head.length() - was_head.length()
  if d != 0 {
    self.read.each(fn(_, r) { if r.at >= was_head.length() { r.at = r.at + d } })
  }
  self.head = head
  if self.end_taken(was_head, head, None) {
    shaped = true
  }
  // (the unread line moved: the rows it left and came to show otherwise; its message looked for from the end, where
  // what is new is)
  if v.unread_line != self.line {
    for seq in [self.line, v.unread_line] {
      match seq {
        Some(s) => self.said_at(self.message_at(s), sized=true)
        None => ()
      }
    }
    self.line = v.unread_line
  }
  // (the tail: a few rows, compared by key; one showing otherwise told by its sign)
  let was_tail = self.tail
  self.tail = tail
  let n = self.count()
  let last = if n > 0 { Some(self.key(self.head.length() + n - 1)) } else { self.head.last().map(fn(e) { e.id() }) }
  if self.end_taken(was_tail, tail, last) {
    shaped = true
  }
  // (a row gone from one place and come to another, an outbox entry's taken by its message's: moved, not gone)
  let came : Set[String] = Set::new()
  for c in self.told[told_from:] {
    if c is Came(k) {
      came.add(k)
    }
  }
  if !came.is_empty() {
    let told = self.told[told_from:].to_array().filter(fn(c) { !(c is Went(k, _, _) && came.contains(k)) })
    self.told.truncate(told_from)
    self.told.push_iter(told.iter())
    let gone = self.gone[gone_from:].to_array().filter(fn(g) { !came.contains(g.1) })
    self.gone.truncate(gone_from)
    self.gone.push_iter(gone.iter())
  }
  // (the keys gone kept as many as chat_rows_gone_kept: a list that read none since those let go of reads all anew)
  if self.gone.length() > chat_rows_gone_kept {
    let drop = self.gone.length() - chat_rows_gone_kept / 2
    self.gone_from = self.gone[drop - 1].0
    let kept = self.gone[drop:].to_array()
    self.gone.clear()
    self.gone.push_iter(kept.iter())
  }
  // (its list told of a row showing otherwise as of one come or gone: it reads what changed as they do)
  if shaped || self.told.length() > told_from {
    self.shapes += 1
    self.shape.set(self.shapes)
  }
  self.lead.set(if self.length_now() > 1 { self.key(1) } else { "" })
}

///|
/// Where the message `seq` is among them, looked for from the end (the unread line is under what is new), -1 where it
/// is none of them.
pub fn ChatRows::message_at(self : ChatRows, seq : Double) -> Int {
  let mut i = self.all_count() - 1
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

///|
/// The first of the messages whose seq is `seq` or more (they are in the order of their seqs), by halves: its index
/// among them, their count where there is none.
pub fn ChatRows::message_from(self : ChatRows, seq : Double) -> Int {
  let mut lo = 0
  let mut hi = self.all_count()
  while lo < hi {
    let mid = (lo + hi) / 2
    self.work += 1
    if self.messages[mid].seq < seq {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// The key of the message at `i` among them (not its row's index: the head's rows before them).
pub fn ChatRows::message_key(self : ChatRows, i : Int) -> String {
  (self.key_of)(self.messages[i])
}

///|
/// The same rows only as the very same ones.
pub impl Eq for ChatRows with equal(a, b) {
  physical_equal(a, b)
}
