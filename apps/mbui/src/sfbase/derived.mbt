// What the pages work out of the core's topics, worked out once: alien-signals' computed (mbui/signals, its
//), following the core's changes from the core on. Each subscription's changes are a signal the core
// client sets as the core's message for it comes, and as it ends (src/core client.mbt Sub.changes); a topic read
// (Source.topic) reads it, so what a computed reads of a topic it follows, wherever it reads it (in a computed it reads
// in turn too). A page reads a field or two of a topic as it is; what it makes of the whole of it (a chat's messages,
// the chats' list, a folder's entries, an agent's history, a job's output) is a computed here (Kept, Derived), worked
// out again only as what it read changed, and then from what it made last: the core's deltas keep what they do not
// touch (the same JSON), and what is made of that is kept as it was made (a chat's messages, the chats' rows: one row
// changed, one row made). Kept while something follows it (the frames' watch that read it as the window was last built,
// a part kept as it was drawn, a computed of it): one nothing follows is let go as another is made.

///|
/// Computeds kept by a key each (a chat's view by its chat, a folder's entries by its folder): each a computed made of
/// the getter its first read gave (given what it made last, none the first time), read as a computed is (worked out
/// again only as what it read changed), let go of (Computed::dispose) once nothing follows it, as another is made.
pub struct Kept[T] {
  priv kept : Map[String, KeptOne[T]]
  /// listed with what a new one made goes over (kept_lists), once it keeps anything
  priv mut listed : Bool
}

///|
struct KeptOne[T] {
  value : @signals.Computed[T]
}

///|
pub fn[T] Kept::new() -> Kept[T] {
  { kept: {}, listed: false }
}

///|
/// What `getter` makes for `key` (given what it made last): worked out the first time, and again only once what it
/// read changed since; what reads it told only where that comes out otherwise than before, by `same` where given (else
/// as signals compare).
pub fn[T] Kept::read(self : Kept[T], key : String, getter : (T?) -> T, same? : (T, T) -> Bool) -> T {
  let one = match self.kept.get(key) {
    Some(k) => k
    None => {
      // (a new one: those nothing follows let go first, once there are twice as many kept as the last time that was done,
      // so making n costs O(n) in all; where no getter is working one out, whose own is not followed yet)
      if kept_working.val == 0 && kept_count.made >= 2 * kept_count.left &&
        kept_count.made >= kept_sweep_least {
        for l in kept_lists {
          (l.sweep)()
        }
        kept_count.left = kept_count.made
      }
      let k = { value: @signals.computed(getter, same?) }
      self.kept[key] = k
      kept_count.made += 1
      if !self.listed {
        self.listed = true
        kept_lists.push({ sweep: fn() { self.sweep() }, clear: fn() { self.clear() } })
      }
      k
    }
  }
  kept_working.val += 1
  let v = one.value.get()
  kept_working.val -= 1
  v
}

///|
/// How many are kept in all the Kepts (`made`), and how many were left as those nothing followed were last let go.
priv struct KeptCount {
  mut made : Int
  mut left : Int
}

///|
// kept across runs: back to 0 by kept_reset
let kept_count : KeptCount = { made: 0, left: 0 }

///|
/// Fewer kept than this, none let go as another is made.
// kept across runs: a value
let kept_sweep_least : Int = 64

///|
/// How many Kepts' reads are under way (a getter reading another Kept): none let go meanwhile.
// kept across runs: back to 0 as each read ends
let kept_working : Ref[Int] = Ref(0)

///|
/// What was made last for `key`, if it is kept: not worked out again, nothing it reads asked for.
pub fn[T] Kept::peek(self : Kept[T], key : String) -> T? {
  match self.kept.get(key) {
    Some(k) => k.value.peek()
    None => None
  }
}

///|
/// Let go of a key now. A value still followed by something else keeps its dependencies until that reader lets go.
fn[T] Kept::forget(self : Kept[T], key : String) -> Unit {
  match self.kept.get(key) {
    Some(k) => {
      if !k.value.watched() {
        k.value.dispose()
      }
      self.kept.remove(key) |> ignore
      kept_count.made -= 1
    }
    None => ()
  }
}

///|
/// Those nothing follows let go: what the frames' watch read as the window was last built, or as this one is, is
/// followed by it till it reads anew without it (mbui/signals' Watch::read); a part kept as it was drawn, which reads it
/// no more each frame, holds it (mbui's Ctx::kept_part); a computed that read it, as long as it is itself kept.
fn[T] Kept::sweep(self : Kept[T]) -> Unit {
  let gone = []
  for key, k in self.kept {
    if !k.value.watched() {
      gone.push(key)
    }
  }
  for key in gone {
    match self.kept.get(key) {
      Some(k) => k.value.dispose()
      None => ()
    }
    self.kept.remove(key) |> ignore
    kept_count.made -= 1
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
/// What a new one made does with a Kept that kept anything, and what reset does.
priv struct KeptList {
  sweep : () -> Unit
  clear : () -> Unit
}

///|
// kept across runs: the Kepts themselves, each listed once; what they keep let go of by kept_reset
let kept_lists : Array[KeptList] = []

///|
fn init {
  // a run anew (a Tester begun: another test's) lets go of everything, whatever the source it reads
  @ui.on_reset(kept_reset)
}

///|
/// Everything worked out let go (the app's reset, a run anew).
fn kept_reset() -> Unit {
  for l in kept_lists {
    (l.clear)()
  }
  kept_working.val = 0
  kept_count.made = 0
  kept_count.left = 0
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
/// What was last made of topic `name` with `params`, if it is kept (Kept::peek): the topic not
/// asked for.
pub fn[T] Derived::kept(self : Derived[T], params : Map[String, Json]) -> T? {
  match self.kept.peek(Json::object(params).stringify()) {
    Some(v) => v
    None => None
  }
}

///|
/// `jsons` made (`make`) each, from what was made of them last (`was`: each with the JSON it was made of): one that is
/// the same JSON as before (the core's deltas keep what they do not touch: src/core delta.mbt) taken as it was made;
/// only what changed is made anew. Looked for where the last one found was and on from there (what was between them
/// gone, or one moved on), then among those passed over (one moved back); by `key` once that has looked at twice as many
/// as there were (a page come before them, all of it new): a message come at the end, one changed, one gone are
/// matched where they stand, never a key made of each.
pub fn[T] made_again(
  jsons : Array[Json],
  was : Array[(Json, T)],
  key : (Json) -> String,
  make : (Json) -> T,
) -> Array[(Json, T)] {
  let n = was.length()
  let most = 2 * n + 16
  let mut looked = 0
  // where the next is looked for first: after the last found
  let mut at = 0
  // those passed over on the way to one found further on (gone, or wanted later: moved back)
  let passed : Array[Int] = []
  let by : Ref[Map[String, (Json, T)]?] = Ref(None)
  jsons.map(fn(j) {
    if looked < most {
      for q in at..<n {
        looked += 1
        if physical_equal(was[q].0, j) {
          for s in at..<q {
            passed.push(s)
          }
          at = q + 1
          return was[q]
        }
        if looked >= most {
          break
        }
      }
      for s in passed {
        looked += 1
        if physical_equal(was[s].0, j) {
          return was[s]
        }
      }
      if looked < most {
        return (j, make(j))
      }
    }
    // (too much looked at: by its key)
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
  })
}
