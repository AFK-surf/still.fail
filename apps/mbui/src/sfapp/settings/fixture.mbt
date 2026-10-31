// Made-up settings in the core's shapes (WorkspaceView, StationView, LockView, VaultsView, ProfilesView, ConnectsView,
// UsageView, ArchiveView, StationMemory…) for the app with no core (src/sffix): screenshots that are the same on every
// run (scripts/shots.sh settings, web-settings). Every word here is made up. The workspace is the fixture's own ws1
// (星火工作室, lin@example.com), its stations ws1/st1 (Studio) and ws1/st2 (MBA, offline).

///|
/// What the made-up settings changed since they started (a station renamed, a chat restored), and how often.
priv struct SettingsFixture {
  names : Map[String, String]
  restored : Map[String, Bool]
  mut version : Int
  /// the stations' marks set (by id)
  marks : Map[String, String]
  /// the station's updating by itself
  mut auto : Bool
  /// the station's congestion control
  mut congestion : String
  /// the station going on afresh by itself once a session's cache is over, and its cost threshold
  mut afresh : Bool
  mut afresh_above : Double
  /// the station sending its log to still.fail
  mut logs : Bool
  /// a program granted Studio's data and another asking for it (docs/data-outflow.md: its overview's
  /// `outflowGrants`), as a test sets it
  mut outflow : Bool
  /// what an admin answered the program asking (`outflow.answer`'s params)
  mut outflow_answer : Json?
  /// a Windows station's running as administrator, as the core shows it (its overview's `elevation`), as a test sets
  /// it; none: not a Windows station
  mut elevation : Json?
  /// the mode's page has no station (settings-first-station)
  mut none : Bool
  /// the subscription's sign-in: "" none, "needs_code" under way (settings-profile-login), "failed"
  /// (settings-profile-login-failed)
  mut login : String
  /// the sign-in's page can be opened in the station's own browser (settings-profile-login-station,
  /// settings-new-profile-login-station)
  mut login_station : Bool
  /// a new profile's page at an Anthropic plan's sign-in, waiting for the code (settings-new-profile-login…)
  mut new_login : Bool
  /// Claude 主账号's trouble: "" none, "quota" its allowance unreadable (settings-profile-quota-failed), "blocked"
  /// its allowance used up (settings-profile-blocked), "login" to be signed in to again (settings-profile-signin)
  mut trouble : String
  /// the vault not set up on this device (settings-vault-off)
  mut vault_off : Bool
  /// secrets of lin's still in plain text from before security mode (settings-vault-plain), until encrypted
  mut plain_left : Int
  /// the skills shared (true) or no longer (false) since the run started (`skill.share`), by name
  skills_shared : Map[String, Bool]
  /// the quota's resets used on ChatGPT 团队 (`profile.resetQuota`)
  mut resets_used : Int
  /// the models named by hand on ChatGPT 团队 (`profile.addModel`)
  models_added : Array[String]
  /// the profiles given ChatGPT 团队's GPT-6 mini from its page (`profile.addModel` on another one), by id
  models_given : Array[String]
  /// a new device of lin's asking to be let in with this one's code (settings-lock-prompt), until turned away or its
  /// prompt closed
  mut pairing : Bool
  /// how its prompt went: "deny" (turned away), "hide" (closed, the code still good), "" while it is up
  mut pair_ended : String
  /// MBA online too (settings-profiles-pick: Profile's ＋ asks which station)
  mut mba_online : Bool
  /// the subscriptions' allowances a month's window too, three in all (settings-profiles-monthly: OpenCode Go's)
  mut monthly : Bool
  /// how far the made-up workspace has changed on its own (settings-workspace-motion, settings-stations-motion): 1 a
  /// person and a station come, 2 one of each goes (fixture_motion)
  mut motion : Int
  /// the bytes of the drives' files kept (`cache.usage`'s `drive`), until let go (`drive.kept.clear`)
  mut drive_kept : Double
  /// the chats' files kept let go (`cache.file.clear`), by name
  kept_cleared : Array[String]
}

///|
let fx : SettingsFixture = {
  names: {},
  restored: {},
  version: 0,
  marks: {},
  auto: false,
  congestion: "cubic",
  afresh: false,
  afresh_above: 1.0,
  logs: true,
  outflow: false,
  outflow_answer: None,
  elevation: None,
  none: false,
  login: "",
  login_station: false,
  new_login: false,
  trouble: "",
  vault_off: false,
  plain_left: 0,
  skills_shared: {},
  resets_used: 0,
  models_added: [],
  models_given: [],
  pairing: false,
  pair_ended: "",
  mba_online: false,
  monthly: false,
  motion: 0,
  drive_kept: fx_drive_kept,
  kept_cleared: [],
}

///|
/// A chat's file kept (`cache.usage`'s `files`, `loose`): its session, its name, its size, the bytes kept of it, when
/// it was last opened (the fixture's clock stands at 0), unless let go.
fn fx_kept_file(key : String, name : String, size : Double, bytes : Double, opened : Double, station? : String) -> Json? {
  if fx.kept_cleared.contains(name) {
    return None
  }
  let o : Map[String, Json] = {
    "key": str(key),
    "name": str(name),
    "size": Json::number(size),
    "bytes": Json::number(bytes),
    "opened": Json::number(opened),
  }
  match station {
    Some(s) => o["station"] = str(s)
    None => ()
  }
  Some(Json::object(o))
}

///|
/// What the drives' files kept come to as a run starts: 38.5 MB.
let fx_drive_kept : Double = 40370176.0

///|
/// A sheet a fixture's mode puts up over its page once it is drawn (mark, add, add-existing, add-command, env), and a
/// page's list to scroll to a block ("" none).
priv struct FixtureOpen {
  mut sheet : String
  mut list : String
  mut block : Int
  mut frames : Int
  /// a dialog of the desktop's pages to put up (src/sfdesk: fixture_desk), "" none
  mut desk : String
}

///|
let fixture_open : FixtureOpen = { sheet: "", list: "", block: 0, frames: 0, desk: "" }

///|
/// The new connect's step its fixture shows (MBUI_FIXTURE=settings-new-connect: team; -platform, -scan: Feishu's).
let fx_connect_step : Ref[String] = Ref("team")

///|
/// The made-up settings as a run starts (reset): none changed, no sheet or scroll to put up.
fn fixture_reset() -> Unit {
  fx.names.clear()
  fx_many_models.val = false
  fx_many_kept.val = false
  fx.restored.clear()
  fx.skills_shared.clear()
  fx.drive_kept = fx_drive_kept
  fx.kept_cleared.clear()
  fx.resets_used = 0
  fx.models_added.clear()
  fx.models_given.clear()
  fx.version = 0
  fx.marks.clear()
  fx.auto = false
  fx.afresh = false
  fx.afresh_above = 1.0
  fx.logs = true
  fx.outflow = false
  fx.outflow_answer = None
  fx.elevation = None
  fx.congestion = "cubic"
  fx.none = false
  fx_adb.val = ""
  fx.login = ""
  fx.login_station = false
  fx.new_login = false
  fx.trouble = ""
  fx.vault_off = false
  fx.plain_left = 0
  fx.pairing = false
  fx.pair_ended = ""
  fx.mba_online = false
  fx.monthly = false
  fx.motion = 0
  fixture_open.sheet = ""
  fixture_open.list = ""
  fixture_open.block = 0
  fixture_open.frames = 0
  fixture_open.desk = ""
  fx_connect_step.val = "team"
}

///|
/// The made-up workspace's people (settings-workspace-motion: 林 comes, then 周 goes).
fn fx_members(me : Json) -> Json {
  let all = [
    me,
    obj([("sub", str("u2")), ("email", str("ana@example.com")), ("name", str("Ana")), ("role", str("admin"))]),
    obj([("sub", str("u3")), ("email", str("zhou@example.com")), ("name", str("周")), ("role", str("member"))]),
  ]
  if fx.motion >= 1 {
    all.push(obj([("sub", str("u5")), ("email", str("lin2@example.com")), ("name", str("林")), ("role", str("member"))]))
  }
  if fx.motion >= 2 {
    all.remove(2) |> ignore
  }
  Json::array(all)
}

///|
/// `v`'s items as the made-up workspace has changed on its own (fx's `motion`): `add` come at 1, the one `gone` names
/// gone at 2 (settings-*-motion).
fn fx_moved(v : Json, add : Json, gone : (Json) -> Bool) -> Json {
  match v {
    Object(m) =>
      match m.get("items") {
        Some(Array(a)) => {
          let b = a.copy()
          if fx.motion >= 1 {
            b.push(add)
          }
          m["items"] = Json::array(if fx.motion >= 2 { b.filter(fn(x) { !gone(x) }) } else { b })
        }
        _ => ()
      }
    _ => ()
  }
  v
}

///|
/// The made-up workspace changed on its own as far as `step` (fx's `motion`), for the recordings of its pages' lists'
/// motion: told to what follows the made-up core's topics.
pub fn fixture_motion(step : Int) -> Unit {
  fx.motion = step
  fx_changed()
}

///|
/// How often the made-up settings changed: added to the fixture's own version.
pub fn fixture_version() -> Int {
  fx.version
}

///|
/// The made-up settings changed: their version on by one, told to what follows the made-up core's topics.
fn fx_changed() -> Unit {
  fx.version += 1
  fixture_changed()
}

///|
/// The made-up core's changes (the app's fixture's and its settings'), told to what follows its topics as they happen,
/// as the core client tells a subscription's (src/core Sub.changes): fixture_changed with each, fixture_followed as a
/// topic of it is read.
// kept across runs: a count of changes; a run anew reads its topics anew
let fixture_changes : @signals.Signal[Int] = @signals.signal(0)

///|
/// The made-up core changed (the app's fixture, its settings, its browsing): what read its topics in a computed is
/// worked out again.
pub fn fixture_changed() -> Unit {
  fixture_changes.set(@signals.untracked(fn() { fixture_changes.get() }) + 1)
}

///|
/// A topic of the made-up core read: what reads it in a computed follows its changes (fixture_changed).
pub fn fixture_followed() -> Unit {
  fixture_changes.get() |> ignore
}

///|
/// How the new device's prompt went (`lockPrompt.deny` "deny", `lockPrompt.hide` "hide"; "" while it is up).
pub fn fixture_pair_ended() -> String {
  fx.pair_ended
}

///|
/// Studio with a program granted its data and one asking for it (its page's 数据外流), or not.
pub fn fixture_outflow(on : Bool) -> Unit {
  fx.outflow = on
}

///|
/// What an admin answered the program asking for Studio's data, if they did.
pub fn fixture_outflow_answer() -> Json? {
  fx.outflow_answer
}

///|
/// Studio a Windows station, running as administrator as `v` says (the core's `StationElevation`), or not.
pub fn fixture_elevation(v : Json?) -> Unit {
  fx.elevation = v
}

///|
/// The page a fixture's mode opens (MBUI_FIXTURE=settings-<page>[-dark]), by the name route_of takes.
pub fn fixture_page(mode : String) -> String {
  let m = if mode.has_suffix("-dark") {
    mode.unsafe_substring(start=0, end=mode.length() - 5)
  } else {
    mode
  }
  // a sheet up over the page, or the page scrolled down (fixture_open; the library's pages too)
  @sf.page_list_opened.val = fn(c, key, rows) { fixture_scroll(c, key, rows~) }
  let up = fn(sheet : String, list : String, block : Int) {
    fixture_open.sheet = sheet
    fixture_open.list = list
    fixture_open.block = block
    fixture_open.frames = 0
  }
  // 共享调试 as it stands with the phone (fx_adb_share), its host's word on the phone said already
  fx_adb.val = ""
  if m.has_prefix("settings-adb-") {
    fx_adb.val = m.unsafe_substring(start=13, end=m.length())
    adb_host.phone.set(Some(
      obj([
        ("supported", Json::boolean(true)),
        ("developer", Json::boolean(true)),
        ("wireless", Json::boolean(fx_adb.val != "off")),
        ("wifi", Json::boolean(true)),
        ("canSwitch", Json::boolean(false)),
        ("reads", Json::boolean(false)),
      ]),
    ))
  }
  match m {
    "settings-station-mark" => up("mark", "", 0)
    // the page's 设置 (its variables' sheet up over it), its 软件与设备
    "settings-station-env" => station_parts["ws1/st1"] = "settings"
    // its 设置 with 高级网络设置 opened: its congestion control, a section of the page after it
    "settings-station-network" => {
      station_parts["ws1/st1"] = "settings"
      station_network_open["ws1/st1"] = true
      up("", "settings/station/ws1/st1", -1)
    }
    // its 进程: what still.fail uses of the machine
    "settings-station-processes" => station_parts["ws1/st1"] = "processes"
    "settings-station-lower" => {
      station_parts["ws1/st1"] = "settings"
      up("", "settings/station/ws1/st1", 0)
    }
    "settings-station-versions" => {
      station_parts["ws1/st1"] = "machine"
      up("", "settings/station/ws1/st1", 0)
    }
    "settings-stations-add" => up("add", "", 0)
    // Profile's ＋ with more than one station online: which to add it on (pressed by the film's step)
    "settings-profiles-pick" => fx.mba_online = true
    "settings-profiles-monthly" => fx.monthly = true
    "settings-stations-existing" => up("add-existing", "", 0)
    "settings-stations-command" => up("add-command", "", 0)
    "settings-first-station" => fx.none = true
    "settings-profile-lower" => up("", "settings/profile/ws1/st1/cc", 2)
    // ChatGPT 团队's page at its models: GPT-6 mini to be given to 备用 key too
    "settings-profile-spread" => up("", "settings/profile/ws1/st1/cx", 3)
    "settings-profile-spread-dialog" => fixture_open.desk = "profile-spread"
    // ChatGPT 团队's models on their page (many, a filter, one to name by hand)
    "settings-profile-models" => up("", "settings/profile-models/ws1/st1/cx", 0)
    "settings-profile-login" => {
      fx.login = "needs_code"
      up("", "settings/profile/ws1/st1/cc", 0)
    }
    "settings-profile-login-station" => {
      fx.login = "needs_code"
      fx.login_station = true
      up("", "settings/profile/ws1/st1/cc", 0)
    }
    "settings-new-profile-login" => fx.new_login = true
    "settings-new-profile-login-station" => {
      fx.new_login = true
      fx.login_station = true
    }
    "settings-profile-login-failed" => {
      fx.login = "failed"
      up("", "settings/profile/ws1/st1/cc", 0)
    }
    "settings-profile-quota-failed" => fx.trouble = "quota"
    "settings-profile-blocked" => fx.trouble = "blocked"
    "settings-profile-signin" => fx.trouble = "login"
    // a connect's page; its way of making sessions asked (src/sfpages connect.mbt's dialog)
    "settings-connect-menu" => ()
    "settings-connect-mode" => fixture_open.desk = "connect-mode"
    "settings-vault-off" => fx.vault_off = true
    "settings-vault-plain" => fx.plain_left = 2
    "settings-lock-prompt" => fx.pairing = true
    "settings-vault-words" => recovery_words["ws1"] = fx_words()
    "settings-vault-add" => fixture_open.desk = "vault-add"
    "settings-vault-editor" => fixture_open.desk = "vault-editor"
    "settings-vault-recover" => fixture_open.desk = "vault-recover"
    "settings-add-people" => up("add-people", "", 0)
    "settings-workspace-mark" => up("workspace-mark", "", 0)
    // 外观's 本机字体 open (src/sfpages font_setting.mbt local_tile: the families the host lists)
    "settings-local-fonts" => fixture_open.desk = "local-fonts"
    // the archive policy with a dialog up (src/sfpages automatic_decisions.mbt): its words, an option of the
    // station's; its 安全 with one (security.mbt): a device's code to confirm, MBA to take in, turning it off
    "settings-policy-text" => fixture_open.desk = "policy-text"
    "settings-policy-option" => fixture_open.desk = "policy-option"
    "settings-security-confirm" => fixture_open.desk = "lock-confirm"
    "settings-security-join" => fixture_open.desk = "lock-join"
    "settings-security-off" => fixture_open.desk = "lock-off"
    // the run's models listed (model_list.mbt): more than 8, by series, one of another station's to borrow
    "settings-run-models" => {
      fx_many_models.val = true
      run_list["session:s-c1"] = "model"
    }
    // 本机缓存 with many chats kept (a card of 200 rows)
    "settings-kept-many" => fx_many_kept.val = true
    // the run's accounts listed (run_more.mbt account_list)
    "settings-run-accounts" => run_list["session:s-c1"] = "account"
    // the fonts page at code's faces
    "settings-fonts-code" => fonts_at.set(2)
    "settings-new-connect-platform" => fx_connect_step.val = "platform"
    "settings-new-connect-scan" => fx_connect_step.val = "feishuScan"
    // a new Slack app's step: its name, its look
    "settings-new-connect-app" => fx_connect_step.val = "app"
    _ => fx_connect_step.val = "team"
  }
  // a new connect's dialog over 连接 (src/sfpages new_connect.mbt), at the step said above
  if m.has_prefix("settings-new-connect") {
    fixture_open.desk = "new-connect"
  }
  match m {
    "settings" => "home"
    "settings-station-mark" | "settings-station-env" | "settings-station-processes" | "settings-station-lower" | "settings-station-versions" | "settings-station-network" =>
      "station:ws1/st1"
    "settings-stations-add" | "settings-stations-existing" | "settings-stations-command" | "settings-first-station" =>
      "stations"
    "settings-adb" | "settings-adb-off" | "settings-adb-unpaired" | "settings-adb-pairing" | "settings-adb-connected" | "settings-adb-failed" =>
      "adb:ws1/st1"
    "settings-adb-chats" | "settings-adb-idle" => "adb:"
    // the second station a phone is lent to, its first paired already
    "settings-adb-second" => "adb:ws1/st2"
    "settings-profile-menu" | "settings-profile-lower" | "settings-profile-login" | "settings-profile-login-station" =>
      "profile:ws1/st1#cc"
    "settings-new-profile" | "settings-new-profile-hermes" | "settings-new-profile-login" | "settings-new-profile-login-station" => "new-profile:ws1/st1"
    "settings-connect-menu" | "settings-connect-mode" => "connect:ws1/st1#k1"
    "settings-connect-run" | "settings-slack-app" => "connect:ws1/st1#k1"
    "settings-new-connect" | "settings-new-connect-platform" | "settings-new-connect-scan" | "settings-new-connect-app" =>
      "connects"
    "settings-vault-off" | "settings-vault-words" | "settings-vault-recover" | "settings-vault-plain" => "vault"
    "settings-vault-items" | "settings-vault-add" | "settings-vault-editor" => "vault-items"
    "settings-vault-item" => "vault-item:v1#it1"
    "settings-decisions" => "decisions-settings"
    "settings-completion" => "completion"
    "settings-policy" | "settings-policy-text" | "settings-policy-option" => "policy:ws1/st1"
    "settings-bars" => "bars"
    "settings-kept" | "settings-kept-many" | "settings-kept-fill" => "kept"
    "settings-changelog" => "changelog"
    "settings-about-flow" => "about"
    "settings-fonts-coming" | "settings-fonts-code" => "fonts"
    "settings-prices" => "prices:7"
    "settings-run" | "settings-run-models" | "settings-run-accounts" => "run:ws1/st1#s-c1"
    "settings-add-people" | "settings-workspace-mark" | "settings-workspace-motion" => "workspace"
    "settings-stations-motion" => "stations"
    "settings-connects-motion" => "connects"
    "settings-vault-motion" => "vault-items"
    "settings-local-fonts" => "fonts"
    "settings-security-confirm" | "settings-security-join" | "settings-security-off" => "security"
    "settings-notify-off" | "settings-lock-prompt" => "home"
    // (the notifications' page; the system having refused them: its banner's way to allow them)
    "settings-notify" | "settings-notify-denied" => "notifications"
    "settings-station" => "station:ws1/st1"
    "settings-station-offline" => "station:ws1/st2"
    "settings-memory" => "memory:ws1/st1"
    "settings-memory-doc" => "memory-doc:ws1/st1#发布流程"
    "settings-profile" | "settings-profile-quota-failed" | "settings-profile-blocked" | "settings-profile-signin" =>
      "profile:ws1/st1#cc"
    "settings-profile-key" => "profile:ws1/st1#k2"
    "settings-profile-quota" | "settings-profile-spread" | "settings-profile-spread-dialog" => "profile:ws1/st1#cx"
    "settings-profile-models" => "profile-models:ws1/st1#cx"
    "settings-me-reading" => "me"
    "settings-profiles-pick" | "settings-profiles-monthly" => "profiles"
    "settings-connect" => "connect:ws1/st1#k1"
    _ =>
      if m.has_prefix("settings-") {
        m.unsafe_substring(start=9, end=m.length())
      } else {
        ""
      }
  }
}

///|
fn stamp_of(ago : String, until? : String = "") -> Json {
  obj([
    ("at", Json::number(0.0)),
    ("ago", str(ago)),
    ("full", str("")),
    ("until", str(until)),
    ("past", Json::boolean(true)),
  ])
}

///|
fn meter(short : String, left : Int, level : String, remaining : String, big : String, unit : String, title : String, total : String) -> Json {
  obj([
    ("label", str(short)),
    ("short", str(short)),
    ("percent", Json::number((100 - left).to_double())),
    ("left", Json::number(left.to_double())),
    ("level", str(level)),
    ("value", str("")),
    ("remaining", str(remaining)),
    ("big", str(big)),
    ("unit", str(unit)),
    ("title", str(title)),
    ("total", str(total)),
  ])
}

///|
fn fx_profile(id : String, name : String, kind : String, tone : String, check : String, group : String, title : String, more : Array[(String, Json)]) -> Json {
  let p : Map[String, Json] = {
    "id": str(id),
    "name": str(name),
    "runtime": str(if group == "chatgpt" { "codex" } else { "claude" }),
    "runtimes": [str(if group == "chatgpt" { "codex" } else { "claude" })],
    "access": obj([("kind", str(kind)), ("key", str(if kind == "subscription" { "" } else { "sk-…a41f" }))]),
    "home": "",
    "homeExists": true,
    "models": ["claude-opus-5-5", "claude-sonnet-5"],
    "env": [],
    "usedBy": ["k1"],
    "loginCommand": "",
    "checkText": str(check),
    "checkTone": str(tone),
    // (the core's words of it: present.ts profile)
    "signInProvider": str(if group == "chatgpt" { "ChatGPT" } else { "Claude" }),
    "group": str(group),
    "groupTitle": str(title),
    "makers": obj([]),
    "names": obj([("claude-opus-5-5", str("Opus 5.5")), ("claude-sonnet-5", str("Sonnet 5")), ("claude-haiku-5", str("Haiku 5"))]),
    "series": [
      obj([("name", str("Opus")), ("models", ["claude-opus-5-5"])]),
      obj([("name", str("Sonnet")), ("models", ["claude-sonnet-5"])]),
      obj([("name", str("Haiku")), ("models", ["claude-haiku-5"])]),
    ],
    "modelsText": "2 个模型",
    "available": ["claude-opus-5-5", "claude-sonnet-5", "claude-haiku-5"],
    "usesText": "Claude Code",
    "check": obj([("state", str("ok")), ("detail", str("可用，订阅有效")), ("checkedAt", Json::number(0.0)), ("time", obj([("checkedAt", stamp_of("5 分钟前"))]))]),
    "quota": obj([
      ("state", str("ok")),
      (
        "windows",
        Json::array(
        [
          obj([("label", str("5 小时")), ("usedPercent", Json::number(38.0)), ("mark", str("5H")), ("left", Json::number(62.0)), ("level", str("ok")), ("refills", str("2 小时后恢复"))]),
          obj([("label", str("本周")), ("usedPercent", Json::number(81.0)), ("mark", str("W")), ("left", Json::number(19.0)), ("level", str("amber")), ("refills", str("星期一恢复"))]),
        ].iter().concat(
          (if fx.monthly {
            [obj([("label", str("每月")), ("usedPercent", Json::number(3.0)), ("mark", str("M")), ("left", Json::number(97.0)), ("level", str("ok")), ("refills", str("11 月 1 日恢复"))])]
          } else {
            []
          }).iter(),
        ).collect()),
      ),
      ("checkedAt", Json::number(0.0)),
      ("time", obj([("checkedAt", stamp_of("3 分钟前"))])),
    ]),
  }
  for kv in more {
    p[kv.0] = kv.1
  }
  // (the core's words of it: present.ts profile, as it is after `more`)
  let pv = Some(Json::object(p))
  if !p.contains("kindText") {
    p["kindText"] = str(
      if flag(pv, "machine") {
        "终端里的登录"
      } else if text(pv, "providerName") != "" {
        text(pv, "providerName")
      } else {
        match kind {
          "subscription" => "订阅账号"
          "anthropic-api" => "Anthropic API"
          "opencode-go" => "OpenCode Go"
          "api-provider" => "API 服务商"
          "env" => "自定义环境变量"
          _ => ""
        }
      },
    )
  }
  p["checkLine"] = str(
    match field(pv, "check") {
      Some(Object(_)) => text(field(pv, "check"), "detail").replace(old="可用，", new="")
      _ => "尚未检查"
    },
  )
  Json::object(p)
}

///|
/// The made-up station's profiles (Studio's), for the chats' fixture's overview of it too: one made-up world.
pub fn fixture_profiles() -> Array[Json] {
  fx_profiles()
}

///|
fn fx_profiles() -> Array[Json] {
  [
    fx_profile("cc", "Claude 主账号", "subscription", fx_cc_tone(), "可用", "claude", "Claude 订阅", fx_cc_with([
      ("share", obj([("id", str("sh1")), ("role", str("host")), ("host", str("st1")), ("users", ["st2"])])),
      ("fast", Json::boolean(false)),
      ("backgroundOnMessage", Json::boolean(true)),
      ("workspaces", ["ws2"]),
      ("loginCommand", str("claude setup-token")),
      (
        "login",
        match fx.login {
          "" => Json::null()
          "failed" =>
            obj([
              ("profile", str("cc")),
              ("runtime", str("claude")),
              ("state", str("failed")),
              ("error", str("授权码已过期")),
              ("startedAt", Json::number(0.0)),
              ("expiresAt", Json::number(0.0)),
            ])
          state => fx_login_job("cc", state)
        },
      ),
    ])),
    fx_profile("cx", "ChatGPT 团队", "subscription", "green", "可用", "chatgpt", "ChatGPT 订阅", fx_cx_more()),
    fx_profile("k2", "备用 key", "anthropic-api", "red", "没能使用", "key", "API key", [
      // (as the core says it: present.ts issue, trouble.key_next, trouble.key_label)
      ("trouble", obj([("title", str("key 已失效")), ("detail", str("服务商拒绝了这个 key")), ("next", str("核对服务商的 key 是否有效、余额和权限是否足够；可以更换 key，保存后会自动检查")), ("action", str("key")), ("label", str("更换 key"))])),
      ("quota", obj([("state", str("unsupported")), ("windows", []), ("checkedAt", Json::number(0.0))])),
      ("usedBy", []),
    ]),
  ]
}

///|
/// Claude 主账号's dot as its trouble has it (fx.trouble).
fn fx_cc_tone() -> String {
  match fx.trouble {
    "login" | "blocked" => "red"
    _ => "green"
  }
}

///|
/// Claude 主账号's own (`more`) and its trouble (fx.trouble) as the core says it (present.ts profileTrouble), with what
/// its check and its allowance say then.
fn fx_cc_with(more : Array[(String, Json)]) -> Array[(String, Json)] {
  let issue = fn(title : String, detail : String, next : String, action : String, label : String) {
    ("trouble", obj([("title", str(title)), ("detail", str(detail)), ("next", str(next)), ("action", str(action)), ("label", str(label))]))
  }
  more..append(match fx.trouble {
    "quota" =>
      [
        issue("额度查询失败", "请求超时，已中止", "查不到额度不代表账号不能用。先重新查询；还是失败，再按返回的原因检查登录或网络。", "quota", "重新查询额度"),
        ("quota", obj([("state", str("unavailable")), ("detail", str("请求超时，已中止")), ("windows", []), ("checkedAt", Json::number(0.0))])),
      ]
    "blocked" =>
      [
        issue("额度已用完", "本周额度已用完", "等额度恢复，或换一个账号。", "quota", "重新查询额度"),
        ("quota", obj([("state", str("blocked")), ("detail", str("本周额度已用完")), ("windows", []), ("checkedAt", Json::number(0.0))])),
      ]
    "login" =>
      [
        issue("需要重新登录", "登录已过期", "", "login", "登录"),
        ("check", obj([("state", str("login")), ("detail", str("登录已过期")), ("checkedAt", Json::number(0.0)), ("time", obj([("checkedAt", stamp_of("5 分钟前"))]))])),
        ("checkText", str("需要登录")),
      ]
    _ => []
  })
}

///|
/// A profile's models the others could have too (views/profiles.ts spread): ChatGPT 团队's GPT-6 mini, which 备用 key
/// and MBA's 团队 key list, each until given it.
fn fx_spread(id : String) -> Json {
  let targets = [("ws1/st1", "Studio", "k2", "备用 key"), ("ws1/st2", "MBA", "team", "团队 key")].filter(fn(x) {
    !fx.models_given.contains(x.2)
  })
  if id != "cx" || targets.is_empty() {
    return Json::array([])
  }
  [
    obj([
      ("model", str("gpt-6-mini")),
      ("name", str("GPT-6-MINI")),
      (
        "targets",
        Json::array(
          targets.map(fn(x) {
            obj([("station", str(x.0)), ("stationName", str(x.1)), ("profileId", str(x.2)), ("profileName", str(x.3)), ("title", str(x.3)), ("model", str("gpt-6-mini"))])
          }),
        ),
      ),
      ("targetsText", str(targets.map(fn(x) { x.3 }).join("、"))),
    ]),
  ]
}

///|
/// ChatGPT 团队's own: more models than a filter is over (one named by hand once added), a reset of its quota left.
fn fx_cx_more() -> Array[(String, Json)] {
  let ids = [
    "gpt-6", "gpt-6-mini", "gpt-6-nano", "gpt-6-codex", "gpt-6-codex-mini", "gpt-5.5", "gpt-5.5-mini", "gpt-5.5-codex", "gpt-5",
    "gpt-5-mini", "o9", "o9-mini",
  ]..append(fx.models_added)
  let names : Map[String, Json] = {}
  for m in ids {
    names[m] = str(m.to_upper())
  }
  let left = 2 - fx.resets_used
  [
    ("modelsText", str("1 个模型")),
    ("models", ["gpt-6-mini"]),
    ("available", Json::array(ids.map(str))),
    ("names", Json::object(names)),
    ("series", fx_cx_series(ids)),
    ("canAddModel", Json::boolean(true)),
    (
      "quota",
      obj([
        ("state", str("ok")),
        (
          "windows",
          [
            obj([("label", str("5 小时")), ("usedPercent", Json::number(38.0)), ("mark", str("5H")), ("left", Json::number(62.0)), ("level", str("ok")), ("refills", str("2 小时后恢复"))]),
            obj([("label", str("本周")), ("usedPercent", Json::number(81.0)), ("mark", str("W")), ("left", Json::number(19.0)), ("level", str("amber")), ("refills", str("星期一恢复"))]),
          ],
        ),
        ("resetCount", Json::number(left.to_double())),
        ("resetText", str("还可重置 \{left} 次")),
        ("checkedAt", Json::number(0.0)),
        ("time", obj([("checkedAt", stamp_of("3 分钟前"))])),
      ]),
    ),
  ]
}

///|
/// Its models by series, as the core gives them (newest first, one named by hand under 其他).
fn fx_cx_series(ids : Array[String]) -> Json {
  let series = [
    ("GPT-6", ["gpt-6", "gpt-6-mini", "gpt-6-nano", "gpt-6-codex", "gpt-6-codex-mini"]),
    ("GPT-5.5", ["gpt-5.5", "gpt-5.5-mini", "gpt-5.5-codex"]),
    ("GPT-5", ["gpt-5", "gpt-5-mini"]),
    ("o9", ["o9", "o9-mini"]),
  ]
  let rest = ids.filter(fn(m) { !series.iter().any(fn(s) { s.1.contains(m) }) })
  let all = series.map(fn(s) { obj([("name", str(s.0)), ("models", Json::array(s.1.map(str)))]) })
  if rest.length() > 0 {
    all.push(obj([("name", str("其他")), ("models", Json::array(rest.map(str)))]))
  }
  Json::array(all)
}

///|
fn fx_connect(id : String, name : String, presence : String, status : String, mode : String) -> Json {
  obj([
    ("id", str(id)),
    ("name", str(name)),
    ("team", str("星火")),
    ("enabled", Json::boolean(true)),
    ("kind", str("slack")),
    ("mode", str(mode)),
    ("requireMention", Json::boolean(true)),
    ("bind", obj([("runtime", str("claude")), ("model", str("claude-opus-5-5")), ("effort", str("high"))])),
    ("slack", obj([("appToken", str("")), ("botToken", str(""))])),
    ("connection", obj([("state", str(if presence == "error" { "error" } else { "connected" })), ("error", str("Slack 拒绝了 token"))])),
    ("createdBy", obj([("id", str("lin@example.com")), ("name", str("林")), ("shown", obj([("name", str("林")), ("display", str("你")), ("mine", Json::boolean(true))]))])),
    ("sessions", Json::number(4.0)),
    ("statusText", str(status)),
    ("presence", str(presence)),
    ("modeText", str(if mode == "multi-session" { "每个 thread 一个会话" } else { "所有 thread 共用一个会话" })),
    ("modeShort", str("")),
    ("runtimeText", str("Claude Code")),
    ("runText", str("")),
    ("modelName", str("Opus 5.5")),
    // (the core's words of it: present.ts connect)
    ("placeText", str("星火")),
    ("modeLabel", str(if mode == "multi-session" { "每个 thread 一个会话" } else { "所有 thread 共用一个会话" })),
    (
      "modeSentence",
      str(
        if mode == "multi-session" {
          "在 thread 中 @ 它即开启一个新会话，该 thread 的后续消息都进入此会话"
        } else {
          "它看到的所有 thread 都进入同一个会话，适合长期值守的助手仅在被 @ 时唤醒。"
        },
      ),
    ),
    ("modeWords", fx_mode_words(false)),
  ])
}

///|
/// How a connect's ways are said, as the core says them (present.ts modeWords): a Feishu one's in its groups' words.
fn fx_mode_words(feishu : Bool) -> Json {
  if feishu {
    obj([
      ("multi", obj([("label", str("每个群一个会话")), ("description", str("在群里 @ 它开始，之后群里的消息都交给这个会话；@ 它说「新会话」另开一个，话题群的每个话题各一个会话"))])),
      ("single", obj([("label", str("所有群共用一个会话")), ("description", str("它所在的群和私聊都进入同一个会话，适合长期值守的助手"))])),
      ("mentionOn", str("被 @ 后，同一个群里的后续消息无需再 @。")),
      ("mentionOff", str("它所在的群里的每条消息都会进入会话。")),
    ])
  } else {
    obj([
      ("multi", obj([("label", str("每个 thread 一个会话")), ("description", str("在 thread 中 @ 它即开启一个新会话，该 thread 的后续消息都进入此会话"))])),
      ("single", obj([("label", str("所有 thread 共用一个会话")), ("description", str("它看到的所有 thread 都进入同一个会话，适合长期值守的助手"))])),
      ("mentionOn", str("被 @ 的 thread 中，后续回复无需再 @。")),
      ("mentionOff", str("频道中它可见的每条消息都会进入会话。")),
    ])
  }
}

///|
/// A Slack app's permissions as the core says them (present.ts slackSections).
fn fx_sections() -> Json {
  [
    obj([
      ("title", str("消息")),
      (
        "groups",
        [
          fx_group("base", "读取和回复消息", "", fixed=true),
          fx_group("public", "在未加入的公开频道发言", ""),
          fx_group("dm", "主动发私信", ""),
          fx_group("customize", "使用自定义名称和头像发消息", ""),
          fx_group("reactions", "表情回应、置顶和书签", ""),
        ],
      ),
    ]),
    obj([
      ("title", str("频道和群")),
      (
        "groups",
        [
          fx_group("channels", "创建和管理频道", ""),
          fx_group("topics", "修改频道话题和邀请成员", ""),
          fx_group("connect", "Slack Connect 跨组织频道", "接受邀请需要由能批准 Slack Connect 的人（默认为管理员）安装 app；发送邀请也受工作区设置限制，且仅限付费版"),
        ],
      ),
    ]),
    obj([
      ("title", str("文件和文档")),
      (
        "groups",
        [
          fx_group("files", "读写文件", ""),
          fx_group("canvases", "读写 canvas", ""),
          fx_group("lists", "读写列表", ""),
        ],
      ),
    ]),
    obj([
      ("title", str("成员和搜索")),
      (
        "groups",
        [
          fx_group("people", "查看成员资料", ""),
          fx_group("usergroups", "管理用户组和发起通话", "创建用户组、修改成员需要工作区设置允许，很多工作区仅限管理员；用户组仅限付费版"),
          fx_group("search", "搜索消息、文件和成员", ""),
        ],
      ),
    ]),
    obj([
      ("title", str("其他")),
      (
        "groups",
        [
          fx_group("extras", "链接预览、提醒和状态", ""),
          fx_group("more", "状态、元数据和斜杠命令", ""),
        ],
      ),
    ]),
  ]
}

///|
/// A group of a Slack app's permissions, as the core says it (`admin`: what only Slack's admins allow, "" none).
fn fx_group(id : String, label : String, admin : String, fixed? : Bool = false) -> Json {
  obj([
    ("id", str(id)),
    ("label", str(label)),
    ("description", str(label)),
    ("admin", if admin == "" { Json::null() } else { str(admin) }),
    ("tip", str(if admin == "" { label } else { label + " " + admin })),
    ("fixed", Json::boolean(fixed)),
  ])
}

///|
/// The ways a multi-session connect could be switched to, as the core says them (present.ts modeChanges).
fn fx_mode_changes() -> Json {
  let change = fn(mode : String, mention : Bool, changed : Bool, effects : Array[String], action : String) {
    obj([
      ("mode", str(mode)),
      ("requireMention", Json::boolean(mention)),
      ("changed", Json::boolean(changed)),
      ("effects", Json::array(effects.map(str))),
      ("action", str(action)),
    ])
  }
  let single = "此后它收到的消息都将进入同一个会话；现有各 thread 的会话不再接收新消息，包括这些 thread 中的回复。记录会保留。"
  let fresh = "下一条消息将开始新的单会话；也可在切换后选择已有会话。"
  Json::array([
    change("multi-session", true, false, [], "确认更改"),
    change("single-session", true, true, [single, fresh], "改为单会话"),
    change("single-session", false, true, [single, fresh, "无需 @：它可见的所有频道和私信中的每条消息都会发送给 agent，用量会明显增加。"], "改为单会话"),
  ])
}

///|
fn fx_station(address : String) -> Json {
  let id = station_name(address)
  let renamed = fx.names.get(id)
  if address == "ws1/st1" {
    obj([
      ("station", str(address)),
      ("id", str(id)),
      ("name", str(renamed.unwrap_or("Studio"))),
      ("icon", str(fx.marks.get(id).unwrap_or("glyph:desktop"))),
      ("summary", str("Apple M2 Max · 2 个 agent 在工作")),
      ("face", str("working")),
      ("line", str("Apple M2 Max · 64 GB · macOS 26")),
      ("online", Json::boolean(true)),
      ("link", obj([("state", str("online"))])),
      ("runtimes", []),
      // what its profiles have turned on (Claude 主账号's: Opus 5.5 and Sonnet 5, on claude)
      (
        "models",
        [
          obj([("model", str("claude-opus-5-5")), ("name", str("Opus 5.5")), ("family", str("Opus")), ("maker", obj([("id", str("anthropic"))])), ("runtimes", ["claude"])]),
          obj([("model", str("claude-sonnet-5")), ("name", str("Sonnet 5")), ("family", str("Sonnet")), ("maker", obj([("id", str("anthropic"))])), ("runtimes", ["claude"])]),
        ],
      ),
      (
        "host",
        obj([
          ("identity", str("Apple M2 Max · 64 GB · macOS 26")),
          (
            "meters",
            [
              meter("CPU", 72, "ok", "空闲 72%", "72", "%", "CPU 空闲", "负载 1.4"),
              meter("内存", 18, "amber", "剩 11.5 G", "11.5", "GB", "内存剩", "共 64 GB"),
              meter("磁盘", 41, "ok", "剩 380 G", "380", "GB", "磁盘剩", "共 926 GB"),
            ],
          ),
          (
            "details",
            [
              obj([("label", str("主机名")), ("value", str("studio"))]),
              obj([("label", str("芯片")), ("value", str("Apple M2 Max，12 核"))]),
              obj([("label", str("已运行")), ("value", str("6 天 4 小时"))]),
              obj([("label", str("进程")), ("value", str("station 412 MB"))]),
            ],
          ),
        ]),
      ),
      (
        "net",
        obj([
          ("path", str("直连")),
          ("via", str("direct")),
          ("rtt", obj([("text", str("38 ms")), ("level", str("ok"))])),
          ("rttHistory", []),
          ("down", str("1.4 MB/s")),
          ("up", str("96 KB/s")),
          ("total", str("")),
          ("downTotal", str("212 MB")),
          ("upTotal", str("9.6 MB")),
        ]),
      ),
      (
        "overview",
        obj([
          ("connects", [fx_connect("k1", "星火助手", "online", "在线", "multi-session")]),
          ("profiles", Json::array(fx_profiles())),
          // a new profile's sign-in under way (settings-new-profile-login…)
          ("logins", if fx.new_login { [obj([("id", str("login-new")), ("runtime", str("claude")), ("job", fx_login_job("login-new", "needs_code"))])] } else { [] }),
          ("processesText", str("2 个 agent 进程 · claude 1.2 GB")),
          ("slackApps", []),
          ("drive", obj([("roots", [{ "path": "~/项目", "name": "项目", "state": "ok" }, { "path": "~/文档", "name": "文档", "state": "ok" }]), ("all", Json::boolean(false))])),
          (
            "updates",
            [
              obj([
                ("id", str("station")),
                ("name", str("Station")),
                ("installed", Json::boolean(true)),
                ("version", str("0.1.1288")),
                ("latest", str("0.1.1300")),
                ("newer", Json::boolean(true)),
                ("channel", str("stable")),
                ("auto", Json::boolean(fx.auto)),
                ("updatable", Json::boolean(true)),
                ("state", str("idle")),
                ("checkedAt", Json::number(1.0)),
                // (the core's words of it: present.ts software)
                ("shownText", str("0.1.1288")),
                ("tipText", str("")),
              ]),
              obj([
                ("id", str("claude")),
                ("name", str("Claude Code")),
                ("installed", Json::boolean(true)),
                ("version", str("2.1.4")),
                ("latest", str("2.1.4")),
                ("newer", Json::boolean(false)),
                ("updatable", Json::boolean(true)),
                ("state", str("idle")),
                ("checkedAt", Json::number(1.0)),
                ("shownText", str("2.1.4")),
                ("tipText", str("已是最新")),
              ]),
              obj([
                ("id", str("codex")),
                ("name", str("Codex")),
                ("installed", Json::boolean(false)),
                ("newer", Json::boolean(false)),
                ("updatable", Json::boolean(true)),
                ("state", str("idle")),
                ("checkedAt", Json::number(1.0)),
                ("shownText", str("未安装")),
                ("tipText", str("")),
              ]),
            ],
          ),
          (
            "permissions",
            obj([
              (
                "grants",
                [
                  obj([("id", str("capture")), ("name", str("屏幕录制")), ("line", str("查看这台 Mac 的屏幕")), ("granted", Json::boolean(true)), ("asking", Json::boolean(false))]),
                  obj([("id", str("control")), ("name", str("辅助功能")), ("line", str("操作这台 Mac 的鼠标和键盘")), ("granted", Json::boolean(false)), ("asking", Json::boolean(false))]),
                  obj([("id", str("documents")), ("name", str("文稿")), ("line", str("读写「文稿」中的文件")), ("granted", Json::boolean(false)), ("asking", Json::boolean(true))]),
                ],
              ),
              ("note", str("未允许辅助功能：agent 只能查看屏幕，不能操作")),
              ("canRequest", Json::boolean(true)),
            ]),
          ),
          (
            "agentEnv",
            [
              obj([("key", str("HTTPS_PROXY")), ("secret", Json::boolean(false)), ("value", str("http://127.0.0.1:7890"))]),
              obj([("key", str("NO_PROXY")), ("secret", Json::boolean(false)), ("value", str("localhost,.internal"))]),
            ],
          ),
          ("search", obj([("files", str("spotlight")), ("personal", Json::boolean(false))])),
          ("context", obj([("afreshWhenCold", Json::boolean(fx.afresh)), ("afreshAbove", Json::number(fx.afresh_above))])),
          ("diagnostics", obj([("logs", Json::boolean(fx.logs))])),
          ("network", obj([("congestion", str(fx.congestion))])),
          ("outflowGrants", Json::number(if fx.outflow { 2.0 } else { 0.0 })),
          ("outflowAnswers", Json::boolean(true)),
          ("elevation", fx.elevation.unwrap_or(Json::null())),
          ("sharing", Json::boolean(true)),
          (
            "machineLogins",
            [
              obj([("runtime", str("codex")), ("installed", Json::boolean(true)), ("loggedIn", Json::boolean(true)), ("email", str("lin@example.com")), ("plan", str("plus")), ("planText", str("Plus")), ("usable", Json::boolean(true)), ("text", str("")), ("offered", Json::boolean(true))]),
            ],
          ),
          (
            "archiving",
            // (the core's words and choices, as it gives them: archiving.ts in the core)
            obj([
              ("days", Json::number(1.0)),
              ("slackDays", Json::number(3.0)),
              ("reviewed", Json::boolean(false)),
              ("canEdit", Json::boolean(true)),
              ("mode", str("idle")),
              ("summaryText", str("空闲就归档 · 1 天 · Slack：3 天")),
              ("daysOffered", [Json::number(1.0), Json::number(3.0), Json::number(7.0), Json::number(30.0)]),
              ("slackDaysOffered", [Json::number(0.0), Json::number(3.0), Json::number(7.0), Json::number(30.0)]),
              ("daysOfferedText", [str("1 天"), str("3 天"), str("7 天"), str("30 天")]),
              ("slackDaysOfferedText", [str("不归档"), str("3 天"), str("7 天"), str("30 天")]),
              ("reviewOn", Json::boolean(true)),
              ("reviewText", str("已开启 · GPT-6 mini")),
              ("stalled", Json::boolean(false)),
              ("lineText", str("空闲就归档 · 1 天 · Slack：3 天")),
              (
                "modes",
                [
                  obj([("mode", str("off")), ("label", str("不自动归档")), ("days", Json::number(0.0)), ("reviewed", Json::boolean(false)), ("allowed", Json::boolean(true))]),
                  obj([("mode", str("idle")), ("label", str("空闲就归档")), ("days", Json::number(1.0)), ("reviewed", Json::boolean(false)), ("allowed", Json::boolean(true))]),
                  obj([("mode", str("reviewed")), ("label", str("按模型判断")), ("days", Json::number(1.0)), ("reviewed", Json::boolean(true)), ("allowed", Json::boolean(true))]),
                ],
              ),
              ("modeNote", str("空闲超过下面的天数就归档。只看状态，不读内容：chat 里提到但没做完的事，它看不出来。")),
            ]),
          ),
          (
            "automaticDecisions",
            obj([
              ("canEdit", Json::boolean(true)),
              ("canReview", Json::boolean(true)),
              ("settings", obj([("completion", obj([("enabled", Json::boolean(true))]))])),
              ("models", [obj([("id", str("gpt-6-mini")), ("name", str("GPT-6 mini")), ("profiles", ["cx"])])]),
              ("recent", []),
              (
                "policy",
                obj([
                  ("text", str("做完、没有待办的对话归档；还在等人回复或有后续计划的留下。")),
                  (
                    "options",
                    [
                      obj([("id", str("o1")), ("name", str("已完成")), ("rubric", str("任务做完，没有后续")), ("archive", Json::boolean(true)), ("count", Json::number(12.0)), ("chats", [obj([("session", str("s-c3")), ("title", str("夜里的构建又失败了"))])])]),
                      obj([("id", str("o2")), ("name", str("被放弃")), ("rubric", str("明确不再继续")), ("archive", Json::boolean(true)), ("count", Json::number(3.0)), ("chats", [])]),
                      obj([("id", str("o3")), ("name", str("等回复")), ("rubric", str("在等某人的答复")), ("archive", Json::boolean(false)), ("count", Json::number(5.0)), ("chats", [])]),
                    ],
                  ),
                  ("days", Json::number(7.0)),
                  ("checked", Json::number(20.0)),
                  ("failed", Json::number(0.0)),
                  ("edited", Json::boolean(false)),
                  ("summaryText", str("近 7 天检查了 20 个对话")),
                  ("changeText", str("上次修改 3 天前")),
                ]),
              ),
            ]),
          ),
        ]),
      ),
      ("betaOffered", Json::boolean(true)),
    ])
  } else {
    obj([
      ("station", str(address)),
      ("id", str(id)),
      ("name", str(renamed.unwrap_or("MBA"))),
      ("icon", str(fx.marks.get(id).unwrap_or("glyph:laptop:teal"))),
      ("summary", str(if fx.mba_online { "Apple M3 · 空闲" } else { "离线 · 2 天前" })),
      ("face", str(if fx.mba_online { "idle" } else { "offline" })),
      ("online", Json::boolean(fx.mba_online)),
      ("link", obj([("state", str(if fx.mba_online { "online" } else { "offline" }))])),
      ("runtimes", []),
      ("models", []),
    ])
  }
}

///|
fn fx_archive() -> Json {
  let all = [
    ("a1", "整理上个月的发票", "已经把 23 张发票按月份归好", "14:05", "今天", true),
    ("a2", "试一下新的图标尺寸", "三种尺寸的对比图放在共享文件夹里", "11:30", "今天", true),
    ("a3", "周会纪要", "下周一前补上第三项的负责人", "18:20", "昨天", false),
    ("a4", "清理旧的构建缓存", "删掉了 41 GB 的旧缓存", "09:12", "星期三", true),
  ]
  let days : Array[(String, Array[Json])] = []
  for a in all {
    if fx.restored.contains("s-" + a.0) {
      continue
    }
    let row = obj([
      ("station", str("ws1/st1")),
      ("id", str(a.0)),
      ("session", str("s-" + a.0)),
      ("thread", Json::number(a.0.length().to_double())),
      ("title", str(a.1)),
      ("last", str(a.2)),
      ("at", Json::number(0.0)),
      ("clock", str(a.3)),
      ("how", str("手动归档")),
      ("deletable", Json::boolean(a.5)),
    ])
    match days.iter().find_first(fn(d) { d.0 == a.4 }) {
      Some(d) => d.1.push(row)
      None => days.push((a.4, [row]))
    }
  }
  obj([
    ("days", Json::array(days.map(fn(d) { obj([("label", str(d.0)), ("items", Json::array(d.1))]) }))),
    ("errors", []),
    ("wait", obj([("reading", Json::boolean(false)), ("failing", []), ("empty", Json::boolean(days.length() == 0))])),
    ("total", Json::number(days.length().to_double())),
    ("more", Json::boolean(false)),
  ])
}

///|
fn fx_usage(days : Int) -> Json {
  let daily : Array[Json] = []
  for i in 0..<days {
    let cost = ((i * 37 + 11) % 23).to_double() + 4.0
    let a = cost * 0.6
    let b = cost * 0.3
    let rest = cost - a - b
    daily.push(
      obj([
        ("day", str("2026-10-" + (if i + 1 < 10 { "0" } else { "" }) + (i + 1).to_string())),
        ("label", str("10/" + (i + 1).to_string())),
        ("today", Json::boolean(i == days - 1)),
        ("cost", Json::number(cost)),
        ("costText", str("$" + cost.to_int().to_string())),
        ("calls", Json::number(cost * 12.0)),
        ("callsText", str((cost * 12.0).to_int().to_string() + " 次调用")),
        ("parts", [Json::number(a), Json::number(b), Json::number(rest)]),
        ("partsText", [str("$" + a.to_int().to_string()), str("$" + b.to_int().to_string()), str("$" + rest.to_int().to_string())]),
        // (what the core says of it: views/usage.ts)
        ("name", str(if i == days - 1 { "今天" } else { "10/" + (i + 1).to_string() })),
        ("tick", str(if i == days - 1 { "今天" } else if days <= 10 || (days - 1 - i) % 7 == 0 { "10/" + (i + 1).to_string() } else { "" })),
        ("shares", [Json::number(0.6), Json::number(0.3), Json::number(0.1)]),
      ]),
    )
  }
  let item = fn(key : String, title : String, sub : String, cost : String, share : Double, shareText : String) {
    obj([
      ("key", str(key)),
      ("title", str(title)),
      ("sub", str(sub)),
      ("cost", Json::number(share * 100.0)),
      ("costText", str(cost)),
      ("share", Json::number(share)),
      ("shareText", str(shareText)),
      ("calls", Json::number(0.0)),
      ("callsText", str("")),
      ("tokensText", str("")),
      ("detail", str("1,204 次 · 3.2 万")),
    ])
  }
  obj([
    ("days", Json::number(days.to_double())),
    ("wait", obj([("reading", Json::boolean(false)), ("failing", []), ("empty", Json::boolean(false))])),
    ("empty", Json::boolean(false)),
    (
      "tiles",
      [
        obj([("label", str("折合费用")), ("value", str(if days == 7 { "$118" } else { "$486" })), ("sub", str("按 API 价算"))]),
        obj([("label", str("调用")), ("value", str(if days == 7 { "1,416" } else { "5,830" })), ("sub", str("3 个 station"))]),
        obj([("label", str("token")), ("value", str(if days == 7 { "2,310 万" } else { "9,870 万" })), ("sub", str("输入 · 输出 · 缓存"))]),
        obj([("label", str("对话")), ("value", str("42")), ("sub", str("其中 9 个今天"))]),
      ],
    ),
    ("series", [obj([("key", str("lin@example.com")), ("name", str("林"))]), obj([("key", str("ana@example.com")), ("name", str("Ana"))]), obj([("key", str("")), ("name", str("其他"))])]),
    ("daily", Json::array(daily)),
    ("many", Json::boolean(days > 10)),
    ("max", Json::number(27.0)),
    // (the scale the core works out for it: views/usage.ts scale)
    ("top", Json::number(30.0)),
    ("ticks", [obj([("value", Json::number(10.0)), ("label", str("10"))]), obj([("value", Json::number(20.0)), ("label", str("20"))]), obj([("value", Json::number(30.0)), ("label", str("30"))])]),
    (
      "lists",
      [
        obj([
          ("key", str("chats")),
          ("title", str("按对话")),
          (
            "items",
            [
              item("c1", "整理发布清单", "Studio", "$31", 0.26, "26%"),
              item("c4", "给设置页加一个深色模式开关", "Studio", "$22", 0.19, "19%"),
              item("c3", "夜里的构建又失败了", "MBA", "$15", 0.13, "13%"),
            ],
          ),
        ]),
        obj([("key", str("people")), ("title", str("按人")), ("items", [item("lin", "林", "", "$80", 0.68, "68%")])]),
        obj([("key", str("models")), ("title", str("按模型")), ("items", [item("opus", "Opus 5.5", "", "$96", 0.81, "81%")])]),
      ],
    ),
    ("notes", []),
    ("basis", str("按各服务商公开的 API 价格折算，不是实际账单。")),
    (
      "prices",
      [
        obj([
          ("station", str("Studio")),
          ("note", str("每百万 token 的美元价格，取自服务商公开价格")),
          (
            "rows",
            [
              obj([("model", str("Opus 5.5")), ("rates", [obj([("label", str("输入")), ("value", str("$5"))]), obj([("label", str("输出")), ("value", str("$25"))]), obj([("label", str("缓存读")), ("value", str("$0.5"))])])]),
              obj([("model", str("Sonnet 5")), ("rates", [obj([("label", str("输入")), ("value", str("$3"))]), obj([("label", str("输出")), ("value", str("$15"))]), obj([("label", str("缓存读")), ("value", str("$0.3"))])])]),
            ],
          ),
        ]),
        obj([("station", str("MBA")), ("note", str("station 离线，读不到它的价格表")), ("rows", [])]),
      ],
    ),
  ])
}

///|
fn fx_memory() -> Json {
  obj([
    (
      "global",
      obj([
        ("path", str("~/.claude/CLAUDE.md")),
        ("text", str("")),
        ("size", str("4 KB")),
        (
          "sections",
          [
            obj([("title", str("开头")), ("text", str("这台机器上的 agent 共用的记忆。")), ("note", str("1 KB"))]),
            obj([("title", str("习惯")), ("text", str("- 提交前先跑测试\n- 说明写成完整的句子")), ("note", str("2 条"))]),
          ],
        ),
      ]),
    ),
    (
      "skills",
      [
        obj([
          ("name", str("发布流程")),
          ("description", str("项目记忆：发布新版本时")),
          ("project", Json::boolean(true)),
          ("builtin", Json::boolean(false)),
          ("text", str("")),
          ("body", str("## 步骤\n\n1. 改版本号\n2. 写更新说明\n3. 打包并上传")),
          ("about", str("发布新版本时")),
          ("size", str("3 KB")),
          ("files", [obj([("name", str("checklist.md")), ("text", str("- 签名\n- 截图")), ("label", str("checklist")), ("size", str("1 KB"))])]),
          // (the core's words of it: looks.ts)
          ("group", str("project")), ("kindText", str("项目记忆")), ("whenText", str("发布新版本时")), ("line", str("发布新版本时")), ("pages", [obj([("key", str("")), ("label", str("总览")), ("text", str("## 步骤\n\n1. 改版本号\n2. 写更新说明\n3. 打包并上传"))]), obj([("key", str("checklist.md")), ("label", str("checklist")), ("size", str("1 KB")), ("text", str("- 签名\n- 截图"))])]),
          (
            "share",
            if fx.skills_shared.get("发布流程").unwrap_or(true) {
              obj([("id", str("sh1")), ("role", str("host")), ("host", str("st1")), ("conflicts", ["SKILL.md"]), ("users", ["st2"]), ("missing", [])])
            } else {
              obj([])
            },
          ),
        ]),
        obj([
          ("name", str("周报")),
          ("description", str("写周报时用的格式")),
          ("project", Json::boolean(false)),
          ("builtin", Json::boolean(false)),
          ("text", str("每周五下午写。")),
          ("size", str("1 KB")),
          ("group", str("skill")), ("kindText", str("Skill")), ("whenText", str("写周报时用的格式")), ("line", str("写周报时用的格式")), ("pages", [obj([("key", str("")), ("label", str("总览")), ("text", str("每周五下午写。"))])]),
        ]),
        obj([("name", str("pdf")), ("description", str("读写 PDF")), ("project", Json::boolean(false)), ("builtin", Json::boolean(true)), ("text", str("")), ("group", str("builtin")), ("kindText", str("station 内置")), ("whenText", str("读写 PDF")), ("line", str("读写 PDF")), ("pages", [obj([("key", str("")), ("label", str("总览")), ("text", str("（空）"))])])]),
        obj([("name", str("xlsx")), ("description", str("读写表格")), ("project", Json::boolean(false)), ("builtin", Json::boolean(true)), ("text", str("")), ("group", str("builtin")), ("kindText", str("station 内置")), ("whenText", str("读写表格")), ("line", str("读写表格")), ("pages", [obj([("key", str("")), ("label", str("总览")), ("text", str("（空）"))])])]),
      ],
    ),
  ])
}

///|
/// A made-up settings topic, None for one these do not make.
pub fn fixture_topic(mode : String, name : String, params : Map[String, Json]) -> Json? {
  if name == "lock" && mode.has_prefix("lock-") {
    return Some(waiting_lock(mode))
  }
  let me : Json = obj([("sub", str("u1")), ("email", str("lin@example.com")), ("name", str("林")), ("role", str("owner"))])
  match name {
    // Studio's programs granted its data (sfpages/station_outflow.mbt, docs/data-outflow.md): Comma's; and Comma for
    // Teams asking for the whole workspace's, until answered
    "outflowGrants" if mode.has_prefix("settings") && text(Some(Json::object(params)), "station") == "ws1/st1" =>
      Some(
        obj([
          ("supported", Json::boolean(true)),
          (
            "requests",
            if fx.outflow_answer is Some(_) {
              []
            } else {
              [
                obj([
                  ("id", str("q1")),
                  ("program", str("Comma for Teams")),
                  ("signed", Json::boolean(true)),
                  ("signedText", str("签名：Developer ID Application: AFK Inc. (D9AAN3VJK8)")),
                  ("said", str("Comma — 按团队算 token 的 ROI")),
                  (
                    "scopes",
                    [
                      obj([("id", str("usage")), ("text", str("token 用量和金额")), ("why", str("不含消息。"))]),
                      obj([("id", str("chats")), ("text", str("chat 和它们的状态")), ("why", str("不含消息。"))]),
                    ],
                  ),
                  ("reach", str("workspace")),
                  ("reachText", str("整个 workspace 的所有 station")),
                  ("askedText", str("今天 10:12 申请")),
                ]),
              ]
            },
          ),
          (
            "grants",
            [
              obj([
                ("id", str("g1")),
                ("program", str("Comma")),
                ("signed", Json::boolean(true)),
                ("signedText", str("签名：Developer ID Application: AFK Inc. (D9AAN3VJK8)")),
                ("scopes", [obj([("id", str("usage")), ("text", str("token 用量和金额"))]), obj([("id", str("chats")), ("text", str("chat 和它们的状态"))])]),
                ("grantedText", str("昨天 14:02 授权")),
                ("lastReadText", str("最近读取 今天 09:30")),
              ]),
            ],
          ),
        ]),
      )
    // Studio's logins (station_logins.mbt): codex's under way, gh's done yesterday
    // (the settings' own pages only: a chat's login cards are the chats' fixture's)
    "machineLogins" if mode.has_prefix("settings") && text(Some(Json::object(params)), "station") == "ws1/st1" => {
      let gh_login = obj([
        ("id", str("login-0")),
        ("active", Json::boolean(false)),
        ("name", str("gh")),
        ("command", str("env GH_HOST=github.com /opt/homebrew/bin/gh auth login")),
        ("chat", str("s-c1")),
        ("chatTitle", str("整理发布清单")),
        ("whenText", str("昨天")),
        ("statusText", str("已登录")),
        ("doneByText", str("林 完成")),
        ("state", str("done")),
      ])
      Some(
        obj([
          ("supported", Json::boolean(true)),
          ("canLogin", Json::boolean(true)),
          ("canRelay", Json::boolean(true)),
          (
            "logins",
            [
              obj([("id", str("login-2")), ("active", Json::boolean(true)), ("command", str("codex login"))]),
              gh_login,
            ],
          ),
          (
            "tools",
            [
              obj([
                ("name", str("gh")),
                ("summaryText", str("林 登录 · 昨天")),
                ("failed", Json::boolean(false)),
                ("chat", str("s-c1")),
                ("chatTitle", str("整理发布清单")),
                ("countText", str("1 次")),
                ("tries", [gh_login]),
              ]),
            ],
          ),
        ]),
      )
    }
    "machineLogin" if mode.has_prefix("settings") && text(Some(Json::object(params)), "id") == "login-2" =>
      Some(
        obj([
          ("id", str("login-2")),
          ("title", str("在 Studio 上登录 codex")),
          ("state", str("browser")),
          ("step", str("open")),
          ("url", str("https://auth.openai.com/log-in")),
          ("domain", str("auth.openai.com")),
          ("active", Json::boolean(true)),
          ("statusText", str("等你在浏览器里登录")),
        ]),
      )
    "workspace" =>
      Some(
        obj([
          ("id", str("ws1")),
          ("name", str("星火工作室")),
          ("role", str("owner")),
          (
            "members",
            fx_members(me),
          ),
          ("stations", [obj([("id", str("st1")), ("name", str("Studio"))]), obj([("id", str("st2")), ("name", str("MBA"))])]),
          ("invitations", [obj([("id", str("i1")), ("role", str("member")), ("email", str("qin@example.com")), ("time", obj([("expires_at", stamp_of("", until="6 天后"))]))])]),
          ("added", [obj([("email", str("he@example.com")), ("role", str("member"))])]),
          ("relays", []),
        ]),
      )
    // every way its devices reach its stations (the core's views/ways.ts), the punched path turned off
    "workspaceWays" =>
      Some(
        obj([
          (
            "ways",
            [
              obj([("id", str("https://app.still.fail/")), ("kind", str("relay")), ("name", str("Cloudflare")), ("own", Json::boolean(false)), ("on", Json::boolean(true))]),
              obj([("id", str("https://39.105.157.122/")), ("kind", str("relay")), ("name", str("北京")), ("own", Json::boolean(false)), ("on", Json::boolean(true))]),
              obj([("id", str("lan")), ("kind", str("lan")), ("name", str("")), ("own", Json::boolean(false)), ("on", Json::boolean(true))]),
              obj([("id", str("tailnet")), ("kind", str("tailnet")), ("name", str("")), ("own", Json::boolean(false)), ("on", Json::boolean(true))]),
              obj([("id", str("direct")), ("kind", str("direct")), ("name", str("")), ("own", Json::boolean(false)), ("on", Json::boolean(false))]),
            ],
          ),
          ("off", Json::number(1.0)),
          ("offLabel", str("已关闭 1 项")),
        ]),
      )
    "stations" =>
      if fx.none {
        Some([])
      } else {
        // (settings-stations-motion: 3 comes, then MBA goes)
        let all = [fx_station("ws1/st1"), fx_station("ws1/st2")]
        if fx.motion >= 1 {
          all.push(fx_station("ws1/st3"))
        }
        if fx.motion >= 2 {
          all.remove(1) |> ignore
        }
        Some(Json::array(all))
      }
    // a new device asking with this one's code (lock_prompts.mbt)
    "lockPrompts" =>
      Some(
        obj([
          (
            "pairing",
            if fx.pairing {
              [
                obj([
                  ("device", str("d-new")),
                  ("name", str("林")),
                  ("email", str("lin@example.com")),
                  ("kind", str("android")),
                  ("label", str("Pixel 9")),
                  ("code", str("482915")),
                  ("deviceText", str("Pixel 9")),
                  ("created_at", Json::number(0.0)),
                  ("untilText", str("14:05 前有效")),
                  ("workspaces", [obj([("id", str("ws1")), ("name", str("星火工作室"))]), obj([("id", str("ws2")), ("name", str("个人"))])]),
                ]),
              ]
            } else {
              []
            },
          ),
        ]),
      )
    "screens" =>
      Some(
        obj([
          (
            "screens",
            [
              obj([("id", str("desktop")), ("kind", str("desktop")), ("title", str("Studio 的屏幕")), ("width", Json::number(3024.0)), ("height", Json::number(1964.0)), ("line", str("3024 × 1964 · 无人在看")), ("link", str(""))]),
              obj([("id", str("browser:t1")), ("kind", str("browser")), ("title", str("发布清单 - 文档")), ("width", Json::number(1280.0)), ("height", Json::number(800.0)), ("line", str("浏览器标签页 · 1280 × 800")), ("link", str(""))]),
            ],
          ),
          ("outdated", Json::boolean(false)),
          ("control", Json::boolean(true)),
          ("known", Json::boolean(true)),
        ]),
      )
    // what still.fail uses of Studio's machine (the `resources` view): a chat's agent and the station
    "resources" => Some(fx_resources())
    "adbShare" => Some(fx_adb_share())
    "joinable" =>
      Some(
        obj([
          ("offered", Json::boolean(true)),
          ("loading", Json::boolean(false)),
          (
            "items",
            [
              obj([("station", str("ws2/st9")), ("id", str("st9")), ("name", str("家里的 mini")), ("icon", str("glyph:mini:green")), ("workspace", str("ws2")), ("workspaceName", str("个人")), ("online", Json::boolean(true)), ("line", str("个人 · 在线"))]),
              obj([("station", str("ws3/st7")), ("id", str("st7")), ("name", str("实验机")), ("workspace", str("ws3")), ("workspaceName", str("实验室")), ("online", Json::boolean(false)), ("line", str("实验室已开启安全模式，此 workspace 未开启")), ("needsLock", Json::boolean(true))]),
            ],
          ),
        ]),
      )
    "memberships" =>
      Some(
        obj([
          ("manages", Json::boolean(true)),
          ("loading", Json::boolean(false)),
          ("canJoin", Json::boolean(true)),
          (
            "workspaces",
            [
              obj([("id", str("ws1")), ("workspace", str("ws1")), ("home", Json::boolean(true)), ("name", str("星火工作室")), ("line", str("主 workspace"))]),
              obj([("id", str("ws2")), ("workspace", str("ws2")), ("home", Json::boolean(false)), ("name", str("个人")), ("line", str("~/项目/个人"))]),
            ],
          ),
        ]),
      )
    "profileFlow" if fx.new_login => Some(fx_profile_flow_plan())
    "profileFlow" => Some(fx_profile_flow(hermes=mode == "settings-new-profile-hermes"))
    "pick" if text(Some(Json::object(params)), "of").has_prefix("session:") => Some(fx_session_pick())
    "connectFlow" if fx_connect_step.val != "team" && fx_connect_step.val != "app" =>
      Some(fx_feishu_flow(fx_connect_step.val))
    "connectFlow" =>
      Some(
        obj([
          ("step", str(fx_connect_step.val)),
          ("title", str("Slack 工作区")),
          ("back", str("close")),
          ("number", Json::number(1.0)),
          ("total", Json::number(4.0)),
          ("mobile", Json::boolean(true)),
          ("adding", Json::boolean(false)),
          (
            "settings",
            obj([
              ("name", str("still.fail")),
              ("description", str("Coding agent in your threads (still.fail)")),
              ("backgroundColor", str("#F3E3D3")),
            ]),
          ),
          ("config", str("")),
          ("configReady", Json::boolean(false)),
          ("mode", str("multi-session")),
          ("requireMention", Json::boolean(true)),
          ("gettingToken", Json::boolean(false)),
          ("noProfile", Json::boolean(false)),
          ("canMake", Json::boolean(false)),
          ("canCreate", Json::boolean(false)),
          (
            "teams",
            [
              obj([("teamId", str("T1")), ("name", str("星火")), ("owner", obj([("user", str("林")), ("teamDomain", str("xinghuo"))]))]),
              obj([("teamId", str("T2")), ("name", str("实验室")), ("owner", obj([("user", str("林"))]))]),
            ],
          ),
          ("chosen", obj([("teamId", str("T1")), ("name", str("星火"))])),
          ("modeWords", fx_mode_words(fx_connect_step.val.has_prefix("feishu"))),
          ("sections", fx_sections()),
        ]),
      )
    "slackApp" =>
      Some(
        obj([
          ("state", str("ok")),
          ("appId", str("A1")),
          ("links", obj([("settings", str("https://api.slack.com/apps/A1")), ("install", str("")), ("appToken", str("")), ("oauth", str(""))])),
          (
            "settings",
            obj([
              ("name", str("星火助手")),
              ("displayName", str("星火助手")),
              ("description", str("帮团队整理发布和构建")),
              ("longDescription", str("")),
              ("backgroundColor", str("#F3E3D3")),
              ("groups", obj([("base", Json::boolean(true)), ("public", Json::boolean(true)), ("dm", Json::boolean(true)), ("files", Json::boolean(true))])),
            ]),
          ),
          // its permissions as the core says them (present.ts slackSections)
          ("sections", fx_sections()),
        ]),
      )
    "vaultUses" =>
      Some(
        obj([
          (
            "uses",
            [
              obj([("at", stamp_of("昨天")), ("session", str("s-c1")), ("station", str("st1")), ("chatTitle", str("整理发布清单")), ("mode", str("proxy")), ("hosts", ["api.github.com"]), ("command", str("git push origin main")), ("howText", str("git push origin main · 代理"))]),
              obj([("at", stamp_of("3 天前")), ("session", str("s-c4")), ("station", str("st1")), ("chatTitle", str("给设置页加一个深色模式开关")), ("mode", str("proxy")), ("hosts", []), ("denied", Json::boolean(true)), ("howText", str("代理"))]),
            ],
          ),
        ]),
      )
    "decisionForm" =>
      Some(obj([("enabled", Json::boolean(true)), ("model", str("gpt-6-mini")), ("dirty", Json::boolean(false)), ("pending", Json::boolean(false))]))
    "policyForm" =>
      Some(
        obj([
          ("policy", str("做完、没有待办的对话归档；还在等人回复或有后续计划的留下。")),
          // the station's options, each its draft's key its id
          (
            "options",
            [
              obj([("key", str("o1")), ("id", str("o1")), ("name", str("已完成")), ("rubric", str("任务做完，没有后续")), ("archive", Json::boolean(true))]),
              obj([("key", str("o2")), ("id", str("o2")), ("name", str("被放弃")), ("rubric", str("明确不再继续")), ("archive", Json::boolean(true))]),
              obj([("key", str("o3")), ("id", str("o3")), ("name", str("等回复")), ("rubric", str("在等某人的答复")), ("archive", Json::boolean(false))]),
            ],
          ),
          ("dirty", Json::boolean(false)),
          ("pending", Json::boolean(false)),
        ]),
      )
    // what the settings say of the workspace (the core's views/settings.ts): Studio's completion rule on
    "settings" =>
      Some(
        obj([
          ("decisionsOn", Json::number(1.0)),
          ("decisionsText", str("1 台 station 已启用")),
          // (Studio reviews, MBA is offline: nothing to say of the hint)
          ("hintNoReview", Json::boolean(false)),
          ("hintReviewText", str("")),
        ]),
      )
    "changelog" =>
      Some(
        obj([
          ("build", Json::number(1300.0)),
          (
            "tabs",
            [
              obj([
                ("part", str("app")),
                ("label", str("此 app")),
                (
                  "days",
                  [
                    obj([
                      ("label", str("10 月 19 日")),
                      (
                        "entries",
                        [
                          obj([("version", Json::number(2.0)), ("versionName", str("0.1.1300")), ("text", []), ("lines", [obj([("kind", str("new")), ("label", str("新增")), ("text", str("设置里可以添加 station 和 Profile"))])]), ("has", Json::boolean(false)), ("note", str("更新后可用")), ("mine", Json::boolean(true))]),
                          obj([("version", Json::number(1.0)), ("versionName", str("0.1.1288")), ("text", []), ("lines", [obj([("kind", str("fix")), ("label", str("修复")), ("text", str("对话列表偶尔把同一行显示两次，滑到底再滑回来也不会消失"))])]), ("has", Json::boolean(true)), ("note", str("")), ("mine", Json::boolean(true))]),
                        ],
                      ),
                    ]),
                  ],
                ),
              ]),
              obj([("part", str("station")), ("label", str("Station")), ("days", [])]),
            ],
          ),
        ]),
      )
    "agentEnvForm" =>
      Some(
        obj([
          ("text", str("HTTPS_PROXY=http://127.0.0.1:7890\nNO_PROXY=localhost,.internal\nBAD LINE")),
          (
            "lines",
            [
              obj([("parts", []), ("error", Json::boolean(false))]),
              obj([("parts", []), ("error", Json::boolean(false))]),
              obj([("parts", []), ("error", Json::boolean(true)), ("problem", str("缺少「=」"))]),
            ],
          ),
          ("errors", Json::number(1.0)),
          ("dirty", Json::boolean(true)),
          ("pending", Json::boolean(false)),
        ]),
      )
    "connects" =>
      Some(
        fx_moved(obj([
          ("me", obj([("email", str("lin@example.com"))])),
          (
            "items",
            [
              obj([
                ("station", str("ws1/st1")),
                ("stationName", str("Studio")),
                ("connect", fx_connect("k1", "星火助手", "online", "在线", "multi-session")),
                (
                  "sessions",
                  [
                    obj([("key", str("s-c7")), ("titleText", str("Slack 里问的报销流程")), ("statusText", str("昨天"))]),
                    obj([("key", str("s-c2")), ("titleText", str("首页的列表改成按天分组")), ("statusText", str("8 分钟前"))]),
                  ],
                ),
                ("candidates", []),
                ("running", Json::number(0.0)),
                ("changes", fx_mode_changes()),
              ]),
              obj([
                ("station", str("ws1/st1")),
                ("stationName", str("Studio")),
                ("connect", fx_connect("k2", "值班机器人", "error", "连接失败", "single-session")),
                ("sessions", []),
                ("candidates", []),
                ("running", Json::number(0.0)),
                ("changes", Json::array([])),
              ]),
            ],
          ),
          ("wait", obj([("reading", Json::boolean(false)), ("failing", []), ("empty", Json::boolean(false))])),
        ]), obj([
          ("station", str("ws1/st1")),
          ("stationName", str("Studio")),
          ("connect", fx_connect("k9", "发布助手", "online", "在线", "multi-session")),
          ("sessions", []),
          ("candidates", []),
          ("running", Json::number(0.0)),
          ("changes", Json::array([])),
        ]), fn(x) { text(field(Some(x), "connect"), "id") == "k2" }),
      )
    "lock" =>
      Some(
        obj([
          ("available", Json::boolean(true)),
          ("locked", Json::boolean(true)),
          ("notice", Json::boolean(false)),
          ("role", str("owner")),
          ("manages", Json::boolean(true)),
          ("owner", Json::boolean(true)),
          ("canSign", Json::boolean(true)),
          ("signs", Json::boolean(true)),
          ("signers", Json::number(5.0)),
          ("protected", Json::number(1.0)),
          ("attention", Json::number(1.0)),
          (
            "requests",
            [
              obj([
                ("device", str("d9")),
                ("sub", str("u2")),
                ("email", str("ana@example.com")),
                ("name", str("Ana")),
                ("kind", str("app")),
                ("label", str("Pixel 9")),
                ("code", str("482 917")),
                ("created_at", Json::number(0.0)),
                ("yours", Json::boolean(false)),
                ("whoText", str("Ana")),
                ("deviceText", str("Pixel 9")),
                ("time", obj([("created_at", stamp_of("2 分钟前"))])),
              ]),
            ],
          ),
          (
            "members",
            [
              obj([
                ("sub", str("u1")),
                ("email", str("lin@example.com")),
                ("name", str("林")),
                ("role", str("owner")),
                ("you", Json::boolean(true)),
                ("nameText", str("林")),
                ("roleText", str("Owner")),
                (
                  "groups",
                  [
                    obj([
                      ("appText", str("still.fail Android")),
                      ("devices", [
                        obj([("id", str("d1")), ("kind", str("app")), ("label", str("still.fail Android · Pixel 9")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(true)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false)), ("lastSeen", Json::number(1760000000.0)), ("removable", Json::boolean(false)), ("nameText", str("Pixel 9")), ("fullText", str("Pixel 9 · still.fail Android")), ("metaText", str("此设备 · 受信任"))]),
                      ]),
                    ]),
                    obj([
                      ("appText", str("still.fail 桌面版")),
                      ("devices", [
                        obj([("id", str("d4")), ("kind", str("app")), ("label", str("still.fail 桌面版 · 林的 MacBook Pro")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false)), ("lastSeen", Json::number(1759990000.0)), ("removable", Json::boolean(true)), ("nameText", str("林的 MacBook Pro")), ("fullText", str("林的 MacBook Pro · still.fail 桌面版")), ("metaText", str("一天内使用过 · 受信任"))]),
                        obj([("id", str("d6")), ("kind", str("app")), ("label", str("still.fail 桌面版 · Mac Studio")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false)), ("lastSeen", Json::number(1759700000.0)), ("removable", Json::boolean(true)), ("nameText", str("Mac Studio")), ("fullText", str("Mac Studio · still.fail 桌面版")), ("metaText", str("3 天前使用过 · 受信任"))]),
                      ]),
                    ]),
                    obj([
                      ("appText", str("still.fail 网页版")),
                      ("devices", [
                        obj([("id", str("d2")), ("kind", str("web")), ("label", str("still.fail 网页版 · Chrome · macOS")), ("signs", Json::boolean(false)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("daysLeft", Json::number(4.0)), ("renewSoon", Json::boolean(true)), ("recent", Json::boolean(false)), ("lastSeen", Json::number(1759800000.0)), ("removable", Json::boolean(true)), ("nameText", str("Chrome · macOS")), ("fullText", str("Chrome · macOS · still.fail 网页版")), ("metaText", str("2 天前使用过 · 剩余 4 天"))]),
                      ]),
                    ]),
                    obj([
                      ("appText", str("其他")),
                      ("devices", [
                        obj([("id", str("d5")), ("kind", str("app")), ("label", str("")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false)), ("removable", Json::boolean(true)), ("nameText", str("客户端")), ("fullText", str("客户端")), ("metaText", str("超过一个月未使用 · 受信任"))]),
                      ]),
                    ]),
                  ],
                ),
              ]),
              obj([
                ("sub", str("u2")),
                ("email", str("ana@example.com")),
                ("name", str("Ana")),
                ("role", str("admin")),
                ("you", Json::boolean(false)),
                ("nameText", str("Ana")),
                ("roleText", str("管理员")),
                (
                  "groups",
                  [
                    obj([
                      ("appText", str("still.fail 桌面版")),
                      ("devices", [
                        obj([("id", str("d3")), ("kind", str("app")), ("label", str("still.fail 桌面版 · Ana 的 MacBook Air")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false)), ("lastSeen", Json::number(1759570000.0)), ("removable", Json::boolean(true)), ("nameText", str("Ana 的 MacBook Air")), ("fullText", str("Ana 的 MacBook Air · still.fail 桌面版")), ("metaText", str("5 天前使用过 · 受信任"))]),
                      ]),
                    ]),
                  ],
                ),
              ]),
            ],
          ),
          (
            "stations",
            [
              obj([("id", str("st1")), ("name", str("Studio")), ("online", Json::boolean(true)), ("protected", Json::boolean(true))]),
              obj([("id", str("st2")), ("name", str("MBA")), ("online", Json::boolean(false)), ("protected", Json::boolean(false))]),
            ],
          ),
          ("renew", []),
        ]),
      )
    "vaults" =>
      Some(
        obj([
          ("available", Json::boolean(true)),
          ("locked", Json::boolean(true)),
          ("canSign", Json::boolean(true)),
          ("setUp", Json::boolean(!fx.vault_off)),
          ("plainLeft", Json::number(fx.plain_left.to_double())),
          (
            "vaults",
            [
              obj([
                ("id", str("v1")),
                ("name", str("林的库")),
                ("owner", str("u1")),
                ("ownerName", str("林")),
                ("mine", Json::boolean(true)),
                ("members", []),
                ("station", str("st1")),
                ("stationName", str("Studio")),
                ("items", Json::number(3.0)),
                ("devices", Json::number(2.0)),
                ("open", Json::boolean(false)),
                ("keyed", Json::boolean(true)),
                ("missing", Json::number(0.0)),
                ("recoverable", Json::boolean(true)),
              ]),
            ],
          ),
          (
            "requests",
            [
              obj([
                ("id", str("r1")),
                ("vault", str("v1")),
                ("vaultName", str("林的库")),
                ("item", str("it1")),
                ("itemName", str("GitHub token")),
                ("session", str("s-c1")),
                ("station", str("st1")),
                ("chat", str("c1")),
                ("mode", str("proxy")),
                ("reason", str("要把发布清单推到仓库")),
                ("command", str("git push origin main")),
                ("hosts", ["api.github.com"]),
                ("howText", str("代理 · 限 api.github.com")),
                ("at", Json::number(0.0)),
              ]),
            ],
          ),
          ("refused", []),
          // (the core's words of it: its one request waits)
          ("statusText", str("1 个待批准")),
          ("statusBad", Json::boolean(true)),
        ]),
      )
    "vaultItems" =>
      Some(
        fx_moved(obj([
          ("vault", str("v1")),
          ("name", str("林的库")),
          ("open", Json::boolean(false)),
          (
            "items",
            [
              obj([("id", str("it1")), ("version", Json::number(1.0)), ("at", Json::number(0.0)), ("name", str("GitHub token")), ("kind", str("token")), ("listed", Json::boolean(true)), ("modes", ["proxy"]), ("hosts", ["api.github.com"]), ("lastUse", obj([("at", stamp_of("昨天")), ("session", str("s-c1")), ("chatTitle", str("修 CI")), ("mode", str("proxy")), ("hosts", [])])), ("kindText", str("Token")), ("shut", [obj([("key", str("value")), ("label", str("值")), ("value", str("••••••••••••••••••••")), ("secret", Json::boolean(true)), ("mono", Json::boolean(true))])]), ("agentText", str("允许 agent 申请 · 代理 · api.github.com")), ("lineText", str("代理 · api.github.com · 昨天在「修 CI」用过")), ("howText", str("代理 · 限 api.github.com")), ("lastsText", str("跟随默认 · 直到对话归档"))]),
              obj([("id", str("it2")), ("version", Json::number(1.0)), ("at", Json::number(0.0)), ("name", str("部署机")), ("kind", str("ssh_key")), ("listed", Json::boolean(true)), ("modes", ["ssh"]), ("hosts", []), ("kindText", str("SSH 密钥")), ("shut", [obj([("key", str("private_key")), ("label", str("私钥")), ("value", str("••••••••••••••••••••")), ("secret", Json::boolean(true)), ("mono", Json::boolean(true))])]), ("agentText", str("允许 agent 申请 · ssh-agent")), ("lineText", str("ssh-agent")), ("howText", str("ssh-agent")), ("lastsText", str("跟随默认 · 直到对话归档"))]),
              obj([("id", str("it3")), ("version", Json::number(1.0)), ("at", Json::number(0.0)), ("kind", str("login")), ("listed", Json::boolean(false)), ("modes", []), ("hosts", []), ("kindText", str("登录")), ("shut", [obj([("key", str("username")), ("label", str("用户名")), ("value", str("••••••••••")), ("secret", Json::boolean(false)), ("mono", Json::boolean(false))]), obj([("key", str("password")), ("label", str("密码")), ("value", str("••••••••••••")), ("secret", Json::boolean(true)), ("mono", Json::boolean(true))])]), ("agentText", str("仅自己可见")), ("lineText", str("仅自己可见")), ("howText", str("")), ("lastsText", str("跟随默认 · 直到对话归档"))]),
            ],
          ),
        ]), obj([("id", str("it4")), ("version", Json::number(1.0)), ("at", Json::number(0.0)), ("name", str("OpenAI key")), ("kind", str("token")), ("listed", Json::boolean(true)), ("modes", ["proxy"]), ("hosts", ["api.openai.com"]), ("kindText", str("Token")), ("shut", []), ("agentText", str("允许 agent 申请 · 代理 · api.openai.com")), ("lineText", str("代理 · api.openai.com")), ("howText", str("代理 · 限 api.openai.com")), ("lastsText", str("跟随默认 · 直到对话归档"))]), fn(x) { text(Some(x), "id") == "it1" }),
      )
    "profiles" => {
      let list = fx_profiles().map(fn(p) {
        // how it is, as the core says it (views/profiles.ts stateOf): its trouble, in its check's words where the check
        // did not pass
        let pv = Some(p)
        let look = field(pv, "trouble") is Some(Object(_))
        let green = text(pv, "checkTone") == "green"
        let state = if look && green {
          obj([("text", str(text(field(pv, "trouble"), "title"))), ("tone", str("amber"))])
        } else if green {
          Json::null()
        } else {
          obj([("text", str(text(pv, "checkText"))), ("tone", str(text(pv, "checkTone")))])
        }
        obj([
          ("key", str("ws1/st1/" + text(Some(p), "id"))),
          ("group", str(text(Some(p), "group"))),
          ("groupTitle", str(text(Some(p), "groupTitle"))),
          ("station", str("ws1/st1")),
          ("stationId", str("st1")),
          ("stationName", str("Studio")),
          ("profile", p),
          ("title", str(if text(Some(p), "email") == "" { text(Some(p), "name") } else { text(Some(p), "email") })),
          ("shared", Json::boolean(false)),
          ("host", str("st1")),
          ("hostName", str("Studio")),
          ("hostOnline", Json::boolean(true)),
          ("usable", Json::boolean(true)),
          ("state", state),
          ("look", Json::boolean(look)),
          ("where", str("Studio 可用")),
          (
            "stations",
            [
              obj([("id", str("st1")), ("station", str("ws1/st1")), ("name", str("Studio")), ("online", Json::boolean(true)), ("allowed", Json::boolean(true))]),
              obj([("id", str("st2")), ("station", str("ws1/st2")), ("name", str("MBA")), ("online", Json::boolean(false)), ("allowed", Json::boolean(true))]),
            ],
          ),
          (
            "members",
            [
              obj([("station", str("ws1/st1")), ("stationId", str("st1")), ("stationName", str("Studio")), ("online", Json::boolean(true)), ("profileId", str(text(Some(p), "id"))), ("role", str("host")), ("about", str("")), ("usable", Json::boolean(true)), ("checkText", str("可用")), ("checkTone", str("green")), ("usedBy", Json::number(1.0)), ("spread", fx_spread(text(Some(p), "id")))]),
            ],
          ),
          ("editable", Json::boolean(true)),
          ("canShare", Json::boolean(true)),
        ])
      })
      let attention = list.filter(fn(e) { flag(Some(e), "look") }).length()
      Some(
        obj([
          ("items", Json::array(list)),
          ("attention", Json::number(attention.to_double())),
          ("wait", obj([("reading", Json::boolean(false)), ("failing", []), ("empty", Json::boolean(false))])),
        ]),
      )
    }
    "usage" =>
      Some(
        fx_usage(
          match params.get("days") {
            Some(Number(n, ..)) => n.to_int()
            _ => 7
          },
        ),
      )
    "archive" => Some(fx_archive())
    "memory" => Some(fx_memory())
    // (settings-me-reading: where the account is signed in not read yet, its wait line shown)
    "loginSessions" if mode.has_prefix("settings-me-reading") => None
    "loginSessions" =>
      Some([
        obj([("id", str("l1")), ("name", str("Pixel 9 · still.fail")), ("current", Json::boolean(true)), ("time", obj([("created_at", stamp_of("3 天前")), ("expires_at", stamp_of("", until="27 天后"))]))]),
        obj([("id", str("l2")), ("name", str("Chrome · macOS")), ("current", Json::boolean(false)), ("time", obj([("created_at", stamp_of("2 周前")), ("expires_at", stamp_of("", until="16 天后"))]))]),
      ])
    "notify" => {
      // notifications off (slice 10's settings-notify-off)
      let on = !mode.has_prefix("settings-notify-off")
      Some(
        obj([
          ("on", Json::boolean(on)),
          ("asked", Json::boolean(true)),
          ("push", Json::boolean(false)),
          ("show", []),
          ("kinds", obj([("wait", Json::boolean(true)), ("failed", Json::boolean(true)), ("done", str("away")), ("message", Json::boolean(false))])),
          ("preview", Json::boolean(true)),
          ("permission", str(if mode.has_prefix("settings-notify-denied") { "denied" } else { "granted" })),
          // (the account's two workspaces, 个人 turned off)
          ("muted", [str("ws2")]),
          (
            "workspaces",
            [
              obj([("id", str("ws1")), ("name", str("星火工作室")), ("on", Json::boolean(true))]),
              obj([("id", str("ws2")), ("name", str("个人")), ("on", Json::boolean(false))]),
            ],
          ),
        ]),
      )
    }
    "doing" => Some(obj([("doing", [])]))
    "lockDraft" =>
      Some(
        obj([
          ("available", Json::boolean(true)),
          ("loading", Json::boolean(false)),
          ("canSign", Json::boolean(true)),
          ("owner", Json::boolean(true)),
          ("ready", Json::boolean(true)),
          (
            "members",
            [
              obj([("sub", str("u1")), ("email", str("lin@example.com")), ("name", str("林")), ("role", str("owner")), ("nameText", str("林")), ("roleText", str("Owner"))]),
              obj([("sub", str("u2")), ("email", str("ana@example.com")), ("name", str("Ana")), ("role", str("admin")), ("nameText", str("Ana")), ("roleText", str("管理员"))]),
            ],
          ),
          (
            "devices",
            [
              obj([("id", str("d1")), ("person", str("林")), ("kind", str("app")), ("label", str("这台手机")), ("older", Json::boolean(false)), ("current", Json::boolean(true)), ("on", Json::boolean(true)), ("fixed", Json::boolean(true)), ("nameText", str("林 · 此设备")), ("howText", str("客户端 · 受信任"))]),
              obj([("id", str("d3")), ("person", str("Ana")), ("kind", str("app")), ("label", str("MacBook")), ("older", Json::boolean(false)), ("current", Json::boolean(false)), ("on", Json::boolean(true)), ("fixed", Json::boolean(false)), ("nameText", str("Ana · MacBook")), ("howText", str("客户端"))]),
            ],
          ),
          (
            "stations",
            [
              obj([("id", str("st1")), ("name", str("Studio")), ("version", str("0.1.4600")), ("state", str("ok")), ("on", Json::boolean(true)), ("fixed", Json::boolean(false))]),
              obj([("id", str("st2")), ("name", str("MBA")), ("state", str("offline")), ("on", Json::boolean(false)), ("fixed", Json::boolean(true)), ("stateText", str("离线 · 上线后可在此保护"))]),
            ],
          ),
        ]),
      )
    _ => None
  }
}

///|
/// A made-up settings call (a station renamed, a chat restored, a station's memory read), None for one these do not
/// take.
pub fn fixture_call(name : String, params : Json) -> Result[Json, Json]? {
  let p = Some(params)
  match name {
    "workspace.renameStation" => {
      // a name, or (the mark picker's) a mark
      match field(p, "icon") {
        Some(_) => fx.marks[text(p, "station")] = text(p, "icon")
        None => fx.names[text(p, "station")] = text(p, "name")
      }
      fx_changed()
      Some(Ok(obj([])))
    }
    "chat.archive" if field(p, "archived") is Some(False) => {
      fx.restored[text(p, "session")] = true
      fx_changed()
      Some(Ok(obj([])))
    }
    // still.fail's buddies a Slack app can wear (the core's own list, web/public/avatars/index.json: three of it)
    "buddies" =>
      Some(
        Ok(
          Json::array([
            obj([("id", str("backend")), ("label", str("后端接口")), ("bg", str("#B582EB"))]),
            obj([("id", str("mobile")), ("label", str("移动应用")), ("bg", str("#B9D84A"))]),
            obj([("id", str("documentation")), ("label", str("写文档")), ("bg", str("#F3CA43"))]),
          ]),
        ),
      )
    // an admin's answer to the program asking for Studio's data
    "outflow.answer" => {
      fx.outflow_answer = Some(params)
      fx_changed()
      Some(Ok(obj([])))
    }
    // lin's secrets from before security mode encrypted into their vault
    "vault.migrate" => {
      fx.plain_left = 0
      fx_changed()
      Some(Ok(obj([])))
    }
    // the new device turned away, or its prompt closed: no longer shown
    "lockPrompt.deny" | "lockPrompt.hide" => {
      fx.pairing = false
      fx.pair_ended = if name == "lockPrompt.deny" { "deny" } else { "hide" }
      fx_changed()
      Some(Ok(obj([])))
    }
    // a skill shared with the workspace's other stations, or no longer
    "skill.share" => {
      fx.skills_shared[text(p, "name")] = flag(p, "on")
      fx_changed()
      Some(Ok(obj([])))
    }
    "cache.usage" =>
      Some(
        Ok(
          obj([
            (
              "chats",
              Json::array([
                // a PDF opened, 5 minutes ago; a video, 12 of its 48 MB come
                obj([
                  ("station", str("ws1/st1")),
                  ("thread", Json::number(1.0)),
                  ("title", str("整理发布清单")),
                  ("sessions", ["s-c1"]),
                  ("bytes", Json::number(2400000.0)),
                  (
                    "files",
                    Json::array(
                      [
                        fx_kept_file("s-c1", "季度报告.pdf", 3355443.0, 3355443.0, -300000.0),
                        fx_kept_file("s-c1", "演示录屏.mp4", 50331648.0, 12582912.0, -7200000.0),
                      ].filter_map(fn(f) { f }),
                    ),
                  ),
                ]),
                obj([("station", str("ws1/st1")), ("thread", Json::number(4.0)), ("title", str("给设置页加一个深色模式开关")), ("sessions", ["s-c4"]), ("bytes", Json::number(860000.0))]),
                obj([("station", str("ws1/st2")), ("thread", Json::number(3.0)), ("title", str("夜里的构建又失败了")), ("sessions", ["s-c3"]), ("bytes", Json::number(41000.0))]),
                ] +
                fx_kept_many()
                |> fx_kept_most_first,
              ),
            ),
            ("drive", Json::number(fx.drive_kept)),
            // one of a chat no longer kept here, 3 days ago
            ("loose", Json::array([fx_kept_file("s-old", "旧日志.zip", 921600.0, 921600.0, -3.0 * 86400000.0, station="ws1/st2")].filter_map(fn(f) { f }))),
          ]),
        ),
      )
    "drive.kept.clear" => {
      fx.drive_kept = 0.0
      fx_changed()
      Some(Ok(Json::null()))
    }
    "cache.file.clear" => {
      fx.kept_cleared.push(text(p, "name"))
      fx_changed()
      Some(Ok(Json::null()))
    }
    "machineSessions.list" => Some(Ok(obj([("sessions", [])])))
    "workspace.enroll" =>
      Some(
        Ok(
          obj([
            ("token", str("made-up")),
            ("install", str("curl -fsSL https://still.fail/install.sh | sh -s -- 4f7c2a9e1b")),
            ("command", str("stillfail station enroll https://still.fail 4f7c2a9e1b")),
          ]),
        ),
      )
    "software.auto" => {
      fx.auto = flag(p, "on")
      fx_changed()
      Some(Ok(obj([])))
    }
    "network.setCongestion" => {
      fx.congestion = text(p, "congestion")
      Some(Ok(obj([])))
    }
    "station.restart" => Some(Ok(obj([("restarting", Json::boolean(true))])))
    "elevation.set" => {
      match fx.elevation {
        Some(Object(e)) => {
          let shown = e.copy()
          shown["on"] = Json::boolean(flag(p, "on"))
          shown["busy"] = Json::boolean(true)
          shown["canChange"] = Json::boolean(false)
          fx.elevation = Some(Json::object(shown))
          fx_changed()
        }
        _ => ()
      }
      Some(Ok(obj([])))
    }
    "context.setAfresh" => {
      match field(p, "afreshWhenCold") {
        Some(True) => fx.afresh = true
        Some(False) => fx.afresh = false
        _ => ()
      }
      match field(p, "afreshAbove") {
        Some(Number(above, ..)) => fx.afresh_above = above
        _ => ()
      }
      fx_changed()
      Some(Ok(obj([])))
    }
    "diagnostics.setLogs" => {
      fx.logs = flag(p, "logs")
      fx_changed()
      Some(Ok(obj([])))
    }
    "software.check" | "software.update" | "software.channel" | "search.setPersonal" | "permissions.request" =>
      Some(Ok(obj([])))
    "agentEnv.form.open" | "agentEnv.form.edit" | "agentEnv.form.drop" | "agentEnv.form.save" => Some(Ok(obj([])))
    "profile.quota" | "profile.check" | "profile.put" => Some(Ok(obj([])))
    // the subscription's sign-in begun: as settings-profile-login has it, waiting on the code
    "profile.login" => {
      fx.login = "needs_code"
      fx_changed()
      Some(Ok(obj([])))
    }
    "profile.resetQuota" => {
      fx.resets_used += 1
      fx_changed()
      Some(Ok(obj([])))
    }
    "profile.addModel" => {
      if text(p, "id") == "cx" {
        fx.models_added.push(text(p, "model"))
      } else {
        fx.models_given.push(text(p, "id"))
      }
      fx_changed()
      Some(Ok(obj([])))
    }
    // the drafts' forms (a new profile's, a new connect's, the decisions' and the archive policy's), opened and edited
    // an Anthropic plan's sign-in for a new profile, begun (settings-new-profile-login…)
    "login.new" if fx.new_login => Some(Ok(obj([("id", str("login-new")), ("job", fx_login_job("login-new", "needs_code"))])))
    "profile.flow.open" | "profile.flow.edit" | "profile.flow.drop" | "connect.flow.open" | "connect.flow.edit"
    | "connect.flow.drop" | "automaticDecisions.form.open" | "automaticDecisions.form.edit"
    | "automaticDecisions.form.drop" | "automaticDecisions.policy.open" | "automaticDecisions.policy.drop" =>
      Some(Ok(obj([])))
    // people added: each as one who has not signed in yet
    "workspace.addMembers" =>
      Some(Ok(obj([("joined", []), ("added", field(p, "emails").unwrap_or(Json::array([]))), ("already", [])])))
    // a chat agent's run settings (a new chat's picks are the new chat fixture's)
    "pick.set" if text(p, "of").has_prefix("session:") => Some(Ok(obj([])))
    _ => None
  }
}

///|
/// The lock as a device not confirmed in it has it (MBUI_FIXTURE=lock-waiting, lock-finding, lock-code, lock-wrong,
/// lock-checking, lock-none, lock-failed, lock-refused, lock-nocode, lock-security, each also -dark: its waiting page
/// asking, finding, the code being typed, typed wrong, being checked, no device found, the pairing failed, the request
/// refused, this device without its code yet; its security page): this device waiting (its own request among the
/// workspace's), not a signer. lock-upgrade: in the lock but not signing (its key lost), the code being typed on its
/// security page.
fn waiting_lock(mode : String) -> Json {
  let mode = if mode.has_suffix("-dark") { mode.unsafe_substring(start=0, end=mode.length() - 5) } else { mode }
  let pair = match mode {
    "lock-finding" => obj([("state", str("finding"))])
    "lock-code" | "lock-upgrade" =>
      obj([("state", str("code")), ("left", Json::number(3.0)), ("untilText", str("14:05 前有效"))])
    "lock-wrong" => obj([("state", str("wrong")), ("left", Json::number(2.0)), ("untilText", str("14:05 前有效"))])
    "lock-checking" => obj([("state", str("checking")), ("left", Json::number(3.0))])
    "lock-none" => obj([("state", str("none"))])
    "lock-failed" => obj([("state", str("failed")), ("error", str("配对超时"))])
    _ => Json::null()
  }
  let failed = if mode == "lock-refused" { "station 不在线" } else { "" }
  // in the lock, its key since lost (a phone moved to a new one): made one that signs on its security page
  let upgrade = mode == "lock-upgrade"
  let code = if mode == "lock-nocode" { "" } else { "Q4K-7PM" }
  obj([
    ("available", Json::boolean(true)),
    ("locked", Json::boolean(true)),
    ("notice", Json::boolean(false)),
    ("role", str("owner")),
    ("manages", Json::boolean(true)),
    ("owner", Json::boolean(true)),
    ("canSign", Json::boolean(true)),
    ("signs", Json::boolean(false)),
    ("signers", Json::number(5.0)),
    ("protected", Json::number(4.0)),
    ("attention", Json::number(2.0)),
    (
      "me",
      obj([
        ("device", str("d-me")),
        ("code", str(code)),
        ("kind", str("app")),
        ("confirmed", Json::boolean(upgrade)),
        ("asked", Json::boolean(!upgrade)),
        ("waiting", Json::boolean(!upgrade)),
        ("unsigned", Json::boolean(upgrade)),
        ("failed", str(failed)),
        ("pair", pair),
      ]),
    ),
    (
      "requests",
      [
        obj([("device", str("d-me")), ("sub", str("u1")), ("email", str("lin@example.com")), ("name", str("林")), ("kind", str("app")), ("label", str("still.fail mbui Android · OPPO PLP110")), ("code", str("Q4K-7PM")), ("created_at", Json::number(0.0)), ("yours", Json::boolean(true)), ("whoText", str("林")), ("deviceText", str("OPPO PLP110 · still.fail mbui Android")), ("time", obj([("created_at", stamp_of("1 分钟前"))]))]),
        obj([("device", str("d9")), ("sub", str("u2")), ("email", str("ana@example.com")), ("name", str("Ana")), ("kind", str("app")), ("label", str("Pixel 9")), ("code", str("482 917")), ("created_at", Json::number(0.0)), ("yours", Json::boolean(false)), ("whoText", str("Ana")), ("deviceText", str("Pixel 9")), ("time", obj([("created_at", stamp_of("2 分钟前"))]))]),
      ],
    ),
    (
      "members",
      [
        obj([
          ("sub", str("u1")),
          ("email", str("lin@example.com")),
          ("name", str("林")),
          ("role", str("owner")),
          ("you", Json::boolean(true)),
          ("nameText", str("林")),
          ("roleText", str("Owner")),
          (
            "groups",
            [
              obj([
                ("appText", str("still.fail Android")),
                ("devices", [
                  obj([("id", str("d1")), ("kind", str("app")), ("label", str("still.fail Android · OPPO PLP110")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false)), ("lastSeen", Json::number(1760000000.0)), ("removable", Json::boolean(false)), ("nameText", str("OPPO PLP110")), ("fullText", str("OPPO PLP110 · still.fail Android")), ("metaText", str("一天内使用过 · 受信任"))]),
                ]),
              ]),
            ],
          ),
        ]),
      ],
    ),
    ("stations", []),
    ("renew", []),
  ])
}

///|
/// The dialog of the desktop's pages a fixture's mode puts up ("" none), taken once: the desktop's page puts it up
/// once it is drawn with what it needs.
pub fn fixture_desk() -> String {
  let d = fixture_open.desk
  fixture_open.desk = ""
  d
}

///|
/// The sheet a fixture's mode puts up, once its page is drawn with what it needs (`page`).
fn fixture_sheet(core : Core, here : Here) -> Unit {
  let what = fixture_open.sheet
  if what == "" {
    return
  }
  fixture_open.sheet = ""
  match what {
    "mark" => {
      let s = Some(fx_station("ws1/st1"))
      open_mark_pick(core, text(s, "name"), text(s, "emoji"), text(s, "icon"), "", fn(_, _, _) {  })
    }
    "add-people" => open_add_people(core, here, workspace_view(core, here).value)
    "workspace-mark" => open_mark_pick(core, "星火工作室", "", "glyph:rocket:orange", "", fn(_, _, _) {  })
    "add" | "add-existing" | "add-command" => {
      open_add_station(core, here, ["st1", "st2"], existing=what == "add-existing")
      if what == "add-command" {
        adding.made.set(Some(
          (
            "curl -fsSL https://still.fail/install.sh | sh -s -- 4f7c2a9e1b",
            "stillfail station enroll https://still.fail 4f7c2a9e1b",
          ),
        ))
      }
    }
    _ => ()
  }
}

///|
/// A page's list scrolled as a fixture's mode asks (its first frames), by its key: to its block, or (a block under 0,
/// the list's `rows` known) its last.
fn fixture_scroll(c : @ui.Ctx, key : String, rows? : Int = 0) -> Unit {
  if fixture_open.list == key && fixture_open.frames < 4 {
    fixture_open.frames += 1
    // (the list asks for the frames its scroll takes)
    c.list_scroll_to(key, if fixture_open.block < 0 { rows - 1 } else { fixture_open.block })
  }
}

///|
/// Made-up recovery words for the words' screenshot (no one's: the words of a fixture are not a key to anything).
fn fx_words() -> Array[String] {
  [
    "amber", "basin", "cedar", "delta", "ember", "fable", "grove", "harbor", "island", "jasper", "kettle", "lantern", "meadow",
    "nectar", "orbit", "pebble", "quarry", "river", "saddle", "timber", "umbra", "velvet", "willow", "zephyr",
  ]
}

///|
/// A subscription's sign-in under way in `state` (a profile's, or a new one's by its login's id): its page, and that
/// the station's own browser can open it where the fixture says so.
fn fx_login_job(profile : String, state : String) -> Json {
  let o = [
    ("profile", str(profile)),
    ("runtime", str("claude")),
    ("state", str(state)),
    ("url", str("https://claude.example/oauth/authorize")),
    ("startedAt", Json::number(0.0)),
    ("expiresAt", Json::number(0.0)),
  ]
  if fx.login_station {
    o.push(("browser", Json::boolean(true)))
  }
  obj(o)
}

///|
/// A new profile's draft at an Anthropic plan's sign-in (`profileFlow`, settings-new-profile-login…): 连接 Anthropic.
fn fx_profile_flow_plan() -> Json {
  obj([
    ("step", str("connect")),
    ("station", str("ws1/st1")),
    ("title", str("连接 Anthropic")),
    ("hint", str("")),
    ("method", str("plan")),
    ("tile", obj([("id", str("anthropic")), ("name", str("Anthropic")), ("kind", str("subscription")), ("runtime", str("claude")), ("mark", str("anthropic"))])),
    ("signIn", obj([("runtime", str("claude")), ("provider", str("Claude")), ("access", str(""))])),
    ("groups", []),
    ("choices", []),
    ("showEndpoint", Json::boolean(false)),
    ("endpoint", str("")),
    ("protocols", []),
    ("showKey", Json::boolean(false)),
    ("key", str("")),
    ("keyLabel", str("")),
    ("canSubmit", Json::boolean(false)),
    ("pending", Json::boolean(false)),
    ("submitLabel", str("")),
    ("usesLine", str("")),
  ])
}

///|
/// A new profile's draft at its first step (`profileFlow`): the providers by group.
fn fx_profile_flow(hermes? : Bool = false) -> Json {
  let provider = fn(id : String, name : String, group : String, runtime : String, mark : String) {
    obj([("id", str(id)), ("name", str(name)), ("group", str(group)), ("kind", str("api-provider")), ("runtime", str(runtime)), ("mark", str(mark))])
  }
  let groups : Array[Json] = [
    obj([
      ("id", str("labs")),
      ("title", str("模型厂商")),
      (
        "providers",
        [
          provider("openai", "OpenAI", "labs", "codex", "openai"),
          provider("anthropic", "Anthropic", "labs", "claude", "anthropic"),
          provider("deepseek", "DeepSeek", "labs", "", "deepseek"),
          provider("kimi", "Kimi", "labs", "", "kimi"),
        ],
      ),
    ]),
    obj([("id", str("gateways")), ("title", str("中转站")), ("providers", [provider("openrouter", "OpenRouter", "gateways", "", "openrouter")])]),
  ]
  if hermes {
    groups.push(obj([
      ("id", str("local")), ("title", str("自定义变量")),
      ("providers", [obj([
        ("id", str("env-hermes")), ("name", str("Hermes Agent")), ("group", str("local")),
        ("kind", str("env")), ("runtime", str("hermes")),
      ])]),
    ]))
  }
  obj([
    ("step", str("pick")),
    ("station", str("ws1/st1")),
    ("title", str("选择服务商")),
    ("hint", str("订阅和 API key 都在这里添加，选择服务商开始")),
    ("groups", Json::array(groups)),
    ("choices", []),
    ("showEndpoint", Json::boolean(false)),
    ("endpoint", str("")),
    ("protocols", []),
    ("showKey", Json::boolean(false)),
    ("key", str("")),
    ("keyLabel", str("")),
    ("canSubmit", Json::boolean(false)),
    ("pending", Json::boolean(false)),
    ("submitLabel", str("")),
    ("usesLine", str("")),
  ])
}

///|
/// Whether the run's models are many (MBUI_FIXTURE=settings-run-models).
let fx_many_models : Ref[Bool] = Ref(false)

///|
/// Whether many chats are kept (MBUI_FIXTURE=settings-kept-many): 200 more after the three, each with a few KB.
let fx_many_kept : Ref[Bool] = Ref(false)

///|
/// The chats kept after the three when many are (fx_many_kept): 测试会话 1 to 200.
fn fx_kept_many() -> Array[Json] {
  if !fx_many_kept.val {
    return []
  }
  Array::makei(200, fn(i) -> Json {
    obj([
      ("station", str("ws1/st2")),
      ("thread", Json::number((100 + i).to_double())),
      ("title", str("测试会话 \{i + 1}")),
      ("sessions", Json::array([str("s-m\{i}")])),
      ("bytes", Json::number((4096 * (i + 1)).to_double())),
    ])
  })
}

///|
/// The chats kept, the one keeping most (its messages and its files) first, as the core gives them.
fn fx_kept_most_first(chats : Array[Json]) -> Array[Json] {
  let all = fn(x : Json) {
    items(Some(x), "files").fold(init=number(Some(x), "bytes"), fn(s, f) { s + number(Some(f), "bytes") })
  }
  let out = chats.copy()
  out.sort_by(fn(a, b) { all(b).compare(all(a)) })
  out
}

///|
/// A chat's agent as it runs and as it is to run (`pick` of `session:<key>`, MBUI_FIXTURE=settings-run): its effort
/// raised to high, the rest as it was.
fn fx_session_pick() -> Json {
  let model = obj([("model", str("claude-opus-5-5")), ("name", str("Opus 5.5")), ("maker", obj([("id", str("anthropic"))]))])
  let m = fn(id : String, name : String, family : String) {
    obj([("model", str(id)), ("name", str(name)), ("family", str(family)), ("maker", obj([("id", str("anthropic"))]))])
  }
  // (MBUI_FIXTURE=settings-run-models: many, by series, one borrowed from MBA)
  let options : Json = if fx_many_models.val {
    [
      obj([("model", str("claude-opus-5-5")), ("name", str("Opus 5.5")), ("family", str("Opus")), ("maker", obj([("id", str("anthropic"))]))]),
      m("claude-opus-5-1", "Opus 5.1", "Opus"),
      m("claude-opus-5", "Opus 5", "Opus"),
      m("claude-sonnet-5-5", "Sonnet 5.5", "Sonnet"),
      m("claude-sonnet-5", "Sonnet 5", "Sonnet"),
      m("claude-sonnet-4-5", "Sonnet 4.5", "Sonnet"),
      m("claude-haiku-4-5", "Haiku 4.5", "Haiku"),
      m("claude-haiku-4", "Haiku 4", "Haiku"),
      obj([
        ("model", str("claude-fable-5-1")),
        ("name", str("Fable 5.1")),
        ("family", str("Fable")),
        ("maker", obj([("id", str("anthropic"))])),
        ("availability", str("borrowable")),
        ("fromStation", obj([("name", str("MBA")), ("icon", str("glyph:laptop:teal"))])),
        ("fromText", str("借自 MBA")),
      ]),
    ]
  } else {
    [model]
  }
  obj([
    ("value", obj([("model", str("claude-opus-5-5")), ("runtime", str("claude"))])),
    ("draft", obj([("model", str("claude-opus-5-5")), ("runtime", str("claude")), ("effort", str("high"))])),
    ("option", str("claude-opus-5-5")),
    ("options", options),
    ("maker", obj([("id", str("anthropic"))])),
    ("modelText", str("Opus 5.5")),
    ("efforts", ["low", "medium", "high"]),
    ("was", ["Opus 5.5", "默认深度", "自动 · Claude 主账号"]),
    ("becomes", ["Opus 5.5", "high", "自动 · Claude 主账号"]),
    ("accountText", str("自动分配")),
    ("accountNote", str("Claude 主账号 · 5 小时窗口已用 62%")),
    ("repick", str("重新分配")),
    // (RunnableProfile: its kind, its runtime, its allowance)
    (
      "accounts",
      [
        obj([
          ("id", str("p1")),
          ("name", str("Claude 主账号")),
          ("current", Json::boolean(true)),
          ("kind", str("subscription")),
          ("runtime", str("claude")),
          (
            "quota",
            obj([
              ("state", str("ok")),
              ("windows", [obj([("mark", str("5H")), ("left", Json::number(38.0)), ("level", str("ok"))]), obj([("mark", str("W")), ("left", Json::number(70.0)), ("level", str("ok"))])]),
            ]),
          ),
        ]),
      ],
    ),
    ("changed", Json::boolean(true)),
    ("saveText", str("改成 Opus 5.5 · high · 自动分配")),
  ])
}

///|
/// A new connect on Feishu's path (MBUI_FIXTURE=settings-new-connect-platform, -scan): the platform picked (飞书), or
/// the bot being made by scanning, its QR code waiting.
fn fx_feishu_flow(step : String) -> Json {
  let scan = step == "feishuScan"
  let feishu : Array[(String, Json)] = [
    ("way", str("scan")),
    ("appId", str("")),
    ("appSecret", str("")),
    ("lark", Json::boolean(false)),
    ("canVerify", Json::boolean(false)),
    ("verified", Json::boolean(false)),
    ("errors", []),
    ("failed", Json::boolean(false)),
    ("creating", Json::boolean(false)),
    ("error", Json::null()),
    ("connect", Json::null()),
  ]
  if scan {
    feishu.push(("registration", obj([("state", str("waiting")), ("url", str("https://open.feishu.cn/page/launcher?code=made-up"))])))
    feishu.push(("stateText", str("使用飞书扫描二维码，按提示创建机器人")))
    feishu.push(("qr", fx_qr(25)))
  }
  obj([
    ("step", str(step)),
    ("title", str(if scan { "扫码创建" } else { "选择平台" })),
    ("back", str(if scan { "feishuWay" } else { "close" })),
    ("number", Json::number(if scan { 4.0 } else { 1.0 })),
    ("total", Json::number(4.0)),
    ("mobile", Json::boolean(true)),
    ("platforms", [str("slack"), str("feishu")]),
    ("platform", str("feishu")),
    ("feishu", obj(feishu)),
    ("mode", str("multi-session")),
    ("requireMention", Json::boolean(true)),
    ("noProfile", Json::boolean(false)),
    ("canCreate", Json::boolean(true)),
  ])
}

///|
/// A made-up QR code's modules, `n` a side (the three finder squares, the rest a fixed scatter): only drawn, never
/// read.
fn fx_qr(n : Int) -> Json {
  let rows : Array[Json] = []
  for y in 0..<n {
    let row = StringBuilder::new()
    for x in 0..<n {
      let finder = fn(ox : Int, oy : Int) {
        let dx = x - ox
        let dy = y - oy
        if dx < 0 || dy < 0 || dx > 6 || dy > 6 {
          None
        } else {
          let ring = if dx < dy { dx } else { dy }
          let far = if 6 - dx < 6 - dy { 6 - dx } else { 6 - dy }
          let d = if ring < far { ring } else { far }
          Some(d != 1)
        }
      }
      let dark = match finder(0, 0) {
        Some(b) => b
        None =>
          match finder(n - 7, 0) {
            Some(b) => b
            None =>
              match finder(0, n - 7) {
                Some(b) => b
                None => (x * 7 + y * 13 + x * y * 3) % 5 < 2
              }
          }
      }
      row.write_char(if dark { '1' } else { '0' })
    }
    rows.push(str(row.to_string()))
  }
  obj([("size", Json::number(n.to_double())), ("rows", Json::array(rows))])
}

///|
/// A use, its figures and each said (ResourceUse): CPU, memory, the network's and the disk's rates.
fn fx_use(cpu : Double, memory : Double, net : Double, disk : Double, texts : (String, String, String, String)) -> Json {
  let (cpu_text, memory_text, net_text, disk_text) = texts
  obj([
    ("cpu", Json::number(cpu)),
    ("memory", Json::number(memory)),
    ("netIn", Json::number(net / 2.0)),
    ("netOut", Json::number(net / 2.0)),
    ("net", Json::number(net)),
    ("diskRead", Json::number(disk)),
    ("diskWrite", Json::number(0.0)),
    ("disk", Json::number(disk)),
    ("cpuText", str(cpu_text)),
    ("memoryText", str(memory_text)),
    ("netText", str(net_text)),
    ("diskText", str(disk_text)),
  ])
}

///|
/// What still.fail uses of Studio's machine now (ResourcesView), as a busy Mac says it: its four totals with what is
/// under each (the network and the disk both read), two chats' agents (one titled at length) and the station, each with
/// its processes.
fn fx_resources() -> Json {
  let process = fn(key : String, pid : Double, name : String, endable : Bool, u : Json) {
    obj([("key", str(key)), ("pid", Json::number(pid)), ("name", str(name)), ("endable", Json::boolean(endable)), ("use", u)])
  }
  let tile = fn(key : String, label : String, value : String, sub : String, points : Array[Double]) {
    obj([("key", str(key)), ("label", str(label)), ("value", str(value)), ("sub", str(sub)), ("points", Json::array(points.map(Json::number(_))))])
  }
  let chat = fx_use(25.9, 59.0e6, 0.0, 2.9e6, ("25.9%", "59 MB", "0 B/s", "2.9 MB/s"))
  let notes = fx_use(14.1, 980.0e6, 0.0, 13.0e3, ("14.1%", "980 MB", "0 B/s", "13 KB/s"))
  let station = fx_use(2.8, 363.0e6, 56.0e3, 0.0, ("2.8%", "363 MB", "56 KB/s", "0 B/s"))
  obj([
    ("wait", obj([("reading", Json::boolean(false)), ("text", str("")), ("failing", [])])),
    ("empty", Json::boolean(false)),
    ("net", Json::boolean(true)),
    ("disk", Json::boolean(true)),
    ("everyMs", Json::number(5000.0)),
    (
      "tiles",
      [
        tile("cpu", "CPU", "20.5%", "占 12 核的 2%", [12.0, 18.0, 15.0, 22.0, 20.5]),
        tile("memory", "内存", "508 MB", "占 64 GB 的 1%", [480.0, 495.0, 500.0, 504.0, 508.0]),
        tile("disk", "磁盘", "↓ 2.9 MB/s", "↑ 13 KB/s", [9.0, 1.0, 1.2, 0.9, 2.9]),
        tile("net", "网络", "↓ 1.6 KB/s", "↑ 410 B/s", [0.8, 2.4, 1.1, 1.9, 1.6]),
      ],
    ),
    ("kinds", [obj([("key", str("chat")), ("label", str("对话"))]), obj([("key", str("station")), ("label", str("Station"))])]),
    (
      "groups",
      [
        obj([
          ("key", str("chat:c1")),
          ("kind", str("chat")),
          ("title", str("修一下登录")),
          ("kindText", str("对话")),
          ("chat", obj([("station", str("ws1/st1")), ("session", str("s1"))])),
          ("station", str("ws1/st1")),
          ("session", str("s1")),
          ("use", chat),
          (
            "processes",
            [
              process("p1", 4211.0, "claude", false, fx_use(12.0, 41.0e6, 0.0, 1.9e6, ("12.0%", "41 MB", "0 B/s", "1.9 MB/s"))),
              process("p2", 4290.0, "node", true, fx_use(13.9, 18.0e6, 0.0, 1.0e6, ("13.9%", "18 MB", "0 B/s", "1.0 MB/s"))),
            ],
          ),
        ]),
        obj([
          ("key", str("chat:c2")),
          ("kind", str("chat")),
          ("title", str("把发版日志按平台分开写清楚，再给每一条补上改前改后的截图")),
          ("kindText", str("对话")),
          ("chat", obj([("station", str("ws1/st1")), ("session", str("s2"))])),
          ("station", str("ws1/st1")),
          ("session", str("s2")),
          ("use", notes),
          ("processes", [process("p4", 5120.0, "claude", false, notes)]),
        ]),
        obj([
          ("key", str("station")),
          ("kind", str("station")),
          ("title", str("Station")),
          ("kindText", str("")),
          ("station", str("ws1/st1")),
          ("use", station),
          ("processes", [process("p3", 812.0, "stillfail", false, station)]),
        ]),
      ],
    ),
    (
      "stations",
      [
        obj([
          ("station", str("ws1/st1")),
          ("net", Json::boolean(true)),
          ("use", fx_use(20.5, 508.0e6, 1.6e3, 2.9e6, ("20.5%", "508 MB", "1.6 KB/s", "2.9 MB/s"))),
        ]),
      ],
    ),
    ("notes", []),
    ("basis", str("按 Activity Monitor 的口径：CPU 100% 是一个核")),
  ])
}

///|
/// 共享调试 as a fixture's mode has it (MBUI_FIXTURE=settings-adb-<off|unpaired|pairing|connected|failed|chats|idle>; ""
/// not lent).
let fx_adb : Ref[String] = Ref("")

///|
/// The core's `adbShare` for fx_adb: lent to Studio (ws1/st1) and how its adb holds the phone, the ports the app found.
fn fx_adb_share() -> Json {
  let lent = fn(adb : String, fields : Array[(String, Json)]) {
    obj(
      [
        ("sharing", Json::boolean(true)),
        ("station", str("ws1/st1")),
        ("phase", str("offered")),
        ("serial", str("127.0.0.1:37762")),
        ("adb", str(adb)),
        ("tunnels", Json::number(0.0)),
        ("connectPort", Json::number(41239.0)),
      ]..append(fields),
    )
  }
  match fx_adb.val {
    "unpaired" => lent("unpaired", [])
    "pairing" => lent("unpaired", [("pairPort", Json::number(37115.0))])
    "connected" => lent("connected", [("tunnels", Json::number(1.0))])
    "failed" =>
      lent("failed", [
        ("message", str("the phone did not reach adb: 无法连接手机上的 adb：Connection refused (os error 111)")),
        ("refusedPort", Json::number(41239.0)),
      ])
    // settings' 共享调试, its switch off: nothing granted
    "idle" => obj([("sharing", Json::boolean(false)), ("phase", str("off")), ("on", Json::boolean(false)), ("tunnels", Json::number(0.0))])
    // lent for chats' grants to two stations: Studio's adb holds the phone, the other's waits to be paired with it (as
    // a core from before it said the one it names at its top: the first)
    "second" =>
      lent("connected", [
        ("pairPort", Json::number(37115.0)),
        (
          "lends",
          Json::array([
            obj([("station", str("ws1/st1")), ("phase", str("offered")), ("adb", str("connected")), ("serial", str("127.0.0.1:37762")), ("tunnels", Json::number(1.0))]),
            obj([("station", str("ws1/st2")), ("phase", str("offered")), ("adb", str("unpaired")), ("serial", str("127.0.0.1:37715")), ("tunnels", Json::number(0.0))]),
          ]),
        ),
      ])
    // settings' 共享调试, its switch on: two chats granted it, one asking; lent to both their stations, Studio's adb
    // holding the phone and the other's waiting to be paired
    "chats" =>
      obj([
        ("sharing", Json::boolean(true)),
        ("station", str("ws1/st2")),
        ("phase", str("offered")),
        ("adb", str("unpaired")),
        ("on", Json::boolean(true)),
        ("tunnels", Json::number(0.0)),
        (
          "lends",
          Json::array([
            obj([("station", str("ws1/st1")), ("phase", str("offered")), ("adb", str("connected")), ("tunnels", Json::number(1.0))]),
            obj([("station", str("ws1/st2")), ("phase", str("offered")), ("adb", str("unpaired")), ("tunnels", Json::number(0.0))]),
          ]),
        ),
        (
          "grants",
          Json::array([
            obj([("station", str("ws1/st1")), ("id", str("p-1")), ("reason", str("装上刚编好的测试包，看首屏在折叠屏展开时排得对不对")), ("status", str("granted")), ("scope", str("chat"))]),
            obj([("station", str("ws1/st2")), ("id", str("p-2")), ("reason", str("录一段登录流程的视频")), ("status", str("granted")), ("scope", str("hour"))]),
            obj([("station", str("ws1/st1")), ("id", str("p-3")), ("reason", str("看通知权限弹窗的文案")), ("status", str("pending"))]),
          ]),
        ),
      ])
    _ => obj([("sharing", Json::boolean(false)), ("phase", str("idle")), ("tunnels", Json::number(0.0))])
  }
}

///|
/// MBUI_FIXTURE=newchat-machine: the sessions Studio's machine kept (as the core gives them: the parts of each line
/// apart too), their list open over the new chat: two runtimes, a few folders, still.fail's own among them, one of them
/// already going on in a chat.
pub fn fixture_machine_sessions(core : Core) -> Unit {
  let s = fn(id : String, runtime : String, title : String, where_ : String, day : String, when : String, session : String) {
    let label = if runtime == "claude" { "Claude Code" } else { "Codex" }
    let parts = where_.split("/").to_array()
    obj([
      ("id", str(id)),
      ("runtime", str(runtime)),
      ("title", str(title)),
      ("first", str(title)),
      ("where", str(where_)),
      ("folder", str(parts[parts.length() - 1].to_owned())),
      ("day", str(day)),
      ("when", str(when)),
      ("own", Json::boolean(where_.has_prefix("~/.stillfail/"))),
      ("meta", str(label + " · " + where_)),
      ("session", if session == "" { Json::null() } else { str(session) }),
    ])
  }
  let own = "~/.stillfail/sessions/ember/c-41f2/workspace"
  machine_sessions["ws1/st1"] = [
    s("m1", "codex", "检查线程并操作应用内浏览器", "~/Documents/GitHub/still.fail", "今天", "3 分钟前", ""),
    s("m2", "codex", "Use your image generation tool to make the app icon", own, "今天", "20 分钟前", ""),
    s("m3", "codex", "[财务] 建立全自动记账系统", "~/Documents/Codex/ledger", "今天", "1 小时前", "s-c2"),
    s("m4", "claude", "整理构建脚本，把 Windows 的打包也接进 CI", "~/Documents/GitHub/still.fail", "今天", "3 小时前", ""),
    s("m5", "codex", "Create PR for airbuild integration with the release workflow", "~/Documents/GitHub/still.fail", "昨天", "22:41", ""),
    s("m6", "claude", "确认沉星之序大地图解密知识锁", "~/Documents/Codex/game", "昨天", "15:02", ""),
    s("m7", "codex", "Use your image generation tool to draw the empty state", own, "昨天", "11:20", ""),
    s("m8", "claude", "Review the onboarding copy", "~/Documents/GitHub/still.fail", "星期二", "18:09", ""),
    s("m9", "codex", "把发票 PDF 按月份归档", "~/Documents/Codex/ledger", "10月20日", "09:31", ""),
  ]
  open_machine_sessions(core, "ws1/st1", "Studio")
}
