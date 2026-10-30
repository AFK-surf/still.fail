// An execution history, an agent's card, jobs, for the app with no core (fixture.mbt; slice 8's screenshots).
// MBUI_FIXTURE: "history" (an agent's steps, a few opened), "history-reading" (the
// steps not read yet: their bones), "history-details", the chat
// with a sheet open over it: "chat-info", "chat-publish", "chat-agent", "chat-agent-unsaid" (an agent's card that knows
// no figure of it, as a station from before tells none of an agent at rest), "chat-peek" (its station's card), "chat-jobs",
// "chat-job"; "chat-letters-many" (their sheet, more chats written with than it holds at its share: its list
// scrolling in it); "chat-letters-info" (the chat's sheet with its row for what its agents and other chats' wrote each
// other), "chat-letters" (their sheet: the chats written with), "chat-letters-open" (one of them opened); the wide
// frame's "chat-letters-pop" (the chat's "…" open), "chat-jobs-pop" (its services' popover), "chat-letters-side",
// "chat-jobs-side", "chat-history-side", "chat-service-side" (what is opened beside it: its web service's page, its bar
// at the panel's width), "chat-tabs-side" (two of them: the history behind
// 任务), "chat-model-pop" (its agent's model control's panel
// open), "chat-find" (⌘F's bar, a word typed in it), "chat-agent-card" (the chat, its agent's details and card read:
// what its card over its picture says); "home-jobs"
// (Home with the jobs left up a long while at its top); "home-attention" (the wide frame's 待处理 open: a decision to let
// go, a failure looked at, a station offline); "home-syncing" (Home catching up on what changed while away: the line
// over the rows); "history-link" (Home, the history there for a link to open at
// an entry: what apps/android's MbuiCompareTest pictures beside it). Every word here is made up.

///|
/// Whether `mode` is one of this slice's.
pub fn decide_mode(mode : String) -> Bool {
  [
    "history", "history-reading", "history-details",
    "chat-info", "chat-publish", "chat-agent", "chat-agent-unsaid", "chat-peek", "chat-jobs", "chat-job", "home-jobs", "history-link",
    "chat-letters-info", "chat-letters", "chat-letters-many", "chat-letters-open", "chat-letters-pop", "chat-letters-side", "chat-jobs-pop",
    "chat-things", "chat-things-side", "chat-info-pulls",
    "chat-jobs-side", "chat-history-side", "chat-service-side", "chat-tabs-side", "chat-model-pop", "chat-find", "chat-agent-card",
    "chat-station-tag", "home-attention", "home-syncing",
  ].contains(mode)
}

///|
/// The fixture's first agent as the chat's view has it once its details are read.
pub fn fix_agent() -> Json {
  {
    "session": {
      "key": "s-c1",
      "runtime": "claude",
      "maker": { "id": "anthropic", "name": "Anthropic" },
      "agentText": "Claude · Opus 5.5",
      "statusText": "做完了",
      "tone": "green",
      "process": "warm",
      "processText": "空闲 · 还在内存里",
      "runtimeText": "Claude Code 2.1.3",
      "model": "claude-opus-5-5",
      "modelName": "Opus 5.5",
      "effort": "high",
      "time": { "lastActiveAt": { "ago": "5 分钟前" } },
    },
    "status": "idle",
    "account": {
      "name": "林的 Max",
      "quota": {
        "state": "ok",
        "windows": [
          // (named and when they refill as the core says them: present.ts quota)
          { "label": "5 小时", "mark": "5H", "left": 62, "level": "ok", "refills": "3 小时后刷新" },
          { "label": "每周", "mark": "W", "left": 18, "level": "amber", "refills": "2 天 4 小时后刷新" },
        ],
      },
    },
    "attention": [],
    "turns": [{ "text": "3 步 · 发出 1 条" }],
    "jobs": [fix_job("j-web")],
  }
}

///|
/// A job of the fixture's chat.
pub fn fix_job(id : String) -> Json {
  match id {
    "j-web" =>
      {
        "id": "j-web",
        "session": "s-c1",
        "name": "web",
        "state": "running",
        "port": 5173,
        "startedAt": 0,
        "command": "pnpm dev --port 5173",
        "tone": "up",
        "service": true,
        "open": true,
        "current": true,
        "word": "在线",
        "meta": [{ "text": "在线", "kind": "word" }, { "text": " · 3 小时" }],
        "notices": [],
      }
    "j-ci" =>
      {
        "id": "j-ci",
        "session": "s-c1",
        "name": "盯 CI",
        "state": "running",
        "startedAt": 0,
        "command": "gh run watch 4821 --exit-status",
        "tone": "live",
        "watch": true,
        "current": true,
        "meta": [
          { "text": "在盯着", "kind": "word" },
          { "text": " · " },
          { "text": "第 3 步通过", "kind": "notice" },
        ],
        "notices": [
          { "at": 2, "text": "第 3 步通过：单元测试全部通过", "clock": "14:05", "ago": "3 分钟前" },
          { "at": 1, "text": "开始跑：构建、测试、截图", "clock": "13:58", "ago": "10 分钟前" },
        ],
        "outputSaid": "最后输出 · 3 分钟前",
      }
    _ =>
      {
        "id": id,
        "session": "s-c1",
        "name": "构建安装包",
        "state": "exited",
        "startedAt": 0,
        "command": "scripts/android.sh build",
        "tone": "off",
        "ended": true,
        "current": false,
        "meta": [{ "text": "已结束", "kind": "word" }, { "text": " · 20 分钟前" }],
        "notices": [],
      }
  }
}

///|
/// Its agent, its context compactable and clearable by hand (`chat-agent-unsaid`).
pub fn fix_context_actions(chat : Json) -> Json {
  match chat {
    Object(m) => {
      let o = m.copy()
      o["agents"] = Json::array(
        items(Some(chat), "agents").map(fn(a) {
          match a {
            Object(am) => {
              let ao = am.copy()
              let session = match am.get("session") {
                Some(Object(sm)) => sm.copy()
                _ => Map::new()
              }
              session["canCompact"] = Json::boolean(true)
              session["canClear"] = Json::boolean(true)
              ao["session"] = Json::object(session)
              Json::object(ao)
            }
            other => other
          }
        }),
      )
      Json::object(o)
    }
    other => other
  }
}

///|
/// The chat's view with no agent in it yet (`chat-station-tag`).
pub fn fix_no_agent(chat : Json) -> Json {
  match chat {
    Object(m) => {
      let o = m.copy()
      o["agents"] = []
      Json::object(o)
    }
    other => other
  }
}

///|
/// The chat's view with its thread's facts and its agent's details (what its sheets show).
pub fn fix_detailed_chat(base : Json) -> Json {
  match base {
    Object(m) => {
      let o = m.copy()
      o["pinned"] = Json::boolean(false)
      o["thread"] = {
        "id": 7,
        "unread": 0,
        "creator": { "shown": { "display": "林" } },
        "time": { "createdAt": { "ago": "3 小时前" } },
        "lastMessage": { "time": { "createdAt": { "ago": "5 分钟前" } } },
      }
      o["agents"] = [fix_agent()]
      // made public twice (apps/android PublishSheetTest's `two`): the viewer's own, which they may revoke, and Bob's
      let link = "https://share.still.fail/#B5CrvEZwwZq7oct4Vs0Ld90SJHgZO4uOwQdhtJsLRNE.Qm9vSzVnUkN2dUdS.k3Yq"
      let published = fn(id : String, by : String, mine : Bool, ago : String) -> Json {
        {
          "id": Json::string(id),
          "link": Json::string(link + "-" + id),
          "createdAt": 0,
          "byName": Json::string(by),
          "mayRevoke": Json::boolean(mine),
          "time": { "createdAt": { "ago": Json::string(ago), "full": "10月15日 10:00" } },
        }
      }
      o["publish"] = { "may": true, "links": [published("p2", "Alice", true, "10 分钟前"), published("p1", "Bob", false, "2 天前")] }
      // shared with one of the viewer's other workspaces, read only (ChatInfo.kt ShareRow)
      o["xshare"] = {
        "session": "s-c1",
        "text": "开源 · 只读",
        "to": [],
        "write": false,
        "may": true,
        "places": [
          { "workspace": "ws2", "name": "日常", "on": false },
          { "workspace": "ws3", "name": "开源", "on": true },
        ],
      }
      Json::object(o)
    }
    _ => base
  }
}

///|
pub fn fix_history() -> Json {
  let item = fn(key : String, kind : String, content : Json) -> Json {
    { "key": Json::string(key), "entries": [1, 2], "body": { "kind": Json::string(kind), "content": content } }
  }
  let step = fn(
    said : String,
    name : String,
    hint : String,
    meta : String,
    failed : Bool,
    call : String,
    result : String,
  ) -> Json {
    let o : Map[String, Json] = {
      "name": Json::string(name),
      "hint": Json::string(hint),
      "meta": Json::string(meta),
      "failed": Json::boolean(failed),
      "call": Json::string(call),
      "result": Json::string(result),
      "entries": [3, 4],
      "brief": false,
    }
    if said != "" {
      o["said"] = Json::string(said)
    }
    { "kind": "step", "content": Json::object(o) }
  }
  {
    "items": [
      item("h1", "received", {
        "tasks": [],
        "messages": [
          {
            "key": "m1",
            "from": { "name": "林", "bound": false },
            "text": "帮我把聊天页的列表做成虚拟列表，几千条消息也要滚得顺。",
          },
        ],
      }),
      item("h2", "group", {
        "summary": "读了 src/ui/list.mbt 等 2 个文件，跑了测试",
        "title": "读取",
        "failures": 0,
        "pending": 0,
        "rows": [
          step(
            "",
            "Read",
            "src/ui/list.mbt",
            "",
            false,
            "{\"file_path\": \"/Users/lin/mbui/src/ui/list.mbt\", \"offset\": 80, \"limit\": 3}",
            "    80→pub fn Ctx::list(\n    81→  self : Ctx,\n    82→  key : String,",
          ),
          step(
            "跑一遍列表的测试",
            "Bash",
            "",
            "4.2s",
            false,
            "{\"command\": \"moon test -p ui -f list_test.mbt\", \"description\": \"跑一遍列表的测试\", \"timeout\": 120000}",
            "Total tests: 9, passed: 9, failed: 0.",
          ),
          {
            "kind": "thought",
            "content": {
              "text": "行高先按估计值占位，滚到时再量。",
              "first": "行高先按估计值占位",
              "entries": [5],
              "brief": false,
            },
          },
        ],
      }),
      item("h3", "text", {
        "text": "列表只建看得见的行，其余的按估计的高度占位；量过一次的行记住它的高度，滚回来时不再跳。",
        "line": "列表只建看得见的行，其余的按估计的高度占位；量过一次的行记住它的高度，滚回来时不再跳。",
        "subagent": false,
      }),
      item("h4", "group", {
        "summary": "改了 src/ui/list.mbt，跑了 2 条命令",
        "title": "修改",
        "failures": 1,
        "pending": 0,
        "rows": [
          step(
            "",
            "Edit",
            "src/ui/list.mbt",
            "",
            false,
            "{\"file_path\": \"/Users/lin/mbui/src/ui/list.mbt\", \"old_string\": \"  est : Double,\\n  row : (Int) -> Unit,\", \"new_string\": \"  est : Double,\\n  row : (Int) -> Unit,\\n  stick_end? : Bool = false,\"}",
            "The file has been updated.",
          ),
          step(
            "截图对比",
            "Bash",
            "",
            "退出码 1",
            true,
            "{\"command\": \"scripts/shots.sh chat\", \"description\": \"截图对比\"}",
            "mac-chat.png: 312 px differ\n[exit code: 1]",
          ),
        ],
      }),
      item("h5", "post", {
        "text": "做完了：列表、跳到最新的按钮、加载更早的消息都好了，截图也换了。",
        "place": { "name": "整理发布清单", "surface": "ember", "session": "s-c1" },
        "block": false,
        "failed": false,
      }),
      item("h6", "mark", { "text": "标记为做完了：截图已更新，测试全部通过" }),
    ],
    "live": [],
    "usage": [
      { "label": "输入", "value": "1.2M tokens" },
      { "label": "输出", "value": "34K tokens" },
    ],
    "edge": "从 10/19 08:12 开始",
    "empty": false,
    "loaded": true,
    "more": false,
  }
}

///|
pub fn fix_chat_jobs() -> Json {
  {
    "jobs": [fix_job("j-web"), fix_job("j-ci"), fix_job("j-build")],
    "servicesNote": "1 个在线",
    "jobsNote": "1 个在盯着",
    "current": 2,
    "ended": 1,
    "clear": ["s-c1"],
    "allText": "全部 3 个",
    "clearText": "清掉 1 个已结束的",
    "hiddenText": "另有 1 个已停止或结束",
  }
}

///|
/// This slice's topics in the fixture, for its modes (Some: handled, with its value).
pub fn decide_fixture_topic(f : Fixture, name : String, params : Map[String, Json]) -> Json?? {
  if !decide_mode(f.mode) {
    return None
  }
  match name {
    "chat" => {
      let session = match params.get("session") {
        Some(String(s)) => s
        _ => ""
      }
      let base = fixture_chat_topic(f, name, params)
      let base = if f.mode.has_prefix("chat-letters") { base.map(fix_with_letters) } else { base }
      if session == "s-c1" && f.mode == "chat-agent-unsaid" {
        Some(base.map(fn(b) { fix_context_actions(fix_detailed_chat(b)) }))
      } else if session == "s-c1" && f.mode == "chat-station-tag" {
        // no agent in it yet: its station's tag in its bar (pressed by the film's step: its card beside it)
        Some(base.map(fn(b) { fix_no_agent(fix_detailed_chat(b)) }))
      } else if session == "s-c1" {
        Some(base.map(fix_detailed_chat))
      } else {
        Some(base)
      }
    }
    "chatLetters" =>
      if f.mode == "chat-letters-many" {
        Some(Some(fix_letters_many()))
      } else if f.mode.has_prefix("chat-letters") {
        Some(Some(fix_letters()))
      } else {
        None
      }
    "history" if f.mode == "history-reading" => Some(None)
    "history" => Some(Some(fix_history()))
    "agentCard" if f.mode == "chat-agent-unsaid" =>
      Some(
        Some({
          "work": "8 轮 · 共干了 1 小时 12 分",
          "latest": [
            { "key": "k1", "text": "读了 src/ui/list.mbt" },
            { "key": "k2", "text": "跑了列表的测试" },
            { "key": "k3", "text": "改了 src/ui/list.mbt" },
          ],
          "attention": [],
        }),
      )
    "agentCard" =>
      Some(
        Some({
          "work": "8 轮 · 共干了 1 小时 12 分",
          "cost": "$4.20",
          "cache": { "percent": 91, "text": "91%", "level": "ok" },
          "context": { "percent": 64, "text": "64%", "level": "ok" },
          "jobs": "服务在线：web · 在盯着：CI",
          "latest": [
            { "key": "k1", "text": "读了 src/ui/list.mbt" },
            { "key": "k2", "text": "跑了列表的测试" },
            { "key": "k3", "text": "改了 src/ui/list.mbt" },
          ],
          "attention": [],
        }),
      )
    "host" => Some(Some({ "identity": "Mac Studio · macOS 26 · M2 Max" }))
    "chatJobs" =>
      if f.mode.has_prefix("chat-jobs") || f.mode == "chat-job" || f.mode == "chat-agent" {
        Some(Some(fix_chat_jobs()))
      } else {
        None
      }
    "jobLog" =>
      Some(
        Some({
          "text": "✓ build (1m 12s)\n✓ unit tests (48s)\n✓ step 3: screenshots\n… waiting for deploy",
          "said": "最后输出 · 3 分钟前",
          "last": "… waiting for deploy",
        }),
      )
    "longJobs" =>
      if f.mode == "home-jobs" {
        Some(
          Some({
            "groups": [
              {
                "key": "services",
                "head": "开了很久的网页服务 · 1",
                "jobs": [long_job()],
              },
            ],
            "lit": true,
            "ids": ["ws1/st1/j-web"],
          }),
        )
      } else {
        None
      }
    _ => None
  }
}

///|
/// A service left up a long while, as the `longJobs` view has it.
pub fn long_job() -> Json {
  let m = match fix_job("j-web") {
    Object(m) => m.copy()
    _ => {}
  }
  m["station"] = Json::string("ws1/st1")
  m["whereText"] = Json::string("Studio · 整理发布清单")
  m["age"] = Json::string("3 小时")
  m["chat"] = { "id": "s-c1", "title": "整理发布清单", "archived": false }
  Json::object(m)
}

///|
/// What the fixture's core says a snapshot would hold (apps/android PublishSheetTest's `preview`, the same words, so
/// the two are pictured alike): a person's message with a key hidden, an agent's reply, three attachments.
pub fn fix_preview() -> Json {
  let file = fn(k : String, name : String, size : Int, size_text : String, kind : String) -> Json {
    {
      "k": Json::string(k),
      "name": Json::string(name),
      "size": Json::number(size.to_double()),
      "sizeText": Json::string(size_text),
      "type": Json::string(kind),
      "n": 9,
      "file": { "name": Json::string(name), "path": Json::string("/w/uploads/" + name), "size": Json::number(size.to_double()) },
    }
  }
  let files = [
    file("f0", "login-page.png", 665, "665 B", "image/png"),
    file("f1", "deploy.log", 2048, "2.0 KB", "text/plain"),
    file("f2", "build-cache.tar", 12582912, "12 MB", "application/x-tar"),
  ]
  let ago = fn(words : String) -> Json { { "createdAt": { "ago": Json::string(words), "full": "10月15日 10:00" } } }
  let claude = by_agent("anthropic", "claude", "s-c1")
  {
    "upto": 9,
    "title": "部署登录页",
    // as the chat's page draws them: the viewer's own, an agent's words and its request about a vault item (allowed:
    // how it ended), someone else's with its files (where the preview's `files` have them)
    "list": [
      msg(4, "person", by_person("林"), "帮我把登录页部署到预发，token 是 [已隐藏]", "", {
        "mine": true,
        "author": "lin@example.com",
        "time": ago("12 分钟前"),
      }),
      msg(6, "agent", claude, "部署好了：**登录后跳回原页面**，`npm run deploy:staging` 跑了 42 秒。", "", { "time": ago("10 分钟前") }),
      msg(7, "agent", claude, "申请使用「Axiom 查询 token」：查登录页的错误日志", "", {
        "card": {
          "type": "options",
          "vault": "r-axiom",
          "vaultAsk": {
            "name": "Axiom 查询 token",
            "mode": "proxy",
            "hosts": ["api.axiom.co"],
            "command": "curl -s https://api.axiom.co/v1/datasets/_apl -H \"Authorization: Bearer $AXIOM_TOKEN\"",
            // (allowed since: the chat says how it ended)
            "status": "granted",
            "scope": "chat",
          },
        },
        "time": ago("9 分钟前"),
      }),
      msg(9, "person", by_person("Ana"), "截图、日志和构建缓存都附上了", "", {
        "attachments": Json::array(files.map(fn(f) { field(Some(f), "file").unwrap_or(Json::null()) })),
        "time": ago("8 分钟前"),
      }),
    ],
    "messages": [
      {
        "n": 4,
        "author": "Alice",
        "agent": false,
        "text": "帮我把登录页部署到预发，token 是 [已隐藏]",
        "files": [],
        "hidden": 1,
        "hiddenText": "已隐藏 1 处",
        "createdAt": 0,
        "time": ago("12 分钟前"),
      },
      {
        "n": 6,
        "author": "Opus 5.5",
        "agent": true,
        "text": "部署好了：**登录后跳回原页面**，`npm run deploy:staging` 跑了 42 秒。",
        "files": [],
        "hidden": 0,
        "createdAt": 0,
        "time": ago("10 分钟前"),
      },
      {
        "n": 7,
        "author": "Opus 5.5",
        "agent": true,
        "text": "申请使用「Axiom 查询 token」：查登录页的错误日志",
        "files": [],
        "hidden": 0,
        "createdAt": 0,
        "time": ago("9 分钟前"),
      },
      {
        "n": 9,
        "author": "Alice",
        "agent": false,
        "text": "截图、日志和构建缓存都附上了",
        "files": Json::array(files),
        "hidden": 0,
        "createdAt": 0,
        "time": ago("8 分钟前"),
      },
    ],
    "files": Json::array(files),
    "hidden": 1,
    "hiddenText": "共隐藏 1 处疑似机密",
  }
}

///|
/// This slice's calls in the fixture: taken as a station would.
pub fn decide_fixture_call(name : String) -> Result[Json, Json]? {
  match name {
    "decision.answer" | "decision.dismiss" | "decision.defer" | "decision.reply" | "chat.keep" | "chat.pin" | "chat.rename" | "session.stop" | "session.evict" | "session.compact" | "session.clear" | "job.stop" | "job.clearEnded" | "history.detail" | "history.older" | "machineLogin.cancel" | "chat.unpublish" =>
      Some(Ok(Json::object({})))
    "chat.publishPreview" => Some(Ok(fix_preview()))
    _ => None
  }
}

///|
/// The letters with 30 chats written with (`chat-letters-many`): fix_letters' first, again and again, each its own.
pub fn fix_letters_many() -> Json {
  let base = fix_letters()
  let first = match items(Some(base), "chats") {
    [c, ..] => c
    _ => return base
  }
  let chats : Array[Json] = []
  for i in 0..<30 {
    match first {
      Object(o) => {
        let o = o.copy()
        let key = "many-" + i.to_string()
        o["key"] = Json::string(key)
        o["link"] = Json::string(key)
        o["title"] = Json::string("往来的对话 " + (i + 1).to_string())
        chats.push(Json::object(o))
      }
      other => chats.push(other)
    }
  }
  match base {
    Object(o) => {
      let o = o.copy()
      o["chats"] = Json::array(chats)
      Json::object(o)
    }
    other => other
  }
}

///|
/// The chat's view saying how many letters its agents and other chats' wrote each other (the core's `letters`).
pub fn fix_with_letters(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      o["letters"] = Json::number(4.0)
      Json::object(o)
    }
    _ => v
  }
}

///|
/// What wants the viewer in 待处理 (home-attention: the core's `workspaceMarks`): a decision waiting in 整理发布清单,
/// to be let go, and a failure in another chat, looked at.
pub fn fix_attention_marks() -> Json {
  let item = fn(kind : String, title : String, what : String, station : String, name : String, thread : Double) {
    let m : Map[String, Json] = {
      "kind": Json::string(kind),
      "title": Json::string(title),
      "what": Json::string(what),
      "station": Json::string(station),
      "stationName": Json::string(name),
      "thread": Json::number(thread),
      "workspaceName": "家里",
    }
    m
  }
  let wait = item("wait", "整理发布清单", "选一个发布的时间", "ws1/st1", "Studio", 7.0)
  wait["session"] = Json::string("s-c1")
  wait["seq"] = Json::number(12.0)
  let failed = item("alert", "夜里的备份", "备份没有跑完", "ws1/st2", "MBA", 9.0)
  failed["seen"] = Json::boolean(true)
  {
    "workspaces": {
      "ws1": {
        "alert": 1,
        "wait": 1,
        "tone": "alert",
        "items": [Json::object(wait), Json::object(failed)],
      },
    },
    "others": "done",
    "badge": 1,
    "badgeKinds": { "on": true, "wait": true, "failed": true, "done": false, "message": false, "services": true },
  }
}

///|
/// The chats' view of `ws1` with its stations' trouble (home-attention: MBA offline).
pub fn fix_with_trouble(v : Json, params : Map[String, Json]) -> Json {
  match (v, params.get("scope")) {
    (Object(m), Some(String("ws1"))) => {
      let o = m.copy()
      o["trouble"] = { "text": "MBA 离线" }
      Json::object(o)
    }
    _ => v
  }
}

///|
/// The chats' view catching up on what changed while away (home-syncing: twelve chats left).
pub fn fix_with_syncing(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      o["syncing"] = "正在同步 · 还剩 12 个对话"
      Json::object(o)
    }
    _ => v
  }
}

///|
/// The chat a letter came from, by its link (the core's key for it).
pub let fix_letters_link : String = "https://app.still.fail/o/w/s/ember%3Ac-4dbf0d0c6e"

///|
/// What the chat's agents and other chats' wrote each other (the core's `chatLetters`): two chats written with, the
/// one written with last first; the other's three letters, two coming in and one going out.
pub fn fix_letters() -> Json {
  let link = fix_letters_link
  let theirs = fn(chat : String, from : String) -> Json {
    { "name": "「" + chat + "」的 agent", "from": from, "maker": { "id": "anthropic", "name": "anthropic" } }
  }
  let way = fn(m : Json, w : String) -> Json {
    match m {
      Object(o) => {
        let o = o.copy()
        o["way"] = Json::string(w)
        Json::object(o)
      }
      _ => m
    }
  }
  let mbui = "https://app.still.fail/o/w/s/ember%3Ac-06ffb79643"
  {
    "title": "整理发布清单",
    "whole": true,
    "chats": [
      {
        "key": mbui,
        "title": "接手监督 mbui",
        "link": mbui,
        "last": "测试版 4521 已出，你这边的改动等它跑完再合",
        "lastActiveAt": 1790000300000.0,
        "time": { "lastActiveAt": { "ago": "4 分钟前" } },
        "letters": [
          way(msg(300, "agent", theirs("接手监督 mbui", mbui), "测试版 **4521** 已出，你这边的改动等它跑完再合", "4 分钟前", { "author": "peer/ember:c-8" }), "in"),
        ],
      },
      {
        "key": link,
        "title": "BFT 备份尺寸分析",
        "link": link,
        "last": "补充一点：系统自带的 tar 能直接解 zstd",
        "lastActiveAt": 1790000200000.0,
        "time": { "lastActiveAt": { "ago": "5 分钟前" } },
        "letters": [
          way(msg(200, "agent", theirs("BFT 备份尺寸分析", link), "用户让精简备份并改用 zstd，改好的两个脚本放在 `~/bft/backup/`，麻烦替换一下", "7 分钟前", { "author": "peer/ember:c-9" }), "in"),
          way(msg(201, "agent", by_agent("anthropic", "claude", "s-c1"), "已替换，**今晚 02:00** 那份会按新脚本出", "6 分钟前", {}), "out"),
          way(msg(202, "agent", theirs("BFT 备份尺寸分析", link), "补充一点：系统自带的 tar 能直接解 zstd", "5 分钟前", { "author": "peer/ember:c-9" }), "in"),
        ],
      },
    ],
  }
}
