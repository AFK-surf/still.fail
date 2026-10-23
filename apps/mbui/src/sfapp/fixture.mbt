// Made-up chats in the core's own shapes (ChatsView and the rest), for the app with no core: screenshots that are
// the same on every run (scripts/shots.sh home, web-home), and the web's preview. Every word here is made up.
//
// `mode`: "home" (signed in, the chats), "signin" (signed out), "loading" (the list being read), "empty" (a
// workspace with nothing in it yet); "chat" (the first row's chat open: chat_fixture.mbt), "chat-loading" (it being
// read), "chat-long" (thousands of messages in it); "long" (the chats and many weeks more of them: for flinging,
// scripts/android.sh fling-test).

///|
priv struct Fixture {
  mode : String
  mut workspace : String
  /// the theme chosen (the prefs' `appearance`): light unless the mode ends in -dark or MBUI_DARK=1, so that
  /// screenshots do not follow the machine's own
  mut appearance : String
  archived : Map[String, Bool]
  filters : Map[String, String]
  /// the faces chosen (the prefs' `fonts`), and those whose files the core has (fonts_fixture.mbt)
  fonts : Map[String, String]
  fonts_fetched : Map[String, Bool]
  mut version : Int
  /// the first row's chat: how many older pages have come in
  mut older : Int
  /// "home-motion": how far the list's changes have gone (a chat with news to the top, a new chat, one archived,
  /// a mark come)
  mut step : Int
}

///|
fn agent(maker : String, runtime : String) -> Json {
  let a : Map[String, Json] = {
    "runtime": Json::string(runtime),
    "agentText": Json::string(maker + " · " + runtime),
  }
  if maker != "" {
    a["maker"] = { "id": Json::string(maker), "name": Json::string(maker) }
  }
  Json::object(a)
}

///|
fn person(id : String, name : String, mine : Bool) -> Json {
  {
    "id": Json::string(id),
    "name": Json::string(name),
    "email": Json::string(id),
    "via": "cloud",
    "shown": {
      "name": Json::string(name),
      "display": Json::string(if mine { "你" } else { name }),
      "mine": Json::boolean(mine),
    },
  }
}

///|
/// A row: its id and title, its station, when, and the rest as the view gives it.
fn row(
  id : String,
  title : String,
  station : String,
  ago : String,
  more : Map[String, Json],
) -> Json {
  let r : Map[String, Json] = {
    "id": Json::string(id),
    "session": Json::string("s-" + id),
    "thread": Json::number(id.length().to_double()),
    "title": Json::string(title),
    "agents": [agent("anthropic", "claude")],
    "unread": false,
    "mine": true,
    "lastActiveAt": 0,
    "station": Json::string(station),
    "stationName": Json::string(if station == "ws1/st1" { "Studio" } else { "MBA" }),
    "stationIcon": Json::string(
      if station == "ws1/st1" {
        "glyph:desktop"
      } else {
        "glyph:laptop:teal"
      },
    ),
    "time": { "lastActiveAt": { "at": 0, "ago": Json::string(ago), "full": "", "until": "", "past": true } },
  }
  for k, v in more {
    r[k] = v
  }
  Json::object(r)
}

///|
let me : Json = person("lin@example.com", "林", true)

///|
let ana : Json = person("ana@example.com", "Ana", false)

///|
let zhou : Json = person("zhou@example.com", "周", false)

///|
fn last(text : String) -> Json {
  { "seq": 1, "authorKind": "agent", "author": "a", "text": Json::string(text), "createdAt": 0, "preview": Json::string(text) }
}

///|
/// The web's demo's chats (ember web/src/demo/fixtures.ts startingChats), its one station's, as its core lists them:
/// MBUI_FIXTURE=webdemo, the wide frame beside the web's story app-chat with the same chats (their people's pictures
/// letters here).
fn webdemo_days() -> Array[Json] {
  let lin = person("lin@acme.dev", "林晓", false)
  let chen = person("chen@acme.dev", "陈默", false)
  let zhou = person("zhou@acme.dev", "周宁", false)
  let one = fn(id, title, ago, more : Map[String, Json]) {
    let r = row(id, title, "ws1/st1", ago, more)
    match r {
      Object(m) => {
        m.remove("stationIcon")
        Json::object(m)
      }
      _ => r
    }
  }
  [
    {
      "label": "今天",
      "items": [
        one("safari", "把那个弄一下", "1 分钟前", {
          "last": last("还是不行"),
          "people": [lin, chen],
          "creator": { "id": "lin@acme.dev", "name": "林晓", "via": "cloud" },
        }),
        one("csv", "订单导出支持 CSV", "26 分钟前", {
          "unread": true,
          "tone": "done",
          "last": last("做好了：导出按当前筛选条件走流式写出，10 万行大约 2.3 秒，已合进 main（a3f9c21）。"),
          "agents": [agent("openai", "codex")],
          "people": [zhou],
        }),
        one("deps", "每周依赖升级", "58 分钟前", {
          "state": "block",
          "tone": "alert",
          "last": last("其余 23 个包都升好了，测试通过。只剩 React Router 8：它改了 loader 的写法，要动 14 个路由文件。这周要一起升吗？"),
          "people": [chen],
        }),
        one("p99", "排查 API p99 变慢", "20 小时前", {
          "last": last("罪魁是 orders 表少了 (user_id, created_at) 联合索引：上周的分页改动让查询走了全表扫描。"),
          "people": [lin],
        }),
      ],
    },
    {
      "label": "昨天",
      "items": [one("docs", "补一下部署文档", "26 小时前", { "last": last("谢谢，文档看过了"), "people": [chen] })],
    },
  ]
}

///|
/// The chats of the first workspace, newest first, by day.
fn fixture_days(f : Fixture) -> Array[Json] {
  if f.mode == "webdemo" {
    return webdemo_days()
  }
  let today = [
    row("c1", "整理发布清单", "ws1/st1", "2 分钟前", {
      "state": "run",
      "tone": "busy",
      "last": last("正在核对第三项：安装包的签名"),
      "agents": [agent("anthropic", "claude"), agent("openai", "codex")],
    }),
    row("c2", "首页的列表改成按天分组", "ws1/st1", "8 分钟前", {
      "unread": true,
      "tone": "wait",
      "decision": { "seq": 3, "options": [], "text": "奏 · 分组的标题用相对日期还是具体日期？" },
      "people": [me, ana],
      "creator": { "id": "lin@example.com", "name": "林", "via": "cloud" },
    }),
    row("c3", "夜里的构建又失败了", "ws1/st2", "15 分钟前", {
      "state": "failed",
      "tone": "alert",
      "stateText": "要你帮忙：测试机的磁盘满了，要不要清理旧的缓存？",
      "unread": true,
    }),
    row("c4", "给设置页加一个深色模式开关", "ws1/st1", "40 分钟前", {
      "unread": true,
      "tone": "done",
      "stateText": "做完了：开关和三处颜色都改好了",
      "agents": [agent("deepseek", "dsh")],
    }),
    row("c5", "盯着 CI，绿了告诉我", "ws1/st2", "1 小时前", {
      "stateText": "监控中：每 5 分钟看一次主干的构建",
      "stateAbout": 12,
      "watch": { "text": "监控中：主干构建", "ask": "它会在归档里继续盯着。" },
    }),
  ]
  let yesterday = [
    row("c6", "和 Ana 一起看新版的引导页", "ws1/st1", "昨天 21:14", {
      "tone": "other",
      "last": last("Ana：第二屏的插画可以再小一点"),
      "people": [ana, me, zhou],
      "creator": { "id": "ana@example.com", "name": "Ana", "via": "cloud" },
    }),
    row("c7", "Slack 里问的报销流程", "ws1/st2", "昨天 18:02", {
      "connect": "slack-1",
      "originText": "Slack · 星火 · #行政",
      "last": last("已经把三个步骤整理成一页文档"),
    }),
    row("c8", "把旧的截图都换成新的", "ws1/st1", "昨天 10:30", {
      "settled": true,
      "archivable": true,
      "stateText": "做完了",
    }),
  ]
  let earlier = [
    row("c9", "迁移数据库的演练", "ws1/st2", "星期三", {
      "offline": "MBA 离线",
      "last": last("演练到第二步时 MBA 断开了"),
      "agents": [agent("anthropic", "claude"), agent("openai", "codex"), agent("deepseek", "dsh"), agent("qwen", "dsh"), agent("kimi", "dsh")],
    }),
    row("c10", "周报的模板", "ws1/st1", "星期三", {
      "last": last("模板放在共享文件夹的第一层"),
      "agents": [agent("gemini", "dsh")],
    }),
  ]
  if f.mode == "home-motion" {
    // 1: news in 盯着 CI, which goes to the top; 2: a new chat comes; 3: one archived goes; 4: a mark comes
    if f.step >= 1 {
      let ci = today.remove(4)
      today.insert(
        0,
        row("c5", "盯着 CI，绿了告诉我", "ws1/st2", "刚刚", {
          "unread": true,
          "tone": "done",
          "last": last("CI 绿了：主干 #812 的检查都过了"),
        }),
      )
      ignore(ci)
    }
    if f.step >= 2 {
      today.insert(
        0,
        row("c11", "看一下新的崩溃报告", "ws1/st1", "刚刚", {
          "state": "run",
          "tone": "busy",
          "last": last("正在读第一份报告"),
        }),
      )
    }
    if f.step >= 3 {
      f.archived["c8"] = true
    }
    if f.step >= 4 {
      let i = today.search_by(fn(r) { text(Some(r), "id") == "c4" }).unwrap()
      today[i] = row("c4", "给设置页加一个深色模式开关", "ws1/st1", "刚刚", {
        "unread": true,
        "tone": "alert",
        "stateText": "要你帮忙：深色模式下图标看不清，要不要换一套？",
        "agents": [agent("deepseek", "dsh")],
      })
    }
  }
  let keep = fn(items : Array[Json]) -> Json {
    Json::array(items.filter(fn(r) { !f.archived.contains(text(Some(r), "id")) }))
  }
  let days : Array[Json] = [
    { "daysAgo": 0, "at": 0, "label": "今天", "items": keep(today) },
    { "daysAgo": 1, "at": 0, "label": "昨天", "items": keep(yesterday) },
    { "daysAgo": 4, "at": 0, "label": "星期三", "items": keep(earlier) },
  ]
  if f.mode == "long" {
    // weeks more, six chats a day, every word made up
    let topics = ["例会的记录", "接口的命名", "图标的尺寸", "崩溃的日志", "发布的说明", "测试的清单"]
    let states = ["做完了", "等你回复", "监控中：每小时看一次", "写到一半", "要你帮忙看一眼", "已经交给评审"]
    for d in 0..<40 {
      let items = Array::makei(6, fn(k) {
        let n = d * 6 + k + 11
        row("c\{n}", "第 \{n} 个：" + topics[k], if k % 2 == 0 { "ws1/st1" } else { "ws1/st2" }, "\{d + 5} 天前", {
          "stateText": Json::string(states[(d + k) % 6]),
        })
      })
      days.push({ "daysAgo": Json::number((d + 5).to_double()), "at": 0, "label": Json::string("\{d + 5} 天前"), "items": keep(items) })
    }
  }
  days
}

///|
fn fixture_chats(f : Fixture, params : Map[String, Json]) -> Json? {
  let scope = match params.get("scope") {
    Some(String(s)) => s
    _ => ""
  }
  let stations : Json = if f.mode == "webdemo" {
    [{ "id": "ws1/st1", "name": "Studio" }]
  } else {
    [{ "id": "ws1/st1", "name": "Studio" }, { "id": "ws1/st2", "name": "MBA" }]
  }
  if f.mode == "loading" {
    return None
  }
  let mine = params.get("mine") is Some(True)
  let watching = params.get("watching") is Some(True)
  let days = if scope == "ws1" && f.mode != "empty" && !watching {
    let all = fixture_days(f)
    if mine {
      // the viewer's: those they are in
      all.map(fn(d) {
        let items = match field(Some(d), "items") {
          Some(Array(a)) =>
            a.filter(fn(r) {
              match field(Some(r), "people") {
                Some(Array(ps)) => ps.iter().any(fn(p) { flag(field(Some(p), "shown"), "mine") })
                _ => true
              }
            })
          _ => []
        }
        let o : Map[String, Json] = {
          "label": Json::string(text(Some(d), "label")),
          "items": Json::array(items),
        }
        Json::object(o)
      })
    } else {
      all
    }
  } else {
    []
  }
  let empty = days.iter().all(fn(d) { items(Some(d), "items").length() == 0 })
  Some({
    "me": { "email": "lin@example.com" },
    "stations": if scope == "ws1" { stations } else { [] },
    "loading": false,
    "days": Json::array(days),
    "leading": "agents",
    "note": { "reading": false, "failing": [], "empty": Json::boolean(empty) },
    // the stations at a glance (Station's place in the bar): Studio online, MBA not (the web's demo: its one, online)
    "glyph": if scope == "ws1" && f.mode != "webdemo" {
      { "online": 1, "dim": 1, "failing": 0, "working": 0, "connecting": 0, "label": "1 台在线" }
    } else {
      { "online": 1, "dim": 0, "failing": 0, "working": 0, "connecting": 0, "label": "1 台在线" }
    },
  })
}

///|
fn fixture_topic(f : Fixture, name : String, params : Map[String, Json]) -> Topic {
  fix_tick(f)
  let value = fixture_topic_inner(f, name, params)
  // a station's network as the core gives it: how this device reaches it (`way`) in the list, its figures in the
  // `stationNet` view of its own (the made-up stations say both as `net`)
  let value = match name {
    "stations" => fixture_stations_way(value)
    "stationNet" => {
      let address = text(Some(Json::object(params)), "station")
      let ws = match address.find("/") {
        Some(i) => address.view(end_offset=i).to_owned()
        None => address
      }
      let mut net = None
      match fixture_topic_inner(f, "stations", { "scope": Json::string(ws) }) {
        Some(Array(list)) =>
          for x in list {
            if text(Some(x), "station") == address && flag(Some(x), "online") {
              net = field(Some(x), "net")
            }
          }
        _ => ()
      }
      net
    }
    _ => value
  }
  { value, error: None, version: f.version + @settings.fixture_version() }
}

///|
/// What a made-up topic says (fixture_topic: as the screens' fixtures have it, before the core's shapes are made of it).
fn fixture_topic_inner(f : Fixture, name : String, params : Map[String, Json]) -> Json? {
  let account : Json = { "sub": "u1", "email": "lin@example.com", "name": "林" }
  let value : Json? = match name {
    "accounts" => if f.mode == "signin" { Some([]) } else { Some([account]) }
    // a draft's files going up in the core (composer.add): up at once
    "composer" =>
      Some({ "files": Json::array(fix_composers.get(text(Some(Json::object(params)), "key")).unwrap_or([])) })
    // signed in with no workspace yet (landing.mbt): landing, landing-invited (an invitation waiting), blocked (the
    // account not let into this app)
    "workspaces" if f.mode == "landing" || f.mode == "landing-invited" || f.mode == "blocked" => {
      let o : Map[String, Json] = {
        "account": account,
        "workspaces": [],
        "invitations": if f.mode == "landing-invited" {
          [{ "id": "inv1", "name": "星火工作室", "inviter": "安娜", "role": "member" }]
        } else {
          []
        },
        "loaded": true,
      }
      if f.mode == "blocked" {
        o["blocked"] = "此账号暂未开放测试版"
      }
      Some([Json::object(o)])
    }
    "workspaces" =>
      Some([
        {
          "account": account,
          "workspaces": if f.mode == "webdemo" {
            [{ "id": "ws1", "name": "Acme", "stations": 1, "members": 3 }]
          } else {
            [
              { "id": "ws1", "name": "星火工作室", "stations": 2, "members": 3 },
              { "id": "ws2", "name": "个人", "stations": 1, "members": 1 },
            ]
          },
          "invitations": [],
          "loaded": true,
        },
      ])
    "prefs" => {
      let lf : Map[String, Json] = {}
      for k, v in f.filters {
        lf[k] = Json::string(v)
      }
      Some({
        "workspace": Json::string(f.workspace),
        "listFilter": Json::object(lf),
        "appearance": Json::string(f.appearance),
        "fonts": fixture_fonts(f.fonts),
        "faces": fixture_faces(f.fonts),
      })
    }
    "fonts" => Some(fixture_fonts_topic(f))
    "job" | "previewLoad" => fixture_service_topic(f, name, params)
    "shareIn" => fixture_share_topic(params)
    "imageNear" => fixture_image_near(params)
    "chats" => fixture_chats(f, params)
    "search" => fixture_search(params)
    // the archive's chats (the settings' made-up ones): the wide frame's sidebar lists them
    "archive" => @settings.fixture_topic(f.mode, name, params)
    // (the web's demo has none)
    "workspaceMarks" if f.mode == "webdemo" => Some({ "workspaces": { "ws1": {} } })
    "workspaceMarks" =>
      Some({
        "workspaces": {
          "ws1": { "alert": 1, "unread": 2, "wait": 1, "decisions": 2, "tone": "alert" },
          "ws2": { "alert": 0, "unread": 2, "tone": "done" },
        },
        "others": if f.workspace == "ws1" { "done" } else { "alert" },
      })
    "status" => Some({ "items": [] })
    // what the last update brought (home_news.mbt): said on MBUI_FIXTURE=home-news only
    "changelog" if f.mode == "home-news" =>
      Some({
        "build": 1310,
        "tabs": [],
        "news": {
          "build": "0.1.1310",
          "entries": [
            { "text": ["设置里可以注销账号", "聊天顶栏会提示 station 更新"] },
            { "text": ["执行历史里可以认领 Slack 用户", "后台任务的面板可以拖高"] },
          ],
        },
      })
    "screenCard" | "adbCard" => fixture_link_card(name, params)
    // (a chat's agent's run settings, a settings page: the settings' own)
    "pick" if f.mode == "settings-run" || f.mode == "settings-run-models" || f.mode == "settings-run-accounts" =>
      @settings.fixture_topic(f.mode, name, params)
    "newChat" | "pick" => fixture_new_topic(f, name)
    _ =>
      match decide_fixture_topic(f, name, params) {
        Some(v) => v
        // the settings' pages (src/sfapp/settings/fixture.mbt): theirs first on their own screenshots, else the chats'
        None if f.mode.has_prefix("settings") || f.mode.has_prefix("place-") =>
          match @settings.fixture_topic(f.mode, name, params) {
            Some(v) => Some(v)
            None => fixture_chat_topic(f, name, params)
          }
        None =>
          match fixture_chat_topic(f, name, params) {
            Some(v) => Some(v)
            None => @settings.fixture_topic(f.mode, name, params)
          }
      }
  }
  value
}

///|
/// The made-up stations as the core lists them: each one's `net` left out, how this device reaches it (`way`: its
/// path and via) in its place.
fn fixture_stations_way(v : Json?) -> Json? {
  match v {
    Some(Array(list)) =>
      Some(
        Json::array(
          list.map(fn(x) {
            match x {
              Object(o) => {
                let m : Map[String, Json] = {}
                for k, val in o {
                  if k != "net" {
                    m[k] = val
                  }
                }
                match o.get("net") {
                  Some(n) =>
                    m["way"] = { "path": Json::string(text(Some(n), "path")), "via": Json::string(text(Some(n), "via")) }
                  None => ()
                }
                Json::object(m)
              }
              _ => x
            }
          }),
        ),
      )
    _ => v
  }
}

///|
/// `base` answering `ms` late, as a phone's core across its thread does: each call's answer and each topic's first value
/// (src/sffilm's MBUI_CORE_MS: what shows meanwhile filmed too). What is due comes as the fixture is next read
/// (fix_later).
pub fn round_trip(base : Source, ms : Double) -> Source {
  let read : Map[String, Bool] = {}
  {
    ..base,
    call: fn(name, params, done) { (base.call)(name, params, fn(r) { fix_later(ms, fn() { done(r) }) }) },
    topic: fn(name, params) {
      let t = (base.topic)(name, params)
      let k = name + Json::object(params).stringify()
      match read.get(k) {
        Some(true) => t
        Some(false) => { value: None, error: None, version: -1 }
        None => {
          read[k] = false
          fix_later(ms, fn() { read[k] = true })
          { value: None, error: None, version: -1 }
        }
      }
    },
  }
}

///|
/// A source of made-up chats (see the top of this file for `mode`).
pub fn fixture(mode : String) -> Source {
  fixture_preview(mode)
  let f : Fixture = {
    mode: if mode == "" { "home" } else { mode },
    workspace: "ws1",
    appearance: if mode.has_suffix("-dark") || @ui.env("MBUI_DARK") == "1" {
      "dark"
    } else {
      "light"
    },
    archived: {},
    filters: {},
    fonts: if mode == "settings-fonts-coming" { { "ui": "noto-sans-sc" } } else { {} },
    fonts_fetched: {},
    version: 1,
    older: 0,
    step: 0,
  }
  if f.mode == "home-motion" {
    // the list changing on its own, a step every 1.6 s from MBUI_MOTION_AT ms (2000) after it starts: rows moving,
    // coming, going (ListMotion.kt), for the recordings of the Home rows' motion
    let at = {
      let w = @ui.env("MBUI_MOTION_AT")
      let mut v = 0
      for ch in w {
        let d = ch.to_int() - 48
        if d >= 0 && d <= 9 {
          v = v * 10 + d
        }
      }
      if w == "" {
        2000.0
      } else {
        v.to_double()
      }
    }
    for k in 1..=4 {
      fix_later(at + (k - 1).to_double() * 1600.0, fn() { f.step = k })
    }
  }
  {
    topic: fn(name, params) { fixture_topic(f, name, params) },
    call: fn(name, params, done) {
      match fixture_kept(name, params, None) {
        Some(r) => {
          done(r.map(fn(a) { a.0 }))
          return
        }
        None => ()
      }
      match @settings.fixture_call(name, params) {
        Some(r) => {
          done(r)
          return
        }
        None => ()
      }
      // the faces' files (fonts_fixture.mbt)
      if fixture_fonts_call(f, name, params, done) {
        return
      }
      match name {
        "chat.archive" => {
          let session = text(Some(params), "session")
          f.archived[session.view(start_offset=2).to_owned()] = true
          f.version += 1
          done(Ok(Json::object({})))
        }
        // a visualization's widget kept nothing yet; what it keeps is taken (viz.mbt)
        "widget.state" => done(Ok({ "state": Json::null() }))
        "widget.setState" => done(Ok(Json::object({})))
        "chat.older" => {
          f.older += 1
          f.version += 1
          done(Ok(Json::object({})))
        }
        // a screen's preview's frame taken (chat-screens): the fixture sends no other
        "screen.ack" => done(Ok(Json::object({})))
        "prefs.set" => {
          match field(Some(params), "workspace") {
            Some(String(w)) => f.workspace = w
            _ => ()
          }
          match field(Some(params), "appearance") {
            Some(String(a)) => f.appearance = a
            _ => ()
          }
          match field(Some(params), "listFilter") {
            Some(Object(m)) =>
              for k, v in m {
                match v {
                  String(s) => f.filters[k] = s
                  _ => ()
                }
              }
            _ => ()
          }
          // a place's face (null: back to the app's own)
          match field(Some(params), "fonts") {
            Some(Object(m)) =>
              for k, v in m {
                match v {
                  String(s) => f.fonts[k] = s
                  _ => f.fonts.remove(k)
                }
              }
            _ => ()
          }
          f.version += 1
          done(Ok(Json::object({})))
        }
        _ =>
          match fixture_new_call(f, name, params) {
            Some(r) => done(r)
            None if name == "shareIn.open" => done(fixture_share_call(name, params).unwrap())
            None =>
              match fixture_card_call(f, name, params) {
                Some(r) => done(r)
                None =>
              match fixture_chat_call(f, name, params) {
                Some(r) => done(r)
                None if name == "link.parse" =>
                  done(Ok(fixture_link_parse(text(Some(params), "url"))))
                None =>
                  match decide_fixture_call(name) {
                    Some(r) => done(r)
                    None => done(Err({ "code": "unknown_call", "message": "这份假数据没有 " + name }))
                  }
              }
              }
          }
      }
    },
    read_bytes: fn(name, params, done) {
      match fixture_kept(name, params, None) {
        Some(r) => {
          done(r.map(fn(a) { (a.0, a.1.unwrap_or(Bytes::new(0))) }))
          return
        }
        None => ()
      }
      // the faces' files (fonts_fixture.mbt)
      match fixture_fonts_read(f, name) {
        Some(r) => {
          done(r)
          return
        }
        None => ()
      }
      // a chat's made-up files (the preview's), else the made-up drive's
      if name.has_prefix("station.file") {
        fixture_fetch(name, params, done)
        return
      }
      // the player's made-up films (play_fixture.mbt)
      if name == "drive.read" && fixture_play_read(params, done) {
        return
      }
      match fixture_drive_read(name, params) {
        Some(r) => done(r)
        None => done(Err({ "code": "unknown_call", "message": "这份假数据没有 " + name }))
      }
    },
    // a chat's made-up files, whole: here at once, nothing said of how far they have got
    read_going: fn(name, params, _on_value, done) { fixture_fetch(name, params, done) },
    stream: fn(name, params, _bytes, on_value, done) {
      // a file's part going up (composer.mbt upload_part): as the station takes it, all of it at once
      if name == "station.upload.part" {
        match fixture_chat_call(f, name, params) {
          Some(r) => done(r)
          None => done(Err({ "code": "unknown_call", "message": "这份假数据没有 " + name }))
        }
        return 0
      }
      fixture_stream(name, params, on_value, done)
    },
    cancel: fn(_) {  },
    call_bytes: fn(name, params, bytes, done) {
      match fixture_kept(name, params, Some(bytes)) {
        Some(r) => {
          done(r.map(fn(a) { a.0 }))
          return
        }
        None => ()
      }
      if fixture_fonts_call(f, name, params, done) {
        return
      }
      match fixture_chat_call(f, name, params) {
        Some(r) => done(r)
        None => done(Err({ "code": "unknown_call", "message": "这份假数据没有 " + name }))
      }
    },
    sign_in: fn() {  },
    signing_in: fn() { false },
    picture: fn(_, _) { "" },
    fatal: fn() { None },
    file: fn(_, _, name) { fixture_file(name) },
    // a video's still: its first frame as the station makes it (the made-up ones' each a picture of its own)
    poster: fn(_, _, name) { fixture_file(name) },
    now: fn() { 0.0 },
    leave: fn(_, _) {  },
    read_only: false,
  }
}

///|
/// The core's pure calls (`markdown`, `code.ink`, `reader.*`) as the real core answered them, kept (src/sfkept: bound
/// by a run without a core); None for any other.
fn fixture_kept(name : String, params : Json, bytes : Bytes?) -> Result[(Json, Bytes?), Json]? {
  match @sf.kept_call.val {
    Some(kept) => kept(name, params, bytes)
    None => None
  }
}

///|
/// What a fixture mode opens over Home before the first frame, as src/sffix (the screenshots' app) opens it: the
/// first row's chat (opened at a message from a notification for chat-flash…), its cards' states; the drive's pages;
/// the 奏 page, a history, a chat's sheets; a new chat, the bar's panel, a place; a page of the settings.
pub fn open_fixture_mode(mode : String) -> Unit {
  let rich : ChatRef = {
    station: "ws1/st1",
    session: "s-c1",
    title: "整理发布清单",
    station_name: "Studio",
  }
  if mode == "chat-flash" || mode == "chat-flash-mine" {
    // opened from a notification at a message (Ana's, or yours), its flash held at its peak (slice 10's)
    open_chat_at(rich, if mode == "chat-flash" { 4.0 } else { 6.0 }, held=true)
  } else if mode.has_prefix("chat") {
    open_chat(rich)
    // the cards' states (chat_fixture.mbt): chat-cards, chat-answering
    open_cards_fixture(mode)
  }
  // the drive's pages (src/sfapp/drive_fixture.mbt): files, drive…, reader…
  open_drive_fixture(mode)
  // slice 8's (src/sfapp/decide_fixture.mbt): the 奏 page, a history, a chat's sheets
  open_fixture(mode)
  // a new chat (with its sheets), the bar's panel, a place: newchat_fixture.mbt
  open_mode(mode)
  // a station's screen (screen_fixture.mbt)
  open_screen_fixture(mode)
  if mode.has_prefix("settings") {
    open_setting(@settings.fixture_page(mode))
  }
  // the search open over Home, words typed (search_fixture.mbt)
  open_search_mode(mode)
  // a device not yet confirmed in the workspace's safe mode: lock-waiting, lock-finding, lock-code, lock-wrong (its
  // waiting page in the chats' place), lock-security (its security page)
  if mode == "lock-security" {
    open_setting(@settings.fixture_page("settings-security"))
  }
}

///|
/// The app as src/sffix starts it for `mode`, for a Tester made next (src/sfscreens): the app as at the start (reset:
/// whatever ran before in the process), the made-up source of the mode and what it opens before the first frame
/// (open_fixture_mode). The Tester keeps it as it starts (reset by hand).
pub fn fixture_app(mode : String) -> Source {
  reset()
  let src = fixture(mode)
  open_fixture_mode(mode)
  src
}
