// Settings and the pages under it, as still.fail's Android app has them (ember apps/android: app/screens/SettingsHome.kt
// and settings/*.kt: Me, Archive, Usage, Stations, Profiles, Connects, Vault, Security, Settings.kt's Workspace,
// Memory), over the core's topics and calls. The app (src/sfapp) pushes them on its page stack and hands them `Core`:
// what to read and call, and how to move between pages. Everything said is the core's (or the Chinese catalog's).

///|
/// A topic as it stands (the app's Topic): its value, why it could not be read, how often it changed.
pub(all) struct Read {
  value : Json?
  error : Json?
  version : Int
}

///|
/// What the pages need of the app around them.
pub(all) struct Core {
  /// the topic `name` with its params (the core's `subscribe`)
  topic : (String, Map[String, Json]) -> Read
  /// a call to the core, its answer or its error to `done`
  call : (String, Json, (Result[Json, Json]) -> Unit) -> Unit
  /// a page pushed over this one
  push : (Route) -> Unit
  /// back to the page under this one
  pop : () -> Unit
  /// back to the chats (a workspace left)
  home : () -> Unit
  /// a chat opened: its station, its session, its title
  open_chat : (String, String, String) -> Unit
  /// a station's drive opened (its folders lent: src/sfapp/drive.mbt), by its address
  open_drive : (String) -> Unit
  /// signing another account in (登录其他账号)
  sign_in : () -> Unit
  /// a toast (Sheet.kt ToastHost)
  say : (String) -> Unit
  /// a person's picture by its URL: an image's key once it is here, "" until then
  picture : (String) -> String
  /// notifications turned on here: the system asked to allow them (Notices.kt rememberNotificationAsk)
  notify_ask : () -> Unit
  /// this device's push registration as the core now wants it (Push.sync): what `notify.set` answered (`push`), or
  /// None for what the core's `notify` says
  push_sync : (Bool?) -> Unit
  /// what the page under this one is: "chats" (Home), "settings", or "" (another)
  under : () -> String
  /// the version row's words at its end and whether they are the accent's (an update: 更新到 …, how far, 检查更新)
  version_words : () -> (String, Bool)
  /// the version row tapped: a newer build installed, or still.fail cloud asked now
  version_tap : () -> Unit
}

///|
/// A page of the settings (AppState.kt's Screen, the ones of these slices).
pub(all) enum Route {
  /// settings itself, from the gear (SettingsHome.kt)
  Home
  Me
  Appearance
  /// the workspace: its name, its people, its invitations (Settings.kt WorkspaceScreen)
  Workspace
  /// security mode (Security.kt)
  Security
  Vault
  Stations
  /// a station's page, by its address (ws/st)
  Station(String)
  /// the profiles, of every station ("") or of one
  Profiles(String)
  /// a profile's page: its station's address, its id
  Profile(String, String)
  /// the connects, of every station ("") or of one
  Connects(String)
  /// a connect's page: its station's address, its id
  Connect(String, String)
  /// every station's memory, a row each
  Memories
  /// a station's memory
  Memory(String)
  /// one of its pages: the station, the skill ("" the global memory), which part
  MemoryDoc(String, String, Int)
  Usage
  /// the archived chats (the list's filter menu, settings)
  Archive
} derive(Eq)

///|
/// The workspace in view and the account it is reached through (AppState's WorkspaceEntry).
pub(all) struct Here {
  workspace : String
  name : String
  sub : String
  email : String
  person : String
  picture : String
}

// ---------------------------------------------------------------------------
// Reading the core's JSON (as sfapp/model.mbt: a field left out reads as nothing)

///|
fn field(v : Json?, key : String) -> Json? {
  match v {
    Some(Object(m)) => m.get(key)
    _ => None
  }
}

///|
fn text(v : Json?, key : String) -> String {
  match field(v, key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn opt_text(v : Json?, key : String) -> String? {
  match field(v, key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn flag(v : Json?, key : String) -> Bool {
  match field(v, key) {
    Some(True) => true
    _ => false
  }
}

///|
fn has(v : Json?, key : String) -> Bool {
  match field(v, key) {
    Some(Null) | None => false
    _ => true
  }
}

///|
fn number(v : Json?, key : String) -> Double {
  match field(v, key) {
    Some(Number(n, ..)) => n
    _ => 0.0
  }
}

///|
fn count(v : Json?, key : String) -> Int {
  number(v, key).to_int()
}

///|
fn items(v : Json?, key : String) -> Array[Json] {
  match field(v, key) {
    Some(Array(a)) => a
    _ => []
  }
}

///|
fn strings(v : Json?, key : String) -> Array[String] {
  items(v, key).filter_map(fn(x) {
    match x {
      String(s) => Some(s)
      _ => None
    }
  })
}

///|
/// A time of `v` in words (`time.<key>.<how>`: ago, until, full), as the core puts them in.
fn stamp(v : Json?, key : String, how : String) -> String {
  text(field(field(v, "time"), key), how)
}

///|
/// What a call's error says (errorText): its message, else its code.
fn error_text(e : Json) -> String {
  match text(Some(e), "message") {
    "" => text(Some(e), "code")
    m => m
  }
}

///|
fn obj(pairs : Array[(String, Json)]) -> Json {
  let m : Map[String, Json] = Map::new()
  for p in pairs {
    m[p.0] = p.1
  }
  Json::object(m)
}

///|
fn str(v : String) -> Json {
  Json::string(v)
}

///|
fn join(parts : Array[String], sep : String) -> String {
  let b = StringBuilder()
  let mut first = true
  for p in parts {
    if p == "" {
      continue
    }
    if !first {
      b.write_string(sep)
    }
    b.write_string(p)
    first = false
  }
  b.to_string()
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

// ---------------------------------------------------------------------------
// What was set going (the core's `doing`: AppState.isDoing, failedOf, act)

///|
/// Whether one of `calls` about what `on` names is under way (the core's `doing` topic: its params as words).
fn is_doing(core : Core, calls : Array[String], on : Array[(String, String)]) -> Bool {
  doing_items(core).iter().any(fn(d) { text(Some(d), "stage") != "failed" && doing_matches(d, calls, on) })
}

///|
/// Why one of `calls` about what `on` names failed a moment ago (the core keeps it a few seconds), if it did.
fn failed_of(core : Core, calls : Array[String], on : Array[(String, String)]) -> String? {
  let mut why : String? = None
  for d in doing_items(core) {
    if text(Some(d), "stage") == "failed" && doing_matches(d, calls, on) {
      why = Some(
        match text(Some(d), "error") {
          "" => tr("android-misc.failed")
          e => e
        },
      )
    }
  }
  why
}

///|
fn doing_items(core : Core) -> Array[Json] {
  items((core.topic)("doing", Map::new()).value, "doing")
}

///|
fn doing_matches(d : Json, calls : Array[String], on : Array[(String, String)]) -> Bool {
  calls.contains(text(Some(d), "call")) &&
  on.iter().all(fn(kv) { text(field(Some(d), "params"), kv.0) == kv.1 })
}

///|
/// What a person did, let go on by itself (AppState.act): the call made; failed, `没能<what>：<why>` said; gone
/// through, `done` (when there is one) said and `then` run.
fn act(
  core : Core,
  what : String,
  name : String,
  params : Json,
  done? : String = "",
  then? : (Json) -> Unit = fn(_) {  },
) -> Unit {
  (core.call)(name, params, fn(r) {
    match r {
      Ok(v) => {
        if done != "" {
          (core.say)(done)
        }
        then(v)
      }
      Err(e) =>
        (core.say)(
          fill(
            if text(Some(e), "code") == "unconfirmed" {
              "android-misc.act.unconfirmed"
            } else {
              "android-misc.act.failed"
            },
            [("what", what), ("error", error_text(e))],
          ),
        )
    }
  })
}

///|
/// The workspace's view (`workspace`, still.fail cloud's: its role, members, stations, added, invitations, relays).
fn workspace_view(core : Core, here : Here) -> Read {
  (core.topic)("workspace", { "workspace": str(here.workspace) })
}

///|
/// The workspace's stations (`stations`: StationView).
fn stations_of(core : Core, here : Here) -> Read {
  (core.topic)("stations", { "scope": str(here.workspace) })
}

///|
/// Whether the viewer is one of the workspace's owners or admins; None until the workspace is read (Settings.kt
/// managerOf).
fn manager_of(core : Core, here : Here) -> Bool? {
  let w = workspace_view(core, here)
  match w.value {
    Some(_) => {
      let role = text(w.value, "role")
      Some(role == "owner" || role == "admin")
    }
    None => if w.error is Some(_) { Some(false) } else { None }
  }
}

///|
/// A role in words (Accounts.kt ROLE_LABEL).
fn role_label(role : String) -> String {
  match role {
    "owner" => "Owner"
    "admin" => tr("android-misc.role.admin")
    "member" => tr("android-misc.role.member")
    r => r
  }
}

///|
/// A station's name from its address (ChatInk.kt stationName): what is after the workspace.
fn station_name(address : String) -> String {
  match address.find("/") {
    Some(i) => address.unsafe_substring(start=i + 1, end=address.length())
    None => address
  }
}

///|
/// The workspace of an address (ws/st).
fn workspace_of(address : String) -> String {
  match address.find("/") {
    Some(i) => address.unsafe_substring(start=0, end=i)
    None => address
  }
}

///|
/// The workspace `id` and the account it is reached through, from the `workspaces` topic (AccountWorkspaces).
pub fn here_of(core : Core, id : String, name : String) -> Here {
  let ws = (core.topic)("workspaces", Map::new())
  match ws.value {
    Some(Array(accounts)) =>
      for a in accounts {
        for w in items(Some(a), "workspaces") {
          if text(Some(w), "id") == id {
            let acc = field(Some(a), "account")
            return {
              workspace: id,
              name: text(Some(w), "name"),
              sub: text(acc, "sub"),
              email: text(acc, "email"),
              person: text(acc, "name"),
              picture: text(acc, "picture"),
            }
          }
        }
      }
    _ => ()
  }
  { workspace: id, name, sub: "", email: "", person: "", picture: "" }
}

///|
/// A page of the settings left the stack: what it kept goes (its words looked for, a sheet of its own).
pub fn left(route : Route) -> Unit {
  match route {
    Archive => archive_reset()
    Security => opening_lock.val = false
    Memory(a) | MemoryDoc(a, _, _) =>
      match memories.get(a) {
        Some(m) => m.asked = false
        None => ()
      }
    Connects(_) => connects_mine.val = false
    Usage => {
      usage_state.day = ""
      usage_state.all = false
    }
    _ => ()
  }
  close_sheet()
  menu.up = false
}

///|
/// As at the start: nothing chosen, no sheet (tests).
pub fn reset() -> Unit {
  archive_reset()
  notify_switched.val = None
  opening_lock.val = false
  memories.clear()
  connects_mine.val = false
  usage_state.days = 7
  usage_state.day = ""
  usage_state.list = 0
  usage_state.all = false
  chosen.clear()
  builtin_open.clear()
  doc_picked.clear()
  close_sheet()
  sheet.last = None
  sheet.was_up = false
  sheet.height = 0.5
  sheet.on_close = fn() {  }
  sheet.serial = 0
  menu.items = []
  menu.selected = -1
  menu.x = 0.0
  menu.y = 0.0
  menu.pick = fn(_) {  }
  menu.up = false
  frame_core.val = None
  at_root.val = false
  wide.val = false
  wide_deep.val = false
  top_trailing.val = None
  top_label.val = ""
  fx.names.clear()
  fx.restored.clear()
  fx.version = 0
}

///|
/// A page by its name, for opening one from the start (MBUI_FIXTURE=settings-<name>, a scripted run): home, me,
/// appearance, workspace, security, vault, stations, station:<address>, profiles, connects, memories, memory:<address>,
/// usage, archive.
pub fn route_of(name : String) -> Route? {
  match name {
    "" | "home" => Some(Home)
    "me" => Some(Me)
    "appearance" => Some(Appearance)
    "workspace" => Some(Workspace)
    "security" => Some(Security)
    "vault" => Some(Vault)
    "stations" => Some(Stations)
    "profiles" => Some(Profiles(""))
    "connects" => Some(Connects(""))
    "memories" => Some(Memories)
    "usage" => Some(Usage)
    "archive" => Some(Archive)
    _ =>
      match name.find(":") {
        Some(i) => {
          let what = name.unsafe_substring(start=0, end=i)
          let arg = name.unsafe_substring(start=i + 1, end=name.length())
          // address#id where a page is something of a station's
          let (address, id) = match arg.find("#") {
            Some(k) => (arg.unsafe_substring(start=0, end=k), arg.unsafe_substring(start=k + 1, end=arg.length()))
            None => (arg, "")
          }
          match what {
            "station" => Some(Station(arg))
            "memory" => Some(Memory(arg))
            "memory-doc" => Some(MemoryDoc(address, id, 0))
            "profiles" => Some(Profiles(arg))
            "profile" => Some(Profile(address, id))
            "connects" => Some(Connects(arg))
            "connect" => Some(Connect(address, id))
            _ => None
          }
        }
        None => None
      }
  }
}

///|
/// Whether the thing `id` was tapped (what it changed is drawn in the next frame, which a handled click asks for).
fn hit(c : @ui.Ctx, id : Int) -> Bool {
  c.clicked(id)
}
