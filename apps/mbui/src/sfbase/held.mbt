// The core's topics read for something that ends (a page, a chat's sheets), let go of as it ends: a topic read is
// shown to the core until it is left, and some keep the station working while shown (a folder watched, a job's log
// told as it grows, the machine's figures sampled). Each is read through `hold` under the name of what it is read
// for, and `let_go` leaves what that read once it ends; one never read is not left (a leave asks it first), nor one
// read in the build it ended in (something still shown reads it).

///|
/// A legacy scope's reader, independent of the frame that last read it.
priv struct HeldTopic {
  source : Source
  state : @signals.Computed[TopicState]
  watch : @signals.Watch
  mut read : Int
}

///|
/// Each legacy scope holds its own graph reader, so leaving one scope does not end another scope's topic.
let held_topics : Map[String, Map[String, HeldTopic]] = {}

///|
/// The build each topic was last read in, and the build going on (held_build): what is read in the build its thing
/// ended in is still shown by another (a chat that took a new one's place, its agent's line the same), and stays.
let held_deferred : Array[(Int, HeldTopic)] = []

///|
let held_now : Ref[Int] = Ref::new(0)

///|
let held_building : Ref[Bool] = Ref::new(false)

///|
/// This watch belongs to its legacy scope, not to the particular build which first read that scope.
fn held_watch() -> @signals.Watch {
  let owner = @signals.set_owner(None)
  let watch = @signals.watch(fn() {  })
  @signals.set_owner(owner) |> ignore
  watch
}

///|
/// A build begins (the app's view, each frame it builds).
pub fn held_build(n : Int) -> Unit {
  held_now.val = n
  held_building.val = true
  let mut i = held_deferred.length() - 1
  while i >= 0 {
    if held_deferred[i].0 != n {
      held_deferred[i].1.watch.stop()
      held_deferred.remove(i) |> ignore
    }
    i -= 1
  }
}

///|
/// Finish a frame's scope handovers now, even if no later frame is drawn.
pub fn held_end() -> Unit {
  held_building.val = false
  let deferred = held_deferred.copy()
  held_deferred.clear()
  for t in deferred {
    t.1.watch.stop()
  }
}

///|
/// The topic `name` with `params`, read for `scope` (let go of with it: let_go).
pub fn hold(src : Source, scope : String, name : String, params : Map[String, Json]) -> Topic {
  let key = name + "\u{1}" + Json::object(params).stringify()
  let topics = match held_topics.get(scope) {
    Some(m) => m
    None => {
      let m : Map[String, HeldTopic] = {}
      held_topics[scope] = m
      m
    }
  }
  let held = match topics.get(key) {
    Some(t) if physical_equal(t.source, src) => t
    old => {
      let t = { source: src, state: topic_signal(src, name, params), watch: held_watch(), read: held_now.val }
      topics[key] = t
      t.watch.read(fn() { t.state.get() }) |> ignore
      match old {
        Some(was) => was.watch.stop()
        None => ()
      }
      t
    }
  }
  held.read = held_now.val
  held.watch.read(fn() { held.state.get() }) |> ignore
  let state = held.state.get()
  { value: state.value, error: state.error, version: state.version }
}

///|
/// What `scope` read, let go of (it ended: its page left, its chat closed).
pub fn let_go(src : Source, scope : String) -> Unit {
  match held_topics.get(scope) {
    Some(m) => {
      held_topics.remove(scope)
      for _, t in m {
        if held_building.val && t.read == held_now.val {
          held_deferred.push((held_now.val, t))
        } else {
          t.watch.stop()
        }
      }
    }
    None => ()
  }
}

///|
/// Every scope whose name starts with `prefix`, let go of.
pub fn let_go_all(src : Source, prefix : String) -> Unit {
  let scopes = held_topics.keys().filter(fn(s) { s.has_prefix(prefix) }).collect()
  for s in scopes {
    let_go(src, s)
  }
}

///|
fn held_reset() -> Unit {
  for _, topics in held_topics {
    for _, topic in topics {
      topic.watch.stop()
    }
  }
  for t in held_deferred {
    t.1.watch.stop()
  }
  held_topics.clear()
  held_deferred.clear()
  held_now.val = 0
  held_building.val = false
}

///|
/// What a chat's agents' lines read (its agents' `live`): let go of as the chat is left.
pub fn chat_scope(station : String, session : String) -> String {
  "chat/" + station + "\u{1}" + session
}

///|
/// What a station's jobs' sheets and their last lines read (`jobLog`): let go of as a chat of that station is left.
pub fn jobs_scope(station : String) -> String {
  "jobs/" + station
}

///|
/// What a history's details read (the station's `host`): let go of as the history is left.
pub fn history_scope(station : String, key : String) -> String {
  "history/" + station + "\u{1}" + key
}

///|
/// The drive's folders read (`drive`): let go of as a page of the drive is left.
pub let drive_scope : String = "drive"
