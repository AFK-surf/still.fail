// What the pages work out of the core's topics, worked out once: alien-signals' computed (mbui/signals, its
// docs/signals.md). The app builds its view again each frame, so what a page works out as it builds is worked out again
// each frame, however little changed. A page reads a field or two of a topic's value as it is; what it makes of the
// whole of it (a chat's messages, the chats' list, a folder's entries, an agent's history, a job's output) is a computed
// here, worked out again only as what it read changed: the topics it read (topic_read: each topic's version a signal,
// as the core counts it) and the signals of the page's own it read (只看收发, the theme's ink). Kept while a frame reads
// it: one no frame read since the last is let go.

///|
/// A topic as the computeds read it: its version (a signal), set each time the topic is read (topic_read).
struct TopicCell {
  version : @signals.Signal[Int]
}

///|
/// The topics read, by their name and params; one nothing follows any more let go as a frame begins (kept_frame).
// kept across runs: let go of by a run anew and by reset (kept_reset)
let topic_cells : Map[String, TopicCell] = {}

///|
/// Topic `name` with `params` read (Source.topic: subscribed, as it is), its version told to what follows it. Read in
/// a computed's getter, the computed follows the topic: worked out again once its version changed, read here again.
pub fn topic_read(src : Source, name : String, params : Map[String, Json]) -> Topic {
  kept_frame() |> ignore
  let topic = (src.topic)(name, params)
  let key = name + " " + Json::object(params).stringify()
  let cell = match topic_cells.get(key) {
    Some(c) => c
    None => {
      let c = { version: @signals.signal(topic.version, same=fn(a, b) { a == b }) }
      topic_cells[key] = c
      c
    }
  }
  cell.version.set(topic.version)
  cell.version.get() |> ignore
  topic
}

///|
/// Computeds kept by a key each (a chat's view by its chat, a folder's entries by its folder): each a computed made of
/// the getter its first read gave, read as a computed is (worked out again only as what it read changed), let go of
/// (Computed::dispose) once a frame has gone by that did not read it. A topic's version is told as it is read
/// (topic_read): where it reads a Kept, a page reads the topics its getter reads first (Derived::read does), so a
/// topic changed since is seen as changed.
pub struct Kept[T] {
  priv kept : Map[String, KeptOne[T]]
  /// listed with what a frame's beginning goes over (kept_lists), once it keeps anything
  priv mut listed : Bool
}

///|
struct KeptOne[T] {
  value : @signals.Computed[T]
  mut read : Int
}

///|
pub fn[T] Kept::new() -> Kept[T] {
  { kept: {}, listed: false }
}

///|
/// What `getter` makes for `key`: worked out the first time, and again only once what it read changed since.
pub fn[T] Kept::read(self : Kept[T], key : String, getter : () -> T) -> T {
  let frame = kept_frame()
  let one = match self.kept.get(key) {
    Some(k) => k
    None => {
      let k = { value: @signals.computed(fn(_) { getter() }), read: frame }
      self.kept[key] = k
      if !self.listed {
        self.listed = true
        kept_lists.push({ sweep: fn(f) { self.sweep(f) }, clear: fn() { self.clear() } })
      }
      k
    }
  }
  one.read = frame
  one.value.get()
}

///|
/// What was made last for `key`, if a frame read it since the last: not worked out again, nothing it reads asked for.
pub fn[T] Kept::peek(self : Kept[T], key : String) -> T? {
  match self.kept.get(key) {
    Some(k) => k.value.peek()
    None => None
  }
}

///|
/// Those no frame read since the last (neither `frame` nor the one before) let go.
fn[T] Kept::sweep(self : Kept[T], frame : Int) -> Unit {
  let gone = []
  for key, k in self.kept {
    if k.read != frame && k.read != frame - 1 {
      gone.push(key)
    }
  }
  for key in gone {
    match self.kept.get(key) {
      Some(k) => k.value.dispose()
      None => ()
    }
    self.kept.remove(key) |> ignore
  }
}

///|
fn[T] Kept::clear(self : Kept[T]) -> Unit {
  for _, k in self.kept {
    k.value.dispose()
  }
  self.kept.clear()
}

///|
/// What a frame's beginning does with a Kept that kept anything, and what reset does.
priv struct KeptList {
  sweep : (Int) -> Unit
  clear : () -> Unit
}

///|
// kept across runs: the Kepts themselves, each listed once; what they keep let go of by kept_reset
let kept_lists : Array[KeptList] = []

///|
/// The frame whose first read went over the Kepts, and the run (its Ctx) it is in.
priv struct KeptRun {
  mut frame : Int
  mut ctx : @ui.Ctx?
}

///|
// kept across runs: a run anew (another Ctx: another test's) lets go of everything
let kept_run : KeptRun = { frame: -1, ctx: None }

///|
/// This frame's number; its first read lets go of what no frame read since the last and of the topics nothing follows
/// any more; a run anew (a Ctx of its own: another test's) of all of it.
fn kept_frame() -> Int {
  let c = @ui.current()
  let frame = c.frame_number()
  match kept_run.ctx {
    Some(was) if physical_equal(was, c) => ()
    _ => {
      kept_reset()
      kept_run.ctx = Some(c)
    }
  }
  if kept_run.frame != frame {
    kept_run.frame = frame
    for l in kept_lists {
      (l.sweep)(frame)
    }
    let gone = []
    for key, cell in topic_cells {
      if !cell.version.watched() {
        gone.push(key)
      }
    }
    for key in gone {
      topic_cells.remove(key) |> ignore
    }
  }
  frame
}

///|
/// Everything worked out let go (the app's reset, a run anew).
fn kept_reset() -> Unit {
  for l in kept_lists {
    (l.clear)()
  }
  topic_cells.clear()
  kept_run.frame = -1
}

///|
/// What `work` makes of topic `name`'s value (Derived::read), by the topic's params: a Kept whose getter reads the
/// topic, so worked out once for each of its versions.
pub struct Derived[T] {
  priv name : String
  priv work : (Json) -> T
  priv kept : Kept[T?]
}

///|
pub fn[T] Derived::new(name : String, work : (Json) -> T) -> Derived[T] {
  { name, work, kept: Kept::new() }
}

///|
/// Topic `name` with `params` (topic_read), and what `work` makes of its value: None while it has none.
pub fn[T] Derived::read(self : Derived[T], src : Source, params : Map[String, Json]) -> (T?, Topic) {
  let topic = topic_read(src, self.name, params)
  let value = self.kept.read(Json::object(params).stringify(), fn() {
    match topic_read(src, self.name, params).value {
      Some(v) => Some((self.work)(v))
      None => None
    }
  })
  (value, topic)
}

///|
/// What was last made of topic `name` with `params`, if a frame read it since the last (Kept::peek): the topic not
/// asked for.
pub fn[T] Derived::kept(self : Derived[T], params : Map[String, Json]) -> T? {
  match self.kept.peek(Json::object(params).stringify()) {
    Some(v) => v
    None => None
  }
}
