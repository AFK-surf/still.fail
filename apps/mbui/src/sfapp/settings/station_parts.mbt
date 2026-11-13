// A station's page, past its machine and what runs on it: its screens (StationScreens),
// what macOS lets a Mac station's helper do, the variables its agents run with
// (StationAgentEnv, edited in a sheet), what its search finds (StationSearchSection), the workspaces it is in
// (StationWorkspaces), its versions; and this device's adb lent to its agents.

///|
/// A count of the variables' sheets opened: each its own draft (`form`).
let env_form : Ref[Int] = Ref(0)

///|
/// What changes of the versions from here are on their way (Versions.kt's own state: the one updating, checking, the
/// channel and the updating by itself as asked), and what failed: by the station.
priv struct VersionsState {
  updating : Map[String, String]
  checking : Map[String, Bool]
  switching : Map[String, String]
  turning : Map[String, Bool]
  failed : Map[String, String]
}

///|
let versions_state : VersionsState = {
  updating: {},
  checking: {},
  switching: {},
  turning: {},
  failed: {},
}

///|
/// A moment (ms since 1970) as Android's short date and time say it in Chinese (DateFormat.SHORT, SHORT: 2026/9/21
/// 22:13), in the device's local time.
pub fn short_date_time(ms : Double) -> String {
  let day_ms = 86400000.0
  let local_ms = ms + @ui.utc_offset_min(ms).to_double() * 60000.0
  let days = (local_ms / day_ms).floor()
  let minutes = ((local_ms - days * day_ms) / 60000.0).floor().to_int()
  // the day's date from the days since 1970-01-01 (the proleptic Gregorian calendar: H. Hinnant's civil_from_days)
  let z = days.to_int() + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let y = yoe + era * 400 + (if m <= 2 { 1 } else { 0 })
  let two = fn(n : Int) { if n < 10 { "0" + n.to_string() } else { n.to_string() } }
  "\{y}/\{m}/\{d} \{two(minutes / 60)}:\{two(minutes % 60)}"
}

///|
/// What this device's host says it has for 共享调试 (the app's Android's AdbShare.java, as `adb.phone` answers and
/// "native:adb.phone" says again: supported, developer, wireless, wifi, canSwitch, switchRefused); None until it has said.
/// Whether `adb.phone` is being asked, and how many nodes read it (adb_phone_node): what an answer that changed the
/// phone (adb.switch's) asks again for.
priv struct AdbHost {
  phone : @signals.Signal[Json?]
  mut asking : Bool
  mut readers : Int
}

///|
let adb_host : AdbHost = { phone: @signals.signal(None), asking: false, readers: 0 }

///|
fn adb_reset() -> Unit {
  adb_host.phone.set(None)
  adb_host.asking = false
  adb_host.readers = 0
}

///|
/// The host said what the phone has now (its message on "native:adb.phone": Wireless debugging switched, the app back
/// from Settings): src/sfapp/app.mbt hands it here.
pub fn adb_phone_said(json : String) -> Unit {
  adb_host.phone.set(Some(@json.parse(json) catch { _ => return }))
}

///|
/// `adb.phone` asked of the host where the phone is not said and it is not asked already, from an event (a node made:
/// adb_phone_node; an old view's build: Ctx::tell; an answer that changed it), its answer taken as the host's event
/// tells it (@ui.native_call's on_got): said in adb_host.phone, a signal, what reads it told then; a host without
/// 共享调试 at all (a computer's, iOS): nothing it can lend, and no phone to say anything of (`none`; an Android before
/// 11 answers `supported: false` itself).
fn adb_phone_ask() -> Unit {
  guard !adb_host.asking && adb_host.phone.untracked() is None else { return }
  adb_host.asking = true
  @ui.native_call("adb.phone", obj([]), on_got=fn(r) {
    adb_host.asking = false
    adb_host.phone.set(
      Some(
        match r {
          Ok(j) => j
          Err(_) => obj([("supported", Json::boolean(false)), ("none", Json::boolean(true))])
        },
      ),
    )
  })
  |> ignore
}

///|
/// The phone as its host last said it, asked once as an old view's page shows (adb_phone_ask, after its build).
fn adb_phone(c : @ui.Ctx) -> Json? {
  if adb_host.phone.get() is None && !adb_host.asking {
    c.tell("adb-phone", adb_phone_ask)
  }
  adb_host.phone.get()
}

///|
/// The phone as its host says it, for what node `v` makes (a request's card in its chat): asked as `v` is made, between
/// frames (View::at_moment, its making's moment), where it is not said; asked again while `v` lives as an answer changes
/// it; read where it is read, told as it is said (a signal), never looked at frame by frame.
pub fn adb_phone_node(v : @view.View) -> () -> Json? {
  adb_host.readers = adb_host.readers + 1
  v.owns(fn() { adb_host.readers = if adb_host.readers > 0 { adb_host.readers - 1 } else { 0 } }) |> ignore
  v.at_moment(0.0, adb_phone_ask) |> ignore
  fn() { adb_host.phone.get() }
}

///|
/// The phone as its host last said it, followed (a signal): None till it has said (adb_phone_node asks it).
pub fn adb_phone_now() -> Json? {
  adb_host.phone.get()
}

///|
/// What a tap asks of the host (adb.switch, adb.open), its answer taken as the host's event tells it: one that changed
/// the phone (`on`) has it said again, asked again at once where a node reads it (an old view's page asks as it builds).
fn adb_ask(name : String, params : Json) -> Unit {
  @ui.native_call(name, params, on_got=fn(r) {
    if r is Ok(Object(m)) && m.contains("on") {
      adb_host.phone.set(None)
      if adb_host.readers > 0 {
        adb_phone_ask()
      }
    }
  })
  |> ignore
}

///|
/// The notifications' words, the app's own (AdbShare.java fills `{name}`, `{n}`, `{error}`).
pub fn adb_texts() -> Json {
  let m : Map[String, Json] = Map([])
  for k in [
      "title", "notify.title", "notify.chats", "notify.on", "notify.idle", "notify.screen", "notify.screens", "stop", "turnOff", "pair.channel", "code", "pair.ask", "typeCode", "enterCode", "connecting",
      "connected", "connected.left", "notPaired", "pair.popped", "off", "attaching", "pairing", "paired", "pairFailed",
      "shareFailed",
    ] {
    let key = "android-misc.adb." + k
    m[key] = Json::string(tr(key))
  }
  Json::object(m)
}

///|
/// The one thing to do next for 共享调试 on this phone, as settings' page and a granted request's card in its chat say it
/// alike: what it is (`sub` how, or why it is not done by itself, where that needs saying), what the press on it says
/// (`go`: the page's button, "" none) and does (`act`, adb_do: "" nothing to press, the step the phone's own or the
/// station's), and the call it makes under way (`doing`).
pub(all) struct AdbStep {
  title : String
  sub : String
  go : String
  doing : String
  act : String
}

///|
/// The lendings chats' grants made (`adbShare`'s `lends`: each station's, how its adb holds the phone).
pub fn adb_lends(all : Json?) -> Array[Json] {
  match field(all, "lends") {
    Some(Array(a)) => a
    _ => []
  }
}

///|
/// The phone's lending to the station at `address`, as `adbShare` says the one it names at its top: that one, or the
/// station's among its `lends` (a phone granted to chats on two stations is lent to both; what the topic's top says is
/// only the one a person has something to do for), with the ports the app found for adbd (the phone's, the same for
/// each). Not lent there: the topic as it is.
pub fn adb_lend_view(all : Json?, address : String) -> Json? {
  if flag(all, "sharing") && text(all, "station") == address {
    return all
  }
  match adb_lends(all).iter().find_first(fn(l) { text(Some(l), "station") == address }) {
    Some(Object(l)) => {
      let out : Map[String, Json] = Map([])
      for k, v in l {
        out[k] = v
      }
      out["sharing"] = Json::boolean(true)
      for key in ["connectPort", "pairPort", "refusedPort"] {
        match field(all, key) {
          Some(v) => out[key] = v
          None => ()
        }
      }
      Some(Json::object(out))
    }
    _ => all
  }
}

///|
/// A step for adb_next to say.
fn step_of(title : String, sub? : String = "", go? : String = "", doing? : String = "", act? : String = "") -> AdbStep? {
  Some({ title, sub, go, doing, act })
}

///|
/// What is next for the lending, as the phone has it and the station holds it: the first thing the phone lacks, else
/// what the station's adb waits on (pairing, the phone's 允许); None while nothing is asked of the person (lent and
/// connected, connecting, adb failing and tried again by itself). Each step the phone takes is a press away, Settings
/// opened at it where the app cannot do it (2026-11-11: the chat's card does each step itself, not a page about them).
fn adb_next(view : Json?, phone : Json?, there : Bool) -> AdbStep? {
  let adb = text(view, "adb")
  if !flag(phone, "developer") {
    return step_of(tr("android-misc.adb.step.developer"), sub=tr("android-misc.adb.developer.how"), go=tr("android-misc.adb.developer.go"), act="about")
  }
  // held off Wi-Fi on adbd's plain port (AdbPorts.TCP): neither Wi-Fi nor Wireless debugging is wanted for it
  let held = there && adb == "connected"
  if !held && !flag(phone, "wifi") {
    return step_of(tr("android-misc.adb.step.wifi"), sub=tr("android-misc.adb.wifi.needed"), go=tr("android-misc.adb.wifi.go"), act="wifi")
  }
  if !held && (!flag(phone, "wireless") || (there && adb == "off")) {
    let can_switch = flag(phone, "canSwitch")
    // (the app asks a station holding the phone to let it turn Wireless debugging on itself, nobody asked; a phone that
    // refused it (ColorOS, MIUI): which switch of Developer options lets it)
    return step_of(
      tr("android-misc.adb.step.wireless"),
      sub=if !can_switch && flag(phone, "switchRefused") { tr("android-misc.adb.wireless.refused") } else { "" },
      go=tr(if can_switch { "android-misc.adb.wireless.turnOn" } else { "android-misc.adb.wireless.settings" }),
      act=if can_switch { "switch" } else { "wireless" },
    )
  }
  if !there || text(view, "phase") != "offered" {
    return None
  }
  match adb {
    "unpaired" if has(view, "pairPort") =>
      step_of(tr("android-misc.adb.enterCode"), sub=tr("android-misc.adb.pair.hint"), go=tr("android-misc.adb.pair.action"), doing="adb.pair", act="code")
    "unpaired" =>
      step_of(tr("android-misc.adb.pair.open"), sub=tr("android-misc.adb.step.pairHow"), go=tr("android-misc.adb.pair.go"), act="pairing")
    // (nothing to press: the phone's own prompt, the station's machine)
    "unauthorized" => step_of(tr("android-misc.adb.unauthorized"))
    "missing" => step_of(tr("android-misc.adb.step.install"))
    _ => None
  }
}

///|
/// The first thing left to do on this phone for a chat's grant on the station at `station` (a granted request's card
/// in its chat, decision.mbt): its 共享调试 switch off, then what the phone lacks, then what that station's lending
/// waits on (adb_next). None where nothing is, or this device lends no adb of its own.
pub fn adb_step_at(c : @ui.Ctx, core : Core, station : String) -> AdbStep? {
  adb_step_of(core, station, adb_phone(c))
}

///|
/// The same, the phone as `phone` says it (adb_phone_node's, a node's).
pub fn adb_step_of(core : Core, station : String, phone : Json?) -> AdbStep? {
  if !flag(phone, "supported") {
    return None
  }
  let all = (core.topic)("adbShare", Map([])).get().value
  if !flag(all, "on") {
    return step_of(tr("android-misc.adb.step.on"), sub=tr("android-misc.adb.on.note"), act="on")
  }
  let view = adb_lend_view(all, station)
  let there = flag(view, "sharing") && text(view, "station") == station
  adb_next(if there { view } else { None }, phone, there)
}

///|
/// A step's press (AdbStep `act`): 共享调试's switch turned on (`on`); About phone (`about`) or Wi-Fi's settings
/// (`wifi`) opened; Wireless debugging turned on by the app (`switch`) or in Settings (`wireless`), the pairing dialog
/// opened beside the app (`pairing`), the code asked for and paired with (`code`, with `station`'s lending).
pub fn adb_do(core : Core, what : String, station? : String = "") -> Unit {
  match what {
    "on" => adb_turn(core, true)
    "about" | "wifi" => adb_ask("adb.open", obj([("what", str(what))]))
    "switch" => adb_ask("adb.switch", obj([]))
    "wireless" => adb_ask("adb.open", obj([("what", str("wireless"))]))
    "pairing" => adb_ask("adb.open", obj([("what", str("wireless")), ("beside", Json::boolean(true))]))
    "code" =>
      ask(
        tr("android-misc.adb.pair.ask"),
        "",
        tr("android-misc.adb.code"),
        tr("android-misc.adb.pair.action"),
        hint=tr("android-misc.adb.pair.hint"),
        fn(code) {
          let digits = StringBuilder()
          for ch in code {
            if ch >= '0' && ch <= '9' {
              digits.write_char(ch)
            }
          }
          act(
            core,
            tr("android-misc.adb.pair.action"),
            "adb.pair",
            obj([("code", str(digits.to_string())), ("station", str(station))]),
            done=tr("android-misc.adb.paired"),
          )
        },
      )
    _ => ()
  }
}

///|
/// 共享调试's switch turned (`on`): on, with the notification it shows allowed and Wireless debugging turned on where
/// the app may; the core's `adb.on` either way. The page's switch, and on a phone 允许 or a step in a chat that finds it
/// off (2026-11-11: allowing is turning it on).
pub fn adb_turn(core : Core, on : Bool) -> Unit {
  if on {
    if @ui.notice_permission() != "granted" {
      @ui.notice_ask() |> ignore
    }
    adb_switch_on()
  }
  act(core, tr(if on { "android-misc.adb.step.on" } else { "android-misc.adb.turnOff" }), "adb.on", obj([("on", Json::boolean(on))]))
}

///|
/// 共享调试 while this device is off the person's own lock `p` (of `adbShare`'s `personal`): a page of its own, as a
/// device waiting for a workspace's lock has (@sf.waiting_page, the shield), with the one step this device takes there:
/// be approved (发送批准请求: a code a trusted device of theirs shows, typed in here: personal_join), or say whether
/// their trusted devices set up again elsewhere (the lock the cloud has in the place of the one pinned here) are theirs.
/// With no lock yet there is no step (allowing a request begins it): the page shows as it is.
fn adb_lock_first(c : @ui.Ctx, core : Core, p : Json?) -> Unit {
  let sub = text(p, "sub")
  let said = obj([("sub", str(sub))])
  let doing = is_doing(core, ["adb.personalOpen", "adb.personalJoin", "adb.personalCode", "adb.personalForget", "adb.personalRestart"], [])
  let primary = fn(key : String, words : String, call : String) {
    @sf.button(c, words, key~, tone=Primary, busy=doing, disabled=doing, on_press=fn() {
      act(core, words, call, said)
    })
  }
  match text(p, "standing") {
    "outside" => {
      let state = text(field(p, "pair"), "state")
      @sf.waiting_page(c, "shield-check", tr("android-misc.adb.lock.join"), tr("android-misc.personal.outside.note"), fn() {
        if state != "" && state != "done" {
          personal_join(c, core, p, "adb/" + sub, centred=true)
        }
        if state == "" || state == "none" || state == "failed" || state == "done" {
          primary("adb-lock-join", tr("web-pages.security.request"), "adb.personalJoin")
        }
        // (no device of theirs to be found: only then)
        if state == "none" || state == "failed" {
          @sf.button(c, tr("android-misc.personal.restart"), key="adb-lock-restart", tone=Ghost, disabled=doing, on_press=fn() {
            act(core, tr("android-misc.personal.restart"), "adb.personalRestart", said)
          })
          c.text(tr("android-misc.personal.restart.note"), style=@sf.ask_note) |> ignore
        }
      })
    }
    "replaced" =>
      @sf.waiting_page(c, "shield-check", tr("android-misc.personal.replaced"), tr("android-misc.personal.replaced.note"), fn() {
        primary("adb-lock-forget", tr("android-misc.personal.forget"), "adb.personalForget")
      })
    _ => ()
  }
}

///|
/// Wireless debugging turned on by the app, where it is off and the app may (adb.grant let it).
fn adb_switch_on() -> Unit {
  let phone = adb_host.phone.get()
  if !flag(phone, "wireless") && flag(phone, "canSwitch") {
    adb_ask("adb.switch", obj([]))
  }
}

///|
/// Whether this device lends its own adb (a phone on Android 11 or later, whatever it still lacks): where a granted
/// request's card says what is left to do on it, and 允许 turns its 共享调试 on.
pub fn phone_lends(c : @ui.Ctx) -> Bool {
  flag(adb_phone(c), "supported")
}

///|
/// The station at `address` whole, as its own page shows it (`station`: its overview, machine, profiles' groups, the
/// runtimes it runs and their models, …): no value while the workspace's stations are not known, null where it has no
/// such station. Asked of the workspace the address is of (`here`'s for one without it).
pub fn station_read(core : Core, here : Here, address : String) -> Read {
  station_read_in(core, station_scope(here, address), address)
}

///|
fn station_read_in(core : Core, scope : String, address : String) -> Read {
  let (name, params) = station_ask_in(scope, address)
  (core.topic)(name, params).get()
}

///|
/// What station_read asks of the core for the station at `address` (its topic and its arguments): for a press that asks
/// it ahead of the page that reads it (sfbase's open_answered).
pub fn station_ask(here : Here, address : String) -> (String, Map[String, Json]) {
  station_ask_in(station_scope(here, address), address)
}

///|
fn station_ask_in(scope : String, address : String) -> (String, Map[String, Json]) {
  ("station", { "scope": str(scope), "station": str(address) })
}

///|
/// The station at `address` whole (station_read), None while not known or where there is none.
pub fn station_of(core : Core, here : Here, address : String) -> Json? {
  match station_read(core, here, address).value {
    Some(Object(_)) as s => s
    _ => None
  }
}

///|
/// One part of station `address`'s overview (`stationPart`: `archiving`, `automaticDecisions`, `profiles`,
/// `machineLogins`, `logins`, `updates`), for a page that shows that part of every station, each station's row asking
/// its own, or that part of one station that is not its page (关于's 本机 Station, its `updates`): None while not
/// answered, null while its overview is not read or has none.
pub fn station_part(core : Core, here : Here, address : String, part : String) -> Json? {
  station_part_in(core, station_scope(here, address), address, part)
}

///|
fn station_part_in(core : Core, scope : String, address : String, part : String) -> Json? {
  (core.topic)("stationPart", { "scope": str(scope), "station": str(address), "part": str(part) }).get().value
}

///|
/// Connect `id` of station `address` whole, as its own page shows it (`connect`: its connect, its latest sessions, the
/// one it delivers into, how many of them run, the ways it could change): no value while its station's overview is not
/// read, null where the station is not up or has no such connect. Asked one way wherever one connect is shown, of the
/// workspace the address is of (`here`'s for one without it); a list of connects reads their rows (`connects`), never
/// one whole (the user, 2026-11-10).
pub fn connect_read(core : Core, here : Here, address : String, id : String) -> Read {
  (core.topic)("connect", { "scope": str(station_scope(here, address)), "station": str(address), "id": str(id) }).get()
}

///|
/// Connect `id` of station `address` whole (connect_read), None while not known or where there is none.
pub fn connect_of(core : Core, here : Here, address : String, id : String) -> Json? {
  match connect_read(core, here, address, id).value {
    Some(Object(_)) as c => c
    _ => None
  }
}

///|
/// The sessions connect `id` of station `address` could deliver into (`connectCandidates`: each its key, title,
/// description and whether it is the one now, the latest first), for its choice of one alone: None while not answered
/// or where there is no such connect. Held ahead by a single-session connect's page while its 更换 row shows
/// (connect_candidates_asked), so the choice opens on them whole.
pub fn connect_candidates(core : Core, here : Here, address : String, id : String) -> Array[Json]? {
  match (core.topic)("connectCandidates", connect_candidates_asked(here, address, id)).get().value {
    Some(Object(_)) as v => Some(items(v, "candidates"))
    _ => None
  }
}

///|
/// What `connectCandidates` is asked with for connect `id` of station `address` (connect_candidates'), for what holds it
/// ahead of the choice that reads it.
pub fn connect_candidates_asked(here : Here, address : String, id : String) -> Map[String, Json] {
  { "scope": str(station_scope(here, address)), "station": str(address), "id": str(id) }
}

///|
/// One account of the workspace whole, as its own pages show it (`profile`: its members, the places it is on, its
/// stations, its check's detail, its allowance's resets and times), by the profile of it on station `address`: no value
/// while the stations' overviews are not read, null where no station has that profile. Asked so by a profile's page on
/// a station (sfpages accounts.mbt); the account's page of all its stations asks it by its key (profile_by_key_read). A
/// list of accounts reads their rows (`profiles`), never one whole.
pub fn profile_read(core : Core, here : Here, address : String, id : String) -> Read {
  (core.topic)("profile", { "scope": str(station_scope(here, address)), "station": str(address), "id": str(id) }).get()
}

///|
/// One account of the workspace whole (profile_read), by its key (a row's `key`): the account's page of all its
/// stations (profile_new.mbt), null where the workspace has no such account.
pub fn profile_by_key_read(core : Core, here : Here, key : String) -> Read {
  (core.topic)("profile", { "scope": str(here.workspace), "key": str(key) }).get()
}

///|
/// The account of profile `id` on station `address` whole (profile_read), None while not known or where there is none.
pub fn profile_of(core : Core, here : Here, address : String, id : String) -> Json? {
  match profile_read(core, here, address, id).value {
    Some(Object(_)) as e => e
    _ => None
  }
}

///|
/// The workspace a station is asked of: its address's, `here`'s for one without it.
fn station_scope(here : Here, address : String) -> String {
  if address.contains("/") {
    workspace_of(address)
  } else {
    here.workspace
  }
}

///|
/// Settings' 共享调试 (2026-10-29: as the vault's page): a chat's agent asks for the phone and its person grants it on
/// the card in the chat, which also takes the phone through what it lacks the first time (2026-11-11). Here, on a phone:
/// its switch (2026-10-30: off at first, on until turned off, `adb.on`), lent to no chat while off; while a chat's grant
/// is live and the phone lacks something for it, that step, as the chat's card says it; then the chats it is granted to
/// now, each taken back with 收回. Off a phone, only those chats. (2026-11-11, 左子健: each thing asked "when does a
/// person need this?"; went: the devices that approve phone debugging (安全's 移除 takes one off), the requests waiting
/// (each is a card in its chat, in 待处理), 默认最长授权 (each card chooses), 自动填配对码 (pairing is once per phone),
/// 允许 app 自动开启无线调试 (everyone needs it: the app asks for it itself, AdbShareService).) The one page of
/// 共享调试: a station's (its link in a chat, the desk's tab) is this one, `focus` the lent station whose step is said
/// first.
///|
/// Settings' 共享调试 as a whole, the page's room.
// kept across runs: a value (no field of it changes)
let adb_whole : @ui.Style = @ui.css("w=Full h=Full")

///|
/// What a row says when there is nothing to list, or nothing to lend (muted, the row's width).
// kept across runs: a value (no field of it changes)
let adb_quiet : @ui.TextStyle = @ui.text_style(size=Body, color=Muted, w=Full)

///|
fn adb_settings(c : @ui.Ctx, core : Core, _here : Here, focus? : String = "") -> Unit {
  let view = (core.topic)("adbShare", Map([])).get().value
  let phone = adb_phone(c)
  let grants = match field(view, "grants") {
    Some(Array(a)) => a
    _ => []
  }
  let live = grants.filter(fn(g) { text(Some(g), "status") == "granted" })
  c.box(style=adb_whole, fn() {
    // (what it is, in the title's ⓘ: not a card of words over the page)
    nav_bar(c, core, tr("android-settings.title"), tr("android-misc.adb.title"), about=tr("android-misc.adb.chats.about"))
    // (2026-11-06, 左子健: 如果这个共享调试之后必须用个人锁，那就整个页面只显示个人锁，开了才有后面的; 用专门的 UI) Off
    // the person's own lock nothing else here does anything (the phone lends only on grants a device on it signed):
    // the page is the step alone while this device is to be approved, or the lock was set up again elsewhere. With no
    // lock yet there is no step: the owner took 开启 away (the user, 2026-11-10), allowing a request begins it
    let locks = items(view, "personal")
    if !locks.iter().any(fn(l) { text(Some(l), "standing") == "member" }) {
      match locks.iter().find_first(fn(l) { text(Some(l), "standing") == "outside" || text(Some(l), "standing") == "replaced" }) {
        Some(l) => {
          adb_lock_first(c, core, Some(l))
          return
        }
        None => ()
      }
    }
    let blocks : Array[() -> Unit] = []
    let keys : Array[String] = []
    // the phone's switch: only a phone lends
    if flag(phone, "supported") {
      keys.push("switch")
      blocks.push(fn() {
        list_card(c, fn() {
          let on = flag(view, "on")
          // (the library's switch row, as every setting's; 2026-11-06 左子健: 共享调试的标题为啥没有加粗)
          if @sf.switch_row(c, "adb-on-switch", tr("android-misc.adb.title"), on, note=tr("android-misc.adb.on.note")) != on {
            adb_turn(core, !on)
          }
        })
      })
    }
    // While a chat's grant is live, the first thing to do on this phone for it, with its press, as that chat's card says
    // it (adb_next): what the phone lacks, else what a station it is lent to waits on of it (pairing: the phone's own,
    // once, for every station; the phone's own adb session), `focus`'s first. A station's own step says which station
    // where it is lent to more than one (paired with the first, the card for the second looked the same). The switch
    // off is no step here: the switch is over it.
    let lent = adb_lent(view, focus)
    let (next, next_at) = if live.is_empty() || !flag(phone, "supported") {
      (None, "")
    } else {
      match adb_next(None, phone, false) {
        Some(step) => (Some(step), "")
        None => {
          let mut found : (AdbStep?, String) = (None, "")
          for l in lent {
            if found.0 is None {
              found = (adb_next(l.1, phone, true), l.0)
            }
          }
          found
        }
      }
    }
    match next {
      Some(step) => {
        // (what else the phone lacks after the first, in view with it)
        let later : Array[String] = []
        if !flag(phone, "developer") && !flag(phone, "wifi") {
          later.push(tr("android-misc.adb.wifi") + " " + tr("android-misc.adb.wifi.off"))
        }
        if (!flag(phone, "developer") || !flag(phone, "wifi")) && !flag(phone, "wireless") {
          later.push(tr("android-misc.adb.wireless") + " " + tr("android-misc.adb.offValue"))
        }
        let lines : Array[String] = []
        if next_at != "" && lent.length() > 1 {
          lines.push(adb_station_name(core, next_at))
        }
        if step.sub != "" {
          lines.push(step.sub)
        }
        lines.append(later)
        let note = lines.join("  ·  ")
        keys.push("phone-step")
        blocks.push(fn() {
          card(c, foot=if step.act != "" { UiCapsule } else { Words }, fn() {
            c.box(style=adb_step_box, fn() {
              @sf.card_lines(c, step.title, note~, title_after=fn() {
                @sf.pill(c, tr("web-main.attention.entry"), tone=Amber)
              })
              if step.act != "" {
                @sf.card_foot(c, fn() {
                  // (the call it makes under way: pairing with the code typed)
                  let busy = step.doing != "" && is_doing(core, [step.doing], [])
                  @sf.button(c, step.go, key="adb-phone-next", tone=Primary, busy~, disabled=busy, on_press=fn() {
                    adb_do(core, step.act, station=next_at)
                  })
                })
              }
            })
            |> ignore
          })
          |> ignore
        })
      }
      None => ()
    }
    // an Android before 11 (its host says so); a host with no adb at all (a computer's) has no phone to say it of
    if phone is Some(_) && !flag(phone, "supported") && !flag(phone, "none") {
      keys.push("unsupported")
      blocks.push(fn() {
        list_card(c, fn() {
          list_row(c, fn() {
            c.text(tr("android-misc.adb.unsupported"), style=adb_quiet) |> ignore
          })
          |> ignore
        })
      })
    }
    // the grants from before signatures, one tap from lending again
    confirm_row(c, core, view, blocks, keys)
    // (12 under the page's head where a card comes first; a page opening on the chats' heading starts with it, as
    // Profile's groups do (profiles.mbt): section_header knows it is the first, where a first card would stand)
    if !blocks.is_empty() {
      blocks.insert(0, fn() { gap(c, 12.0) })
      keys.insert(0, "head")
    }
    // the chats it is lent to now, each taken back here
    keys.push("live-heading")
    blocks.push(fn() { section_header(c, tr("android-misc.adb.chats.live"), start=S6) })
    keys.push("live")
    blocks.push(fn() {
      list_card(c, fn() {
        if live.is_empty() {
          list_row(c, fn() {
            // (off a phone: the person's phone, not this device)
            c.text(tr(if flag(phone, "none") { "android-misc.adb.chats.noneYours" } else { "android-misc.adb.chats.none" }), style=adb_quiet) |> ignore
          })
          |> ignore
        }
        for g in live {
          let g = Some(g)
          let station = text(g, "station")
          let request = text(g, "id")
          let session = text(g, "session")
          let title = text(g, "chatTitle")
          let ago = stamp(g, "lastUsedAt", "ago")
          // (on the phone itself: granted, and not signed by a device on the person's own lock: it lends nothing on it)
          let when = if flag(phone, "supported") && field(g, "held") == Some(Json::boolean(false)) {
            tr("android-misc.personal.toConfirm.row")
          } else if ago == "" {
            tr("android-misc.adb.chats.noUsage")
          } else {
            ago
          }
          let busy = is_doing(core, ["adb.revoke"], [("request", request)])
          // (narrow, 收回 by its title alone, the line under it as wide as the row: when it was used, and why it was asked;
          // 2026-11-06 左子健: 不要 title 和 description 都被右边操作给挤压; wide, the library's link_row has it by the
          // row's side)
          @sf.link_row(c, "adb-chat/" + station + "/" + request, if title == "" { @sf.t("android-chat.new.title") } else { title }, note=if text(g, "reason") == "" { when } else { when + " · " + text(g, "reason") }, note_cut=true, goes=station != "" && session != "", control=fn() {
            @sf.button(c, tr("android-misc.adb.chats.revoke"), key="adb-revoke/" + station + "/" + request, tone=Ghost, busy~, disabled=busy, on_press=fn() {
              act(core, tr("android-misc.adb.chats.revoke"), "adb.revoke", obj([("station", str(station)), ("request", str(request))]))
            })
          }, on_press=fn() {
            (core.open_chat)(station, session, "")
          })
        }
      })
    })
    keys.push("foot")
    blocks.push(fn() { gap(c, 30.0) })
    scroll_page(c, "adb/", blocks, keys~, moves=true, continuity=fn(_) { view is Some(_) })
  })
  |> ignore
}

///|
/// The step's card: its lines, its press at its foot.
// kept across runs: a value (no field of it changes)
let adb_step_box : @ui.Style = @ui.css("w=Full gap=S3_5")

///|
/// The stations the phone is lent to (`adbShare`'s `lends`, and the one its top names), each with its lending as
/// adb_lend_view has it, `focus`'s first.
fn adb_lent(view : Json?, focus : String) -> Array[(String, Json?)] {
  let to = adb_lends(view).map(fn(l) { text(Some(l), "station") })
  if flag(view, "sharing") {
    to.push(text(view, "station"))
  }
  let out : Array[(String, Json?)] = []
  let add = fn(l : String) {
    if l != "" && !out.iter().any(fn(o) { o.0 == l }) {
      let lent = adb_lend_view(view, l)
      if flag(lent, "sharing") && text(lent, "station") == l {
        out.push((l, lent))
      }
    }
  }
  if to.contains(focus) {
    add(focus)
  }
  for l in to {
    add(l)
  }
  out
}

///|
/// A lent station's name, as its workspace's station rows say it (its address's last part till they have).
fn adb_station_name(core : Core, address : String) -> String {
  match (core.topic)("stations", { "scope": str(workspace_of(address)) }).get().value {
    Some(Array(a)) =>
      match a.iter().find_first(fn(s) { text(Some(s), "station") == address }) {
        Some(s) if text(Some(s), "name") != "" => text(Some(s), "name")
        _ => station_name(address)
      }
    _ => station_name(address)
  }
}
