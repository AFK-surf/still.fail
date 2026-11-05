// The core's topics read for something that ends (a page, a chat's sheets, a node shown), let go of as it ends: a
// topic read is shown to the core until it is left, and some keep the station working while shown (a folder watched, a
// job's log told as it grows, the machine's figures sampled). Each is read through `hold` by what it is read for, its
// holder (a name's, `let_go` ending it; a node's, as the node goes: hold_node); one holder let go leaves only what no
// other holds, and that once the change it is let go in is over (signals' after_all_flushed): one let go and another
// that holds the same in that change leave nothing (the core sees no leave and read again). A topic never read is not
// left (a leave asks it first). What holds is a holder, never "what a build read": nothing here follows builds.

///|
/// What reads topics for something that ends: a name's (`let_go` ends it), a node's (hold_node). Let go once: again,
/// nothing (`gone`).
priv struct Holder {
  id : Int
  name : String
  mut gone : Bool
}

///|
// kept across runs: only counts on
let held_holder_n : Ref[Int] = Ref(0)

///|
/// The holder of each name still holding (a name let go and read for again holds anew).
// kept across runs: put back as a run begins (held_reset)
let held_named : Map[String, Holder] = Map([])

///|
/// What each holder holds, by its id: each topic's name and params by its key.
// kept across runs: put back as a run begins (held_reset)
let held_holder_topics : Map[Int, Map[String, (String, Map[String, Json])]] = Map([])

///|
/// Who holds each topic, by its key: the holders' ids.
// kept across runs: put back as a run begins (held_reset)
let held_topic_holders : Map[String, Map[Int, Bool]] = Map([])

///|
/// What no holder holds since a holder was let go: left as the change is over unless held again by then.
// kept across runs: put back as a run begins (held_reset)
let held_leaving : Map[String, (String, Map[String, Json])] = Map([])

///|
fn Holder::new(name : String) -> Holder {
  held_holder_n.val += 1
  { id: held_holder_n.val, name, gone: false }
}

///|
fn named_holder(name : String) -> Holder {
  match held_named.get(name) {
    Some(h) => h
    None => {
      let h = Holder::new(name)
      held_named[name] = h
      h
    }
  }
}

///|
/// The topic `name` with `params` read for `h` (let go of with it).
fn Holder::hold(self : Holder, src : Source, name : String, params : Map[String, Json]) -> Topic {
  let key = name + "\u{1}" + Json::object(params).stringify()
  if !self.gone {
    let mine = match held_holder_topics.get(self.id) {
      Some(m) => m
      None => {
        let m : Map[String, (String, Map[String, Json])] = Map([])
        held_holder_topics[self.id] = m
        m
      }
    }
    mine[key] = (name, params)
    match held_topic_holders.get(key) {
      Some(hs) => hs[self.id] = true
      None => {
        let hs : Map[Int, Bool] = Map([])
        hs[self.id] = true
        held_topic_holders[key] = hs
      }
    }
    held_leaving.remove(key)
  }
  (src.topic)(name, params)
}

///|
/// `h` let go: what no other holds left as the change is over (once: let go again, nothing).
fn Holder::let_go(self : Holder, src : Source) -> Unit {
  guard !self.gone else { return }
  self.gone = true
  match held_named.get(self.name) {
    Some(h) if physical_equal(h, self) => held_named.remove(self.name)
    _ => ()
  }
  guard held_holder_topics.get(self.id) is Some(mine) else { return }
  held_holder_topics.remove(self.id)
  for key, t in mine {
    match held_topic_holders.get(key) {
      Some(hs) => {
        hs.remove(self.id)
        if hs.is_empty() {
          held_topic_holders.remove(key)
          held_leaving[key] = t
        }
      }
      None => ()
    }
  }
  guard !held_leaving.is_empty() else { return }
  @signals.after_all_flushed(fn() { held_leave(src) })
}

///|
/// What is still held by none, left.
fn held_leave(src : Source) -> Unit {
  let now = held_leaving.to_array()
  held_leaving.clear()
  for kt in now {
    let (key, t) = kt
    if !held_topic_holders.contains(key) {
      (src.leave)(t.0, t.1)
    }
  }
}

///|
/// The topic `name` with `params`, read for `scope` (let go of with it: let_go).
pub fn hold(src : Source, scope : String, name : String, params : Map[String, Json]) -> Topic {
  named_holder(scope).hold(src, name, params)
}

///|
/// The topic `name` with `params`, read for node `v`: let go of as it goes.
pub fn hold_node(v : @view.View, src : Source, name : String, params : Map[String, Json]) -> Topic {
  let h = Holder::new("node")
  v.owns(fn() { h.let_go(src) }) |> ignore
  h.hold(src, name, params)
}

///|
/// What `scope` read, let go of (it ended: its page left, its chat closed): what nothing else holds left.
pub fn let_go(src : Source, scope : String) -> Unit {
  match held_named.get(scope) {
    Some(h) => h.let_go(src)
    None => ()
  }
}

///|
/// Every scope whose name starts with `prefix`, let go of.
pub fn let_go_all(src : Source, prefix : String) -> Unit {
  let scopes = held_named.keys().filter(fn(s) { s.has_prefix(prefix) }).collect()
  for s in scopes {
    let_go(src, s)
  }
}

///|
fn held_reset() -> Unit {
  held_named.clear()
  held_holder_topics.clear()
  held_topic_holders.clear()
  held_leaving.clear()
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
