// A made-up chat in the core's shapes (ChatView), for the app with no core (fixture.mbt): the first row's chat
// ("整理发布清单") holds every kind of message a chat shows: still.fail's notices (one failing), the viewer's words
// (one quoting, two sent close together), a person's with a picture, an agent's long Markdown (headings, lists,
// a task list, a quote, code, links, a reference to another chat), its files placed in its words and below them, a
// message it sent to Slack, an options card, a login card, its last post offering to archive the chat. An older
// page comes in when the reader nears the top (`chat.older`). Every other row's chat is two lines. "chat-long" is a
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
    "archiveOffered": true,
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
      let (w, h, a, b) = match name {
        "home-after.png" => (60, 130, (0xF5, 0xF3, 0xEF), (0xE5, 0x70, 0x4A))
        "compare.png" => (160, 90, (0x5B, 0x7B, 0xB2), (0xF2, 0xB0, 0x1E))
        _ => (120, 80, (0x2F, 0x8F, 0x5B), (0xE8, 0xE4, 0xDC))
      }
      let rgba = FixedArray::make(w * h * 4, b'\x00')
      for y in 0..<h {
        for x in 0..<w {
          let k = (x + y).to_double() / (w + h - 2).to_double()
          let i = (y * w + x) * 4
          let mix = fn(p : Int, q : Int) -> Byte {
            (p.to_double() + (q - p).to_double() * k).round().to_int().to_byte()
          }
          rgba[i] = mix(a.0, b.0)
          rgba[i + 1] = mix(a.1, b.1)
          rgba[i + 2] = mix(a.2, b.2)
          rgba[i + 3] = b'\xFF'
        }
      }
      let key = "mem:fixture/" + name
      @ui.add_image(key, @sf.png(w, h, rgba))
      fixture_pictures[name] = key
      key
    }
  }
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
          let v = rich_chat(f.older)
          match (v, seeded_outbox(f.mode)) {
            (Object(m), out) if out.length() > 0 => {
              let o = m.copy()
              o["outbox"] = Json::array(out)
              Json::object(o)
            }
            _ => v
          }
        })
        Some(with_sent(base, session))
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
          "online": true,
          "net": { "via": "direct" },
        },
        { "station": "ws1/st2", "id": "st2", "name": "MBA", "icon": "glyph:laptop:teal", "online": false },
      ])
    "chatJobs" => Some({ "jobs": [] })
    "machineLogin" =>
      Some({
        "id": "login-1",
        "title": "在 Studio 上登录 gh",
        "state": "browser",
        "active": true,
        "statusText": "等你在浏览器里登录",
      })
    _ => None
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
      let f = { sent: [], outbox: [] }
      fix_chats[session] = f
      f
    }
  }
}

///|
/// What happens later (the station's answers), at a time of day in ms.
let fix_timers : Array[(Double, () -> Unit)] = []

///|
/// The fixture's clock and how it asks for a frame later (a test sets its own).
let fix_clock : Ref[() -> Double] = { val: fn() { @host.now() } }

///|
let fix_wake : Ref[(Double) -> Unit] = { val: fn(ms) { @host.wake_after(ms) } }

///|
let fix_drafts : Map[String, Json] = {}

///|
let fix_serial : Ref[Int] = { val: 0 }

///|
/// The timers due, run (each a change: the views read again); a frame asked for the next.
fn fix_tick(f : Fixture) -> Unit {
  if fix_timers.length() == 0 {
    return
  }
  let now = (fix_clock.val)()
  let due = fix_timers.filter(fn(t) { t.0 <= now })
  if due.length() > 0 {
    fix_timers.retain(fn(t) { t.0 > now })
    for t in due {
      (t.1)()
    }
    f.version += 1
  }
  let mut next = -1.0
  for t in fix_timers {
    if next < 0.0 || t.0 < next {
      next = t.0
    }
  }
  if next >= 0.0 {
    (fix_wake.val)(dmax(next - now, 1.0))
  }
}

///|
fn fix_later(ms : Double, f : () -> Unit) -> Unit {
  fix_timers.push(((fix_clock.val)() + ms, f))
  (fix_wake.val)(ms)
}

///|
/// The chat with what was sent in it since.
fn with_sent(base : Json, session : String) -> Json {
  match field(field(Some(base), "thread"), "id") {
    Some(Number(n, ..)) => fix_threads[n.to_int()] = session
    _ => ()
  }
  match (fix_chats.get(session), base) {
    (Some(fc), Object(m)) if fc.sent.length() > 0 || fc.outbox.length() > 0 => {
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
  fix_later(1400.0, fn() {
    fix_serial.val += 1
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
      fix_later(700.0, fn() { fix_deliver(session, id) })
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
      fix_later(700.0, fn() { fix_deliver(session, id) })
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
    _ => None
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
    "chat-attach" =>
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
