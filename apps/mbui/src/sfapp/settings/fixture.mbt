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
  /// the mode's page has no station (settings-first-station)
  mut none : Bool
  /// the subscription signing in (settings-profile-login)
  mut login : Bool
  /// the vault not set up on this device (settings-vault-off)
  mut vault_off : Bool
}

///|
let fx : SettingsFixture = {
  names: {},
  restored: {},
  version: 0,
  marks: {},
  auto: false,
  none: false,
  login: false,
  vault_off: false,
}

///|
/// A sheet a fixture's mode puts up over its page once it is drawn (mark, add, add-existing, add-command, env), and a
/// page's list to scroll to a block ("" none).
priv struct FixtureOpen {
  mut sheet : String
  mut list : String
  mut block : Int
  mut frames : Int
}

///|
let fixture_open : FixtureOpen = { sheet: "", list: "", block: 0, frames: 0 }

///|
/// The new connect's step its fixture shows (MBUI_FIXTURE=settings-new-connect: team; -platform, -scan: Feishu's).
let fx_connect_step : Ref[String] = Ref("team")

///|
/// The made-up settings as a run starts (reset): none changed, no sheet or scroll to put up.
fn fixture_reset() -> Unit {
  fx.names.clear()
  fx.restored.clear()
  fx.version = 0
  fx.marks.clear()
  fx.auto = false
  fx.none = false
  fx.login = false
  fx.vault_off = false
  fixture_open.sheet = ""
  fixture_open.list = ""
  fixture_open.block = 0
  fixture_open.frames = 0
  fx_connect_step.val = "team"
}

///|
/// How often the made-up settings changed: added to the fixture's own version.
pub fn fixture_version() -> Int {
  fx.version
}

///|
/// The page a fixture's mode opens (MBUI_FIXTURE=settings-<page>[-dark]), by the name route_of takes.
pub fn fixture_page(mode : String) -> String {
  let m = if mode.has_suffix("-dark") {
    mode.unsafe_substring(start=0, end=mode.length() - 5)
  } else {
    mode
  }
  // a sheet up over the page, or the page scrolled down (fixture_open)
  let up = fn(sheet : String, list : String, block : Int) {
    fixture_open.sheet = sheet
    fixture_open.list = list
    fixture_open.block = block
    fixture_open.frames = 0
  }
  match m {
    "settings-station-mark" => up("mark", "", 0)
    "settings-station-env" => up("env", "", 0)
    "settings-station-lower" => up("", "settings/station/ws1/st1", 6)
    "settings-station-versions" => up("", "settings/station/ws1/st1", 10)
    "settings-stations-add" => up("add", "", 0)
    "settings-stations-existing" => up("add-existing", "", 0)
    "settings-stations-command" => up("add-command", "", 0)
    "settings-first-station" => fx.none = true
    "settings-profile-menu" => up("profile-menu", "", 0)
    "settings-profile-lower" => up("", "settings/profile/ws1/st1/cc", 4)
    "settings-profile-login" => {
      fx.login = true
      up("", "settings/profile/ws1/st1/cc", 2)
    }
    "settings-connect-menu" => up("connect-menu", "", 0)
    "settings-connect-mode" => up("connect-mode", "", 0)
    "settings-vault-off" => fx.vault_off = true
    "settings-vault-words" => recovery_words["ws1"] = fx_words()
    "settings-vault-add" => up("vault-add", "", 0)
    "settings-vault-editor" => up("vault-editor", "", 0)
    "settings-vault-recover" => up("vault-recover", "", 0)
    "settings-add-people" => up("add-people", "", 0)
    "settings-workspace-mark" => up("workspace-mark", "", 0)
    "settings-new-connect-platform" => fx_connect_step.val = "platform"
    "settings-new-connect-scan" => fx_connect_step.val = "feishuScan"
    _ => fx_connect_step.val = "team"
  }
  match m {
    "settings" => "home"
    "settings-station-mark" | "settings-station-env" | "settings-station-lower" | "settings-station-versions" =>
      "station:ws1/st1"
    "settings-stations-add" | "settings-stations-existing" | "settings-stations-command" | "settings-first-station" =>
      "stations"
    "settings-adb" => "adb:ws1/st1"
    "settings-profile-menu" | "settings-profile-lower" | "settings-profile-login" => "profile:ws1/st1#cc"
    "settings-new-profile" => "new-profile:ws1/st1"
    "settings-connect-menu" | "settings-connect-mode" => "connect:ws1/st1#k1"
    "settings-connect-run" => "connect-run:ws1/st1#k1"
    "settings-new-connect" | "settings-new-connect-platform" | "settings-new-connect-scan" => "new-connect:ws1/st1"
    "settings-slack-app" => "slack-app:ws1/st1#k1"
    "settings-vault-off" | "settings-vault-words" | "settings-vault-add" | "settings-vault-editor" => "vault"
    "settings-vault-recover" => "vault"
    "settings-vault-item" => "vault-item:v1#it1"
    "settings-decisions" => "decisions-settings"
    "settings-completion" => "completion"
    "settings-policy" => "policy:ws1/st1"
    "settings-bars" => "bars"
    "settings-kept" => "kept"
    "settings-changelog" => "changelog"
    "settings-prices" => "prices:7"
    "settings-run" => "run:ws1/st1#s-c1"
    "settings-add-people" | "settings-workspace-mark" => "workspace"
    "settings-notify-off" => "home"
    "settings-station" => "station:ws1/st1"
    "settings-station-offline" => "station:ws1/st2"
    "settings-memory" => "memory:ws1/st1"
    "settings-memory-doc" => "memory-doc:ws1/st1#发布流程"
    "settings-profile" => "profile:ws1/st1#cc"
    "settings-me-reading" => "me"
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
        [
          obj([("label", str("5 小时")), ("usedPercent", Json::number(38.0)), ("mark", str("5H")), ("left", Json::number(62.0)), ("level", str("ok")), ("refills", str("2 小时后恢复"))]),
          obj([("label", str("本周")), ("usedPercent", Json::number(81.0)), ("mark", str("W")), ("left", Json::number(19.0)), ("level", str("amber")), ("refills", str("星期一恢复"))]),
        ],
      ),
      ("checkedAt", Json::number(0.0)),
      ("time", obj([("checkedAt", stamp_of("3 分钟前"))])),
    ]),
  }
  for kv in more {
    p[kv.0] = kv.1
  }
  Json::object(p)
}

///|
fn fx_profiles() -> Array[Json] {
  [
    fx_profile("cc", "Claude 主账号", "subscription", "green", "可用", "claude", "Claude 订阅", [
      ("share", obj([("id", str("sh1")), ("role", str("host")), ("host", str("st1")), ("users", ["st2"])])),
      ("fast", Json::boolean(false)),
      ("backgroundOnMessage", Json::boolean(true)),
      ("workspaces", ["ws2"]),
      ("loginCommand", str("claude setup-token")),
      (
        "login",
        if fx.login {
          obj([
            ("profile", str("cc")),
            ("runtime", str("claude")),
            ("state", str("needs_code")),
            ("url", str("https://claude.example/oauth/authorize")),
            ("startedAt", Json::number(0.0)),
            ("expiresAt", Json::number(0.0)),
          ])
        } else {
          Json::null()
        },
      ),
    ]),
    fx_profile("cx", "ChatGPT 团队", "subscription", "green", "可用", "chatgpt", "ChatGPT 订阅", [("modelsText", str("1 个模型"))]),
    fx_profile("k2", "备用 key", "anthropic-api", "red", "没能使用", "key", "API key", [
      ("trouble", obj([("title", str("key 已失效")), ("detail", str("服务商拒绝了这个 key")), ("next", str("")), ("action", str("key")), ("label", str(""))])),
      ("quota", obj([("state", str("unsupported")), ("windows", []), ("checkedAt", Json::number(0.0))])),
      ("usedBy", []),
    ]),
  ]
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
    ("modeText", str(mode_label(mode))),
    ("modeShort", str("")),
    ("runtimeText", str("Claude Code")),
    ("runText", str("")),
    ("modelName", str("Opus 5.5")),
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
      ("models", []),
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
          ("processesText", str("2 个 agent 进程 · claude 1.2 GB")),
          ("slackApps", []),
          ("drive", obj([("roots", ["~/项目", "~/文档"]), ("all", Json::boolean(false))])),
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
              ]),
              obj([
                ("id", str("codex")),
                ("name", str("Codex")),
                ("installed", Json::boolean(false)),
                ("newer", Json::boolean(false)),
                ("updatable", Json::boolean(true)),
                ("state", str("idle")),
                ("checkedAt", Json::number(1.0)),
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
          ("sharing", Json::boolean(true)),
          (
            "machineLogins",
            [
              obj([("runtime", str("codex")), ("installed", Json::boolean(true)), ("loggedIn", Json::boolean(true)), ("email", str("lin@example.com")), ("plan", str("plus")), ("usable", Json::boolean(true)), ("text", str("")), ("offered", Json::boolean(true))]),
            ],
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
      ("summary", str("离线 · 2 天前")),
      ("face", str("offline")),
      ("online", Json::boolean(false)),
      ("link", obj([("state", str("offline"))])),
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
    ("max", Json::number(27.0)),
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
          ("share", obj([("id", str("sh1")), ("role", str("host")), ("host", str("st1"))])),
        ]),
        obj([
          ("name", str("周报")),
          ("description", str("写周报时用的格式")),
          ("project", Json::boolean(false)),
          ("builtin", Json::boolean(false)),
          ("text", str("每周五下午写。")),
          ("size", str("1 KB")),
        ]),
        obj([("name", str("pdf")), ("description", str("读写 PDF")), ("project", Json::boolean(false)), ("builtin", Json::boolean(true)), ("text", str(""))]),
        obj([("name", str("xlsx")), ("description", str("读写表格")), ("project", Json::boolean(false)), ("builtin", Json::boolean(true)), ("text", str(""))]),
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
    "workspace" =>
      Some(
        obj([
          ("id", str("ws1")),
          ("name", str("星火工作室")),
          ("role", str("owner")),
          (
            "members",
            [
              me,
              obj([("sub", str("u2")), ("email", str("ana@example.com")), ("name", str("Ana")), ("role", str("admin"))]),
              obj([("sub", str("u3")), ("email", str("zhou@example.com")), ("name", str("周")), ("role", str("member"))]),
            ],
          ),
          ("stations", [obj([("id", str("st1")), ("name", str("Studio"))]), obj([("id", str("st2")), ("name", str("MBA"))])]),
          ("invitations", [obj([("id", str("i1")), ("role", str("member")), ("email", str("qin@example.com")), ("time", obj([("expires_at", stamp_of("", until="6 天后"))]))])]),
          ("added", [obj([("email", str("he@example.com")), ("role", str("member"))])]),
          ("relays", []),
        ]),
      )
    "stations" => if fx.none { Some([]) } else { Some([fx_station("ws1/st1"), fx_station("ws1/st2")]) }
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
    "adbShare" =>
      Some(obj([("sharing", Json::boolean(false)), ("phase", str("idle")), ("tunnels", Json::number(0.0))]))
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
    "profileFlow" => Some(fx_profile_flow())
    "pick" if text(Some(Json::object(params)), "of").has_prefix("session:") => Some(fx_session_pick())
    "connectFlow" if fx_connect_step.val != "team" => Some(fx_feishu_flow(fx_connect_step.val))
    "connectFlow" =>
      Some(
        obj([
          ("step", str("team")),
          ("title", str("Slack 工作区")),
          ("back", str("close")),
          ("number", Json::number(1.0)),
          ("total", Json::number(4.0)),
          ("mobile", Json::boolean(true)),
          ("adding", Json::boolean(false)),
          ("settings", obj([("name", str("still.fail")), ("description", str("Coding agent in your threads (still.fail)"))])),
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
        ]),
      )
    "vaultUses" =>
      Some(
        obj([
          (
            "uses",
            [
              obj([("at", stamp_of("昨天")), ("session", str("s-c1")), ("station", str("st1")), ("chatTitle", str("整理发布清单")), ("mode", str("proxy")), ("hosts", ["api.github.com"]), ("command", str("git push origin main"))]),
              obj([("at", stamp_of("3 天前")), ("session", str("s-c4")), ("station", str("st1")), ("chatTitle", str("给设置页加一个深色模式开关")), ("mode", str("proxy")), ("hosts", []), ("denied", Json::boolean(true))]),
            ],
          ),
        ]),
      )
    "decisionForm" =>
      Some(obj([("enabled", Json::boolean(true)), ("model", str("gpt-6-mini")), ("dirty", Json::boolean(false)), ("pending", Json::boolean(false))]))
    "policyForm" =>
      Some(obj([("policy", str("做完、没有待办的对话归档；还在等人回复或有后续计划的留下。")), ("options", []), ("dirty", Json::boolean(false)), ("pending", Json::boolean(false))]))
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
                          obj([("version", Json::number(1.0)), ("versionName", str("0.1.1288")), ("text", []), ("lines", [obj([("kind", str("fix")), ("label", str("修复")), ("text", str("对话列表偶尔重复显示同一行"))])]), ("has", Json::boolean(true)), ("note", str("")), ("mine", Json::boolean(true))]),
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
        obj([
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
              ]),
              obj([
                ("station", str("ws1/st1")),
                ("stationName", str("Studio")),
                ("connect", fx_connect("k2", "值班机器人", "error", "连接失败", "single-session")),
                ("sessions", []),
                ("candidates", []),
                ("running", Json::number(0.0)),
              ]),
            ],
          ),
          ("wait", obj([("reading", Json::boolean(false)), ("failing", []), ("empty", Json::boolean(false))])),
        ]),
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
          ("signers", Json::number(2.0)),
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
                (
                  "devices",
                  [
                    obj([("id", str("d1")), ("kind", str("app")), ("label", str("这台手机")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(true)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false))]),
                    obj([("id", str("d2")), ("kind", str("web")), ("label", str("")), ("signs", Json::boolean(false)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("daysLeft", Json::number(4.0)), ("renewSoon", Json::boolean(true)), ("recent", Json::boolean(false))]),
                  ],
                ),
              ]),
              obj([
                ("sub", str("u2")),
                ("email", str("ana@example.com")),
                ("name", str("Ana")),
                ("role", str("admin")),
                ("you", Json::boolean(false)),
                ("devices", [obj([("id", str("d3")), ("kind", str("app")), ("label", str("MacBook")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false))])]),
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
                ("chat", str("c1")),
                ("mode", str("proxy")),
                ("reason", str("要把发布清单推到仓库")),
                ("command", str("git push origin main")),
                ("hosts", ["api.github.com"]),
                ("at", Json::number(0.0)),
              ]),
            ],
          ),
          ("refused", []),
        ]),
      )
    "vaultItems" =>
      Some(
        obj([
          ("vault", str("v1")),
          ("name", str("林的库")),
          ("open", Json::boolean(false)),
          (
            "items",
            [
              obj([("id", str("it1")), ("version", Json::number(1.0)), ("at", Json::number(0.0)), ("name", str("GitHub token")), ("kind", str("token")), ("listed", Json::boolean(true)), ("modes", ["proxy"]), ("hosts", ["api.github.com"]), ("lastUse", obj([("at", stamp_of("昨天")), ("session", str("s-c1")), ("mode", str("proxy")), ("hosts", [])]))]),
              obj([("id", str("it2")), ("version", Json::number(1.0)), ("at", Json::number(0.0)), ("name", str("部署机")), ("kind", str("ssh_key")), ("listed", Json::boolean(true)), ("modes", ["ssh"]), ("hosts", [])]),
              obj([("id", str("it3")), ("version", Json::number(1.0)), ("at", Json::number(0.0)), ("kind", str("login")), ("listed", Json::boolean(false)), ("modes", []), ("hosts", [])]),
            ],
          ),
        ]),
      )
    "profiles" => {
      let list = fx_profiles().map(fn(p) {
        obj([
          ("key", str("ws1/st1/" + text(Some(p), "id"))),
          ("group", str(text(Some(p), "group"))),
          ("groupTitle", str(text(Some(p), "groupTitle"))),
          ("station", str("ws1/st1")),
          ("stationId", str("st1")),
          ("stationName", str("Studio")),
          ("profile", p),
          ("shared", Json::boolean(false)),
          ("host", str("st1")),
          ("hostName", str("Studio")),
          ("hostOnline", Json::boolean(true)),
          ("usable", Json::boolean(true)),
          ("where", str("只在 Studio")),
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
              obj([("station", str("ws1/st1")), ("stationId", str("st1")), ("stationName", str("Studio")), ("online", Json::boolean(true)), ("profileId", str(text(Some(p), "id"))), ("role", str("host")), ("about", str("")), ("usable", Json::boolean(true)), ("checkText", str("可用")), ("checkTone", str("green")), ("usedBy", Json::number(1.0))]),
            ],
          ),
          ("editable", Json::boolean(true)),
          ("canShare", Json::boolean(true)),
        ])
      })
      Some(obj([("items", Json::array(list)), ("wait", obj([("reading", Json::boolean(false)), ("failing", []), ("empty", Json::boolean(false))]))]))
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
      Some(obj([("on", Json::boolean(on)), ("asked", Json::boolean(true)), ("push", Json::boolean(false)), ("show", [])]))
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
          ("members", [me]),
          ("devices", []),
          ("stations", []),
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
      fx.version += 1
      Some(Ok(obj([])))
    }
    "chat.archive" if field(p, "archived") is Some(False) => {
      fx.restored[text(p, "session")] = true
      fx.version += 1
      Some(Ok(obj([])))
    }
    "memory.get" => Some(Ok(fx_memory()))
    "cache.usage" =>
      Some(
        Ok(
          obj([
            (
              "chats",
              [
                obj([("station", str("ws1/st1")), ("thread", Json::number(1.0)), ("title", str("整理发布清单")), ("sessions", ["s-c1"]), ("bytes", Json::number(2400000.0))]),
                obj([("station", str("ws1/st1")), ("thread", Json::number(4.0)), ("title", str("给设置页加一个深色模式开关")), ("sessions", ["s-c4"]), ("bytes", Json::number(860000.0))]),
                obj([("station", str("ws1/st2")), ("thread", Json::number(3.0)), ("title", str("夜里的构建又失败了")), ("sessions", ["s-c3"]), ("bytes", Json::number(41000.0))]),
              ],
            ),
          ]),
        ),
      )
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
      fx.version += 1
      Some(Ok(obj([])))
    }
    "software.check" | "software.update" | "software.channel" | "search.setPersonal" | "permissions.request" =>
      Some(Ok(obj([])))
    "agentEnv.form.open" | "agentEnv.form.edit" | "agentEnv.form.drop" | "agentEnv.form.save" => Some(Ok(obj([])))
    "profile.quota" | "profile.check" | "profile.put" => Some(Ok(obj([])))
    // the drafts' forms (a new profile's, a new connect's, the decisions' and the archive policy's), opened and edited
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
/// workspace's), not a signer.
fn waiting_lock(mode : String) -> Json {
  let mode = if mode.has_suffix("-dark") { mode.unsafe_substring(start=0, end=mode.length() - 5) } else { mode }
  let pair = match mode {
    "lock-finding" => obj([("state", str("finding"))])
    "lock-code" => obj([("state", str("code")), ("left", Json::number(3.0))])
    "lock-wrong" => obj([("state", str("wrong")), ("left", Json::number(2.0))])
    "lock-checking" => obj([("state", str("checking")), ("left", Json::number(3.0))])
    "lock-none" => obj([("state", str("none"))])
    "lock-failed" => obj([("state", str("failed")), ("error", str("配对超时"))])
    _ => Json::null()
  }
  let failed = if mode == "lock-refused" { "station 不在线" } else { "" }
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
        ("confirmed", Json::boolean(false)),
        ("asked", Json::boolean(true)),
        ("waiting", Json::boolean(true)),
        ("failed", str(failed)),
        ("pair", pair),
      ]),
    ),
    (
      "requests",
      [
        obj([("device", str("d-me")), ("sub", str("u1")), ("email", str("lin@example.com")), ("name", str("林")), ("kind", str("app")), ("label", str("still.fail mbui Android · OPPO PLP110")), ("code", str("Q4K-7PM")), ("created_at", Json::number(0.0)), ("yours", Json::boolean(true)), ("time", obj([("created_at", stamp_of("1 分钟前"))]))]),
        obj([("device", str("d9")), ("sub", str("u2")), ("email", str("ana@example.com")), ("name", str("Ana")), ("kind", str("app")), ("label", str("Pixel 9")), ("code", str("482 917")), ("created_at", Json::number(0.0)), ("yours", Json::boolean(false)), ("time", obj([("created_at", stamp_of("2 分钟前"))]))]),
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
          ("devices", [obj([("id", str("d1")), ("kind", str("app")), ("label", str("still.fail Android · OPPO PLP110")), ("signs", Json::boolean(true)), ("older", Json::boolean(false)), ("mine", Json::boolean(false)), ("renewSoon", Json::boolean(false)), ("recent", Json::boolean(false))])]),
        ]),
      ],
    ),
    ("stations", []),
    ("renew", []),
  ])
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
    "env" => open_agent_env(core, "ws1/st1")
    "profile-menu" => {
      let p = fx_profiles()[0]
      open_profile_menu(core, "ws1/st1", Some(p))
    }
    "connect-menu" | "connect-mode" => {
      let item = obj([
        ("station", str("ws1/st1")),
        ("connect", fx_connect("k1", "星火助手", "online", "在线", "multi-session")),
        ("candidates", []),
        ("running", Json::number(2.0)),
      ])
      if what == "connect-menu" {
        open_connect_menu(core, here, "ws1/st1", Some(item))
      } else {
        open_mode(core, "ws1/st1", Some(item))
      }
    }
    "vault-add" => open_vault_add(core, here)
    "vault-editor" => open_vault_editor(core, "ws1", "v1", None, kind="token")
    "vault-recover" => open_vault_recover(core, "ws1")
    "add-people" => open_add_people(core, here, workspace_view(core, here).value)
    "workspace-mark" => open_mark_pick(core, "星火工作室", "", "glyph:rocket:orange", "", fn(_, _, _) {  })
    "add" | "add-existing" | "add-command" => {
      open_add_station(core, here, ["st1", "st2"], existing=what == "add-existing")
      if what == "add-command" {
        adding.made = Some(
          (
            "curl -fsSL https://still.fail/install.sh | sh -s -- 4f7c2a9e1b",
            "stillfail station enroll https://still.fail 4f7c2a9e1b",
          ),
        )
      }
    }
    _ => ()
  }
}

///|
/// A page's list scrolled as a fixture's mode asks (its first frames), by its key.
fn fixture_scroll(c : @ui.Ctx, key : String) -> Unit {
  if fixture_open.list == key && fixture_open.frames < 4 {
    fixture_open.frames += 1
    // (the list asks for the frames its scroll takes)
    c.list_scroll_to(key, fixture_open.block)
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
/// A new profile's draft at its first step (`profileFlow`): the providers by group.
fn fx_profile_flow() -> Json {
  let provider = fn(id : String, name : String, group : String, runtime : String, mark : String) {
    obj([("id", str(id)), ("name", str(name)), ("group", str(group)), ("kind", str("api-provider")), ("runtime", str(runtime)), ("mark", str(mark))])
  }
  obj([
    ("step", str("pick")),
    ("station", str("ws1/st1")),
    ("title", str("选择服务商")),
    ("hint", str("订阅和 API key 都在这里添加，选择服务商开始")),
    (
      "groups",
      [
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
      ],
    ),
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
/// A chat's agent as it runs and as it is to run (`pick` of `session:<key>`, MBUI_FIXTURE=settings-run): its effort
/// raised to high, the rest as it was.
fn fx_session_pick() -> Json {
  let model = obj([("model", str("claude-opus-5-5")), ("name", str("Opus 5.5")), ("maker", obj([("id", str("anthropic"))]))])
  obj([
    ("value", obj([("model", str("claude-opus-5-5")), ("runtime", str("claude"))])),
    ("draft", obj([("model", str("claude-opus-5-5")), ("runtime", str("claude")), ("effort", str("high"))])),
    ("option", str("claude-opus-5-5")),
    ("options", [model]),
    ("maker", obj([("id", str("anthropic"))])),
    ("modelText", str("Opus 5.5")),
    ("efforts", ["low", "medium", "high"]),
    ("was", ["Opus 5.5", "默认深度", "自动 · Claude 主账号"]),
    ("becomes", ["Opus 5.5", "high", "自动 · Claude 主账号"]),
    ("accountText", str("自动分配")),
    ("accountNote", str("Claude 主账号 · 5 小时窗口已用 62%")),
    ("accounts", [obj([("id", str("p1")), ("name", str("Claude 主账号")), ("line", str("订阅 · 只在 Studio"))])]),
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
