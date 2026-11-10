// The made-up cores' stations as the core gives them (client/core-ts views.ts): each fixture describes a station whole
// and answers every topic of it from that, here, so what a list is sent is what a device is sent. `stations` a row each
// (station_row), `station` one whole without the models it can run (station_whole), `stationPart` a part of its
// overview (station_part_said), `connects`' Slack apps and whether no station has a profile (connects_of_stations),
// `profiles`' machine logins offered (profiles_of_stations).
// Both fixtures' packages use these (sffixture, and these settings' own).

///|
/// What a list's row of a station carries (the core's `stations`), its machine's and overview's own fields under it.
// kept across runs: a table, never written
let row_fields : Array[String] = [
  "station", "id", "name", "emoji", "icon", "summary", "face", "line", "online", "reconnecting", "blocked", "stateText",
  "stateBusy", "problems", "lastSeen", "version", "way", "joined", "home", "mine", "host", "overview",
]

///|
// kept across runs: a table, never written
let row_host_fields : Array[String] = ["identity", "os", "meters"]

///|
// kept across runs: a table, never written
let row_overview_fields : Array[String] = ["viewer", "counts", "disk", "drive"]

///|
/// Of object `v`, its fields named in `keep` alone; anything else as it is.
fn fields_kept(v : Json, keep : Array[String]) -> Json {
  match v {
    Object(o) => {
      let m : Map[String, Json] = {}
      for k, x in o {
        if keep.contains(k) {
          m[k] = x
        }
      }
      Json::object(m)
    }
    _ => v
  }
}

///|
/// Station `whole` as a list's row: exactly the row's fields, its `host` and `overview` cut to theirs.
pub fn station_row(whole : Json) -> Json {
  match fields_kept(whole, row_fields) {
    Object(o) => {
      match o.get("host") {
        Some(h) => o["host"] = fields_kept(h, row_host_fields)
        None => ()
      }
      match o.get("overview") {
        Some(v) => o["overview"] = fields_kept(v, row_overview_fields)
        None => ()
      }
      Json::object(o)
    }
    v => v
  }
}

///|
/// Station `whole` as its own page is sent it (`station`): all of it but the models it can run.
pub fn station_whole(whole : Json) -> Json {
  match whole {
    Object(o) => {
      let m : Map[String, Json] = {}
      for k, x in o {
        if k != "models" {
          m[k] = x
        }
      }
      Json::object(m)
    }
    v => v
  }
}

///|
/// One part of station `whole`'s overview (`stationPart`): null while its overview is not read or has none.
pub fn station_part_said(whole : Json, part : String) -> Json {
  match field(field(Some(whole), "overview"), part) {
    Some(v) => v
    None => Json::null()
  }
}

///|
/// Station `address` of the `stations` wholes `all`, as `station` and `stationPart` answer it (`part` "" for the
/// page): no value while they are not known, null where there is no such station.
pub fn station_said(all : Json?, address : String, part : String) -> Json? {
  match all {
    Some(Array(a)) =>
      match a.iter().find_first(fn(s) { text(Some(s), "station") == address }) {
        Some(s) => Some(if part == "" { station_whole(s) } else { station_part_said(s, part) })
        None => Some(Json::null())
      }
    _ => None
  }
}

///|
/// `connects`' value `v` with what the core works out of the stations (`all`, whole): every one's Slack apps not
/// connected yet, each with its station (`slackApps`), and whether there is a station, every one's overview read,
/// none with a profile (`noProfile`).
pub fn connects_of_stations(v : Json?, all : Json?) -> Json? {
  match v {
    Some(Object(o)) => {
      let m = o.copy()
      let stations = match all {
        Some(Array(a)) => a
        _ => []
      }
      let apps : Array[Json] = []
      for s in stations {
        for app in items(field(Some(s), "overview"), "slackApps") {
          apps.push(obj([("station", str(text(Some(s), "station"))), ("stationName", str(text(Some(s), "name"))), ("app", app)]))
        }
      }
      m["slackApps"] = Json::array(apps)
      m["noProfile"] = Json::boolean(
        stations.length() > 0 &&
        stations.iter().all(fn(s) {
          field(Some(s), "overview") is Some(Object(_)) && items(field(Some(s), "overview"), "profiles").length() == 0
        }),
      )
      Some(Json::object(m))
    }
    _ => v
  }
}

///|
/// `profiles`' value `v` with the machine logins each station offers, as the core works them out of the stations
/// (`all`, whole): each station up whose overview is read, in their order, its offered ones (`machineLogins`: station,
/// stationName, logins), one with none left out.
pub fn profiles_of_stations(v : Json?, all : Json?) -> Json? {
  match v {
    Some(Object(o)) => {
      let m = o.copy()
      let out : Array[Json] = []
      let stations = match all {
        Some(Array(a)) => a
        _ => []
      }
      for s in stations {
        let sv = Some(s)
        if !flag(sv, "online") || !(field(sv, "overview") is Some(Object(_))) {
          continue
        }
        let logins = items(field(sv, "overview"), "machineLogins").filter(fn(l) { flag(Some(l), "offered") })
        if logins.length() > 0 {
          out.push(obj([("station", str(text(sv, "station"))), ("stationName", str(text(sv, "name"))), ("logins", Json::array(logins))]))
        }
      }
      m["machineLogins"] = Json::array(out)
      Some(Json::object(m))
    }
    _ => v
  }
}
