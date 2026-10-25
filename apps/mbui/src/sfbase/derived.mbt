// What the pages work out of the core's topics, worked out once (preact signals' computed): the app builds its view
// again each frame, so what a page works out as it builds is worked out again each frame, however little changed. A
// page reads a field or two of a topic's value as it is; what it makes of the whole of it (a chat's messages, the
// chats' list, a folder's entries, an agent's history, a job's output) it reads through one of these, worked out again
// only when what it is worked out of has changed: a topic's version the core counts, and whatever else it is made
// with (`by`). Kept while a frame reads it: one no frame read since the last is let go.

///|
/// What is worked out (`work` given to Memo::get), by its key: each kept with what it was worked out by and the last
/// frame that read it.
pub struct Memo[T] {
  priv kept : Map[String, MemoKept[T]]
  /// the frame whose first read let go of what the frame before did not read, in the run (the Ctx) it was in
  priv mut swept : Int
  priv mut ctx : @ui.Ctx?
  /// listed with those reset lets go of (memo_resets), once it keeps anything
  priv mut listed : Bool
}

///|
struct MemoKept[T] {
  by : String
  value : T
  mut read : Int
}

///|
pub fn[T] Memo::new() -> Memo[T] {
  { kept: {}, swept: -1, ctx: None, listed: false }
}

///|
/// What `work` makes for `key`, worked out again only when `by` (all it is made of: the versions of the topics it
/// reads, anything else it is made with) is not what it was last worked out by.
pub fn[T] Memo::get(self : Memo[T], key : String, by : String, work : () -> T) -> T {
  let frame = self.frame()
  match self.kept.get(key) {
    Some(k) if k.by == by => {
      k.read = frame
      k.value
    }
    _ => {
      let value = work()
      self.kept[key] = { by, value, read: frame }
      if !self.listed {
        self.listed = true
        memo_resets.push(fn() { self.kept.clear() })
      }
      value
    }
  }
}

///|
/// What is kept for `key` as last worked out, if a frame read it since the last: nothing worked out, nothing read.
pub fn[T] Memo::kept(self : Memo[T], key : String) -> T? {
  self.frame() |> ignore
  match self.kept.get(key) {
    Some(k) => Some(k.value)
    None => None
  }
}

///|
/// What is kept for `key` let go (what it is made of is gone).
pub fn[T] Memo::forget(self : Memo[T], key : String) -> Unit {
  self.kept.remove(key) |> ignore
}

///|
/// This frame's number; the first read in a frame lets go of what the frame before did not read, and a run anew (a
/// Ctx of its own: another test's) of all of it.
fn[T] Memo::frame(self : Memo[T]) -> Int {
  let c = @ui.current()
  let frame = c.frame_number()
  match self.ctx {
    Some(was) if physical_equal(was, c) => ()
    _ => {
      self.kept.clear()
      self.ctx = Some(c)
      self.swept = -1
    }
  }
  if self.swept != frame {
    self.swept = frame
    let gone = []
    for key, k in self.kept {
      if k.read != frame && k.read != frame - 1 {
        gone.push(key)
      }
    }
    for key in gone {
      self.kept.remove(key) |> ignore
    }
  }
  frame
}

///|
/// What reset lets go of: every Memo that kept anything.
// kept across runs: the Memos themselves, each listed once; what they keep reset lets go of (memo_reset)
let memo_resets : Array[() -> Unit] = []

///|
/// Everything worked out let go (the app's reset).
fn memo_reset() -> Unit {
  for f in memo_resets {
    f()
  }
}

///|
/// What `work` makes of topic `name`'s value, by the topic's params (Derived::read): worked out once for each version
/// of it.
pub struct Derived[T] {
  priv name : String
  priv work : (Json) -> T
  priv memo : Memo[T]
}

///|
pub fn[T] Derived::new(name : String, work : (Json) -> T) -> Derived[T] {
  { name, work, memo: Memo::new() }
}

///|
/// What was last worked out of topic `name` with `params`, if a frame read it since the last (Memo::kept): the topic
/// not asked for.
pub fn[T] Derived::kept(self : Derived[T], params : Map[String, Json]) -> T? {
  self.memo.kept(Json::object(params).stringify())
}

///|
/// Topic `name` with `params` (subscribed, as Source.topic), and what `work` makes of its value: None while it has
/// none.
pub fn[T] Derived::read(self : Derived[T], src : Source, params : Map[String, Json]) -> (T?, Topic) {
  let topic = (src.topic)(self.name, params)
  let key = Json::object(params).stringify()
  match topic.value {
    Some(v) => (Some(self.memo.get(key, topic.version.to_string(), fn() { (self.work)(v) })), topic)
    None => {
      // (none now: a topic asked anew counts its versions anew)
      self.memo.forget(key)
      (None, topic)
    }
  }
}
