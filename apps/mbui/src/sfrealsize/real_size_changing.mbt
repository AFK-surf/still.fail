// The workspace of real size as a device holds it, for the app's sweep of every screen on it (src/sfapp/
// real_size_wbtest.mbt: its opening, then the frames that take a change): each topic it has asked as a device asks the
// core (sfbase's `core_topic_params`) and answered from what it holds, a message of the core's
// (real_size_changed's) applied to that as a device's subscription applies it (src/core/client.mbt's `take`: the ops
// through `@core.apply_delta`, which copies only what is on their path and keeps the rest the same objects, or a value
// whole in its place; its version one more; its `changes` signal set to that version, which is all that tells what
// reads it). What reads a topic here reads that signal and the value held as a device's `core_topic` reads its `Sub`
// (src/stillfail/main.mbt), so a screen given a change builds what a device's builds for the same message.

///|
/// The params a changing source takes as naming a thing beside `naming`: a job's (`jobLog`'s `job`), which the real
/// workspace names `job-maple-0` and a screen by its fixture's id.
let changing_naming : Array[String] = ["job"]

///|
/// The real workspace's names a changing source reads by the fixture's, beside `fixture_names`: its running job, the
/// one whose log a line more comes to (`jobLog`'s `line`), by the job the chat-job screen opens (decide_fixture.mbt's
/// `j-ci`), so that screen's sheet finds it among its chat's jobs and holds its log. Not in `fixture_names`: the core's
/// own check of what each cause sends (real_size_changes_wbtest.mbt) reads the files by those alone.
let changing_names : Map[String, String] = { "job-maple-0": "j-ci" }

///|
/// `v` with each string and each key that is a name of `changing_names` its fixture's name.
fn changing_named(v : Json) -> Json {
  match v {
    String(s) =>
      match changing_names.get(s) {
        Some(n) => Json::string(n)
        None => v
      }
    Array(a) => Json::array(a.map(changing_named))
    Object(m) => {
      let o : Map[String, Json] = Map([])
      for k, x in m {
        o[changing_names.get(k).unwrap_or(k)] = changing_named(x)
      }
      Json::object(o)
    }
    _ => v
  }
}

///|
/// A topic the changing source answers: the way it is asked (as a device asks the core: sfbase's
/// `core_topic_params`), its value as it was first had, the value now and its version (the messages taken since), and
/// the signal its readers follow (a device's `Sub.changes`).
priv struct Held {
  name : String
  asked : Map[String, Json]
  first : Json
  mut value : Json
  mut version : Int
  changes : @signals.Signal[Int]
}

///|
/// A workspace of real size whose values change (RealSizeChanging::source): what it holds, by the way the app asks
/// each (its topic and params), and those ways in the order a screen first read them.
pub struct RealSizeChanging {
  priv held : Map[String, Held]
  priv order : Array[Held]
}

///|
/// A changing workspace, holding nothing till a screen reads it.
pub fn RealSizeChanging::new() -> RealSizeChanging {
  { held: {}, order: [] }
}

///|
/// What it holds for `name` asked with `params` (the app's): made as it is first asked, holding what the core sends
/// it whole on the real workspace (`real_size_value`, asked as a device asks it), where the real size has it.
fn RealSizeChanging::held_of(
  self : RealSizeChanging,
  name : String,
  params : Map[String, Json],
) -> Held? {
  let key = name + "\u{1}" + Json::object(params).stringify()
  match self.held.get(key) {
    Some(h) => Some(h)
    None => {
      let asked = @sfbase.core_topic_params(name, params)
      match real_size_value(name, asked, naming_too=changing_naming) {
        None => None
        Some(v) => {
          let v = changing_named(v)
          let h = { name, asked, first: v, value: v, version: 0, changes: @signals.signal(0) }
          self.held[key] = h
          self.order.push(h)
          Some(h)
        }
      }
    }
  }
}

///|
/// `src` with every topic it is asked that the real size has answered from what this holds, followed as a device's
/// subscription is (its `changes` read, then its value); the rest as `src` has them.
pub fn RealSizeChanging::source(self : RealSizeChanging, src : @sfbase.Source) -> @sfbase.Source {
  {
    ..src,
    topic_read: fn(name, params) {
      let t = (src.topic_read)(name, params)
      match self.held_of(name, params) {
        Some(h) => {
          h.changes.get() |> ignore
          { value: Some(h.value), error: None, version: t.version + h.version }
        }
        None => t
      }
    },
  }
}

///|
/// The ways of asking a topic of the real size a screen read, in the order it first read them: each its topic and
/// its params as a device asks the core (what `real_size_changed` takes).
pub fn RealSizeChanging::ways(self : RealSizeChanging) -> Array[(String, Map[String, Json])] {
  self.order.map(fn(h) { (h.name, h.asked) })
}

///|
/// What changes of way `at` (of `ways`) on the real workspace, by cause: each cause's messages, in order
/// (real_size_changed's, asked as the value it holds was).
pub fn RealSizeChanging::changed(self : RealSizeChanging, at : Int) -> Array[(String, Array[Json])] {
  let h = self.order[at]
  real_size_changed(h.name, h.asked, naming_too=changing_naming).map(fn(c) { (c.0, c.1.map(changing_named)) })
}

///|
/// Message `message` of the core's (one of `real_size_changed`'s: an array of keyed ops, or `{"value": …}`) taken for
/// way `at` (of `ways`) as a device's subscription takes it: applied to what it holds, its version one more, what
/// reads it told by its signal.
pub fn RealSizeChanging::put(self : RealSizeChanging, at : Int, message : Json) -> Unit {
  let h = self.order[at]
  match message {
    Array(ops) => h.value = @core.apply_delta(h.value, ops)
    Object(o) =>
      match o.get("value") {
        Some(whole) => h.value = whole
        None => return
      }
    _ => return
  }
  h.version += 1
  h.changes.set(h.version)
}

///|
/// Way `at`'s value put back to what the real size sends it whole, as a message `{"value": …}` is taken.
pub fn RealSizeChanging::put_back(self : RealSizeChanging, at : Int) -> Unit {
  let h = self.order[at]
  h.value = h.first
  h.version += 1
  h.changes.set(h.version)
}

///|
/// What names a way of asking among a screen's (`ways`): its topic and the params that say which way it is asked
/// (`compact`, `mine`, `lines` …), not those naming which thing of the workspace it is of (`naming`): `chats mine`,
/// `jobLog lines=300`. A param false or left out is not said.
pub fn real_size_way(name : String, params : Map[String, Json]) -> String {
  let parts = [name]
  let keys = params.keys().collect()
  keys.sort()
  for k in keys {
    if naming.contains(k) || changing_naming.contains(k) {
      continue
    }
    match params.get(k) {
      None | Some(Null) | Some(False) => ()
      Some(True) => parts.push(k)
      Some(String(s)) => parts.push("\{k}=\{s}")
      Some(v) => parts.push("\{k}=\{v.stringify()}")
    }
  }
  parts.join(" ")
}
