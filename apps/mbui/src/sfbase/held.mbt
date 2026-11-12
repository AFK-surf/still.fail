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
  /// read in the build going on (held_build to held_end)
  mut read : Bool
}

///|
/// Each legacy scope holds its own graph reader, so leaving one scope does not end another scope's topic.
let held_topics : Map[String, Map[String, HeldTopic]] = Map([])

///|
/// What was let go of in the build going on though that build read it (held_build): what is read in the build its
/// thing ended in is still shown by another (a chat that took a new one's place, its agent's line the same), and
/// stays till that build ends (held_end).
let held_deferred : Ref[Array[HeldTopic]] = Ref([])

///|
/// The topics read in the build going on, their `read` set: cleared as it ends.
let held_read_now : Ref[Array[HeldTopic]] = Ref([])

///|
let held_building : Ref[Bool] = Ref(false)

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
pub fn held_build() -> Unit {
  // (one before that did not end: ended now)
  held_end()
  held_building.val = true
}

///|
/// Finish a frame's scope handovers now, even if no later frame is drawn.
pub fn held_end() -> Unit {
  held_building.val = false
  for t in held_read_now.val {
    t.read = false
  }
  held_read_now.val = []
  // Drop the old backing array as well as its logical contents, so stopped watches no longer retain their sources.
  let deferred = held_deferred.val
  held_deferred.val = []
  for t in deferred {
    t.watch.stop()
  }
}

///|
/// The topic `name` with `params`, read for `scope` (let go of with it: let_go).
pub fn hold(src : Source, scope : String, name : String, params : Map[String, Json]) -> @signals.Computed[TopicState] {
  let key = name + "\u{1}" + Json::object(params).stringify()
  let topics = match held_topics.get(scope) {
    Some(m) => m
    None => {
      let m : Map[String, HeldTopic] = Map([])
      held_topics[scope] = m
      m
    }
  }
  let held = match topics.get(key) {
    Some(t) if physical_equal(t.source, src) => t
    old => {
      let t = { source: src, state: scoped_topic(src, name, params), watch: held_watch(), read: false }
      topics[key] = t
      t.watch.read(fn() { t.state.get() }) |> ignore
      match old {
        Some(was) => was.watch.stop()
        None => ()
      }
      t
    }
  }
  if held_building.val && !held.read {
    held.read = true
    held_read_now.val.push(held)
  }
  held.watch.read(fn() { held.state.get() }) |> ignore
  held.state
}

///|
/// The topic `name` with `params` as `scope` holds it of `src`, where it does (hold's); None where it holds none such.
/// It asks nothing and holds nothing.
fn held_state(src : Source, scope : String, name : String, params : Map[String, Json]) -> @signals.Computed[TopicState]? {
  let key = name + "\u{1}" + Json::object(params).stringify()
  match held_topics.get(scope) {
    Some(m) =>
      match m.get(key) {
        Some(t) if physical_equal(t.source, src) => Some(t.state)
        _ => None
      }
    None => None
  }
}

///|
/// What `scope` read, let go of (it ended: its page left, its chat closed).
pub fn let_go(_src : Source, scope : String) -> Unit {
  match held_topics.get(scope) {
    Some(m) => {
      held_topics.remove(scope)
      for _, t in m {
        if held_building.val && t.read {
          held_deferred.val.push(t)
        } else {
          t.watch.stop()
        }
      }
    }
    None => ()
  }
}

///|
fn held_reset() -> Unit {
  for _, topics in held_topics {
    for _, topic in topics {
      topic.watch.stop()
    }
  }
  let deferred = held_deferred.val
  held_deferred.val = []
  for t in deferred {
    t.watch.stop()
  }
  held_read_now.val = []
  held_topics.clear()
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
