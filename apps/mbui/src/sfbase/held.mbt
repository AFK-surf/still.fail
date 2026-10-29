// The core's topics read for something that ends (a page, a chat's sheets), let go of as it ends: a topic read is
// shown to the core until it is left, and some keep the station working while shown (a folder watched, a job's log
// told as it grows, the machine's figures sampled). Each is read through `hold` under the name of what it is read
// for, and `let_go` leaves what that read once it ends; one never read is not left (a leave asks it first), nor one
// read in the build it ended in (something still shown reads it).

///|
/// What each thing read and has not let go of yet: by its name, each topic's name and params by its key.
let held_topics : Map[String, Map[String, (String, Map[String, Json])]] = {}

///|
/// The build each topic was last read in, and the build going on (held_build): what is read in the build its thing
/// ended in is still shown by another (a chat that took a new one's place, its agent's line the same), and stays.
let held_read : Map[String, Int] = {}

///|
let held_now : Ref[Int] = Ref::new(0)

///|
/// A build begins (the app's view, each frame it builds).
pub fn held_build(n : Int) -> Unit {
  held_now.val = n
}

///|
/// The topic `name` with `params`, read for `scope` (let go of with it: let_go).
pub fn hold(src : Source, scope : String, name : String, params : Map[String, Json]) -> Topic {
  let key = name + "\u{1}" + Json::object(params).stringify()
  held_read[key] = held_now.val
  match held_topics.get(scope) {
    Some(m) => if !m.contains(key) { m[key] = (name, params) }
    None => {
      let m : Map[String, (String, Map[String, Json])] = {}
      m[key] = (name, params)
      held_topics[scope] = m
    }
  }
  (src.topic)(name, params)
}

///|
/// What `scope` read, let go of (it ended: its page left, its chat closed).
pub fn let_go(src : Source, scope : String) -> Unit {
  match held_topics.get(scope) {
    Some(m) => {
      held_topics.remove(scope)
      for key, t in m {
        if held_read.get(key) == Some(held_now.val) {
          continue
        }
        held_read.remove(key)
        (src.leave)(t.0, t.1)
        // left for all: another that read it reads it again if it still shows it
        for _, other in held_topics {
          other.remove(key)
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
  held_topics.clear()
  held_read.clear()
  held_now.val = 0
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
