// Made-up chats in the core's own shapes (ChatsView and the rest), for the app with no core: screenshots that are
// the same on every run (scripts/shots.sh home, web-home), and the web's preview. Every word here is made up.
//
// `mode`: "home" (signed in, the chats), "signin" (signed out), "loading" (the list being read), "empty" (a
// workspace with nothing in it yet); "chat" (the first row's chat open: chat_fixture.mbt), "chat-loading" (it being
// read), "chat-long" (thousands of messages in it).

///|
priv struct Fixture {
  mode : String
  mut workspace : String
  archived : Map[String, Bool]
  filters : Map[String, String]
  mut version : Int
  /// the first row's chat: how many older pages have come in
  mut older : Int
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
  let keep = fn(items : Array[Json]) -> Json {
    Json::array(items.filter(fn(r) { !f.archived.contains(text(Some(r), "id")) }))
  }
  [
    { "daysAgo": 0, "at": 0, "label": "今天", "items": keep(today) },
    { "daysAgo": 1, "at": 0, "label": "昨天", "items": keep(yesterday) },
    { "daysAgo": 4, "at": 0, "label": "星期三", "items": keep(earlier) },
  ]
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
      Some({ "workspace": Json::string(f.workspace), "listFilter": Json::object(lf) })
    }
    "chats" => fixture_chats(f, params)
    "workspaceMarks" =>
      Some({
        "workspaces": {
          "ws1": { "alert": 1, "unread": 2, "wait": 1, "tone": "alert" },
          "ws2": { "alert": 0, "unread": 2, "tone": "done" },
        },
        "others": if f.workspace == "ws1" { "done" } else { "alert" },
      })
    "status" => Some({ "items": [] })
    _ => fixture_chat_topic(f, name, params)
  }
  { value, error: None, version: f.version }
}

///|
/// A source of made-up chats (see the top of this file for `mode`).
pub fn fixture(mode : String) -> Source {
  let f : Fixture = {
    mode: if mode == "" { "home" } else { mode },
    workspace: "ws1",
    archived: {},
    filters: {},
    version: 1,
    older: 0,
  }
  {
    topic: fn(name, params) { fixture_topic(f, name, params) },
    call: fn(name, params, done) {
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
        _ => done(Err({ "code": "unknown_call", "message": "这份假数据没有 " + name }))
      }
    },
    sign_in: fn() {  },
    signing_in: fn() { false },
    picture: fn(_) { "" },
    fatal: fn() { None },
    file: fn(_, _, name) { fixture_file(name) },
    now: fn() { 0.0 },
    leave: fn(_, _) {  },
    read_only: true,
  }
}
