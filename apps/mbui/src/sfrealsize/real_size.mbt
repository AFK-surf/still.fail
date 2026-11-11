// What the core sends each topic the app asks on a workspace of real size, for the app's sweep of every screen at that
// size (src/sfapp/real_size_wbtest.mbt): the owner's workspace as their phone reported it, 2026-11-10 (five stations of
// eight profiles each, some 400 chats, a chat of 300 messages: client/core-ts/test/real-size.ts). The `v_*.mbt` files beside this are made by
// client/core-ts/test/real-size-app.test.ts from the core's own rig, a value a file so that two changes to different
// topics touch different files (REAL_SIZE_WRITE=1 writes them; the test fails naming each that differs), so the app's screens and the core's byte bar (topic-bytes.test.ts) are held to the same values: there is
// one real size, not a second one written by hand here.

///|
/// What the v_*.mbt files put as the program starts, as they put it (read only once a test asks: most programs that
/// link this ask none).
let put_raw : Array[(String, String)] = []

///|
/// What a v_*.mbt file puts: `asked` the params the app asks it with, the topic's name among them (JSON), `value` what
/// the core sends it whole (JSON).
fn put(asked : String, value : String) -> Unit {
  put_raw.push((asked, value))
}

///|
/// The real workspace's names of things, each by the name the screens' fixture opens the same thing by: its workspace,
/// its stations (Maple the one the chat, its history and its drive are of), the chat the rig holds of 300 messages and
/// two profiles of Maple's. A screen opens what its fixture names (a chat by its session, a profile by its id) and finds
/// it in what a topic sends, so each real value is read with these names in place of its own; a page opening a thing
/// the real workspace has under another name would show it missing and weigh nothing.
let fixture_names : Map[String, String] = {
  "ws": "ws1",
  "ws/maple": "ws1/st1",
  "ws/willow": "ws1/st2",
  "ws/studio": "ws1/st3",
  "ws/cedar": "ws1/st4",
  "ws/ash": "ws1/ash",
  "k-maple-0": "s-c1",
  "claude-maple-0": "cc",
  "codex-maple-0": "cx",
}

///|
/// `v` with each string and each key that is a name of `fixture_names` its fixture's name.
fn fixture_named(v : Json) -> Json {
  let named = fn(s : String) -> String { fixture_names.get(s).unwrap_or(s) }
  match v {
    String(s) => Json::string(named(s))
    Array(a) => Json::array(a.map(fixture_named))
    Object(m) => {
      let o : Map[String, Json] = {}
      for k, x in m {
        o[named(k)] = fixture_named(x)
      }
      Json::object(o)
    }
    _ => v
  }
}

///|
/// The values put, by topic: each with the params it was asked with.
let table : Ref[Map[String, Array[(Map[String, Json], Json)]]?] = Ref(None)

///|
fn values() -> Map[String, Array[(Map[String, Json], Json)]] {
  match table.val {
    Some(t) => t
    None => {
      let t : Map[String, Array[(Map[String, Json], Json)]] = {}
      for raw in put_raw {
        match (@json.parse(raw.0) catch { _ => Json::null() }) {
          Object(params) =>
            match params.get("topic") {
              Some(String(topic)) => {
                let v = fixture_named(@json.parse(raw.1) catch { _ => Json::null() })
                let kept = t.get(topic).unwrap_or([])
                kept.push((params, v))
                t[topic] = kept
              }
              _ => ()
            }
          _ => ()
        }
      }
      table.val = Some(t)
      t
    }
  }
}

///|
/// The params that name which thing of the workspace a topic is of (its station, its chat, a search's words, how many
/// rows): the fixture's own name another thing than the real size's, so they are not compared. The rest (`mine`,
/// `part`, `compact`, `summary`, `news`, `of`, `place`, `elsewhere`) say which way it is asked, and must be the same.
let naming : Array[String] = [
  "topic", "scope", "station", "session", "key", "workspace", "id", "thread", "query", "exclude", "limit", "days",
]

///|
/// Whether `asked` (as the app asks) asks the way `kept` was asked: every param but those naming a thing the same, one
/// left out the same as false.
fn asked_so(asked : Map[String, Json], kept : Map[String, Json]) -> Bool {
  let way = fn(m : Map[String, Json], k : String) -> Json {
    match m.get(k) {
      None | Some(Null) | Some(False) => Json::boolean(false)
      Some(v) => v
    }
  }
  let keys : Map[String, Bool] = {}
  for k, _ in asked {
    keys[k] = true
  }
  for k, _ in kept {
    keys[k] = true
  }
  for k, _ in keys {
    if !naming.contains(k) && way(asked, k) != way(kept, k) {
      return false
    }
  }
  true
}

///|
/// What the core would send `name` asked with `params` on the real workspace, where a v_*.mbt file has it asked so.
pub fn real_size_value(name : String, params : Map[String, Json]) -> Json? {
  let asked = params.copy()
  asked["topic"] = Json::string(name)
  for kept in values().get(name).unwrap_or([]) {
    if asked_so(asked, kept.0) {
      return Some(kept.1)
    }
  }
  None
}

///|
/// `src` with every topic it is asked that the real size has, as it is there; the rest as `src` has them.
pub fn real_size_source(src : @sfbase.Source) -> @sfbase.Source {
  {
    ..src,
    topic_read: fn(name, params) {
      let t = (src.topic_read)(name, params)
      match real_size_value(name, params) {
        Some(v) => { ..t, value: Some(v), error: None }
        None => t
      }
    },
  }
}
