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
/// The chats of the first workspace, newest first, by day.
fn fixture_days(f : Fixture) -> Array[Json] {
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
  let stations : Json = [
    { "id": "ws1/st1", "name": "Studio" },
    { "id": "ws1/st2", "name": "MBA" },
  ]
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
  })
}

///|
fn fixture_topic(f : Fixture, name : String, params : Map[String, Json]) -> Topic {
  fix_tick(f)
  let account : Json = { "sub": "u1", "email": "lin@example.com", "name": "林" }
  let value : Json? = match name {
    "accounts" => if f.mode == "signin" { Some([]) } else { Some([account]) }
    "workspaces" =>
      Some([
        {
          "account": account,
          "workspaces": [
            { "id": "ws1", "name": "星火工作室", "stations": 2, "members": 3 },
            { "id": "ws2", "name": "个人", "stations": 1, "members": 1 },
          ],
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
      })
    }
    "job" | "previewLoad" => fixture_service_topic(f, name, params)
    "chats" => fixture_chats(f, params)
    "workspaceMarks" =>
      Some({
        "workspaces": {
          "ws1": { "alert": 1, "unread": 2, "wait": 1, "decisions": 2, "tone": "alert" },
          "ws2": { "alert": 0, "unread": 2, "tone": "done" },
        },
        "others": if f.workspace == "ws1" { "done" } else { "alert" },
      })
    "status" => Some({ "items": [] })
    "newChat" | "pick" => fixture_new_topic(f, name)
    _ =>
      match decide_fixture_topic(f, name, params) {
        Some(v) => v
        // the settings' pages (src/sfapp/settings/fixture.mbt): theirs first on their own screenshots, else the chats'
        None if f.mode.has_prefix("settings") =>
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
  { value, error: None, version: f.version + @settings.fixture_version() }
}

///|
/// A source of made-up chats (see the top of this file for `mode`).
pub fn fixture(mode : String) -> Source {
  fixture_preview(mode)
  let f : Fixture = {
    mode: if mode == "" { "home" } else { mode },
    workspace: "ws1",
    appearance: if mode.has_suffix("-dark") || @host.env("MBUI_DARK") == "1" {
      "dark"
    } else {
      "light"
    },
    archived: {},
    filters: {},
    version: 1,
    older: 0,
    step: 0,
  }
  if f.mode == "home-motion" {
    // the list changing on its own, a step every 1.6 s from MBUI_MOTION_AT ms (2000) after it starts: rows moving,
    // coming, going (ListMotion.kt), for the recordings of the Home rows' motion
    let at = {
      let w = @host.env("MBUI_MOTION_AT")
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
      match @settings.fixture_call(name, params) {
        Some(r) => {
          done(r)
          return
        }
        None => ()
      }
      match name {
        "chat.archive" => {
          let session = text(Some(params), "session")
          f.archived[session.view(start_offset=2).to_owned()] = true
          f.version += 1
          done(Ok(Json::object({})))
        }
        "chat.older" => {
          f.older += 1
          f.version += 1
          done(Ok(Json::object({})))
        }
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
          f.version += 1
          done(Ok(Json::object({})))
        }
        _ =>
          match fixture_new_call(f, name, params) {
            Some(r) => done(r)
            None =>
              match fixture_chat_call(f, name, params) {
                Some(r) => done(r)
                None =>
                  match decide_fixture_call(name) {
                    Some(r) => done(r)
                    None => done(Err({ "code": "unknown_call", "message": "这份假数据没有 " + name }))
                  }
              }
          }
      }
    },
    read_bytes: fn(name, params, done) {
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
    stream: fn(name, params, _bytes, on_value, done) { fixture_stream(name, params, on_value, done) },
    cancel: fn(_) {  },
    call_bytes: fn(name, params, _bytes, done) {
      match fixture_chat_call(f, name, params) {
        Some(r) => done(r)
        None => done(Err({ "code": "unknown_call", "message": "这份假数据没有 " + name }))
      }
    },
    sign_in: fn() {  },
    signing_in: fn() { false },
    picture: fn(_) { "" },
    fatal: fn() { None },
    file: fn(_, _, name) { fixture_file(name) },
    now: fn() { 0.0 },
    leave: fn(_, _) {  },
    read_only: false,
  }
}
