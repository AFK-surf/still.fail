// What the pages work out of the core's topics, worked out once: alien-signals' computed (mbui/signals, its
// docs/signals.md), following the core's changes from the core on. Each subscription's changes are a signal the core
// client sets as the core's message for it comes, and as it ends (src/core client.mbt Sub.changes); a topic read
// (Source.topic) reads it, so what a computed reads of a topic it follows, wherever it reads it (in a computed it reads
// in turn too). A page reads a field or two of a topic as it is; what it makes of the whole of it (a chat's messages,
// the chats' list, a folder's entries, an agent's history, a job's output) is a computed here (Kept, Derived), worked
// out again only as what it read changed, and then from what it made last: the core's deltas keep what they do not
// touch (the same JSON), and what is made of that is kept as it was made (a chat's messages, the chats' rows: one row
// changed, one row made). Kept while a frame reads it: one no frame read since the last is let go.

///|
/// Computeds kept by a key each (a chat's view by its chat, a folder's entries by its folder): each a computed made of
/// the getter its first read gave (given what it made last, none the first time), read as a computed is (worked out
/// again only as what it read changed), let go of (Computed::dispose) once a frame has gone by that did not read it.
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
/// What `getter` makes for `key` (given what it made last): worked out the first time, and again only once what it
/// read changed since.
pub fn[T] Kept::read(self : Kept[T], key : String, getter : (T?) -> T) -> T {
  let frame = kept_frame()
  let one = match self.kept.get(key) {
    Some(k) => k
    None => {
      let k = { value: @signals.computed(getter), read: frame }
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
/// This frame's number; its first read lets go of what no frame read since the last, and of the made-up topics nothing
/// follows any more; a run anew (a Ctx of its own: another test's) of all of it.
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
    for key, cell in made_up_cells {
      if !cell.watched() {
        gone.push(key)
      }
    }
    for key in gone {
      made_up_cells.remove(key) |> ignore
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
  made_up_cells.clear()
  kept_run.frame = -1
}

///|
/// What `work` makes of topic `name`'s value (Derived::read), by the topic's params: a Kept whose getter reads the
/// topic, so worked out again as it changes, given what it made of it last.
pub struct Derived[T] {
  priv name : String
  priv work : (Json, T?) -> T
  priv kept : Kept[T?]
}

///|
pub fn[T] Derived::new(name : String, work : (Json, T?) -> T) -> Derived[T] {
  { name, work, kept: Kept::new() }
}

///|
/// Topic `name` with `params` (Source.topic), and what `work` makes of its value: None while it has none.
pub fn[T] Derived::read(self : Derived[T], src : Source, params : Map[String, Json]) -> (T?, Topic) {
  let topic = (src.topic)(self.name, params)
  let value = self.kept.read(Json::object(params).stringify(), fn(was) {
    match (src.topic)(self.name, params).value {
      Some(v) =>
        Some(
          (self.work)(v, match was {
            Some(w) => w
            None => None
          }),
        )
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

///|
/// `jsons` made (`make`) each, from what was made of them last (`was`: each with the JSON it was made of): one that is
/// the same JSON as before (the core's deltas keep what they do not touch: src/core delta.mbt) taken as it was made,
/// found where it was or by `key`; only what changed is made anew.
pub fn[T] made_again(
  jsons : Array[Json],
  was : Array[(Json, T)],
  key : (Json) -> String,
  make : (Json) -> T,
) -> Array[(Json, T)] {
  let by : Ref[Map[String, (Json, T)]?] = Ref(None)
  jsons.mapi(fn(i, j) {
    match was.get(i) {
      Some((pj, t)) if physical_equal(pj, j) => (pj, t)
      _ => {
        // (moved, or more came before it: found by its key)
        let index = match by.val {
          Some(m) => m
          None => {
            let m : Map[String, (Json, T)] = {}
            for p in was {
              m[key(p.0)] = p
            }
            by.val = Some(m)
            m
          }
        }
        match index.get(key(j)) {
          Some((pj, t)) if physical_equal(pj, j) => (pj, t)
          _ => (j, make(j))
        }
      }
    }
  })
}

///|
/// The made-up topics followed, by their name and params (topic_as_read).
// kept across runs: let go of by a run anew and by reset (kept_reset)
let made_up_cells : Map[String, @signals.Signal[Int]] = {}

///|
/// A topic a made-up core works out as it is read (a test's, a tape's, a late answer's), followed by its version as
/// read: what a computed made of it is worked out again once it is read changed. The core's own topics are followed by
/// what the core says (Sub.changes); the fixture's by its own changes (fixture.mbt fix_changes).
pub fn topic_as_read(name : String, params : Map[String, Json], topic : Topic) -> Topic {
  kept_frame() |> ignore
  let key = name + " " + Json::object(params).stringify()
  let cell = match made_up_cells.get(key) {
    Some(c) => c
    None => {
      let c = @signals.signal(topic.version)
      made_up_cells[key] = c
      c
    }
  }
  cell.set(topic.version)
  cell.get() |> ignore
  topic
}
