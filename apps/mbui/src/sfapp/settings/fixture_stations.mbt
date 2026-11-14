// The made-up cores' stations as the core gives them (client/core-ts views.ts): each fixture describes a station whole
// and answers every topic of it from that, here, so what a list is sent is what a device is sent. `stations` a row each
// (station_row), `station` one as its page is sent it (station_whole), `stationPart` a part of its overview
// (station_part_said), `connects`' Slack apps and whether no station has a profile (connects_of_stations), `profiles`'
// machine logins offered (profiles_of_stations) and its profiles (listed_profile_said): each as client/core-ts
// schema.ts sends it.
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
      let m : Map[String, Json] = Map([])
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
/// Of object `v`, all but its fields named in `drop`; anything else as it is.
fn fields_dropped(v : Json, drop : Array[String]) -> Json {
  match v {
    Object(o) => {
      let m : Map[String, Json] = Map([])
      for k, x in o {
        if !drop.contains(k) {
          m[k] = x
        }
      }
      Json::object(m)
    }
    _ => v
  }
}

///|
/// Object `v` with its field `key` made by `f`, where it has one that is not null; anything else as it is.
fn field_made(v : Json, key : String, f : (Json) -> Json) -> Json {
  match v {
    Object(o) =>
      match o.get(key) {
        Some(Null) | None => v
        Some(x) => {
          let m = o.copy()
          m[key] = f(x)
          Json::object(m)
        }
      }
    _ => v
  }
}

///|
/// Each item of list `v` made by `f`; anything else as it is.
fn each_made(v : Json, f : (Json) -> Json) -> Json {
  match v {
    Array(a) => Json::array(a.map(f))
    _ => v
  }
}

///|
/// What the core sends of a station whole (client/core-ts schema.ts), field by field: what the station's page reads
/// (StationView, StationOverview, StationProfile, StationConnect, StationDecisions) and what a part of it is
/// (`stationPart`: Overview's parts, MachineLogin, SoftwareVersion, ArchivingView, ArchivePolicyView).
// kept across runs: a table, never written
let page_dropped : Array[String] = ["models", "face", "line", "lastSeen", "time"]

///|
// kept across runs: a table, never written
let page_overview_dropped : Array[String] = [
  "viewer", "mesh", "slackUsers", "slackTeams", "slackApps", "comma", "feishuRegistrations", "disk", "logins", "consoleSignIn",
]

///|
// kept across runs: a table, never written
let page_connect_fields : Array[String] = ["id", "name", "team", "presence", "statusText", "runText", "modelName"]

///|
// kept across runs: a table, never written
let page_profile_dropped : Array[String] = [
  "home", "homeExists", "models", "group", "groupTitle", "usesText", "modelsReading", "serves",
]

///|
// kept across runs: a table, never written
let quota_fields : Array[String] = ["state", "windows", "detail", "creditsText", "resetCount", "resets", "time"]

///|
// kept across runs: a table, never written
let quota_window_fields : Array[String] = ["label", "scope", "mark", "left", "level", "refills"]

///|
/// Allowance `q` as a profile's row, chips and page are sent it (ProfileQuota): its windows as their chips draw them,
/// its times in words as `ago` alone.
pub fn quota_said(q : Json) -> Json {
  fields_kept(q, quota_fields)
  |> field_made("windows", fn(w) { each_made(w, fn(x) { fields_kept(x, quota_window_fields) }) })
  |> field_made("time", ago_said)
}

///|
/// Times in words (`time`: a Stamp by field) as a profile's page reads them: `ago` alone.
fn ago_said(time : Json) -> Json {
  match time {
    Object(o) => {
      let m : Map[String, Json] = Map([])
      for k, x in o {
        m[k] = fields_kept(x, ["ago"])
      }
      Json::object(m)
    }
    v => v
  }
}

///|
/// A station's own login as the pages offering it for a profile are sent it (MachineLogin).
fn machine_login_said(l : Json) -> Json {
  fields_dropped(l, ["installed", "loggedIn", "plan", "text"]) |> field_made("quota", quota_said)
}

///|
/// A station's archive policy as it is sent (ArchivePolicyView): each option's chats their session and title.
fn policy_said(p : Json) -> Json {
  fields_dropped(p, ["checked", "edited", "change"])
  |> field_made("options", fn(os) {
    each_made(os, fn(o) { field_made(o, "chats", fn(cs) { each_made(cs, fn(c) { fields_kept(c, ["session", "title"]) }) }) })
  })
}

///|
/// Part `part` of a station's overview as it is sent, on its page or alone (`stationPart`).
fn part_said(part : String, v : Json) -> Json {
  match part {
    "archiving" => fields_dropped(v, ["summaryText", "reviewOn"])
    "automaticDecisions" => field_made(v, "policy", policy_said)
    "updates" => each_made(v, fn(u) { fields_dropped(u, ["version", "progress"]) })
    "machineLogins" => each_made(v, machine_login_said)
    _ => v
  }
}

///|
// kept across runs: a table, never written
let listed_profile_fields : Array[String] = [
  "id", "name", "email", "runtime", "access", "usedBy", "check", "checkText", "checkTone", "group", "quota", "usesText",
  "kindText", "planText", "providerMark",
]

///|
/// A station's profile as the workspace's list (`profiles`) is sent it (ListedProfile): its row's name, mark, check in
/// words and allowance.
pub fn listed_profile_said(p : Json) -> Json {
  fields_kept(p, listed_profile_fields)
  |> field_made("access", fn(a) { fields_kept(a, ["kind"]) })
  |> field_made("check", fn(c) { fields_kept(c, ["detail"]) })
  |> field_made("quota", quota_said)
}

///|
/// A station's profile as its page is sent it (StationProfile): its check's state and when, its allowance as drawn.
fn page_profile_said(p : Json) -> Json {
  fields_dropped(p, page_profile_dropped)
  |> field_made("check", fn(c) { fields_kept(c, ["state", "time"]) |> field_made("time", ago_said) })
  |> field_made("quota", quota_said)
}

///|
/// A station's overview as its page is sent it (StationOverview).
fn page_overview_said(o : Json) -> Json {
  let o = fields_dropped(o, page_overview_dropped)
  let o = ["archiving", "updates", "machineLogins"].fold(init=o, fn(o, part) { field_made(o, part, fn(v) { part_said(part, v) }) })
  o
  |> field_made("automaticDecisions", fn(d) { fields_kept(d, ["canEdit", "policy"]) |> field_made("policy", policy_said) })
  |> field_made("connects", fn(cs) { each_made(cs, fn(c) { fields_kept(c, page_connect_fields) }) })
  |> field_made("profiles", fn(ps) { each_made(ps, page_profile_said) })
}

///|
/// Station `whole` as its own page is sent it (`station`, StationView): all of it the page reads, not the models it can
/// run, nor what a list's row says alone.
pub fn station_whole(whole : Json) -> Json {
  fields_dropped(whole, page_dropped) |> field_made("overview", page_overview_said)
}

///|
/// One part of station `whole`'s overview (`stationPart`): null while its overview is not read or has none.
pub fn station_part_said(whole : Json, part : String) -> Json {
  match field(field(Some(whole), "overview"), part) {
    Some(Null) | None => Json::null()
    Some(v) => part_said(part, v)
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
        let logins = items(field(sv, "overview"), "machineLogins").filter(fn(l) { flag(Some(l), "offered") }).map(machine_login_said)
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
