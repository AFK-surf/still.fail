// A made-up chat in the core's shapes (ChatView), for the app with no core (fixture.mbt): the first row's chat
// ("整理发布清单") holds every kind of message a chat shows: still.fail's notices (one failing), the viewer's words
// (one quoting, two sent close together), a person's with a picture, an agent's long Markdown (headings, lists,
// a task list, a quote, code, links, a reference to another chat), its files placed in its words and below them, a
// message it sent to Slack, an options card, a login card, its last post offering to archive the chat. An older
// page comes in when the reader nears the top (`chat.older`); "chat-login" its login card for one who may finish it,
// its page to open in the browser. Every other row's chat is two lines. "chat-long" is a
// chat of thousands of messages, for timing the list. Every word here is made up.

///|
fn by_agent(maker : String, runtime : String, key : String) -> Json {
  { "name": "Claude", "agent": Json::string(key), "maker": { "id": Json::string(maker), "name": Json::string(maker) }, "runtime": Json::string(runtime), "here": true }
}

///|
fn by_person(name : String) -> Json {
  { "name": Json::string(name) }
}

///|
fn ago(s : String, full : String) -> Json {
  { "createdAt": { "at": 0, "ago": Json::string(s), "full": Json::string(full), "until": "", "past": true } }
}

///|
/// A message: its seq, who said it, its words, and the rest as the view gives it.
fn msg(
  seq : Int,
  kind : String,
  by : Json,
  text : String,
  when : String,
  more : Map[String, Json],
) -> Json {
  let m : Map[String, Json] = {
    "seq": Json::number(seq.to_double()),
    "thread": 7,
    "ts": Json::string("ts\{seq}"),
    "authorKind": Json::string(kind),
    "author": Json::string(
      if kind == "agent" {
        "s-c1"
      } else if kind == "person" {
        "ana@example.com"
      } else {
        "ember"
      },
    ),
    "text": Json::string(text),
    "attachments": [],
    "quotes": [],
    "createdAt": Json::number(seq.to_double()),
    "mine": false,
    "system": Json::boolean(kind == "ember"),
    "by": by,
    "waiting": false,
    "time": ago(when, "10/19 0\{seq % 10}:12:0\{seq % 6}"),
  }
  for k, v in more {
    m[k] = v
  }
  Json::object(m)
}

///|
fn file(name : String, w : Int, h : Int, size : Int) -> Json {
  let f : Map[String, Json] = {
    "name": Json::string(name),
    "path": Json::string("work/s-c1/" + name),
    "size": Json::number(size.to_double()),
    "owner": "s-c1",
  }
  if w > 0 {
    f["width"] = Json::number(w.to_double())
    f["height"] = Json::number(h.to_double())
  }
  Json::object(f)
}

///|
let long_reply : String =
  #|## 列表改成虚拟列表
  #|
  #|先说结论：**只建屏幕上看得见的行**，其余的行按估计的高度占位，滚到时再量真实高度。这样几千条消息也只排十几行。
  #|
  #|### 做了什么
  #|
  #|1. 滚动位置记成「锚点行 + 偏移」，新量出来的行不会让内容跳动
  #|2. 在底部时跟着最新的消息走；往上翻就停下，右下角出现「跳到最新」
  #|   - 点它会滑回底部，不是瞬间跳过去
  #|   - 离底部很远时先跳到附近再滑
  #|3. 翻到顶部附近自动加载更早的一页，屏幕上的内容保持不动
  #|
  #|- [x] 锚点滚动
  #|- [x] 跟随最新
  #|- [ ] 新消息的入场动画
  #|
  #|> 注意：图片在加载前就按它自己的比例占好位置，加载完不会把下面的内容顶下去。
  #|
  #|核心的一段在 `place_list` 里：
  #|
  #|```moonbit
  #|fn ListState::moved(self : ListState, at : Int, n : Int) -> Unit {
  #|  if self.anchor >= at {
  #|    self.anchor = self.anchor + n
  #|  }
  #|}
  #|```
  #|
  #|和首页那边的改动有关，见 [首页的列表改成按天分组](https://app.still.fail/w/ws1/s/st1/chats/s-c2)；性能数据放在 https://example.com/bench/list 了。
  #|
  #|---
  #|
  #|有问题随时说。

///|
/// The first row's chat, its page of `older` pages back included.
fn rich_chat(older : Int) -> Json {
  let claude = by_agent("anthropic", "claude", "s-c1")
  let early : Array[Json] = []
  // the pages before, oldest first: ten short messages each
  for p in 0..<older {
    for k in 0..<10 {
      let seq = -100 * (older - p) + k * 2
      early.push(
        msg(seq, "agent", claude, "第 \{older - p} 页之前的第 \{k + 1} 条：检查了构建脚本的第 \{k + 3} 步。", "昨天", {}),
      )
      early.push(
        msg(seq + 1, "person", by_person("林"), "好，继续。", "昨天", {
          "mine": true,
          "author": "lin@example.com",
        }),
      )
    }
  }
  let messages : Array[Json] = [
    msg(1, "ember", { "name": "still.fail" }, "Studio 上的 claude 已启动。", "3 小时前", {}),
    msg(2, "person", by_person("林"), "帮我把聊天页的列表做成虚拟列表，几千条消息也要滚得顺。", "3 小时前", {
      "mine": true,
      "author": "lin@example.com",
    }),
    msg(3, "agent", claude, long_reply, "2 小时前", {}),
    msg(4, "person", by_person("Ana"), "第二屏的插画可以再小一点，参考这张：https://example.com/review/42", "2 小时前", {
      "attachments": [file("插画参考.png", 1200, 800, 245760)],
    }),
    msg(
      5,
      "agent",
      claude,
      "改好后的样子：\n\n![首页](home-after.png)\n\n对比图和构建日志附在下面。",
      "1 小时前",
      {
        "attachments": [
          file("home-after.png", 1170, 2532, 812000),
          file("compare.png", 1600, 900, 402000),
          file("build.log", 0, 0, 18432),
        ],
        "placed": ["home-after.png"],
        "elsewhere": [
          {
            "key": "e1",
            "after": 5,
            "createdAt": 5,
            "text": "*发布清单* 第三项已经核对完：安装包签名正确。",
            "place": { "name": "星火#发布", "surface": "slack:T1" },
            "failed": false,
            "by": claude,
            "time": ago("1 小时前", "10/19 05:20:00"),
          },
        ],
      },
    ),
    msg(6, "person", by_person("林"), "这里的高度是怎么估的？", "40 分钟前", {
      "mine": true,
      "author": "lin@example.com",
      "followed": true,
      "quotes": [
        {
          "author": "Claude",
          "text": "其余的行按估计的高度占位，滚到时再量真实高度",
          "comment": "",
          "ts": "ts3",
        },
      ],
    }),
    msg(7, "person", by_person("林"), "还有深色模式也看一下", "40 分钟前", {
      "mine": true,
      "author": "lin@example.com",
      "joined": true,
    }),
    msg(8, "agent", claude, "高度先按 90 估，量过一次就记住。深色模式我一起看。要不要把旧的截图也一起换掉？", "30 分钟前", {
      "ending": "need_decision",
      "card": {
        "type": "options",
        "assigneeText": "等 林 决定",
        "options": [
          { "label": "先不换", "detail": "这次只改列表，截图下次再说" },
          { "label": "一起换", "detail": "把首页和聊天页的截图都更新", "recommended": true },
        ],
      },
      "decision": { "resolved": false },
      "asked": true,
    }),
    msg(9, "ember", { "name": "still.fail" }, "⚠️ Studio 上 codex 的登录已失效：请在设置里重新登录。", "20 分钟前", {}),
    msg(10, "agent", claude, "推送截图前要先登录 gh。", "15 分钟前", {
      "card": { "type": "login", "login": "login-1" },
      "decision": { "resolved": false },
    }),
    msg(11, "agent", claude, "做完了：列表、跳到最新的按钮、加载更早的消息都好了，截图也换了。", "5 分钟前", {
      "ending": "all_done",
    }),
  ]
  let all = early + messages
  {
    "archived": false,
    "me": { "email": "lin@example.com" },
    "thread": { "id": 7, "unread": 0 },
    "title": "整理发布清单",
    "people": [me, ana],
    "agents": [
      {
        "session": {
          "key": "s-c1",
          "runtime": "claude",
          "maker": { "id": "anthropic", "name": "Anthropic" },
          "agentText": "Claude",
        },
        "status": "idle",
      },
    ],
    "messages": Json::array(all),
    "more": Json::boolean(older < 2),
    "newer": false,
    "outbox": [],
    "offline": false,
    "archivable": true,
    // what waits to be decided: the two cards not answered (with_cards takes those answered here off)
    "asks": [{ "seq": 8 }, { "seq": 10 }],
  }
}

///|
/// Any other row's chat: what was asked, and the answer.
fn small_chat(title : String, session : String) -> Json {
  let claude = by_agent("anthropic", "claude", session)
  {
    "me": { "email": "lin@example.com" },
    "thread": { "id": 8, "unread": 0 },
    "title": Json::string(title),
    "people": [],
    "agents": [
      {
        "session": {
          "key": Json::string(session),
          "runtime": "claude",
          "maker": { "id": "anthropic", "name": "Anthropic" },
          "agentText": "Claude",
        },
        "status": "idle",
      },
    ],
    "messages": [
      msg(1, "person", by_person("林"), title, "1 小时前", { "mine": true }),
      msg(2, "agent", claude, "好的，我来处理。", "1 小时前", {}),
    ],
    "more": false,
    "outbox": [],
    "offline": false,
  }
}

///|
/// Thousands of messages, of the kinds a long chat has: short words back and forth, an agent's Markdown now and then.
fn long_chat(n : Int) -> Json {
  let claude = by_agent("anthropic", "claude", "s-c1")
  let out : Array[Json] = []
  for i in 0..<n {
    let seq = i + 1
    let m = match i % 5 {
      0 => msg(seq, "person", by_person("林"), "第 \{seq} 条：这一步看起来可以了，继续下一步。", "昨天", { "mine": true })
      1 => msg(seq, "agent", claude, long_reply, "昨天", {})
      2 => msg(seq, "agent", claude, "好的，第 \{seq} 步跑完了，`moon test` 全部通过，接着看第 \{seq + 1} 步。", "昨天", {})
      3 => msg(seq, "person", by_person("Ana"), "我这边也看了一下，第 \{seq} 条里的说明写得很清楚。", "昨天", {})
      _ => msg(seq, "agent", claude, "- 改了 \{i % 7 + 1} 个文件\n- 补了测试\n- 截图更新了\n\n> 下一步：把列表的估计高度调准一点。", "昨天", {})
    }
    out.push(m)
  }
  {
    "me": { "email": "lin@example.com" },
    "thread": { "id": 9, "unread": 0 },
    "title": "一个很长的对话",
    "people": [me, ana],
    "agents": [
      {
        "session": {
          "key": "s-c1",
          "runtime": "claude",
          "maker": { "id": "anthropic", "name": "Anthropic" },
          "agentText": "Claude",
        },
        "status": "idle",
      },
    ],
    "messages": Json::array(out),
    "more": false,
    "outbox": [],
    "offline": false,
  }
}

///|
/// The made-up chats as made the first time (made again each frame, a long one would cost more than the page).
let kept_chats : Map[String, Json] = {}

///|
fn kept_chat(key : String, make : () -> Json) -> Json {
  match kept_chats.get(key) {
    Some(v) => v
    None => {
      let v = make()
      kept_chats[key] = v
      v
    }
  }
}

///|
/// The pictures the made-up files are: soft gradients of their own, made once.
let fixture_pictures : Map[String, String] = {}

///|
fn fixture_file(name : String) -> String {
  match fixture_pictures.get(name) {
    Some(k) => k
    None => {
      let key = "mem:fixture/" + name
      @ui.add_image(key, fixture_file_png(name))
      fixture_pictures[name] = key
      key
    }
  }
}

///|
/// A made-up file's picture as PNG bytes: the same one its thumbnail in the chat shows and the preview opens.
fn fixture_file_png(name : String) -> Bytes {
  let (w, h, a, b) = match name {
    "home-after.png" => (60, 130, (0xF5, 0xF3, 0xEF), (0xE5, 0x70, 0x4A))
    "compare.png" => (160, 90, (0x5B, 0x7B, 0xB2), (0xF2, 0xB0, 0x1E))
    // a screen's preview (chat-screens): a frame of a tab, 16:10
    "peek.png" => (160, 100, (0xFF, 0xFF, 0xFF), (0x5B, 0x7B, 0xB2))
    _ => (120, 80, (0x2F, 0x8F, 0x5B), (0xE8, 0xE4, 0xDC))
  }
  let rgba = FixedArray::make(w * h * 4, b'\x00')
  for y in 0..<h {
    for x in 0..<w {
      let k = (x + y).to_double() / (w + h - 2).to_double()
      let i = (y * w + x) * 4
      let mix = fn(p : Int, q : Int) -> Byte { (p.to_double() + (q - p).to_double() * k).round().to_int().to_byte() }
      rgba[i] = mix(a.0, b.0)
      rgba[i + 1] = mix(a.1, b.1)
      rgba[i + 2] = mix(a.2, b.2)
      rgba[i + 3] = b'\xFF'
    }
  }
  @sf.png(w, h, rgba)
}

///|
/// The fixture's chat topics: the chat (by its session), the workspace's stations, its jobs, its login card.
fn fixture_chat_topic(f : Fixture, name : String, params : Map[String, Json]) -> Json? {
  let session = match params.get("session") {
    Some(String(s)) => s
    _ => ""
  }
  match name {
    "chat" =>
      if f.mode == "chat-loading" {
        None
      } else if f.mode == "chat-long" {
        Some(kept_chat("long", fn() { long_chat(3000) }))
      } else if session == "s-c1" {
        let base = kept_chat("rich/\{f.older}/\{f.mode}", fn() {
          let v = if f.mode == "chat-md" {
            with_md_message(rich_chat(f.older))
          } else if f.mode == "chat-viz" {
            with_viz_message(rich_chat(f.older))
          } else if f.mode == "chat-screens" {
            with_message(rich_chat(f.older), screens_answer)
          } else {
            rich_chat(f.older)
          }
          match (v, seeded_outbox(f.mode)) {
            (Object(m), out) if out.length() > 0 => {
              let o = m.copy()
              o["outbox"] = Json::array(out)
              Json::object(o)
            }
            _ => v
          }
        })
        Some(with_cards(f, with_sent(base, session), session))
      } else {
        // its row's title
        let mut title = ""
        for d in fixture_days(f) {
          for r in items(Some(d), "items") {
            if text(Some(r), "session") == session {
              title = text(Some(r), "title")
            }
          }
        }
        Some(with_sent(small_chat(title, session), session))
      }
    "stations" =>
      Some([
        {
          "station": "ws1/st1",
          "id": "st1",
          "name": "Studio",
          "icon": "glyph:desktop",
          "summary": "Apple M2 Max · 2 个 agent 在工作",
          "online": true,
          // its machine and network as its card (settings/station_peek.mbt) shows them
          "host": {
            "meters": [
              { "short": "CPU", "left": 72, "level": "ok", "remaining": "空闲 72%" },
              { "short": "内存", "left": 18, "level": "amber", "remaining": "剩 11.5 G" },
              { "short": "磁盘", "left": 41, "level": "ok", "remaining": "剩 380 G" },
            ],
          },
          "net": {
            "via": "direct",
            "path": "直连",
            "rtt": { "text": "38 ms", "level": "ok" },
            "down": "1.4 MB/s",
            "up": "96 KB/s",
            "downTotal": "212 MB",
            "upTotal": "9.6 MB",
          },
          "overview": fixture_station_drive(true),
        },
        {
          "station": "ws1/st2",
          "id": "st2",
          "name": "MBA",
          "icon": "glyph:laptop:teal",
          "online": false,
          "overview": fixture_station_drive(false),
        },
      ])
    "chatJobs" => Some({ "jobs": [] })
    // the `@` menu's (chat_refs.mbt): this station's chats whose title has the words (not the one written in), then
    // those of 个人 (fix_outside), saying whose
    "chatSearch" => {
      let query = match params.get("query") {
        Some(String(q)) => q
        _ => ""
      }
      let exclude = match params.get("exclude") {
        Some(String(x)) => x
        _ => ""
      }
      // `@` alone: the Android app's ChatShareTest's (its screenshots' twin, xws-menu): two of this workspace's, then
      // two of the viewer's other workspaces', each saying whose
      if query == "" && params.get("elsewhere") is Some(True) {
        return Some({
          "items": [
            row("c-2", "登录页在 Safari 上没反应", "ws1/st1", "12 分钟前", {}),
            row("c-3", "发版说明 0.1.2500", "ws1/st1", "40 分钟前", {}),
            row("c-9", "首页改版的配色方案", "ws-design/mac", "5 分钟前", { "outside": "设计组", "stationName": "mac" }),
            row("c-8", "Q3 招聘计划", "ws-acme/srv", "90 分钟前", { "outside": "Acme 海外", "stationName": "srv" }),
          ],
        })
      }
      let out : Array[Json] = []
      for d in fixture_days(f) {
        for r in items(Some(d), "items") {
          let title = text(Some(r), "title")
          if text(Some(r), "station") == "ws1/st1" &&
            text(Some(r), "session") != exclude &&
            title.contains(query) &&
            out.length() < 8 {
            out.push(r)
          }
        }
      }
      if params.get("elsewhere") is Some(True) {
        for x in fix_outside {
          let (id, title, _) = x
          if title.contains(query) && out.length() < 8 {
            out.push(
              row(id, title, "ws2/st9", "昨天", { "session": Json::string(id), "outside": "个人", "stationName": "家里" }),
            )
          }
        }
      }
      Some({ "items": Json::array(out) })
    }
    // chat-login: the login's page to open in the browser, for one who may (its pill opens it in a tab over the app;
    // what apps/android's MbuiCompareTest pictures beside it)
    "machineLogins" if f.mode == "chat-login" => Some({ "canLogin": true, "canRelay": true })
    "machineLogin" if f.mode == "chat-login" =>
      Some({
        "id": "login-1",
        "title": "在 Studio 上登录 gh",
        "state": "browser",
        "step": "open",
        "url": "https://github.com/login",
        "domain": "github.com",
        "active": true,
        "statusText": "在浏览器里完成登录",
      })
    "machineLogin" =>
      Some({
        "id": "login-1",
        "title": "在 Studio 上登录 gh",
        "state": "browser",
        "active": true,
        "statusText": "等你在浏览器里登录",
      })
    _ => fixture_drive_topic(f, name, params)
  }
}

// ── sending in the made-up chats ─────────────────────────────────────────
//
// The fixture takes what is sent as a station would: into the chat's outbox at once (正在发送), a moment later the
// chat's own message, and a moment after that an agent's made-up answer. Words with 失败 in them fail instead (未发送,
// with why), and go on 重试. Drafts are kept while the app runs; a file put up is taken at once. The modes
// chat-compose, chat-attach, chat-quote, chat-sending and chat-failed open the first row's chat with its composer in
// that state (scripts/shots.sh composer).

///|
/// A made-up chat as the fixture changes it: what was sent in it since (its messages, its outbox), by session.
priv struct FixChat {
  sent : Array[Json]
  outbox : Array[Json]
  /// its agent at work on what was sent (its activity shows), since when (ms)
  mut working : Double
}

///|
let fix_chats : Map[String, FixChat] = {}

///|
/// The made-up chats' threads, by id: their sessions (what is sent by thread goes to its session's chat).
let fix_threads : Map[Int, String] = {}

///|
fn fix_chat(session : String) -> FixChat {
  match fix_chats.get(session) {
    Some(f) => f
    None => {
      let f = { sent: [], outbox: [], working: -1.0 }
      fix_chats[session] = f
      f
    }
  }
}

///|
/// What the fixture's station does later (its answers): `ms` after it is said, on the window's runtime's clock
/// (Runtime::after: the station is outside the view, timed as a host's answer is), or on a test's own clock
/// (fix_clock). Due, it is done as the fixture is next read (fix_tick): what is shown reads it then.
let fix_due : Array[() -> Unit] = []

///|
/// What was said later before the window's first frame (as the fixture is made): handed to its runtime as the
/// fixture is first read, `ms` from then.
let fix_unsaid : Array[(Double, () -> Unit)] = []

///|
/// What is said later on a test's own clock (fix_clock), at a time on it.
let fix_timers : Array[(Double, () -> Unit)] = []

///|
/// The window's context of the frame being built (`view` sets it): none yet, the fixture is being made.
let fix_ctx : Ref[@ui.Ctx?] = { val: None }

///|
/// A test's own clock for the fixture's station, moved on by the test (none: the window's runtime times it).
let fix_clock : Ref[(() -> Double)?] = { val: None }

///|
let fix_drafts : Map[String, Json] = {}

///|
/// The chats of the viewer's other workspace (个人, its station ws2/st9) that a reference may name (`chat.outsideRefs`):
/// their keys, titles, and whether the viewer may share them.
// kept across runs: a table, never written
let fix_outside : Array[(String, String, Bool)] = [("s-p1", "季度路线图", true), ("s-p2", "预算草稿", false)]

///|
/// Those of them shared with 星火工作室 since (`chat.xshareAdd`): outside no more.
let fix_xshared : Map[String, Bool] = {}

///|
let fix_serial : Ref[Int] = { val: 0 }

///|
/// What is due, done (each a change: the views read again); what was said before the first frame, handed to the
/// runtime.
fn fix_tick(f : Fixture) -> Unit {
  if fix_ctx.val is Some(_) && fix_unsaid.length() > 0 {
    let unsaid = fix_unsaid.copy()
    fix_unsaid.clear()
    for u in unsaid {
      fix_later(u.0, u.1)
    }
  }
  match fix_clock.val {
    Some(clock) => {
      let now = clock()
      for t in fix_timers.filter(fn(t) { t.0 <= now }) {
        fix_due.push(t.1)
      }
      fix_timers.retain(fn(t) { t.0 > now })
    }
    None => ()
  }
  if fix_due.length() > 0 {
    let due = fix_due.copy()
    fix_due.clear()
    for d in due {
      d()
    }
    f.version += 1
  }
}

///|
/// What the fixture's station takes its time over: a message sent (or retried) is in the chat after
/// `fix_deliver_ms`; its agent answers `fix_answer_ms` after that, and its turn ends `fix_turn_end_ms` after the answer.
let fix_deliver_ms : Double = 700.0

///|
let fix_answer_ms : Double = 1400.0

///|
let fix_turn_end_ms : Double = 700.0

///|
fn fix_later(ms : Double, f : () -> Unit) -> Unit {
  match (fix_clock.val, fix_ctx.val) {
    (Some(clock), _) => fix_timers.push((clock() + ms, f))
    (None, Some(_)) => @ui.runtime().after(ms.ceil().to_int(), fn() { fix_due.push(f) })
    (None, None) => fix_unsaid.push((ms, f))
  }
}

///|
/// The chat with what was sent in it since.
fn with_sent(base : Json, session : String) -> Json {
  match field(field(Some(base), "thread"), "id") {
    Some(Number(n, ..)) => fix_threads[n.to_int()] = session
    _ => ()
  }
  match (fix_chats.get(session), base) {
    (Some(fc), Object(m)) if fc.sent.length() > 0 || fc.outbox.length() > 0 || fc.working >= 0.0 => {
      let o = m.copy()
      let all = match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      for x in fc.sent {
        all.push(x)
      }
      o["messages"] = Json::array(all)
      o["outbox"] = Json::array(fc.outbox.copy())
      if fc.working >= 0.0 {
        o["agents"] = Json::array(
          items(Some(base), "agents").map(fn(a) {
            match a {
              Object(am) => {
                let w = am.copy()
                w["status"] = Json::string("running")
                w["started"] = Json::boolean(true)
                w["since"] = Json::number(fc.working)
                Json::object(w)
              }
              _ => a
            }
          }),
        )
      }
      Json::object(o)
    }
    _ => base
  }
}

///|
/// An entry of the outbox (Outgoing).
fn outgoing_json(id : String, params : Json, state : String, error : String) -> Json {
  let p = Some(params)
  let o : Map[String, Json] = {
    "id": Json::string(id),
    "text": Json::string(text(p, "text")),
    "attachments": Json::array(items(p, "attachments")),
    "quotes": Json::array(items(p, "quotes")),
    "createdAt": 0,
    "state": Json::string(state),
  }
  if error != "" {
    o["error"] = Json::string(error)
  }
  Json::object(o)
}

///|
/// The station has it: out of the outbox, the chat's own message; the agent's answer a moment after.
fn fix_deliver(session : String, id : String) -> Unit {
  let fc = fix_chat(session)
  let mut found : Json? = None
  for o in fc.outbox {
    if text(Some(o), "id") == id {
      found = Some(o)
    }
  }
  guard found is Some(params) else { return }
  let words = text(Some(params), "text")
  if words.contains("失败") && text(Some(params), "state") != "retried" {
    fc.outbox.retain(fn(o) { text(Some(o), "id") != id })
    fc.outbox.push(outgoing_json(id, params, "failed", "Studio 没有回应（假数据：带「失败」的消息先发不出去）"))
    return
  }
  fc.outbox.retain(fn(o) { text(Some(o), "id") != id })
  fix_serial.val += 1
  let seq = 100 + fix_serial.val
  fc.sent.push(
    msg(seq, "person", by_person("林"), words, "刚刚", {
      "mine": true,
      "author": "lin@example.com",
      "ts": Json::string("sent\{fix_serial.val}"),
      "attachments": Json::array(items(Some(params), "attachments")),
      "quotes": Json::array(items(Some(params), "quotes")),
    }),
  )
  // its agent sets to work at once (its activity comes in), answers a moment later (its answer said while the chat
  // shows: out of the activity's avatar), and its turn ends a moment after that
  // (at work from its source's now: the fixture's is 0, fixture.mbt)
  fc.working = 0.0
  fix_later(fix_answer_ms, fn() {
    fix_serial.val += 1
    fix_later(fix_turn_end_ms, fn() { fix_chat(session).working = -1.0 })
    let first = paste_preview(words)
    let said = if first == "" {
      "收到文件了，我看一下。"
    } else {
      let cut = if first.length() > 40 {
        first.view(end_offset=40).to_string() + "…"
      } else {
        first
      }
      "收到：「" + cut + "」。我先看一下，有结果再告诉你。"
    }
    fix_chat(session).sent.push(
      msg(100 + fix_serial.val, "agent", by_agent("anthropic", "claude", session), said, "刚刚", {
        "ts": Json::string("reply\{fix_serial.val}"),
        "said": true,
      }),
    )
  })
}

///|
/// The fixture's writes in a chat (`chat.send`, `chat.retry`, `chat.discard`, `draft.get`, `draft.put`,
/// `station.upload.part`, `session.warm`), and what the page tells (`client.focus`, `chat.place`): None for any other.
fn fixture_chat_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
  let p = Some(params)
  let session = match text(p, "session") {
    "" =>
      match field(p, "thread") {
        Some(Number(n, ..)) => fix_threads.get(n.to_int()).unwrap_or("s-c1")
        _ => "s-c1"
      }
    s => s
  }
  match name {
    "chat.send" => {
      fix_serial.val += 1
      let id = "out\{fix_serial.val}"
      fix_chat(session).outbox.push(outgoing_json(id, params, "sending", ""))
      f.version += 1
      fix_later(fix_deliver_ms, fn() { fix_deliver(session, id) })
      Some(Ok(Json::object({})))
    }
    "chat.retry" => {
      let id = text(p, "id")
      let fc = fix_chat(session)
      let mut was : Json = Json::object({})
      for o in fc.outbox {
        if text(Some(o), "id") == id {
          was = o
        }
      }
      fc.outbox.retain(fn(o) { text(Some(o), "id") != id })
      fc.outbox.push(outgoing_json(id, was, "retried", ""))
      f.version += 1
      fix_later(fix_deliver_ms, fn() { fix_deliver(session, id) })
      Some(Ok(Json::object({})))
    }
    "chat.discard" => {
      let id = text(p, "id")
      fix_chat(session).outbox.retain(fn(o) { text(Some(o), "id") != id })
      f.version += 1
      Some(Ok(Json::object({})))
    }
    "draft.get" => {
      let key = text(p, "key")
      match fix_drafts.get(key) {
        Some(d) => Some(Ok(d))
        None => Some(Ok(seeded_draft(f.mode, key)))
      }
    }
    "draft.put" =>
      match params {
        Object(m) => {
          let d = m.copy()
          d.remove("key")
          fix_drafts[text(p, "key")] = Json::object(d)
          Some(Ok(Json::object({})))
        }
        _ => Some(Err({ "code": "invalid_params", "message": "draft.put" }))
      }
    "station.upload.part" => {
      let name = text(p, "name")
      let id = text(p, "id")
      Some(
        Ok({
          "file": {
            "name": Json::string(name),
            "path": Json::string("uploads/" + id + "/" + name),
            "size": Json::number(number(p, "size")),
          },
        }),
      )
    }
    "session.warm" | "client.focus" | "chat.place" => Some(Ok(Json::object({})))
    // a chat's mark (chat.ref): `@[its title]`, its link kept; links kept for marks (chat.refs)
    "chat.ref" => Some(Ok({ "mark": Json::string("@[" + text(p, "title") + "]") }))
    "chat.refs" => Some(Ok(Json::object({})))
    // what the words refer to in 个人 not shared with 星火工作室 yet, by their marks (`@[title]`)
    "chat.outsideRefs" => {
      let words = text(p, "text")
      let chats : Array[Json] = []
      for x in fix_outside {
        let (id, title, may) = x
        if words.contains("@[" + title + "]") && !fix_xshared.contains(id) {
          chats.push({
            "station": "ws2/st9",
            "id": Json::string(id),
            "title": Json::string(title),
            "workspace": "ws2",
            "workspaceName": "个人",
            "may": Json::boolean(may),
          })
        }
      }
      Some(Ok({ "chats": Json::array(chats) }))
    }
    "chat.xshareAdd" => {
      let id = text(p, "id")
      if fix_outside.iter().any(fn(x) { x.0 == id && x.2 }) {
        fix_xshared[id] = true
        Some(Ok(Json::object({})))
      } else {
        Some(Err({ "code": "forbidden", "message": "没有分享权限" }))
      }
    }
    _ => fixture_drive_call(f, name, params)
  }
}

///|
/// The first row's chat's draft as each composer mode has it (none in any other).
fn seeded_draft(mode : String, key : String) -> Json {
  if key != "ws1/st1:s-c1" {
    return Json::null()
  }
  match mode {
    "chat-compose" =>
      {
        "text": "把发布清单再过一遍：\n1. 版本号和更新说明\n2. 安卓和 mac 的包都要签名\n3. 截图换成新的",
        "quotes": [],
        "files": [],
      }
    // chat-attach-row: a station's file before them (drive_fixture.mbt), the row wider than the capsule
    "chat-attach" | "chat-attach-row" =>
      {
        "text": "截图和构建日志都在这里，帮我看看第二屏",
        "quotes": [],
        "files": [file("compare.png", 1600, 900, 402000), file("build.log", 0, 0, 18432)],
      }
    "chat-quote" =>
      {
        "text": "",
        "quotes": [
          {
            "author": "Claude",
            "text": "其余的行按估计的高度占位，滚到时再量真实高度",
            "comment": "",
            "ts": "ts3",
            "role": "agent",
          },
        ],
        "files": [],
      }
    _ => Json::null()
  }
}

///|
/// The outbox the first row's chat opens with in the modes chat-sending and chat-failed.
fn seeded_outbox(mode : String) -> Array[Json] {
  let words : Json = { "text": "好，就按这个改，顺便把深色模式的截图也换掉" }
  match mode {
    "chat-sending" => [outgoing_json("o-seed", words, "sending", "")]
    "chat-failed" => [outgoing_json("o-seed", words, "failed", "Studio 没有回应")]
    _ => []
  }
}

// ── the made-up chat's cards, answered here ─────────────────────────────
//
// The fixture takes a card's answer as the core does (Decisions.kt): answered at once (the option picked, 你 选择了
// 「…」 as how it went), let go at once (no longer asked). An option with 失败 in it fails. The modes chat-cards (the
// card answered) and chat-answering (an option under way) open the first row's chat so (scripts/shots.sh cards).

///|
/// How the first row's chat's cards stand as answered here: by seq, the card's decision.
let fix_decided : Map[Int, Json] = {}

///|
/// The chat `v` with what was answered here in it.
fn with_cards(f : Fixture, v : Json, session : String) -> Json {
  let seeded = f.mode == "chat-cards"
  if session != "s-c1" || (fix_decided.is_empty() && !seeded) {
    return v
  }
  match v {
    Object(m) => {
      let o = m.copy()
      let all = match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      for i, x in all {
        let seq = number(Some(x), "seq").to_int()
        let decided = match fix_decided.get(seq) {
          Some(d) => Some(d)
          None if seeded && seq == 8 => Some(decided_json("一起换"))
          None => None
        }
        match (decided, x) {
          (Some(d), Object(xm)) => {
            let y = xm.copy()
            y["decision"] = d
            y["asked"] = Json::boolean(false)
            all[i] = Json::object(y)
          }
          _ => ()
        }
      }
      o["messages"] = Json::array(all)
      // what waits to be decided: the cards still not answered
      o["asks"] = Json::array(
        all
        .filter(fn(x) { field(field(Some(x), "decision"), "resolved") is Some(False) })
        .map(fn(x) { { "seq": Json::number(number(Some(x), "seq")) } }),
      )
      Json::object(o)
    }
    _ => v
  }
}

///|
/// A card answered with `label`, as the core says it.
fn decided_json(label : String) -> Json {
  {
    "resolved": true,
    "chosen": Json::string(label),
    "text": Json::string("你 选择了「" + label + "」"),
  }
}

///|
/// The cards' calls in the made-up chat (`decision.answer`, `decision.dismiss`): None for any other.
fn fixture_card_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
  let p = Some(params)
  let seq = number(p, "seq").to_int()
  match name {
    "decision.answer" => {
      let label = text(p, "option")
      if label.contains("失败") {
        return Some(Err({ "code": "unavailable", "message": "Studio 没有回应" }))
      }
      fix_decided[seq] = decided_json(label)
      f.version += 1
      Some(Ok(Json::object({})))
    }
    "decision.dismiss" => {
      fix_decided[seq] = { "resolved": false, "dismissed": true }
      f.version += 1
      Some(Ok(Json::object({})))
    }
    _ => None
  }
}

///|
/// What the modes of the cards and words set going as the chat opens: chat-answering's option under way, chat-pick's
/// word picked, chat-link-menu's link held.
pub fn open_cards_fixture(mode : String) -> Unit {
  match mode {
    "chat-answering" => dui.doing["answer/" + seq_key("ws1/st1", 7.0, 8.0) + "/一起换"] = true
    // a word of the last post picked (its handles and its bar), once laid out (pick.mbt)
    "chat-pick" => {
      pk.ts = "ts11"
      pk.key = "pick/ts11"
      pk.author = "Claude"
      pk.role = "agent"
      pk.a = 4
      pk.b = 6
    }
    // the bare address in the long answer held: its menu (link_menu.mbt)
    "chat-link-menu" => {
      link_menu.href = "https://example.com/bench/list"
      link_menu.x = 220.0
      link_menu.top = 360.0
      link_menu.bottom = 383.0
      link_menu.open = true
    }
    _ => ()
  }
}

// ── Markdown's tables and code (MBUI_FIXTURE=chat-md) ───────────────────

///|
/// An agent's answer with a table, highlighted code (one line too long for the message: it scrolls sideways) and a
/// command, at the end of the first row's chat.
let md_answer : String =
  #|对比了三种做法，结果如下：
  #|
  #|| 做法 | 首帧耗时 | 内存 | 结论 |
  #||:--|--:|--:|:-:|
  #|| 全量重排 | 4.2 ms | 18 MB | 太慢 |
  #|| 按行缓存 | 1.1 ms | 22 MB | 可以 |
  #|| 只排可见的行，其余按估计高度占位 | 0.6 ms | 12 MB | 采用 |
  #|
  #|```ts
  #|export function placeRows(rows: Row[], from: number): number {
  #|  const visible = rows.filter((r) => r.top >= from && r.top < from + window.innerHeight * 2) // 只排屏幕附近的行
  #|  return visible.length
  #|}
  #|```
  #|
  #|```sh
  #|pnpm test --filter list -- --reporter dot
  #|```

///|
fn with_viz_message(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let all = match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      all.push(
        msg(12, "agent", by_agent("anthropic", "claude", "s-c1"), viz_answer, "1 分钟前", {
          "attachments": [file("release.html", 0, 0, 1200)],
          "placed": ["release.html"],
          "ending": "all_done",
        }),
      )
      o["messages"] = Json::array(all)
      Json::object(o)
    }
    _ => v
  }
}

///|
/// The words of MBUI_FIXTURE=chat-viz's last message: a visualization placed, and a mermaid chart.
let viz_answer : String =
  #|这周的发布节奏：
  #|
  #|[发布节奏](release.html)
  #|
  #|流程是这样：
  #|
  #|```mermaid
  #|graph LR; 构建-->签名-->发布
  #|```

///|
/// MBUI_FIXTURE=chat-viz's visualization: a fragment, as the viz skill has agents write them.
let fixture_viz_html : String =
  #|<div class="viz-card" style="padding:16px"><b>本周发布</b><p>周一 2 个、周三 1 个、周五 3 个</p>
  #|<button onclick="ember.setWidgetState({seen:true})">看过了</button></div>

///|
fn with_md_message(v : Json) -> Json {
  with_message(v, md_answer)
}

///|
/// The chat with an agent's answer of `words` at its end.
fn with_message(v : Json, words : String) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let all = match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      all.push(
        msg(12, "agent", by_agent("anthropic", "claude", "s-c1"), words, "1 分钟前", {
          "ending": "all_done",
        }),
      )
      o["messages"] = Json::array(all)
      Json::object(o)
    }
    _ => v
  }
}

// ── links to a station's screens and its 共享调试 (MBUI_FIXTURE=chat-screens) ──

///|
/// An agent's answer with links to Studio's screens and its 共享调试 (screen_links.mbt): the desktop's card, a tab's
/// with its preview (the link's own words its title), a tab gone, 共享调试 bare in a sentence (its title) and alone
/// (its card), and a link to anywhere else.
let screens_answer : String =
  #|登录页改好了，Studio 的桌面开着：
  #|
  #|https://still.fail/w/ws1/s/st1/screen/desktop
  #|
  #|预览在它的浏览器里：
  #|
  #|[发布清单预览](https://still.fail/w/ws1/s/st1/screen/browser%3AT1)
  #|
  #|之前那个标签页已经关了：
  #|
  #|https://still.fail/w/ws1/s/st1/screen/browser%3AT0
  #|
  #|要在手机上试，先打开 https://still.fail/w/ws1/s/st1/adb ；设计稿在 https://example.com/login-v2 。
  #|
  #|https://still.fail/w/ws1/s/st1/adb

///|
/// The core's cards of Studio's screens and its 共享调试 (`screenCard`, `adbCard`): the desktop someone looks at, a
/// tab it previews (1280 × 800), a tab it no longer has; this phone's adb not shared.
fn fixture_link_card(name : String, params : Map[String, Json]) -> Json? {
  if name == "adbCard" {
    return Some({ "title": "共享调试", "line": "未共享", "sharing": false, "lendable": true })
  }
  let screen = match params.get("screen") {
    Some(String(s)) => s
    _ => ""
  }
  let card = fn(kind : String, title : String, line : String, gone : Bool, peek : Bool, w : Int, h : Int) -> Json {
    {
      "kind": Json::string(kind),
      "title": Json::string(title),
      "line": Json::string(line),
      "link": Json::string("/w/ws1/s/st1/screen/" + screen),
      "gone": Json::boolean(gone),
      "peek": Json::boolean(peek),
      "width": Json::number(w.to_double()),
      "height": Json::number(h.to_double()),
    }
  }
  match screen {
    "desktop" => Some(card("desktop", "桌面", "Ana 正在查看", false, false, 3024, 1964))
    "browser:T1" => Some(card("browser", "发布清单 - localhost:5173", "林 正在查看", false, true, 1280, 800))
    "browser:T0" => Some(card("browser", "浏览器标签页", "此屏幕已不存在", true, false, 0, 0))
    _ => Some(card("desktop", "桌面", "远程屏幕", false, false, 0, 0))
  }
}

///|
/// A screen's preview (`screen.view` with `peek`): one frame, the made-up tab's picture, as the station sends its
/// first.
fn fixture_peek(on_value : (Json, Bytes?) -> Unit) -> Int {
  fix_later(0.0, fn() { on_value({ "frame": { "ts": 1 } }, Some(fixture_file_png("peek.png"))) })
  fix_stream_ids.val += 1
  fix_stream_ids.val
}
