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
}

///|
let fx : SettingsFixture = { names: {}, restored: {}, version: 0 }

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
  match m {
    "settings" => "home"
    "settings-notify-off" => "home"
    "settings-station" => "station:ws1/st1"
    "settings-station-offline" => "station:ws1/st2"
    "settings-memory" => "memory:ws1/st1"
    "settings-memory-doc" => "memory-doc:ws1/st1#发布流程"
    "settings-profile" => "profile:ws1/st1#cc"
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
    fx_profile("cc", "Claude 主账号", "subscription", "green", "可用", "claude", "Claude 订阅", []),
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
      ("icon", str("glyph:desktop")),
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
        ]),
      ),
    ])
  } else {
    obj([
      ("station", str(address)),
      ("id", str(id)),
      ("name", str(renamed.unwrap_or("MBA"))),
      ("icon", str("glyph:laptop:teal")),
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
    "stations" => Some([fx_station("ws1/st1"), fx_station("ws1/st2")])
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
          ("setUp", Json::boolean(true)),
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
          ("stations", []),
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
      fx.names[text(p, "station")] = text(p, "name")
      fx.version += 1
      Some(Ok(obj([])))
    }
    "chat.archive" if field(p, "archived") is Some(False) => {
      fx.restored[text(p, "session")] = true
      fx.version += 1
      Some(Ok(obj([])))
    }
    "memory.get" => Some(Ok(fx_memory()))
    "profile.quota" | "profile.check" | "profile.put" => Some(Ok(obj([])))
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
