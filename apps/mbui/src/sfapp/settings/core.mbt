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
  /// this page left for another in its place (a step on from it: a profile added on to choosing its models, those
  /// chosen on to its page), over the page under it as this one was
  in_place : (Route) -> Unit
  /// back to the chats (a workspace left)
  home : () -> Unit
  /// a chat opened: its station, its session, its title
  open_chat : (String, String, String) -> Unit
  /// a station's drive opened (its folders lent: src/sfapp/drive.mbt), by its address
  open_drive : (String) -> Unit
  /// A pinned folder opened in the same destination as the station's files.
  open_folder : (String, String) -> Unit
  /// signing another account in (登录其他账号)
  sign_in : () -> Unit
  /// a toast (Sheet.kt ToastHost)
  say : (String) -> Unit
  /// a person's picture by its URL: an image's key once it is here, "" until then
  picture : (String, Int) -> String
  /// notifications turned on here: the system asked to allow them (Notices.kt rememberNotificationAsk)
  notify_ask : () -> Unit
  /// this device's push registration as the core now wants it (Push.sync): what `notify.set` answered (`push`), or
  /// None for what the core's `notify` says
  push_sync : (Bool?) -> Unit
  /// what the page under this one is: "chats" (Home), "settings", or "" (another)
  under : () -> String
  /// how this build's update stands (关于's version row, settings' 关于 row)
  version_now : () -> VersionNow
  /// the version row pressed: a newer build installed, or still.fail cloud asked now; the update dialog saying how it goes
  version_tap : () -> Unit
  /// 本机 Station's installer run (the app's local_station.mbt): `true` a station downloaded and joined to this
  /// workspace (none here), `false` the one here brought up to the latest release and run as a service
  local_install : (Bool) -> Unit
  /// a web page to open (a sign-in's, Slack's): handed to the system's browser (@ui.open_url), said so where nothing
  /// took it
  open_link : (String) -> Unit
  /// a page opened in the station's own browser (a sign-in's): its tab's screen in the viewer, by station and screen,
  /// gone back from by itself once the tab is gone (closed as the sign-in ends)
  open_screen : (String, String) -> Unit
  /// the system's photo picker asked for a picture (false: this host has none); its bytes given as it answers (None:
  /// called off, nothing read)
  pick_picture : ((Bytes?) -> Unit) -> Bool
  /// this device's bottom bars in the workspace in view, and the one shown (Places.kt's)
  bars : () -> (Array[Array[String]], Int)
  /// the bars changed (kept as the workspace's), the one shown
  set_bars : (Array[Array[String]], Int) -> Unit
  /// a place's icon, 28 high in a colour (Station's the stations' glyph, one on)
  place_icon : (@ui.Ctx, String, Int64) -> Unit
  /// whether usage statistics and error reports go out from this device (Crashes.reporting); None where nothing is
  /// sent anyway (no host takes them, a build without PostHog's key): no row then
  reporting : () -> Bool?
  /// them turned on or off on this device (Crashes.setReporting)
  set_reporting : (Bool) -> Unit
  /// a station's login as its card (the chat's, sfpages' login_card.mbt),
  /// by station and id
  login_card : (@ui.Ctx, String, String, Bool) -> Unit
  /// the card to share of the workspace's agents at work opened (sfpages' share_card_open)
  share_card : () -> Unit
  /// face `id` (at `index` in the faces' list; `variable`: one file for every weight) shown in itself on the fonts
  /// page: the host face its preview is given to, 0 until it is here (src/sfapp/faces.mbt)
  face_preview : (String, Int, Bool) -> Int
  /// whether face `id` is what a place is set in now (all its files here)
  face_here : (String) -> Bool
  /// why face `id` could not be had here (its files unzipped wrong), "" none
  face_failed : (String) -> String
  /// the host face the app's own code face is in, for the fonts page's 默认
  own_code_face : () -> Int
  /// the time of day (ms), for what is shown of it (剩余 N 分钟): the source's `now`
  now : () -> Double
  /// run with MBUI_READONLY=1: what is said in place of an answer sent (a vault request's); "" where answers go
  read_only : String
}

///|
/// A page of the settings (AppState.kt's Screen, the ones of these slices).
pub(all) enum Route {
  /// settings itself, from the gear (SettingsHome.kt)
  Home
  Me
  Appearance
  /// 外观 › 字体 (Fonts.kt FontsScreen)
  Fonts
  /// the workspace: its name, its people, its invitations (Settings.kt WorkspaceScreen)
  Workspace
  /// security mode (Security.kt)
  Security
  /// 安全 › 开启安全模式: what turning it on would sign (Security.tsx SecurityOpen)
  SecurityOpen
  Vault
  Stations
  /// a station's page, by its address (ws/st)
  Station(String)
  /// the profiles, of every station ("") or of one
  Profiles(String)
  /// a profile's page: its station's address, its id
  Profile(String, String)
  /// the step right after a profile is added: its models chosen, or skipped (PickModelsScreen)
  PickModels(String, String)
  /// which of a profile's models may be used, from its page: its station's address, its id
  ProfileModels(String, String)
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
  /// this device's adb lent to a station's agents (AdbShare.kt), by the station's address
  AdbShare(String)
  /// a new profile on a station (NewProfileScreen), by its address
  NewProfile(String)
  /// an account on several stations (ProfileAccountScreen), by its key in the workspace's profiles
  ProfileAccount(String)
  /// 全部密钥: what the vault keeps (VaultItemsScreen)
  VaultItems
  /// a secret's page (VaultItemScreen): its vault, its id
  VaultItem(String, String)
  /// the automatic decisions (AutomaticDecisionsScreen), the completion rule's page, a station's archive policy
  AutoDecisions
  AutoCompletion
  AutoPolicy(String)
  /// this device's bottom bars (BarSettingsScreen)
  BarSettings
  /// what this device keeps (KeptFilesScreen), a chat's of it: its station, its thread
  KeptFiles
  KeptChat(String, Int)
  /// what changed in still.fail (ChangelogScreen)
  Changelog
  /// about this app, from settings' 关于 (SettingsHome.kt AboutScreen): this build, the changelog, the terms
  About
  /// the web desktop's page, one for every frame (src/sfpages shortcuts.mbt): 快捷键, each action's keys changed here
  Shortcuts
  /// this machine's station (local_station.mbt)
  LocalStation
  /// the wide frame's pages as the web's has them (src/sfpages notifications.mbt, permissions.mbt): 通知, 权限, 归档
  /// (whether a done chat suggests archiving it, each station's own), a station's archiving
  Notifications
  Permissions
  Archiving
  StationArchiving(String)
  /// the prices the usage is counted at, over its days (UsagePricesScreen)
  UsagePrices(Int)
  /// how a chat's agent runs (RunSettingsScreen): its station, its session's key
  RunSettings(String, String)
} derive(Eq)

///|
/// How this build's update stands: what is under way (正在检查, 下载中 40%, 正在安装; "" while nothing is), how far
/// it has come while it downloads and the host says how far (0 to 1, else None), the newer build known, by its name
/// ("" while none is), and whether newer builds are asked for here at all (not on iOS, nor run from the sources).
pub(all) struct VersionNow {
  doing : String
  part : Double?
  newer : String
  asks : Bool
}

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
pub fn opt_text(v : Json?, key : String) -> String? {
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
pub fn has(v : Json?, key : String) -> Bool {
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
pub fn strings(v : Json?, key : String) -> Array[String] {
  items(v, key).filter_map(fn(x) {
    match x {
      String(s) => Some(s)
      _ => None
    }
  })
}

///|
/// A time of `v` in words (`time.<key>.<how>`: ago, until, full), as the core puts them in.
pub fn stamp(v : Json?, key : String, how : String) -> String {
  text(field(field(v, "time"), key), how)
}

///|
/// What a call's error says (errorText): its message, else its code.
pub fn error_text(e : Json) -> String {
  match text(Some(e), "message") {
    "" => text(Some(e), "code")
    m => m
  }
}

///|
pub fn obj(pairs : Array[(String, Json)]) -> Json {
  let m : Map[String, Json] = Map::new()
  for p in pairs {
    m[p.0] = p.1
  }
  Json::object(m)
}

///|
pub fn str(v : String) -> Json {
  Json::string(v)
}

///|
pub fn join(parts : Array[String], sep : String) -> String {
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
pub fn is_doing(core : Core, calls : Array[String], on : Array[(String, String)]) -> Bool {
  doing_items(core).iter().any(fn(d) { text(Some(d), "stage") != "failed" && doing_matches(d, calls, on) })
}

///|
/// Why one of `calls` about what `on` names failed a moment ago (the core keeps it a few seconds), if it did.
pub fn failed_of(core : Core, calls : Array[String], on : Array[(String, String)]) -> String? {
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
pub fn act(
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
pub fn workspace_view(core : Core, here : Here) -> Read {
  (core.topic)("workspace", { "workspace": str(here.workspace) })
}

///|
/// The workspace's stations (`stations`: StationView).
pub fn stations_of(core : Core, here : Here) -> Read {
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
pub fn role_label(role : String) -> String {
  match role {
    "owner" => "Owner"
    "admin" => tr("android-misc.role.admin")
    "member" => tr("android-misc.role.member")
    r => r
  }
}

///|
/// A station's name from its address (ChatInk.kt stationName): what is after the workspace.
pub fn station_name(address : String) -> String {
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
/// The core the pages were last drawn with (what a page left lets go of: a draft of the core's).
// (plain: said to what is built inside it, around that build and put back after; not a value of the page's)
let left_core : Ref[Core?] = Ref(None)

///|
/// A page of the settings left the stack: what it kept goes (its words looked for, a sheet of its own).
pub fn left(route : Route) -> Unit {
  match route {
    Archive => archive_reset()
    Connects(_) => connects_mine.set(false)
    Station(a) => station_parts.remove(a)
    NewProfile(a) =>
      match left_core.val {
        Some(core) => new_profile_left(core, a)
        None => ()
      }
    VaultItem(_, item) => vault_item_left(item)
    AutoCompletion | AutoPolicy(_) =>
      match left_core.val {
        Some(core) => decisions_left(core, route)
        None => ()
      }
    KeptFiles => {
      kept.chats.set(None)
      kept.drive.set(0.0)
      kept.loose.set([])
      kept.asked.set(kept.asked.get() + 1)
      kept_all.set(false)
    }
    BarSettings => bar_adding.set(false)
    RunSettings(_, key) => {
      run_opened.remove("session:" + key)
      run_list.remove("session:" + key)
    }
    _ => ()
  }
}

///|
/// As at the start: nothing chosen, no sheet (tests).
pub fn reset() -> Unit {
  archive_reset()
  vault_ask_reset()
  keymap_reset()
  login_marked.set(None)
  station_parts.clear()
  station_network_open.clear()
  lock_prompts_reset()
  fonts_at.set(0)
  adb_reset()
  keyed_fields.clear()
  notify_switched.set(None)
  connects_mine.set(false)
  chosen.clear()
  builtin_open.clear()
  panels_core.val = None
  frame_core.val = None
  at_root.val = false
  root_top.val = 0.0
  @sf.named_actions.val = None
  wide.set(false)
  status_top.set(0.0)
  nav_foot.set(0.0)
  bar_room.set(0.0)
  wide_deep.set(false)
  top_trailing.val = None
  top_on_back.val = None
  top_label.val = ""
  on_card.val = false
  // the pages' own state (settings complete): drafts, fields filled once, what was being done, as a run starts
  login_state.copied.clear()
  login_state.manual.clear()
  login_state.error.clear()
  login_state.seen.clear()
  profile_forms.set(0)
  machine_sessions.clear()
  adding.existing.set(false)
  adding.made.set(None)
  adding.error.set("")
  adding.known.set([])
  adding.took.clear()
  adding.order.clear()
  adding.picked.set("")
  adding.serial.set(0)
  mark_pick.emojis.set(false)
  mark_pick.color.set("")
  mark_pick.serial = 0
  mark_pick.asking.set(false)
  mark_pick.reading.set("")
  mark_pictures.set(0)
  env_form.set(0)
  versions_state.updating.clear()
  versions_state.checking.clear()
  versions_state.switching.clear()
  versions_state.turning.clear()
  versions_state.failed.clear()
  recovery_words.clear()
  vault_serial.set(0)
  // the drafts each page opened of the core (a form a station, a new connect's, a profile's, a Slack app's): a run
  // opens its own
  decision_forms.clear()
  policy_forms.clear()
  // what this device keeps, asked of a run's own core
  kept.chats.set(None)
  kept.drive.set(0.0)
  kept.loose.set([])
  kept.asked.set(0)
  kept.read.set(-1)
  kept_all.set(false)
  run_opened.clear()
  run_list.clear()
  new_profiles.clear()
  bar_adding.set(false)
  bar_moves.clear()
  opened.plain.clear()
  opened.opening.clear()
  opened.shown.clear()
  left_core.val = None
  fixture_reset()
}

///|
/// A page by its name, for opening one from the start (MBUI_FIXTURE=settings-<name>, a scripted run): home, me,
/// appearance, fonts, workspace, security, vault, vault-items, stations, station:<address>, profiles, connects, memories, memory:<address>,
/// usage, archive.
pub fn route_of(name : String) -> Route? {
  match name {
    "" | "home" => Some(Home)
    "me" => Some(Me)
    "appearance" => Some(Appearance)
    "fonts" => Some(Fonts)
    "workspace" => Some(Workspace)
    "security" => Some(Security)
    "security-open" => Some(SecurityOpen)
    "vault" => Some(Vault)
    "vault-items" => Some(VaultItems)
    "stations" => Some(Stations)
    "profiles" => Some(Profiles(""))
    "connects" => Some(Connects(""))
    "memories" => Some(Memories)
    "usage" => Some(Usage)
    "archive" => Some(Archive)
    "decisions-settings" => Some(AutoDecisions)
    "completion" => Some(AutoCompletion)
    "bars" => Some(BarSettings)
    "kept" => Some(KeptFiles)
    "changelog" => Some(Changelog)
    "about" => Some(About)
    "shortcuts" => Some(Shortcuts)
    // (版本, a page of the desktop's once: this build and a newer one are 关于's on every screen)
    "version" => Some(About)
    "local-station" => Some(LocalStation)
    "notifications" => Some(Notifications)
    "permissions" => Some(Permissions)
    "archiving" => Some(Archiving)
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
            "adb" => Some(AdbShare(arg))
            "new-profile" => Some(NewProfile(arg))
            "vault-item" => Some(VaultItem(address, id))
            "policy" => Some(AutoPolicy(arg))
            "archiving" => Some(StationArchiving(arg))
            "prices" => Some(UsagePrices(int_of(arg, 7)))
            "run" => Some(RunSettings(address, id))
            "memory" => Some(Memory(arg))
            "memory-doc" => Some(MemoryDoc(address, id, 0))
            "profiles" => Some(Profiles(arg))
            "profile" => Some(Profile(address, id))
            "pick-models" => Some(PickModels(address, id))
            "profile-models" => Some(ProfileModels(address, id))
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
pub fn hit(c : @ui.Ctx, id : Int) -> Bool {
  c.clicked(id)
}

///|
/// The number `s` writes (digits only), else `or_else`.
fn int_of(s : String, or_else : Int) -> Int {
  if s == "" {
    return or_else
  }
  let mut n = 0
  for ch in s {
    if ch < '0' || ch > '9' {
      return or_else
    }
    n = n * 10 + (ch.to_int() - 48)
  }
  n
}

///|
/// `core` as what a page will show is drawn over it in its bones (@sf.waiting's `sample`: made of made-up words): its
/// topics say nothing and its calls are never answered, so what is only shown asks the real core for nothing.
pub fn Core::quiet(self : Core) -> Core {
  { ..self, topic: fn(_, _) { { value: None, error: None, version: 0 } }, call: fn(_, _, _) {  }, picture: fn(_, _) { "" } }
}
