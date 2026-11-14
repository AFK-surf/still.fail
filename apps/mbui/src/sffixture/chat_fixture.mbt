// A made-up chat in the core's shapes (ChatView), for the app with no core (fixture.mbt): the first row's chat
// ("整理发布清单") holds every kind of message a chat shows: still.fail's notices (one failing), the viewer's words
// (one quoting, two sent close together), a person's with a picture, an agent's long Markdown (headings, lists,
// a task list, a quote, code, links, a reference to another chat), its files placed in its words and below them, a
// message it sent to Slack, an options card, a login card, its last post offering to archive the chat. An older
// page comes in when the reader nears the top (`chat.older`); "chat-login" its login card for one who may finish it,
// its page to open in the browser. Every other row's chat is two lines. "chat-long" is a
// chat of thousands of messages, for timing the list. Every word here is made up.

///|
pub fn by_agent(maker : String, runtime : String, key : String) -> Json {
  { "name": "Claude", "agent": Json::string(key), "maker": { "id": Json::string(maker), "name": Json::string(maker) }, "runtime": Json::string(runtime) }
}

///|
pub fn by_person(name : String) -> Json {
  { "name": Json::string(name) }
}

///|
/// When a message (an outgoing one, one said elsewhere) was said, as a chat says it (SaidAt).
pub fn ago(s : String, full : String) -> Json {
  { "createdAt": { "ago": Json::string(s), "full": Json::string(full) } }
}

///|
/// A message: its seq, who said it, its words, and the rest as the view gives it.
pub fn msg(
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
  // a person's words in runs, as the core gives them (views.ts drawn: personWords)
  if kind == "person" {
    match @sf.kept_words(text) {
      Some(w) => m["words"] = w
      None => ()
    }
  }
  for k, v in more {
    m[k] = v
  }
  Json::object(m)
}

///|
pub fn file(name : String, w : Int, h : Int, size : Int) -> Json {
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
/// A film as the station keeps it in a message: its size, and its length (ms) and frames as read from its header.
pub fn film_file(name : String, w : Int, h : Int, size : Int, ms : Int, frames : Int) -> Json {
  match file(name, w, h, size) {
    Object(f) => {
      let f = f.copy()
      f["duration"] = Json::number(ms.to_double())
      f["frames"] = Json::number(frames.to_double())
      Json::object(f)
    }
    j => j
  }
}

///|
pub let long_reply : String =
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
/// How many pages before its first the first row's chat has (`chat.older` brings one each): what its device holds of
/// it, all of them.
let rich_chat_pages : Int = 2

///|
/// The first row's chat, its page of `older` pages back included.
pub fn rich_chat(older : Int) -> Json {
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
    msg(1, "ember", { "name": "still.fail" }, "Willow 上的 claude 已启动。", "3 小时前", {
      "notice": { "failed": false, "words": "Willow 上的 claude 已启动" },
    }),
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
    msg(9, "ember", { "name": "still.fail" }, "⚠️ Willow 上 codex 的登录已失效：请在设置里重新登录。", "20 分钟前", {
      "notice": { "failed": true, "words": "Willow 上 codex 的登录已失效：请在设置里重新登录" },
    }),
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
          // (where it stands in words and its tone, as the core says an idle one: present.ts session, format.ts)
          "statusText": "未开始",
          "tone": "neutral",
        },
        "status": "idle",
      },
    ],
    "messages": Json::array(all),
    "more": Json::boolean(older < rich_chat_pages),
    "newer": false,
    "outbox": [],
    "offline": false,
    "archivable": true,
    // what waits to be decided: the two cards not answered (with_cards takes those answered here off)
    "asks": [{ "seq": 8 }, { "seq": 10 }],
    // (posts after them: the end keeps clear of the bell to them)
    "askClear": true,
  }
}

///|
/// Any other row's chat: what was asked, and the answer.
pub fn small_chat(title : String, session : String) -> Json {
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
          // (where it stands in words and its tone, as the core says an idle one: present.ts session, format.ts)
          "statusText": "未开始",
          "tone": "neutral",
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
/// An archived chat's title by its session, as the archive lists it (settings' fixture.mbt fx_archive): "" for none.
fn archived_title(session : String) -> String {
  match session {
    "s-a1" => "整理上个月的发票"
    "s-a2" => "试一下新的图标尺寸"
    "s-a3" => "周会纪要"
    "s-a4" => "清理旧的构建缓存"
    _ => ""
  }
}

///|
/// A chat just made from a new chat (`new:N`, newChat.create): named by no one yet (新对话, as the core calls it),
/// nothing said in it.
pub fn made_chat(session : String) -> Json {
  match small_chat("新对话", session) {
    Object(m) => {
      let o = m.copy()
      o["messages"] = Json::array([])
      Json::object(o)
    }
    v => v
  }
}

///|
/// Thousands of messages, of the kinds a long chat has: short words back and forth, an agent's Markdown now and then.
pub fn long_chat(n : Int) -> Json {
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
          // (where it stands in words and its tone, as the core says an idle one: present.ts session, format.ts)
          "statusText": "未开始",
          "tone": "neutral",
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
pub let kept_chats : Map[String, Json] = Map([])

///|
pub fn kept_chat(key : String, make : () -> Json) -> Json {
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
/// The pictures the made-up files are: soft gradients of their own, made once (by name: the key they are shown by, and
/// their bytes).
pub let fixture_pictures : Map[String, (String, Bytes)] = Map([])

///|
pub fn fixture_file(name : String) -> String {
  let (key, png) = match fixture_pictures.get(name) {
    Some(p) => p
    None => {
      let p = ("mem:fixture/" + name, fixture_file_png(name))
      fixture_pictures[name] = p
      p
    }
  }
  // (handed over each time it is asked for: what holds what is handed over, mbui's, is emptied as each Tester starts,
  // whether the file was asked for before that or after)
  @ui.add_image(key, png)
  key
}

///|
/// A made-up file's picture as PNG bytes: the same one its thumbnail in the chat shows and the preview opens.
pub fn fixture_file_png(name : String) -> Bytes {
  let (w, h, a, b) = match name {
    "home-after.png" => (60, 130, (0xF5, 0xF3, 0xEF), (0xE5, 0x70, 0x4A))
    "before.png" => (60, 130, (0xF5, 0xF3, 0xEF), (0x9A, 0xA4, 0xB0))
    "after.png" => (60, 130, (0xF5, 0xF3, 0xEF), (0x5B, 0x7B, 0xB2))
    "compare.png" => (160, 90, (0x5B, 0x7B, 0xB2), (0xF2, 0xB0, 0x1E))
    // a screen's preview (chat-screens): a frame of a tab, 16:10
    "peek.png" => (160, 100, (0xFF, 0xFF, 0xFF), (0x5B, 0x7B, 0xB2))
    // a video's still (its poster: a frame of a screen recording, 16:9)
    "演示录屏.mp4" => (160, 90, (0x1E, 0x2A, 0x3A), (0x5B, 0x7B, 0xB2))
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
  @pixels.png(w, h, rgba)
}

///|
/// The fixture's chat topics: the chat (by its session), the workspace's stations, its jobs, its login card.
pub fn fixture_chat_topic(f : Fixture, name : String, params : Map[String, Json]) -> Json? {
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
        let base = kept_chat("rich/\{f.older}/\{f.mode}/\{f.step}", fn() {
          let v = if outline_mode(f.mode) {
            outline_chat(f.mode, around=f.older > 0)
          } else if f.mode == "chat-overload-before" || f.mode == "chat-overload-after" {
            with_overload_notice(rich_chat(f.older), f.mode == "chat-overload-after", f.step > 0)
          } else if f.mode == "chat-turn-failed" {
            with_failed_turn(rich_chat(f.older), f.step > 0)
          } else if f.mode == "chat-turn-limit" {
            with_limit_turn(rich_chat(f.older), f.step > 0)
          } else if f.mode == "chat-turn-unanswered" {
            with_unanswered_turn(rich_chat(f.older), f.step > 0)
          } else if f.mode == "chat-model-limit-before" || f.mode == "chat-model-limit-after" {
            with_model_limit(rich_chat(f.older), f.mode == "chat-model-limit-after")
          } else if f.mode == "chat-run-change" {
            with_run_change(rich_chat(f.older))
          } else if f.mode == "chat-md" {
            with_md_message(rich_chat(f.older))
          } else if f.mode == "chat-viz" {
            with_viz_message(rich_chat(f.older))
          } else if f.mode == "chat-file-links" {
            with_file_links(rich_chat(f.older))
          } else if f.mode == "chat-table-images" {
            with_table_images(rich_chat(f.older))
          } else if f.mode == "chat-screens" || f.mode == "chat-screens-pc" {
            // (its tree with it, as a station sends it: what the chat opens on reads its links' cards of it)
            with_message(rich_chat(f.older), screens_answer, md=@sf.kept_md(screens_answer))
          } else if f.mode == "chat-screens-cold" {
            with_cache_cold(with_message(rich_chat(f.older), screens_answer))
          } else if f.mode == "chat-archived" {
            with_flag(rich_chat(f.older), "archived")
          } else if f.mode == "chat-cold-offline" {
            with_flag(with_cache_cold(rich_chat(f.older)), "offline")
          } else if f.mode == "chat-peeks" {
            with_message(rich_chat(f.older), peeks_answer)
          } else if f.mode == "chat-letters" && f.older == 0 {
            with_none_shown(rich_chat(f.older))
          } else if f.mode == "chat-cc" {
            with_cc(rich_chat(f.older))
          } else if f.mode == "chat-need" {
            with_need(rich_chat(f.older))
          } else if f.mode == "chat-working" {
            with_working(rich_chat(f.older))
          } else if f.mode == "chat-update" {
            with_station_update(rich_chat(f.older))
          } else if f.mode == "chat-station-screen" || f.mode == "chat-station-screens" || f.mode == "chat-agent-screens" {
            with_chat_screens(rich_chat(f.older), f.mode != "chat-station-screen")
          } else if f.mode == "chat-cache-cold" {
            with_cache_cold(rich_chat(f.older))
          } else if f.mode == "chat-done" {
            with_state(rich_chat(f.older), done_state)
          } else if f.mode == "chat-image-coming" {
            with_coming_screenshot(rich_chat(f.older))
          } else if f.mode == "chat-download" || f.mode == "chat-keeping" {
            with_download_message(rich_chat(f.older))
          } else if f.mode == "chat-download-on" {
            with_reply_after(with_download_message(rich_chat(f.older)))
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
        // chat-done-live: a chat whose agent's turn is over, saying where the chat stands as the core does: not while
        // words sent are on their way or its agent works (scripts/instrbench.sh's `send`)
        let sent = with_sent(base, session)
        let fc = fix_chat(session)
        let sent = if f.mode == "chat-done-live" && fc.outbox.is_empty() && fc.working < 0.0 {
          with_state(sent, done_state)
        } else {
          sent
        }
        Some(with_cards(f, sent, session))
      } else if session.has_prefix("new:") {
        // one just made from a new chat (newChat.create): nothing in it but what is sent to it
        Some(with_sent(made_chat(session), session))
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
        // (or the archive's row's: settings' fixture.mbt fx_archive, the same chats)
        if title == "" {
          title = archived_title(session)
        }
        Some(with_sent(small_chat(title, session), session))
      }
    "stations" =>
      Some([
        {
          "station": "ws1/st1",
          "id": "st1",
          "name": "Willow",
          "icon": "glyph:desktop",
          "summary": "Apple M1 Pro · 2 个 agent 在工作",
          // how it is, as the core says it (StationView stateText, problems)
          "stateText": "2 个 agent 正在运行",
          "stateBusy": true,
          "problems": [],
          "version": "0.1.4765",
          "online": true,
          // its machine and network as its card (settings/station_peek.mbt) and its page (src/sfdesk
          // station_page.mbt) show them
          "host": {
            "identity": "MacBook Pro · Apple M1 Pro",
            "meters": [
              {
                "short": "CPU",
                "left": 72,
                "level": "ok",
                "remaining": "空闲 72%",
                "big": "72",
                "unit": "%",
                "title": "CPU 空闲",
                "total": "负载 3.1",
              },
              {
                "short": "内存",
                "left": 18,
                "level": "amber",
                "remaining": "剩 5.8 G",
                "big": "5.8",
                "unit": "GB",
                "title": "内存剩",
                "total": "共 32 GB",
              },
              {
                "short": "磁盘",
                "left": 42,
                "level": "ok",
                "remaining": "剩 420 G",
                "big": "420",
                "unit": "GB",
                "title": "磁盘剩",
                "total": "共 1 TB",
              },
            ],
            "details": [
              { "label": "主机名", "value": "willow.local" },
              { "label": "系统", "value": "macOS 26.1 · arm64" },
              { "label": "已运行", "value": "12 天" },
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
          // (drive-roots: a member's, who browses only the folders it pins)
          "overview": if f.mode == "drive-roots" { fixture_station_member() } else { fixture_station_overview() },
        },
        {
          "station": "ws1/st2",
          "id": "st2",
          "name": "Maple",
          "icon": "glyph:laptop:teal",
          "stateText": "3 小时前在线",
          "problems": [{ "key": "away", "level": "red", "text": "离线：在该机器上打开 still.fail 即可重新连接" }],
          "online": false,
          "overview": fixture_station_drive(false),
        },
      ])
    "chatJobs" => Some({ "jobs": [] })
    // what people said in the chat, by the day (the core's `chatOutline`: outline_fixture.mbt)
    "chatOutline" => fixture_outline(f, params)
    // what was said in the chat besides words (the core's `chatThings`: sfpages things.mbt)
    // (the chat's sheet with one pull request, as tall as the window holds: its others with chat-info-pulls)
    "chatThings" => Some(fixture_things(text(Some(Json::object(params)), "q"), many=f.mode != "chat-info"))
    // the `@` menu's (chat_refs.mbt): the workspace's chats whose title has the words (not the one written in), those
    // of another station than the one written on saying so, then those of 个人 (fix_outside), saying whose
    "chatSearch" => {
      let query = match params.get("query") {
        Some(String(q)) => q
        _ => ""
      }
      let exclude = match params.get("exclude") {
        Some(String(x)) => x
        _ => ""
      }
      let written_on = match params.get("station") {
        Some(String(x)) => x
        _ => ""
      }
      // A full reference menu, for viewing and exercising its touch scrolling.
      if query == "" && f.mode == "chat-ref-many" {
        let names = ["整理发布清单", "首页列表的排序", "登录页的问题", "安卓更新通知", "对话里的图片", "工作区切换", "检查网络连接", "服务状态提醒"]
        let results : Array[Json] = []
        for i, name in names {
          results.push(row("ref-\{i}", name, "ws1/st1", "刚才", {}))
        }
        return Some({ "items": Json::array(results) })
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
          if text(Some(r), "session") != exclude && title.contains(query) && out.length() < 8 {
            match r {
              Object(m) if written_on != "" && text(Some(r), "station") != written_on => {
                let m = m.copy()
                m["otherStation"] = Json::boolean(true)
                out.push(Json::object(m))
              }
              _ => out.push(r)
            }
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
    // chat-login-station: the same, where the station's own browser can open it too
    // login-link: a loopback login opened from its Slack link (/w/<ws>/s/<station>/login/<id>) in a standalone sheet
    "machineLogins" if f.mode == "chat-login" || f.mode == "chat-login-station" || f.mode == "login-link" =>
      Some({ "canLogin": true, "canRelay": true })
    "machineLogin" if f.mode == "login-link" =>
      Some({
        "id": "login-1",
        "title": "在 Willow 上登录 gcloud",
        "state": "browser",
        "step": "loopback",
        "url": "https://accounts.google.com/o/oauth2/auth",
        "domain": "accounts.google.com",
        "active": true,
        "browser": true,
        "browserText": "在 Willow 的浏览器中打开",
        "statusText": "在浏览器里完成登录",
      })
    "machineLogin" if f.mode == "chat-login" || f.mode == "chat-login-station" => {
      let l : Map[String, Json] = {
        "id": "login-1",
        "title": "在 Willow 上登录 gh",
        "state": "browser",
        "step": "open",
        "url": "https://github.com/login",
        "domain": "github.com",
        "active": true,
        "statusText": "在浏览器里完成登录",
      }
      if f.mode == "chat-login-station" {
        l["browser"] = Json::boolean(true)
        l["browserText"] = Json::string("在 Willow 的浏览器中打开")
      }
      Some(Json::object(l))
    }
    "machineLogin" =>
      Some({
        "id": "login-1",
        "title": "在 Willow 上登录 gh",
        "state": "browser",
        "active": true,
        "statusText": "等你在浏览器里登录",
      })
    // the station's logins, answered as the core answers them (a chat with a login's card opens once they are:
    // sfbase's chat_opens): nothing under way through still.fail as the station lists it, the viewer one who may only
    // see how they stand (the card as it was drawn while none was answered)
    "machineLogins" =>
      Some({ "supported": true, "loaded": true, "canLogin": false, "canRelay": false, "logins": [], "tools": [] })
    // chat-working: its agent's step, said in more words than a phone's line has room for
    "live" if f.mode == "chat-working" && text(Some(Json::object(params)), "key") == "s-c1" =>
      Some({ "loaded": true, "activity": { "now": { "key": fix_working_now.val.0, "text": fix_working_now.val.1, "important": fix_working_important.val } } })
    // chat-feedback: the still.fail team replied on a bug report sent from the chat (sfpages feedback_replies.mbt);
    // chat-feedback-answered: and someone of the chat answered them
    "chatFeedback" if session == "s-c1" && (f.mode == "chat-feedback" || f.mode == "chat-feedback-answered") =>
      Some(fix_feedback(f.mode == "chat-feedback-answered"))
    _ => fixture_drive_topic(f, name, params)
  }
}

///|
/// The chat's bug report the still.fail team replied on, as the core's `chatFeedback` gives it; `answered`: and Ada
/// answered them in the app.
fn fix_feedback(answered : Bool) -> Json {
  let replies : Array[Json] = [
    {
      "id": "r1",
      "from": "team",
      "who": "still.fail 团队",
      "text": "谢谢反馈！能再说一下出错时 Willow 在跑什么吗？我们在日志里看到那会儿它重启过一次。\n\n临时绕过：把这条对话归档再恢复，消息就会补上。",
      "when": "14:05",
    },
  ]
  if answered {
    replies.push({ "id": "r2", "from": "person", "who": "Ada", "text": "那会儿在跑 pnpm build，重启前内存快满了。", "when": "14:12" })
  }
  {
    "reports": [
      {
        "id": "FB0000000000000000000000012",
        "workspace": "ws1",
        "account": "u1",
        "number": 12,
        "label": "FB-12",
        "title": "chat_post 偶尔发不出去",
        "heading": "still.fail 团队回复了 FB-12",
        "latest": "谢谢反馈！能再说一下出错时 Willow 在跑什么吗？我们在日志里看到那会儿它重启过一次。",
        "latestId": "r1",
        "dismissed": false,
        "replies": Json::array(replies),
      },
    ],
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
pub(all) struct FixChat {
  sent : Array[Json]
  outbox : Array[Json]
  /// its agent at work on what was sent (its activity shows), since when (ms)
  mut working : Double
  /// the unread line as the core puts it (attend.ts): over the first of what was said before the chat was opened and
  /// came after (the app away meanwhile), by its seq; -1 none
  line : Ref[Int]
  /// its agent's turns on what was sent: how many it has begun (its session's lastTurn's id says which), and the
  /// message the last one over is about (its answer, by seq; -1 none), as a station tells them
  mut turns : Int
  mut about : Int
}

///|
pub let fix_chats : Map[String, FixChat] = Map([])

///|
/// The made-up chats' threads, by id: their sessions (what is sent by thread goes to its session's chat).
pub let fix_threads : Map[Int, String] = Map([])

///|
pub fn fix_chat(session : String) -> FixChat {
  match fix_chats.get(session) {
    Some(f) => f
    None => {
      let f = { sent: [], outbox: [], working: -1.0, line: { val: -1 }, turns: 0, about: -1 }
      fix_chats[session] = f
      f
    }
  }
}

///|
/// How many changes the made-up station made later were done (fix_later's at their moments, fix_clock_set's as a
/// test's clock comes to theirs, fix_now's), each told as it is done: what its answers are worked out of
/// (fixture_topic's version).
// kept across runs: put back as a fixture is made (made.mbt)
pub let fix_done : Ref[Int] = Ref(0)

///|
/// `f` done by the made-up station now, and told: what follows the made-up core reads it anew.
pub fn fix_now(f : () -> Unit) -> Unit {
  f()
  fix_done.val += 1
  // (a topic's first value come: told as an answer, @signals.first_told)
  if fix_first.val {
    fix_first.val = false
    @signals.first_told(fn() { @settings.fixture_changed() })
  } else {
    @settings.fixture_changed()
  }
}

///|
/// Whether what is done now (fix_now) gives a topic its first value (round_trip_by's): told as an answer.
// kept across runs: set by what is done and put back as it is told
let fix_first : Ref[Bool] = Ref(false)

///|
/// What was said later before the window's first frame (as the fixture is made): handed to its runtime as the
/// fixture is first read, `ms` from then.
pub let fix_unsaid : Array[(Double, () -> Unit)] = []

///|
/// What is said later on a test's own clock (fix_clock), at a time on it.
pub let fix_timers : Array[(Double, () -> Unit)] = []

///|
/// The window's context of the frame being built (`view` sets it): none yet, the fixture is being made.
pub let fix_ctx : Ref[@ui.Ctx?] = { val: None }

///|
/// A test's own clock for the fixture's station, moved on by the test (fix_clock_set; none: the window's runtime times
/// it).
pub let fix_clock : Ref[(() -> Double)?] = { val: None }

///|
pub let fix_drafts : Map[String, Json] = Map([])

///|
/// The fixture core's composers' files (`composer.add`), by the composer's key: each up as soon as it is added, as the
/// station takes it whole.
pub let fix_composers : Map[String, Array[Json]] = Map([])

///|
/// The chats of the viewer's other workspace (个人, its station ws2/st9) that a reference may name (`chat.outsideRefs`):
/// their keys, titles, and whether the viewer may share them.
// kept across runs: a table, never written
pub let fix_outside : Array[(String, String, Bool)] = [("s-p1", "季度路线图", true), ("s-p2", "预算草稿", false)]

///|
/// Those of them shared with 星火工作室 since (`chat.xshareAdd`): outside no more.
pub let fix_xshared : Map[String, Bool] = Map([])

///|
pub let fix_serial : Ref[Int] = { val: 0 }

///|
/// What was said before the first frame, handed to the runtime as the fixture is first read in a window (fix_later).
fn fix_tick() -> Unit {
  if fix_ctx.val is Some(_) && fix_unsaid.length() > 0 {
    let unsaid = fix_unsaid.copy()
    fix_unsaid.clear()
    for u in unsaid {
      fix_later(u.0, u.1)
    }
  }
}

///|
/// A test's own clock (`clock`, fix_clock's) moved on to `ms`: what the station said it would do by then done, in the
/// order it was said, and told (fix_now), as the core tells a change at its cause; what that says later in turn, done
/// too once it is due by then.
pub fn fix_clock_set(clock : Ref[Double], ms : Double) -> Unit {
  clock.val = ms
  while true {
    match fix_timers.search_by(fn(t) { t.0 <= ms }) {
      Some(i) => fix_now(fix_timers.remove(i).1)
      None => break
    }
  }
}

///|
/// What the fixture's station takes its time over: a message sent (or retried) is in the chat after
/// `fix_deliver_ms`; its agent answers `fix_answer_ms` after that, and its turn ends `fix_turn_end_ms` after the answer.
pub let fix_deliver_ms : Double = 700.0

///|
pub let fix_answer_ms : Double = 1400.0

///|
pub let fix_turn_end_ms : Double = 700.0

///|
/// The pace the fixture's station keeps this run (fix_deliver_ms, fix_answer_ms, fix_turn_end_ms unless a test sets
/// another): a sent message's delivery, its agent's answer after that, its turn's end after the answer (less than 0: that
/// long before it, as a station may tell the turn over before the answer's message comes).
pub let fix_pace : Ref[(Double, Double, Double)] = Ref((fix_deliver_ms, fix_answer_ms, fix_turn_end_ms))

///|
/// How long the fixture's station has a message sent before the chat's entries reach it (views/local.ts outboxSent:
/// its outbox row `sent`, its time under it, till its message takes its place); less than 0, none (the message at once).
// kept across runs: put back as a fixture is made (made.mbt)
pub let fix_sent_for : Ref[Double] = Ref(-1.0)

///|
/// How long the fixture's core has words sent before its view has their row (the app's way to its core and back: a
/// frame or two on a quiet device, many on a busy one); 0, the frame after.
// kept across runs: put back as a fixture is made (made.mbt)
pub let fix_core_for : Ref[Double] = Ref(0.0)

///|
/// The pace a fixture's program was given (MBUI_FIX_PACE's "DELIVER,ANSWER,END" ms: fix_pace; MBUI_FIX_CORE's ms:
/// fix_core_for), set once its fixture is made; what is not said, or not numbers, left as the fixture has it. Read by
/// the fixture's programs alone (sffix, sfbench, a film's scene), never by the app; a run given one says so in what
/// it puts out (sfbench's APPBENCH, a film's record).
pub fn fix_pace_said(pace : String, core : String) -> Unit {
  let ms = fn(s : StringView) -> Double? {
    match (try Some(@json.parse(s.trim(chars=" ").to_owned())) catch { _ => None }) {
      Some(Number(n, ..)) => Some(n)
      _ => None
    }
  }
  let parts = pace.split(",").collect()
  if parts.length() == 3 {
    match (ms(parts[0]), ms(parts[1]), ms(parts[2])) {
      (Some(d), Some(a), Some(e)) => fix_pace.val = (d, a, e)
      _ => ()
    }
  }
  if ms(core) is Some(c) {
    fix_core_for.val = c
  }
}

///|
/// The status its agent at work on what was sent has: "queued" as the station has its words and it has not taken them
/// yet (or a summary read before it took them said so).
// kept across runs: put back as a fixture is made (made.mbt)
pub let fix_working_status : Ref[String] = Ref("running")

///|
pub fn fix_later(ms : Double, f : () -> Unit) -> Unit {
  match (fix_clock.val, fix_ctx.val) {
    (Some(clock), _) => fix_timers.push((clock() + ms, f))
    // (done at its moment and told then, as the core tells a change it made at its cause: what follows the made-up core
    // reads it anew, nothing of it done as that reads it)
    (None, Some(_)) => @ui.runtime().after(ms.ceil().to_int(), fn() { fix_now(f) })
    (None, None) => fix_unsaid.push((ms, f))
  }
}

///|
/// What was sent since (`sent`, the messages; `outbox`, those on their way) as the core says the viewer's own sent one
/// after another, nothing between them (views.ts drawn): each but the last `followed` (its time under a later one),
/// each but the first `joined` (close under the one before). One that did not go stands apart. And whether what is
/// sent next would follow the last of them (the view's `joinsUntil`).
fn fix_followed(sent : Array[Json], outbox : Array[Json]) -> (Array[Json], Array[Json], Bool) {
  let all = sent + outbox
  let mine = fn(i : Int) {
    if i < sent.length() {
      field(Some(all[i]), "mine") is Some(True)
    } else {
      text(Some(all[i]), "state") != "failed"
    }
  }
  let said : Array[Json] = []
  let going : Array[Json] = []
  for i, x in all {
    let followed = i + 1 < all.length() && mine(i) && mine(i + 1)
    let joined = i > 0 && mine(i - 1) && mine(i)
    let x = match x {
      Object(m) if followed || joined => {
        let m = m.copy()
        if followed {
          m["followed"] = Json::boolean(true)
        }
        if joined {
          m["joined"] = Json::boolean(true)
        }
        Json::object(m)
      }
      _ => x
    }
    if i < sent.length() {
      said.push(x)
    } else {
      going.push(x)
    }
  }
  (said, going, all.length() > 0 && mine(all.length() - 1))
}

///|
/// The chat with what was sent in it since.
pub fn with_sent(base : Json, session : String) -> Json {
  match field(field(Some(base), "thread"), "id") {
    Some(Number(n, ..)) => fix_threads[n.to_int()] = session
    _ => ()
  }
  match (fix_chats.get(session), base) {
    (Some(fc), Object(m)) if fc.sent.length() > 0 || fc.outbox.length() > 0 || fc.working >= 0.0 => {
      let o = m.copy()
      if fc.line.val >= 0 {
        o["unreadLine"] = Json::number(fc.line.val.to_double())
      }
      let all = match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      let (sent, outbox, joins) = fix_followed(fc.sent, fc.outbox)
      for x in sent {
        all.push(x)
      }
      o["messages"] = Json::array(all)
      o["outbox"] = Json::array(outbox)
      if joins {
        // (5 minutes from its time: the fixture's now, 0)
        o["joinsUntil"] = Json::number(300000.0)
      }
      if fc.working >= 0.0 || fc.turns > 0 {
        let thread = field(field(Some(base), "thread"), "id")
        o["agents"] = Json::array(
          items(Some(base), "agents").map(fn(a) {
            match a {
              Object(am) => {
                let w = am.copy()
                if fc.working >= 0.0 {
                  w["status"] = Json::string(fix_working_status.val)
                  w["started"] = Json::boolean(true)
                  w["since"] = Json::number(fc.working)
                }
                // (its session's last turn: the one at work on what was sent, or over, about its answer)
                match am.get("session") {
                  Some(Object(sm)) => {
                    let sc = sm.copy()
                    let turn : Map[String, Json] = { "id": Json::string("fix-turn-\{fc.turns}"), "kind": Json::string("message") }
                    match (fc.about, thread) {
                      (n, Some(t)) if n >= 0 && fc.working < 0.0 =>
                        turn["about"] = Json::object({ "thread": t, "seq": Json::number(n.to_double()), "ts": Json::string("reply\{n - 100}") })
                      _ => ()
                    }
                    sc["lastTurn"] = Json::object(turn)
                    w["session"] = Json::object(sc)
                  }
                  _ => ()
                }
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
pub fn outgoing_json(id : String, params : Json, state : String, error : String) -> Json {
  let p = Some(params)
  let o : Map[String, Json] = {
    "id": Json::string(id),
    "text": Json::string(text(p, "text")),
    "attachments": Json::array(fix_own(items(p, "attachments"))),
    "quotes": Json::array(items(p, "quotes")),
    "createdAt": 0,
    "state": Json::string(state),
  }
  // its words in runs, as its message will draw them (views.ts drawn: personWords)
  match @sf.kept_words(text(p, "text")) {
    Some(w) => o["words"] = w
    None => ()
  }
  if error != "" {
    o["error"] = Json::string(error)
  }
  Json::object(o)
}

///|
/// The files put up from here (`composer.add` with their bytes), by where the station keeps each: the upload each was,
/// which every message it goes with says (views.ts uploadOf).
pub let fix_put_up : Map[String, String] = Map([])

///|
/// A message's files as the core draws them: one put up from here naming its upload (views.ts drawn's `own`).
pub fn fix_own(files : Array[Json]) -> Array[Json] {
  files.map(fn(a) {
    match (a, fix_put_up.get(text(Some(a), "path"))) {
      (Object(m), Some(id)) => {
        let o = m.copy()
        o["upload"] = Json::string(id)
        Json::object(o)
      }
      _ => a
    }
  })
}

///|
/// The station has it: out of the outbox, the chat's own message; the agent's answer a moment after.
pub fn fix_deliver(session : String, id : String) -> Unit {
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
    fc.outbox.push(outgoing_json(id, params, "failed", "Willow 没有回应（假数据：带「失败」的消息先发不出去）"))
    return
  }
  // (taken by the station, the chat's entries yet to reach it: sent a while first, as the core says it)
  if fix_sent_for.val >= 0.0 && text(Some(params), "state") != "sent" {
    for i, o in fc.outbox {
      if text(Some(o), "id") == id {
        match outgoing_json(id, params, "sent", "") {
          Object(m) => {
            let m = m.copy()
            m["seq"] = Json::number((100 + fix_serial.val + 1).to_double())
            // (its time under it, as the core says an outgoing one's: Outgoing.time)
            m["time"] = ago("刚刚", "10/19 09:12:00")
            fc.outbox[i] = Json::object(m)
          }
          j => fc.outbox[i] = j
        }
      }
    }
    fix_later(fix_sent_for.val, fn() { fix_deliver(session, id) })
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
      // the outbox entry it was, as the core says it (views.ts: a message sent from here keeps its outbox row)
      "outgoing": Json::string(id),
      "attachments": Json::array(fix_own(items(Some(params), "attachments"))),
      "quotes": Json::array(items(Some(params), "quotes")),
    }),
  )
  // its agent sets to work at once (its activity comes in), answers a moment later (its answer said while the chat
  // shows: out of the activity's avatar), and its turn ends a moment after that
  // (at work from its source's now: the fixture's is 0, fixture.mbt)
  fc.working = 0.0
  fc.turns += 1
  fc.about = -1
  let (_, answer_in, end_in) = fix_pace.val
  // (its turn over: about its answer, said or still on its way (told before it, as a station may))
  let over = fn(answer_seq : Int) {
    let fc = fix_chat(session)
    fc.working = -1.0
    fc.about = answer_seq
  }
  if end_in < 0.0 {
    fix_later(if answer_in + end_in < 0.0 { 0.0 } else { answer_in + end_in }, fn() { over(100 + fix_serial.val + 1) })
  }
  fix_later(answer_in, fn() {
    fix_serial.val += 1
    let answer_seq = 100 + fix_serial.val
    if end_in >= 0.0 {
      fix_later(end_in, fn() { over(answer_seq) })
    }
    // (its first line, as a made-up agent would take it up)
    let lead = words.trim(chars=" \n\r\t").to_owned()
    let first = match lead.find("\n") {
      Some(i) => lead.exact_view(end=i).to_owned()
      None => lead
    }
    let said = if first == "" {
      "收到文件了，我看一下。"
    } else {
      let cut = if first.length() > 40 {
        first.clamped_view(end=40).to_owned() + "…"
      } else {
        first
      }
      "收到：「" + cut + "」。我先看一下，有结果再告诉你。"
    }
    // (its turn ended by the answer, as an agent's post with its state: words with 「进度」 answered by one saying how
    // far it got, its turn going on after it)
    let reply : Map[String, Json] = { "ts": Json::string("reply\{fix_serial.val}"), "said": true }
    if !words.contains("进度") {
      reply["ending"] = Json::string("all_done")
    }
    fix_chat(session).sent.push(msg(100 + fix_serial.val, "agent", by_agent("anthropic", "claude", session), said, "刚刚", reply))
  })
}

///|
/// The fixture's writes in a chat (`chat.send`, `chat.retry`, `chat.discard`, `draft.get`, `draft.put`,
/// `station.upload.part`, `session.warm`), and what the page tells (`client.focus`, `chat.place`): None for any other.
pub fn fixture_chat_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
  // what is written, as the core's composers keep it (compose_fixture.mbt)
  match fix_compose_call(f, name, params) {
    Some(r) => return Some(r)
    None => ()
  }
  // a chat's outline's (outline_fixture.mbt)
  match fixture_outline_call(f, name, params) {
    Some(r) => return Some(r)
    None => ()
  }
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
    // the places the station's bots are in, for a chat relayed (relay.mbt, sfdesk relay.mbt)
    "chat.relayPlaces" => Some(Ok(fix_relay_places()))
    "chat.relay" => Some(Ok({ "place": "#dev" }))
    "chat.send" => {
      fix_serial.val += 1
      let id = "out\{fix_serial.val}"
      let taken = fn() {
        fix_chat(session).outbox.push(outgoing_json(id, params, "sending", ""))
        // (chat-ask-end's card answered by it at once, as the core says it: decisions.ts inMessages)
        if f.mode == "chat-ask-end" && session == "s-c1" && !fix_decided.contains(62) {
          fix_decided[62] = { "resolved": true, "text": "你 回复了" }
        }
        fix_later(fix_pace.val.0, fn() { fix_deliver(session, id) })
      }
      if fix_core_for.val > 0.0 {
        fix_later(fix_core_for.val, taken)
      } else {
        taken()
        f.changed()
      }
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
      // (words with 重发不了 in them fail again: their file's source gone, as the core says it)
      if text(Some(was), "text").contains("重发不了") {
        return Some(Err({ "code": "upload", "message": "a.jpg 的上传源已丢失，请在新消息中重新添加附件。" }))
      }
      fc.outbox.retain(fn(o) { text(Some(o), "id") != id })
      fc.outbox.push(outgoing_json(id, was, "retried", ""))
      f.changed()
      fix_later(fix_pace.val.0, fn() { fix_deliver(session, id) })
      Some(Ok(Json::object({})))
    }
    "chat.discard" => {
      let id = text(p, "id")
      fix_chat(session).outbox.retain(fn(o) { text(Some(o), "id") != id })
      f.changed()
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
    // a file handed over: up at once, at the station's uploads (as station.upload.part's last part answers)
    "composer.add" => {
      let key = text(p, "key")
      let list = fix_composers.get(key).unwrap_or([])
      for one in items(p, "files") {
        let o = Some(one)
        let id = text(o, "id")
        let name = text(o, "name")
        let kept : Map[String, Json] = {
          "id": Json::string(id),
          "name": Json::string(name),
          "size": Json::number(number(o, "size")),
          "sent": Json::number(number(o, "size")),
          "done": {
            "name": Json::string(name),
            "path": Json::string("uploads/" + id + "/" + name),
            "size": Json::number(number(o, "size")),
          },
        }
        if field(o, "blob") is Some(_) {
          fix_put_up["uploads/" + id + "/" + name] = id
        }
        // (pasted words: what the core said of them; a station's file: where it is; the quote it is the picture of;
        // kept with the file as composer.ts keeps them)
        for k in ["pasted", "ref", "quote"] {
          match field(o, k) {
            Some(x) => kept[k] = x
            None => ()
          }
        }
        list.push(Json::object(kept))
      }
      fix_composers[key] = list
      f.changed()
      Some(Ok(Json::object({})))
    }
    "composer.remove" => {
      let key = text(p, "key")
      fix_composers[key] = fix_composers.get(key).unwrap_or([]).filter(fn(x) { text(Some(x), "id") != text(p, "id") })
      f.changed()
      Some(Ok(Json::object({})))
    }
    "composer.retry" => Some(Ok(Json::object({})))
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
    "session.warm" | "client.focus" | "chat.place" | "chat.around" => Some(Ok(Json::object({})))
    // where its runtime keeps the session's transcript
    "session.transcript" => Some(Ok({ "path": "/Users/lin/.claude/projects/release/7c1e5b2a-4f0d-4c8e-9a61-3b2f.jsonl" }))
    // the messages of the made-up chat that have every word (topics.ts find): all of it on the device
    "chat.find" => {
      let words : Array[String] = []
      for w in text(p, "query").to_lower().split(" ") {
        if w.length() > 0 {
          words.push(w.to_owned())
        }
      }
      let all = items(Some(rich_chat(f.older)), "messages")
      let hits : Array[Json] = []
      for m in all {
        let said = text(Some(m), "text").to_lower()
        let mut count = 0
        for w in words {
          let mut from = 0
          while from <= said.length() {
            match said.exact_view(start=from).to_owned().find(w) {
              Some(i) => {
                count += 1
                from = from + i + w.length()
              }
              None => break
            }
          }
        }
        if count > 0 && words.iter().all(fn(w) { said.contains(w) }) {
          hits.push({ "seq": Json::number(number(Some(m), "seq")), "count": Json::number(count.to_double()) })
        }
      }
      let n = Json::number(all.length().to_double())
      Some(
        Ok({
          "words": Json::array(words.map(fn(w) { Json::string(w) })),
          "hits": Json::array(hits),
          "held": n,
          "of": n,
          "whole": true,
        }),
      )
    }
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
    // those of them the viewer may share, shared with 星火工作室 (xshare.ts chat.outsideShare)
    "chat.outsideShare" => {
      let words = text(p, "text")
      let mut shared = 0
      for x in fix_outside {
        let (id, title, may) = x
        if may && words.contains("@[" + title + "]") && !fix_xshared.contains(id) {
          fix_xshared[id] = true
          shared += 1
        }
      }
      Some(Ok({ "shared": Json::number(shared.to_double()) }))
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
/// chat-uploading's picture still going up, as its message names it (views.ts goingUp: its upload).
pub let going_up_picture : Json = {
  "name": "compare.png",
  "path": "upload:up-seed",
  "size": 402000,
  "width": 1600,
  "height": 900,
  "upload": "up-seed",
}

///|
/// The first row's chat's draft as each composer mode has it (none in any other); a new chat's with a picture and words
/// (newchat-attach: scripts/motion/send-newchat-picture.drive).
pub fn seeded_draft(mode : String, key : String) -> Json {
  if mode == "newchat-attach" && key.has_prefix("new:") {
    return {
      "text": "照着这张截图把第二屏改一下",
      "quotes": [],
      "files": [file("compare.png", 1600, 900, 402000)],
    }
  }
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
    // chat-attach-row: a station's file before them (drive_fixture.mbt), the row wider than the capsule;
    // chat-attach-pic: its picture's tile drawn from the picture, as one picked here is (seeded_pictures)
    "chat-attach" | "chat-attach-row" | "chat-attach-pic" =>
      {
        "text": "截图和构建日志都在这里，帮我看看第二屏",
        "quotes": [],
        "files": [file("compare.png", 1600, 900, 402000), file("build.log", 0, 0, 18432)],
      }
    // chat-attach-video: a picture and a video waiting side by side, each drawn from its picture (seeded_pictures)
    "chat-attach-video" =>
      {
        "text": "截图和构建日志都在这里，帮我看看第二屏",
        "quotes": [],
        "files": [file("compare.png", 1600, 900, 402000), file("演示录屏.mp4", 1920, 1080, 3200000)],
      }
    // chat-uploading: another picture going up meanwhile, how much of it the station has (`sent`: seeded_files)
    "chat-uploading" =>
      match file("compare.png", 1600, 900, 402000) {
        Object(m) => {
          let going = m.copy()
          going["sent"] = Json::number(160800.0)
          { "text": "", "quotes": [], "files": [Json::object(going)] }
        }
        _ => Json::null()
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
pub fn seeded_outbox(mode : String) -> Array[Json] {
  let words : Json = { "text": "好，就按这个改，顺便把深色模式的截图也换掉" }
  match mode {
    "chat-sending" => [outgoing_json("o-seed", words, "sending", "")]
    // a picture sent while it went up, among its files from here (views.ts goingUp), how far it is said under it
    "chat-uploading" =>
      match outgoing_json("o-seed", { "text": "第二屏的截图，帮我看看", "attachments": [going_up_picture] }, "sending", "") {
        Object(m) => {
          @sfbase.sent_picture_kept("upload\u{1}up-seed", fixture_file("compare.png"))
          let o = m.copy()
          o["waits"] = Json::string("正在上传 42%")
          o["progress"] = Json::number(0.42)
          [Json::object(o)]
        }
        o => [o]
      }
    "chat-failed" => [outgoing_json("o-seed", words, "failed", "Willow 没有回应")]
    _ => []
  }
}

// ── the made-up chat's cards, answered here ─────────────────────────────
//
// The fixture takes a card's answer as the core does: answered at once (the option picked, 你 选择了
// 「…」 as how it went), let go at once (no longer asked). An option with 失败 in it fails. The modes chat-cards (the
// card answered) and chat-answering (an option under way) open the first row's chat so (scripts/shots.sh cards);
// chat-vault, with an agent asking to keep a password at its end, decided here as the core decides it; chat-vault-typed,
// asking the person to type a token in instead; chat-vault-file, to pick a file; chat-vault-describe, to rename an item; chat-vault-remove, to delete one
// and say what it is.

///|
/// How the first row's chat's cards stand as answered here: by seq, the card's decision.
pub let fix_decided : Map[Int, Json] = Map([])

///|
/// The answers given here, by the card's seq: the viewer's message the core posts with each (said as the chat shows).
pub let fix_replied : Map[Int, String] = Map([])

///|
/// The agent's answers to those answers, after them (fixture_card_call).
pub let fix_card_replies : Array[Json] = []

///|
/// When each of those was said (an answer's "r:SEQ", the agent's "c:INDEX"): in which order, and how many of its chat's
/// own messages since (fix_chat's `sent`) stood then, so a message sent after it stays after it, as a chat's time
/// order has it (with_cards). One said without (a test's own) goes last, as before.
// kept across runs: put back as a fixture is made (made.mbt)
let fix_reply_at : Map[String, (Int, Int)] = Map([])

///|
/// How chat-vault's request to keep a password, at the chat's end, went once decided here ("": waiting).
pub let fix_vault : Ref[String] = Ref("")

///|
/// chat-vault's last post: an agent asking to keep a password (`typed`: a token the person types in; `file`: a file
/// they pick), or `use_secret` for an already answered request to use a token; its card as the core says it.
pub fn vault_post(typed : Bool, file? : Bool = false, use_secret? : Bool = false, timed? : Bool = false, describe? : Bool = false, remove? : Bool = false) -> Json {
  let ask : Map[String, Json] = if remove {
    { "name": "办公室 Mac 主机管理员登录", "reason": "这个密码在 Office-Host-2 上登不上，能用的那个已经另存了，留着会让别的 agent 拿它去试", "mode": "env", "hosts": [], "remove": true, "answer": "approve" }
  } else if describe {
    {
      "name": "127.0.0.1 登录态",
      "reason": "原名称无法看出用途，补充可辨识的名称与使用说明",
      "mode": "browser",
      "hosts": [],
      "describe": {
        "name": "UniFi 管理后台登录状态（经 Studio 转发至 127.0.0.1:8443）",
        "about": "家中 UniFi 管理后台（192.168.0.1）的登录状态。访问方式：先在 Studio 上将 192.168.0.1:443 转发至 127.0.0.1:8443，再转发至本机，然后在对话的浏览器中打开 https://127.0.0.1:8443/。",
        "wasAbout": "",
      },
      "howText": "名称改为：UniFi 管理后台登录状态（经 Studio 转发至 127.0.0.1:8443）",
      "answer": "approve",
    }
  } else if use_secret {
    { "name": "Axiom 查询 token", "reason": "查询中继连接日志，定位拨号失败的原因", "mode": "proxy", "hosts": ["api.axiom.co"], "howText": "代理 · 限 api.axiom.co", "command": "curl -s https://api.axiom.co/v1/datasets/_apl", "answer": "approve", "scope": "chat" }
  } else if file {
    { "name": "生产集群", "mode": "file", "save": { "kind": "file", "typed": true }, "answer": "approve" }
  } else if typed {
    { "name": "OpenCode Go", "mode": "proxy", "hosts": ["opencode.ai"], "save": { "kind": "token", "typed": true }, "answer": "approve" }
  } else {
    { "name": "测试服务登录", "reason": "把测试服务密码安全保存，方便以后登录", "mode": "env", "save": { "kind": "login", "username": "demo-user" }, "answer": "approve" }
  }
  if timed {
    ask["timeoutKind"] = "idle"
    ask["timeoutSeconds"] = 129600
  }
  if fix_vault.val != "" {
    ask["status"] = Json::string(fix_vault.val)
  }
  msg(60, "agent", by_agent("Anthropic", "claude", "s-c1"), if remove { "申请删除密钥「办公室 Mac 主机管理员登录」" } else if describe { "申请修改密钥「127.0.0.1 登录态」的名称与说明" } else if use_secret { "申请使用 Axiom 查询 token 查询日志" } else if file { "请选择生产集群的 kubeconfig" } else if typed { "请填入 OpenCode Go 的 API key" } else { "要存入 测试服务登录 的密码" }, "刚刚", {
    "card": { "type": "options", "vault": "r-demo", "vaultAsk": Json::object(ask) },
    "createdAt": Json::number(1.0e9),
  })
}

///|
/// How chat-phone's request for the person's phone, at the chat's end, went once decided here ("": waiting).
pub let fix_phone : Ref[String] = Ref("")

///|
/// The length chat-phone's request was last allowed for (`adb.decide`'s scope): "" none yet.
pub let fix_phone_scope : Ref[String] = Ref("")

///|
/// Granted, how its station's adb holds the phone, as the station says it on the card ("": not said).
pub let fix_phone_link : Ref[String] = Ref("")

///|
/// chat-phone's last post: an agent asking to debug the person's phone, its card as the core says
/// it, answered here; decided, how it went.
pub fn phone_post() -> Json {
  let ask : Map[String, Json] = { "request": "p-1", "reason": "装上刚编好的测试包，看首屏在折叠屏展开时排得对不对" }
  if fix_phone.val != "" {
    ask["status"] = Json::string(fix_phone.val)
    if fix_phone.val == "granted" {
      ask["scope"] = Json::string("chat")
      if fix_phone_link.val != "" {
        ask["link"] = Json::string(fix_phone_link.val)
      }
    }
  }
  msg(61, "agent", by_agent("Anthropic", "claude", "s-c1"), "申请调试你的手机：装上刚编好的测试包，看首屏在折叠屏展开时排得对不对", "刚刚", {
    "card": { "type": "options", "phoneAsk": Json::object(ask) },
    "createdAt": Json::number(1.0e9),
  })
}

///|
/// How chat-rig's request for a rig, at the chat's end, went once decided here ("": waiting; granted; away: approved,
/// the rig not reached yet; denied; ended).
pub let fix_rig : Ref[String] = Ref("")

///|
/// What `rig.decide` was asked with here, each time (a test reads what the card sent).
pub let fix_rig_asked : Array[Json] = []

///|
/// chat-rig's last post: an agent asking for the rig build-box (a station that only runs tasks), its card as the core says it, answered here
/// by its person; decided, how it went. `mine`: whether the rig is the viewer's (chat-rig-other: 陈's, who is asked).
/// `device`: for one of its devices alone (chat-rig-device: 开发板).
pub fn rig_post(mine : Bool, device? : Bool = false) -> Json {
  let ask : Map[String, Json] = {
    "request": "r-1",
    "rig": "aa11",
    "name": "build-box",
    "owner": if mine { "s" } else { "u-chen" },
    "reason": "在 Linux 上跑一遍完整的 station 测试",
    "timeoutKind": "idle",
    "timeoutSeconds": 3600,
    "session": "s-c1",
    "chat": "CHAT/1",
    "title": "修 CI",
    "by": "lin@example.com",
  }
  if device {
    ask["device"] = "1b2c3d4e5f607182"
    ask["deviceName"] = "开发板"
    ask["reason"] = "给开发板刷新固件，看串口输出"
  }
  match fix_rig.val {
    "" => ()
    "granted" | "away" => {
      ask["status"] = "granted"
      ask["delivered"] = Json::boolean(fix_rig.val == "granted")
      ask["grantedKind"] = "fixed"
      ask["grantedSeconds"] = 28800
    }
    "ended" => {
      ask["status"] = "ended"
      ask["why"] = "所有者已收回"
    }
    s => ask["status"] = Json::string(s)
  }
  let card : Map[String, Json] = { "type": "options", "rigAsk": Json::object(ask), "assignee": if mine { "lin@example.com" } else { "chen@example.com" } }
  if !mine {
    card["assigneeText"] = "等 陈 决定"
  }
  msg(63, "agent", by_agent("Anthropic", "claude", "s-c1"), "申请使用 station「build-box」：在 Linux 上跑一遍完整的 station 测试", "刚刚", {
    "card": Json::object(card),
    "createdAt": Json::number(1.0e9),
  })
}

///|
/// chat-signin's last post: an agent asking the person to sign in to github.com on the chat's tab ( 登录态),
/// its card as the core says it; how it stands by the mode (chat-signin-code: a code asked; -person: a captcha, the
/// person's; -done: signed in, its keeping waiting for this device; -kept: kept).
pub fn signin_post(mode : String) -> Json {
  let ask : Map[String, Json] = { "id": "g-1", "site": "github.com", "reason": "查看 PR #512 的 Actions 日志", "screen": "browser:T1" }
  match mode {
    "chat-signin-code" => ask["status"] = Json::string("code")
    "chat-signin-person" => {
      ask["status"] = Json::string("person")
      ask["why"] = Json::string("blocked")
    }
    "chat-signin-done" | "chat-signin-kept" => {
      ask["status"] = Json::string("done")
      ask["keep"] = Json::boolean(true)
      ask["save"] = Json::string("r-save")
      if mode == "chat-signin-kept" {
        ask["kept"] = Json::string("granted")
      }
    }
    _ => ()
  }
  msg(63, "agent", by_agent("Anthropic", "claude", "s-c1"), "要登录 github.com：查看 PR #512 的 Actions 日志", "刚刚", {
    "card": { "type": "options", "signinAsk": Json::object(ask) },
    "createdAt": Json::number(1.0e9),
  })
}

///|
/// chat-ask-end's last post: an agent asking with an options card, waiting; anything sent in the chat answers it at
/// once, as the core says it (decisions.ts inMessages: what is sending answers the last card).
pub fn ask_end_post() -> Json {
  msg(62, "agent", by_agent("Anthropic", "claude", "s-c1"), "列表的动效改好了，要不要顺便把网页也按同一套改？", "刚刚", {
    "ending": "need_decision",
    "card": {
      "type": "options",
      "assigneeText": "等 林 决定",
      "options": [
        { "label": "先不改网页", "detail": "这次只改 app" },
        { "label": "一起改", "detail": "网页的列表也按同一套重做", "recommended": true },
      ],
    },
    "decision": fix_decided.get(62).unwrap_or({ "resolved": false }),
    "asked": Json::boolean(!fix_decided.contains(62)),
    "createdAt": Json::number(1.0e9),
  })
}

///|
/// The chat `v` with what was answered here in it.
pub fn with_cards(f : Fixture, v : Json, session : String) -> Json {
  let seeded = f.mode == "chat-cards"
  let ask_end = f.mode == "chat-ask-end"
  let vault = f.mode == "chat-vault" || f.mode == "chat-vault-typed" || f.mode == "chat-vault-file" || f.mode == "chat-vault-use" || f.mode == "chat-vault-timeout" || f.mode == "chat-vault-before" || f.mode == "chat-vault-describe" || f.mode == "chat-vault-remove"
  let linked = f.mode.has_prefix("chat-phone-linked-")
  let signin = f.mode.has_prefix("chat-signin")
  // (chat-rig: an agent's request for the viewer's rig, waiting; -other: someone else's rig; -web: on a web page;
  // -outside: on a device not on its person's own lock; -granted, -away, -ended: decided so already)
  let rig = f.mode.has_prefix("chat-rig")
  if fix_rig.val == "" && (f.mode == "chat-rig-granted" || f.mode == "chat-rig-away" || f.mode == "chat-rig-ended") {
    fix_rig.val = f.mode.unsafe_substring(start="chat-rig-".length(), end=f.mode.length())
  }
  let stepped = f.mode.has_prefix("chat-phone-step-")
  let phone = f.mode == "chat-phone" || f.mode == "chat-phone-outside" || f.mode == "chat-phone-none" || f.mode == "chat-phone-granted" || f.mode == "chat-phone-lacks" || f.mode == "chat-phone-off" || linked || stepped
  // (chat-phone-granted: its request approved already; chat-phone-lacks: waiting, on a phone without Developer options;
  // chat-phone-linked-<link>[-desk]: approved, its station holding the phone as <link> says, on the phone or (-desk)
  // on a computer; chat-phone-step-<what>: approved, on a phone that lacks <what> first, its station holding it as
  // that leaves it)
  if (f.mode == "chat-phone-granted" || linked || stepped) && fix_phone.val == "" {
    fix_phone.val = "granted"
  }
  if stepped && fix_phone_link.val == "" {
    fix_phone_link.val = match f.mode {
      "chat-phone-step-wireless" | "chat-phone-step-refused" => "off"
      "chat-phone-step-code" => "unpaired"
      _ => "gone"
    }
  }
  if f.mode == "chat-vault-use" && fix_vault.val == "" {
    fix_vault.val = "granted"
  }
  if linked && fix_phone_link.val == "" {
    let rest = f.mode.unsafe_substring(start="chat-phone-linked-".length(), end=f.mode.length())
    fix_phone_link.val = match rest.find("-") {
      Some(i) => rest.unsafe_substring(start=0, end=i)
      None => rest
    }
  }
  if session != "s-c1" || (fix_decided.is_empty() && !seeded && !vault && !phone && !signin && !ask_end && !rig) {
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
      // what the chat's end says it needs, let go here: said let go at once, as the core says it (views.ts withLetGo)
      match o.get("stateAsk") {
        Some(Number(n, ..)) if fix_decided.get(n.to_int()) is Some(Object(d)) && d.get("dismissed") == Some(Json::boolean(true)) => {
          let rest = text(Some(v), "stateRest")
          o["stateText"] = Json::string("已忽略：" + rest)
          o["stateLead"] = Json::string("dismissed")
          o.remove("stateAsk") |> ignore
        }
        _ => ()
      }
      // chat-vault's request to keep a password, last
      if vault {
        all.push(vault_post(f.mode == "chat-vault-typed", file=f.mode == "chat-vault-file", use_secret=f.mode == "chat-vault-use" || f.mode == "chat-vault-timeout" || f.mode == "chat-vault-before", timed=f.mode == "chat-vault-timeout", describe=f.mode == "chat-vault-describe", remove=f.mode == "chat-vault-remove"))
      }
      // chat-phone's request for the person's phone, last
      if phone {
        all.push(phone_post())
      }
      if signin {
        all.push(signin_post(f.mode))
      }
      // chat-rig's request for a rig, last
      if rig {
        all.push(rig_post(f.mode != "chat-rig-other", device=f.mode == "chat-rig-device"))
      }
      // chat-ask-end's card, last of what was there: what was sent since comes after it, as it was said after it (put
      // at the end, words sent under it came to stand over it once the station had them, a whole row up in one frame)
      if ask_end {
        let card = ask_end_post()
        let at = all.search_by(fn(x) { number(Some(x), "seq") > number(Some(card), "seq") }).unwrap_or(all.length())
        all.insert(at, card)
      }
      // each answer's message and the agent's answer to it, where they were said: before what the chat had sent
      // since, after what it had then (put after everything, a message sent after the answer came to stand over it
      // once the station had it, its row up and the answer's down in one frame)
      let said : Array[(Int, Int, Json)] = []
      let last = 1000000
      for seq, label in fix_replied {
        let (order, before) = fix_reply_at.get("r:\{seq}").unwrap_or((last + said.length(), last))
        said.push(
          (order, before, msg(100 + seq, "person", by_person("林"), label, "刚刚", { "mine": true, "said": true, "createdAt": Json::number(1.0e9) })),
        )
      }
      for i, x in fix_card_replies {
        let (order, before) = fix_reply_at.get("c:\{i}").unwrap_or((last + said.length(), last))
        said.push((order, before, x))
      }
      said.sort_by_key(fn(s) { s.0 })
      let since = match fix_chats.get(session) {
        Some(fc) => fc.sent
        None => []
      }
      for s in said {
        let at = if s.1 < since.length() {
          let ts = text(Some(since[s.1]), "ts")
          all.search_by(fn(x) { text(Some(x), "ts") == ts })
        } else {
          None
        }
        match at {
          Some(i) => all.insert(i, s.2)
          None => all.push(s.2)
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
pub fn decided_json(label : String) -> Json {
  {
    "resolved": true,
    "chosen": Json::string(label),
    "text": Json::string("你 选择了「" + label + "」"),
  }
}

///|
/// The cards' calls in the made-up chat (`decision.answer`, `decision.dismiss`): None for any other.
pub fn fixture_card_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
  let p = Some(params)
  let seq = number(p, "seq").to_int()
  match name {
    "decision.answer" => {
      let label = text(p, "option")
      if label.contains("失败") {
        return Some(Err({ "code": "unavailable", "message": "Willow 没有回应" }))
      }
      fix_decided[seq] = decided_json(label)
      fix_replied[seq] = label
      fix_reply_at["r:\{seq}"] = (fix_reply_at.length(), fix_chat("s-c1").sent.length())
      // its agent takes the answer up as it takes words sent (fix_deliver): at work at once, its answer a moment
      // later out of its avatar, its turn over a moment after that
      fix_chat("s-c1").working = 0.0
      fix_later(fix_answer_ms, fn() {
        fix_serial.val += 1
        fix_later(fix_turn_end_ms, fn() { fix_chat("s-c1").working = -1.0 })
        fix_reply_at["c:\{fix_card_replies.length()}"] = (fix_reply_at.length(), fix_chat("s-c1").sent.length())
        fix_card_replies.push(
          msg(300 + fix_serial.val, "agent", by_agent("anthropic", "claude", "s-c1"), "好，按「" + label + "」来。", "刚刚", {
            "ts": Json::string("card-reply\{fix_serial.val}"),
            "said": true,
            "ending": "all_done",
            "createdAt": Json::number(1.0e9),
          }),
        )
      })
      f.changed()
      Some(Ok(Json::object({})))
    }
    "decision.dismiss" => {
      fix_decided[seq] = { "resolved": false, "dismissed": true }
      f.changed()
      Some(Ok(Json::object({})))
    }
    // chat-vault's request decided: how it went on its card at once, as the core puts it
    "adb.decide" if text(p, "request") == "p-1" => {
      fix_phone_scope.val = text(p, "scope")
      fix_phone.val = if text(p, "scope") != "" { "granted" } else { "denied" }
      f.changed()
      Some(Ok(Json::object({})))
    }
    // chat-rig's request decided: how it went on its card at once, as the core puts it
    "rig.decide" if text(p, "request") == "r-1" => {
      fix_rig_asked.push(params)
      fix_rig.val = if flag(p, "allow") { "granted" } else { "denied" }
      f.changed()
      Some(Ok(Json::object({})))
    }
    "vault.approve" | "vault.deny" if text(p, "request") == "r-demo" => {
      fix_vault.val = if name == "vault.approve" { "granted" } else { "denied" }
      f.changed()
      Some(Ok(Json::object({})))
    }
    _ => None
  }
}

///|
/// An agent's answer with a table, highlighted code (one line too long for the message: it scrolls sideways) and a
/// command, at the end of the first row's chat.
pub let md_answer : String =
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
pub fn with_viz_message(v : Json) -> Json {
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
pub let viz_answer : String =
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
/// MBUI_FIXTURE=chat-image-coming: a last message's two pictures still coming from their station (fixture.mbt's
/// `file`): a photograph (its ThumbHash's field a sky over a meadow), 8400 of its thumbnail's 24000 bytes heard, and a
/// light screenshot (a report's, 780 × 2600, its ThumbHash's field the page's colour), 0 of its 13249.
let coming_screenshot : String = "adb-chats.png"

///|
let coming_photo : String = "meadow.jpg"

///|
/// How far each of chat-image-coming's pictures has come, by its name (None: not one of them).
fn coming_heard(name : String) -> Json? {
  if name == coming_screenshot {
    Some({ "loaded": 0.0, "total": 13249.0 })
  } else if name == coming_photo {
    Some({ "loaded": 8400.0, "total": 24000.0 })
  } else {
    None
  }
}

///|
fn with_coming_screenshot(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let all = match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      let shot = match file(coming_screenshot, 780, 2600, 182000) {
        Object(a) => {
          let a = a.copy()
          a["thumbhash"] = "PAgCAgBQN4aJy7s3lnBcKvU="
          Json::object(a)
        }
        a => a
      }
      let photo = match file(coming_photo, 1200, 860, 412000) {
        Object(a) => {
          let a = a.copy()
          a["thumbhash"] = "3OcRJYB4d3h/iIeHeEh3eIhw+j3A"
          Json::object(a)
        }
        a => a
      }
      all.push(
        msg(12, "agent", by_agent("anthropic", "claude", "s-c1"), "截图在这里。", "1 分钟前", { "ending": "all_done", "attachments": [photo, shot] }),
      )
      o["messages"] = Json::array(all)
      Json::object(o)
    }
    _ => v
  }
}

///|
/// MBUI_FIXTURE=chat-file-links: a last message naming two of its files by links within a sentence, written escaped
/// as the station sends them (`release%2Ehtml`), its Markdown tree with it (file_links_md).
pub fn with_file_links(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let all = match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      all.push(
        msg(12, "agent", by_agent("anthropic", "claude", "s-c1"), file_links_answer, "1 分钟前", {
          "attachments": [file("release.html", 0, 0, 1200), file("界面草图.png", 600, 400, 18000)],
          "placed": ["release.html", "界面草图.png"],
          "md": file_links_md,
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
pub let file_links_answer : String = "这周的[发布节奏](release%2Ehtml)，草图在[界面草图](%E7%95%8C%E9%9D%A2%E8%8D%89%E5%9B%BE.png)。"

///|
/// file_links_answer's tree as the core reads it: its words by where they are in it.
pub let file_links_md : Json = [
  [
    "p",
    [
      [0, 3],
      ["a", [[4, 8]], { "href": "release%2Ehtml" }],
      [25, 29],
      ["a", [[30, 34]], { "href": "%E7%95%8C%E9%9D%A2%E8%8D%89%E5%9B%BE.png" }],
      [77, 78],
    ],
  ],
]

///|
/// MBUI_FIXTURE=chat-table-images: a last message placing two of its pictures in a table's cells, a wide one and a
/// tall one, escaped as the station sends them, its Markdown tree with it (table_images_md).
pub fn with_table_images(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let all = match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      all.push(
        msg(12, "agent", by_agent("anthropic", "claude", "s-c1"), table_images_answer, "1 分钟前", {
          "attachments": [file("web-folded.png", 1440, 900, 90000), file("phone.png", 780, 1688, 60000)],
          "placed": ["web-folded.png", "phone.png"],
          "md": table_images_md,
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
pub let table_images_answer : String = "| 网页 | 手机网页 |\n|---|---|\n| ![](web%2Dfolded.png) | ![](phone.png) |\n"

///|
/// table_images_answer's tree as the core reads it (src/sfkept): its words by where they are in it.
pub let table_images_md : Json = [
  [
    "table",
    [
      ["tr", [["th", [[2, 4]]], ["th", [[7, 11]]]]],
      ["tr", [["td", [["img", { "src": "web%2Dfolded.png" }]]], ["td", [["img", { "src": "phone.png" }]]]]],
    ],
    {
      "align": [Json::null(), Json::null()],
      "md": "| 网页 | 手机网页 |\n| --- | --- |\n| ![](web%2Dfolded.png) | ![](phone.png) |",
      "csv": "网页,手机网页\nweb%2Dfolded.png,phone.png",
    },
  ],
]

///|
/// MBUI_FIXTURE=chat-viz's visualization: a fragment, as the viz skill has agents write them.
pub let fixture_viz_html : String =
  #|<div class="viz-card" style="padding:16px"><b>本周发布</b><p>周一 2 个、周三 1 个、周五 3 个</p>
  #|<button onclick="openai.setWidgetState({seen:true})">看过了</button></div>

///|
pub fn with_md_message(v : Json) -> Json {
  with_message(v, md_answer)
}

///|
/// The chat with an agent's answer of `words` at its end.
pub fn with_message(v : Json, words : String, md? : Json? = None) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let all = match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      all.push(
        msg(12, "agent", by_agent("anthropic", "claude", "s-c1"), words, "1 分钟前", match md {
          Some(t) => { "ending": "all_done", "md": t }
          None => { "ending": "all_done" }
        }),
      )
      o["messages"] = Json::array(all)
      Json::object(o)
    }
    _ => v
  }
}

///|
/// A chat whose run was changed twice, as the core says the notices (run-change.ts): another model and effort, whose
/// line has the room; another runtime and model, whose line has not on a phone, which says what it runs on now.
fn with_run_change(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let notice = fn(words : String, short : String, was : String, now : String, sides : Json) -> Json {
        {
          "failed": false,
          "words": Json::string(words),
          "short": Json::string(short),
          "lines": [Json::string(was), Json::string(now)],
          "sides": sides,
        }
      }
      let sides = fn(was : String, was_maker : String, was_runtime : String, now : String, now_maker : String, now_runtime : String) -> Json {
        {
          "was": Json::string(was),
          "now": Json::string(now),
          "to": "换成",
          "wasMaker": Json::string(was_maker),
          "wasRuntime": Json::string(was_runtime),
          "nowMaker": Json::string(now_maker),
          "nowRuntime": Json::string(now_runtime),
        }
      }
      let was = "之前：Claude Code · Opus 5.5 · 高 · 自动 · lin@example.com"
      let mid = "现在：Claude Code · Sonnet 5.5 · 中 · 自动 · lin@example.com"
      let now = "现在：Codex · GPT-6 Astra · 高 · Fast · 自动 · lin@example.com"
      let long = "Claude Code · Sonnet 5.5 · 中 · 标准 → Codex · GPT-6 Astra · 高 · Fast"
      o["messages"] = [
        msg(1, "person", by_person("林"), "换个模型试试", "刚刚", { "mine": true }),
        msg(2, "ember", { "name": "still.fail" }, "已切换：Opus 5.5 · high → Sonnet 5.5 · medium", "刚刚", {
          "notice": notice(
            "Opus 5.5 · 高 → Sonnet 5.5 · 中",
            "换成 Sonnet 5.5 · 中",
            was,
            mid,
            sides("Opus 5.5 · 高", "anthropic", "claude", "Sonnet 5.5 · 中", "anthropic", "claude"),
          ),
        }),
        msg(3, "ember", { "name": "still.fail" }, "已切换：" + long, "刚刚", {
          "notice": notice(
            long,
            "换成 Codex · GPT-6 Astra · 高 · Fast",
            "之前：Claude Code · Sonnet 5.5 · 中 · 标准 · 自动 · lin@example.com",
            now,
            sides("Claude Code · Sonnet 5.5 · 中 · 标准", "anthropic", "claude", "Codex · GPT-6 Astra · 高 · Fast", "openai", "codex"),
          ),
        }),
      ]
      o["asks"] = []
      o["askClear"] = false
      o["more"] = false
      Json::object(o)
    }
    _ => v
  }
}

///|
/// A model's own limit spent, as the station says it in the chat and the core in its agent's state, before #4365 (as
/// though the account's quota were) and after (the model's, named).
fn with_model_limit(v : Json, after : Bool) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let en = @sf.language() == "en"
      let (words, state) = if after && en {
        ("Fable's limit is spent, not your quota; resumes on refill", "Failed: Fable's limit spent")
      } else if after {
        ("Fable 自身限额已用完（非账号额度），恢复后自动继续", "出错：Fable 自身限额已用完")
      } else if en {
        ("Out of quota; continues when it refills", "Failed: Out of quota")
      } else {
        ("额度已用完，恢复后自动继续", "出错：额度已用完")
      }
      o["messages"] = [
        msg(1, "person", by_person("林"), "请继续处理这个任务", "刚刚", { "mine": true }),
        msg(2, "ember", { "name": "still.fail" }, "⚠️ " + words, "刚刚", {
          "notice": { "failed": true, "words": Json::string(words) },
        }),
      ]
      o["agents"] = Json::array(
        items(Some(v), "agents").map(fn(a) {
          match (a, field(Some(a), "session")) {
            (Object(am), Some(Object(session))) => {
              let w = am.copy()
              let failed = session.copy()
              failed["statusText"] = Json::string(state)
              failed["tone"] = Json::string("red")
              w["session"] = Json::object(failed)
              w["status"] = Json::string("failed")
              w["badge"] = Json::string("failed")
              Json::object(w)
            }
            _ => a
          }
        }),
      )
      o["asks"] = []
      o["askClear"] = false
      o["more"] = false
      Json::object(o)
    }
    _ => v
  }
}

///|
/// The same capacity notice before and after its retry can be cancelled from the chat.
fn with_overload_notice(v : Json, after : Bool, canceled : Bool) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let words = if @sf.language() == "en" {
        if after {
          "Model busy; retrying (not quota)"
        } else {
          "The model is at capacity right now; this is not your account's limit. Retrying automatically after a while. Stop to cancel"
        }
      } else if after {
        "模型满载，自动重试，与额度无关"
      } else {
        "模型暂时满载，与账号额度无关；稍后自动重试，点停止可取消"
      }
      let notice : Map[String, Json] = { "failed": true, "words": Json::string(words) }
      if after && !canceled {
        notice["retrySession"] = "s-c1"
      }
      let claude = by_agent("anthropic", "claude", "s-c1")
      // (a chat as long as its view and more, for what opens at its end to be seen held where it is)
      o["messages"] = [
        msg(1, "person", by_person("林"), "把发布清单整理一下：签名、渠道包、更新日志、回滚预案，各自谁负责、到哪一步了。", "1 小时前", { "mine": true }),
        msg(2, "agent", claude, "好。我先把四项列出来，逐项去查现在的状态：签名看证书和构建日志，渠道包看各平台的上传记录，更新日志看这周合进 main 的改动，回滚预案看上次发布留下的步骤。查完一项就在这里更新一次。", "1 小时前", {}),
        msg(3, "person", by_person("林"), "渠道包那边昨天说华为的审核卡住了，顺便看一下。", "50 分钟前", { "mine": true }),
        msg(4, "agent", claude, "华为的审核是因为隐私政策的链接打不开，已经换成新的链接重新提交了，现在在排队。签名这项查完了：证书有效期到明年三月，这次的构建都用的新证书。", "40 分钟前", {}),
        msg(5, "person", by_person("林"), "更新日志按渠道分开写吗？还是一份通用的？", "30 分钟前", { "mine": true }),
        msg(6, "agent", claude, "一份通用的就够了：这周合进 main 的改动里，只有两条是某个平台独有的，我在那两条后面标上平台名。回滚预案还差最后一步没确认：上次发布留下的回滚脚本引用了已经删掉的配置项，我先改好再跑一遍演练。", "20 分钟前", {}),
        msg(7, "person", by_person("林"), "请继续处理这个任务", "刚刚", { "mine": true }),
        msg(8, "ember", { "name": "still.fail" }, "⚠️ " + words, "刚刚", { "notice": Json::object(notice) }),
      ]
      o["asks"] = []
      o["askClear"] = false
      o["more"] = false
      Json::object(o)
    }
    _ => v
  }
}

///|
/// The chat `v` ending on a turn that lost its connection to the model's service ("chat-turn-failed"): its notice offers
/// 重试 till it is pressed (`retried`: its agent goes on, the notice says it no more).
fn with_failed_turn(v : Json, retried : Bool) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let words = if @sf.language() == "en" { "Connection lost; reply to retry" } else { "与模型服务的连接中断，回复即可重试" }
      let notice : Map[String, Json] = { "failed": true, "words": Json::string(words) }
      if !retried {
        notice["againSession"] = "s-c1"
      }
      let claude = by_agent("anthropic", "claude", "s-c1")
      // (a chat as long as its view and more, for what opens at its end to be seen held where it is)
      o["messages"] = [
        msg(1, "person", by_person("林"), "把发布清单整理一下：签名、渠道包、更新日志、回滚预案，各自谁负责、到哪一步了。", "1 小时前", { "mine": true }),
        msg(2, "agent", claude, "好。我先把四项列出来，逐项去查现在的状态：签名看证书和构建日志，渠道包看各平台的上传记录，更新日志看这周合进 main 的改动，回滚预案看上次发布留下的步骤。查完一项就在这里更新一次。", "1 小时前", {}),
        msg(3, "person", by_person("林"), "渠道包那边昨天说华为的审核卡住了，顺便看一下。", "50 分钟前", { "mine": true }),
        msg(4, "agent", claude, "华为的审核是因为隐私政策的链接打不开，已经换成新的链接重新提交了，现在在排队。签名这项查完了：证书有效期到明年三月，这次的构建都用的新证书。", "40 分钟前", {}),
        msg(5, "person", by_person("林"), "更新日志按渠道分开写吗？还是一份通用的？", "30 分钟前", { "mine": true }),
        msg(6, "agent", claude, "一份通用的就够了：这周合进 main 的改动里，只有两条是某个平台独有的，我在那两条后面标上平台名。回滚预案还差最后一步没确认：上次发布留下的回滚脚本引用了已经删掉的配置项，我先改好再跑一遍演练。", "20 分钟前", {}),
        msg(7, "person", by_person("林"), "请继续处理这个任务", "刚刚", { "mine": true }),
        msg(8, "ember", { "name": "still.fail" }, "⚠️ " + words, "刚刚", { "notice": Json::object(notice) }),
      ]
      o["asks"] = []
      o["askClear"] = false
      o["more"] = false
      Json::object(o)
    }
    _ => v
  }
}

///|
/// The chat `v` ending on a turn whose failure named no limit while its allowance, asked again, showed Fable's own week
/// used up ("chat-turn-limit"): its notice offers 重新分配账号 till it is pressed (`moved`).
fn with_limit_turn(v : Json, moved : Bool) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let words = if @sf.language() == "en" {
        "Fable limit reached"
      } else {
        "这个账号的 Fable 额度已用完"
      }
      let notice : Map[String, Json] = {
        "failed": true,
        "words": Json::string(words),
        "detail": "You've hit your Fable limit · resets Nov 20 at 9am (Asia/Tokyo). Switch to another model to continue.",
      }
      if !moved {
        notice["reassignSession"] = "s-c1"
      }
      let claude = by_agent("anthropic", "claude", "s-c1")
      // (a chat as long as its view and more, for what opens at its end to be seen held where it is)
      o["messages"] = [
        msg(1, "person", by_person("林"), "把发布清单整理一下：签名、渠道包、更新日志、回滚预案，各自谁负责、到哪一步了。", "1 小时前", { "mine": true }),
        msg(2, "agent", claude, "好。我先把四项列出来，逐项去查现在的状态：签名看证书和构建日志，渠道包看各平台的上传记录，更新日志看这周合进 main 的改动，回滚预案看上次发布留下的步骤。查完一项就在这里更新一次。", "1 小时前", {}),
        msg(3, "person", by_person("林"), "渠道包那边昨天说华为的审核卡住了，顺便看一下。", "50 分钟前", { "mine": true }),
        msg(4, "agent", claude, "华为的审核是因为隐私政策的链接打不开，已经换成新的链接重新提交了，现在在排队。签名这项查完了：证书有效期到明年三月，这次的构建都用的新证书。", "40 分钟前", {}),
        msg(5, "person", by_person("林"), "更新日志按渠道分开写吗？还是一份通用的？", "30 分钟前", { "mine": true }),
        msg(6, "agent", claude, "一份通用的就够了：这周合进 main 的改动里，只有两条是某个平台独有的，我在那两条后面标上平台名。回滚预案还差最后一步没确认：上次发布留下的回滚脚本引用了已经删掉的配置项，我先改好再跑一遍演练。", "20 分钟前", {}),
        msg(7, "person", by_person("林"), "请继续处理这个任务", "刚刚", { "mine": true }),
        msg(8, "ember", { "name": "still.fail" }, "⚠️ " + words, "刚刚", { "notice": Json::object(notice) }),
      ]
      o["asks"] = []
      o["askClear"] = false
      o["more"] = false
      Json::object(o)
    }
    _ => v
  }
}

///|
/// The chat `v` ending on a turn the station stopped asking for a state ("chat-turn-unanswered"): its notice
/// (回复即可继续) offers 重试 too till it is pressed (`retried`).
fn with_unanswered_turn(v : Json, retried : Bool) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let words = if @sf.language() == "en" {
        "This turn stopped without a result; reply to continue"
      } else {
        "本轮未产出结果即停止，回复即可继续"
      }
      let notice : Map[String, Json] = { "failed": true, "words": Json::string(words) }
      if !retried {
        notice["againSession"] = "s-c1"
      }
      let claude = by_agent("anthropic", "claude", "s-c1")
      // (a chat as long as its view and more, for what opens at its end to be seen held where it is)
      o["messages"] = [
        msg(1, "person", by_person("林"), "把发布清单整理一下：签名、渠道包、更新日志、回滚预案，各自谁负责、到哪一步了。", "1 小时前", { "mine": true }),
        msg(2, "agent", claude, "好。我先把四项列出来，逐项去查现在的状态：签名看证书和构建日志，渠道包看各平台的上传记录，更新日志看这周合进 main 的改动，回滚预案看上次发布留下的步骤。查完一项就在这里更新一次。", "1 小时前", {}),
        msg(3, "person", by_person("林"), "渠道包那边昨天说华为的审核卡住了，顺便看一下。", "50 分钟前", { "mine": true }),
        msg(4, "agent", claude, "华为的审核是因为隐私政策的链接打不开，已经换成新的链接重新提交了，现在在排队。签名这项查完了：证书有效期到明年三月，这次的构建都用的新证书。", "40 分钟前", {}),
        msg(5, "person", by_person("林"), "更新日志按渠道分开写吗？还是一份通用的？", "30 分钟前", { "mine": true }),
        msg(6, "agent", claude, "一份通用的就够了：这周合进 main 的改动里，只有两条是某个平台独有的，我在那两条后面标上平台名。回滚预案还差最后一步没确认：上次发布留下的回滚脚本引用了已经删掉的配置项，我先改好再跑一遍演练。", "20 分钟前", {}),
        msg(7, "person", by_person("林"), "请继续处理这个任务", "刚刚", { "mine": true }),
        msg(8, "ember", { "name": "still.fail" }, "⚠️ " + words, "刚刚", { "notice": Json::object(notice) }),
      ]
      o["asks"] = []
      o["askClear"] = false
      o["more"] = false
      Json::object(o)
    }
    _ => v
  }
}

///|
/// The chat `v` ending on an agent's need with no card ("chat-need"): what it asks, waiting for a person, nothing to
/// pick; what it needs said at the chat's end, let go there (the core's `stateAsk`).
pub fn with_need(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let all = match m.get("messages") {
        Some(Array(a)) => a.copy()
        _ => []
      }
      all.push(
        msg(12, "agent", by_agent("anthropic", "claude", "s-c1"), "你在手机上试一下新的列表，有问题截个图给我。", "1 分钟前", {
          "ending": "need_human",
        }),
      )
      o["messages"] = Json::array(all)
      o["stateText"] = Json::string(need_state.0)
      o["stateLead"] = Json::string(need_state.1)
      o["stateRest"] = Json::string(need_state.2)
      o["stateAsk"] = Json::number(12.0)
      Json::object(o)
    }
    _ => v
  }
}

///|
/// What chat-need's agent needs, as the chat's end says it (`stateText`, `stateLead`, `stateRest`).
pub let need_state : (String, String, String) = ("要你帮忙：在手机上试新列表", "need", "在手机上试新列表")

// ── an agent at work on a long step (MBUI_FIXTURE=chat-working) ──────────

///|
/// What the agent of the first row's chat does now, as long as an agent's step may say it (its call's description).
pub let working_step : String = "在 Willow 上跑整套检查：先编译 mbui 的原生测试，再逐个对比手机、平板和桌面三种宽度下的截图"

///|
/// What that agent does now, by its call: that step until a test moves it on to another (fix_later, as its station
/// would say the next).
pub let fix_working_now : Ref[(String, String)] = Ref(("call:1", working_step))

///|
pub let fix_working_important : Ref[Bool] = Ref(false)

///|
/// The first row's chat with its agent at work on that step, three minutes in: there as the chat opens.
pub fn with_working(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      o["agents"] = Json::array(
        items(Some(v), "agents").map(fn(a) {
          match a {
            Object(am) => {
              let w = am.copy()
              w["status"] = Json::string("running")
              w["since"] = Json::number(-200000.0)
              match field(Some(a), "session") {
                Some(Object(session)) => {
                  let running = session.copy()
                  running["statusText"] = Json::string("正在工作")
                  running["tone"] = Json::string("accent")
                  w["session"] = Json::object(running)
                }
                _ => ()
              }
              Json::object(w)
            }
            _ => a
          }
        }),
      )
      Json::object(o)
    }
    _ => v
  }
}

// ── links to a station's screens and its 共享调试 (MBUI_FIXTURE=chat-screens) ──

///|
/// An agent's answer last in the chat with a link of each kind a card shows over (peeks.mbt): a pull request on GitHub,
/// a page, another chat, a file it names by its path.
pub let peeks_answer : String = "改动在 https://github.com/acme/shop/pull/128 ，数据在 https://example.com/bench/list ，和 [首页的列表改成按天分组](https://app.still.fail/w/ws1/s/st1/chats/s-c2) 有关，入口在 `src/list/place.mbt:12`。"

///|
/// An agent's answer with links to Willow's screens, its 共享调试 and a web service of the chat's (screen_links.mbt):
/// the desktop's card, a tab's with its preview (the link's own words its title), a tab gone, 共享调试 bare in a
/// sentence (its title) and alone (its card), a link to anywhere else; first, the service alone (its card).
pub let screens_answer : String =
  #|开发服务器在 Willow 上起来了：
  #|
  #|[打开定价页](https://still.fail/o/ws1/st1/s-c1?service=j-web)
  #|
  #|登录页改好了，Willow 的桌面开着：
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
/// The core's cards of Willow's screens and its 共享调试 (`screenCard`, `adbCard`): the desktop someone looks at, a
/// tab it previews (1280 × 800), a tab it no longer has; this phone's adb not shared.
pub fn fixture_link_card(name : String, params : Map[String, Json]) -> Json? {
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
pub fn fixture_peek(on_value : (Json, Bytes?) -> Unit) -> Int {
  fix_later(0.0, fn() { on_value({ "frame": { "ts": 1 } }, Some(fixture_file_png("peek.png"))) })
  fix_stream_ids.val += 1
  fix_stream_ids.val
}

///|
/// The chat with its station's update said in its bar and opened.
/// chat-cache-cold: its agent at rest, its prompt cache over, as the core says it (ChatView::cacheCold).
pub fn with_cache_cold(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      let (status, detail) = if @sf.language() == "en" {
        ("Cache expired", "Reread ≈$1.49")
      } else {
        ("缓存已过期", "重读约 $1.49")
      }
      o["cacheCold"] = { "session": "s-c1", "status": Json::string(status), "detail": Json::string(detail), "afresh": false }
      Json::object(o)
    }
    _ => v
  }
}

///|
/// chat-letters: its latest page all letters its agents wrote other chats (not shown in it, views.ts isLetter), its
/// messages before them: as the core opens it, nothing shown and more before, till the page before is asked.
pub fn with_none_shown(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      o["messages"] = Json::array([])
      o["more"] = Json::boolean(true)
      // (its first entry the page's, a letter: paged back by it, as the core's cursor, views.ts firstEntry)
      o["firstEntry"] = Json::number(201.0)
      Json::object(o)
    }
    _ => v
  }
}

///|
/// chat-cc: the chat linked to a Slack thread and a Feishu chat, its words copied to the Slack one (Chat.tsx CcChooser).
pub fn with_cc(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      o["cc"] = [
        { "thread": 21, "place": "#still-fail", "via": "slack", "on": true },
        { "thread": 22, "place": "产品讨论", "via": "feishu", "on": false },
      ]
      Json::object(o)
    }
    _ => v
  }
}

///|
/// chat-archived: the chat archived; chat-cold-offline: its agent's prompt cache over and its station down (what is
/// said over its composer, one line each: sfpages chat_notices).
pub fn with_flag(v : Json, name : String) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      o[name] = Json::boolean(true)
      Json::object(o)
    }
    _ => v
  }
}

///|
/// chat-station-screen(s), chat-agent-screens: the screens of the station it runs on (ChatView's `screens`): its
/// display alone, or with a tab of its browser an agent drives.
pub fn with_chat_screens(v : Json, more : Bool) -> Json {
  let desktop : Json = { "id": "desktop", "kind": "desktop", "title": "Willow 的桌面", "line": "桌面 · 3024×1964" }
  let tab : Json = {
    "id": "browser:T1",
    "kind": "browser",
    "title": "登录 - GitHub",
    "line": "浏览器标签页 · 1280×800 · 由「整理发布清单」打开",
    "agent": true,
  }
  match v {
    Object(m) => {
      let o = m.copy()
      o["screens"] = if more { [desktop, tab] } else { [desktop] }
      Json::object(o)
    }
    _ => v
  }
}

///|
/// chat-done: its agent's turn over, where it stands said at the end of its messages as its row says it (ChatView's
/// `stateText`, `stateLead`, `stateRest`): `state` its words, what leads them, what follows the lead.
pub fn with_state(v : Json, state : (String, String, String)) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      o["stateText"] = Json::string(state.0)
      o["stateLead"] = Json::string(state.1)
      o["stateRest"] = Json::string(state.2)
      Json::object(o)
    }
    _ => v
  }
}

///|
/// What chat-done's agent said of its turn when it ended.
pub let done_state : (String, String, String) = (
  "已完成：问题已答复，用户确认先不改，没有改动",
  "done",
  "问题已答复，用户确认先不改，没有改动",
)

///|
pub fn with_station_update(v : Json) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      o["stationUpdate"] = {
        "tone": "update",
        "text": "Willow 有新版本",
        "label": "可更新",
        "station": "Willow",
        "detail": "更新时正在运行的 agent 会在更新后继续。",
        "from": "0.24.1",
        "to": "0.25.0",
        "version": "0.25.0",
        "open": true,
        "canUpdate": true,
      }
      Json::object(o)
    }
    _ => v
  }
}

///|
/// Willow's overview (fixture_station_drive's), with its software as the core says it (its versions, a newer Claude
/// Code out) and what its agents' processes take.
pub fn fixture_station_overview() -> Json {
  let o = match fixture_station_drive(true) {
    Object(m) => m
    _ => {}
  }
  o["processes"] = [{ "pid": 4021, "rssBytes": 1200000000.0 }]
  o["processesText"] = "2 个 agent 进程 · 1.1 GB"
  // its profiles, as the workspace's list has them (the settings' fixture's)
  o["profiles"] = Json::array(@settings.fixture_profiles())
  o["updates"] = [
    {
      "id": "station",
      "name": "Station",
      "installed": true,
      "version": "0.1.4765",
      "latest": "0.1.4765",
      "newer": false,
      "channel": "stable",
      "auto": true,
      "updatable": true,
      "state": "idle",
      "checkedAt": 1792300000000.0,
      "shownText": "0.1.4765",
      "tipText": "已是最新",
      "updatingText": "正在更新",
      "failedText": "更新失败",
    },
    {
      "id": "claude",
      "name": "Claude Code",
      "installed": true,
      "version": "2.1.4",
      "latest": "2.1.9",
      "newer": true,
      "updatable": true,
      "state": "idle",
      "checkedAt": 1792300000000.0,
      "shownText": "2.1.4",
      "tipText": "",
      "updatingText": "正在更新",
      "failedText": "更新失败",
    },
  ]
  Json::object(o)
}

///|
/// The places the made-up station's one bot is in (`chat.relayPlaces`): one relayed to before, a private one.
pub fn fix_relay_places() -> Json {
  {
    "connects": [
      {
        "id": "slack-1",
        "kind": "slack",
        "name": "星火助手",
        "team": "星火",
        "places": [
          { "id": "C1", "name": "dev", "kind": "channel", "used": 20 },
          { "id": "C2", "name": "ops", "kind": "channel", "private": true },
        ],
      },
    ],
  }
}

///|
/// What was said in the chat besides words, as the core's `chatThings` says it: its pictures and a video, its files,
/// its links and its pull requests (`many`: four, else the latest), the latest first; those of each kind whose name has
/// the words `q`.
pub fn fixture_things(q : String, many? : Bool = true) -> Json {
  let thing = fn(key : String, seq : Int, by : String, when : String, more : Map[String, Json]) -> Json {
    let m : Map[String, Json] = {
      "key": Json::string(key),
      "seq": Json::number(seq.to_double()),
      "createdAt": Json::number(seq.to_double()),
      "by": Json::string(by),
      "time": { "createdAt": { "at": 0, "ago": Json::string(when), "full": Json::string("10/19 0\{seq % 10}:12:00"), "until": "", "past": true } },
    }
    for k, v in more {
      m[k] = v
    }
    Json::object(m)
  }
  // (each with what its message says and when, the core's `words`; a message's latest first, as the core lists them)
  let said = fn(t : Json, words : String) -> Json {
    match t {
      Object(m) if words != "" => {
        let m = m.copy()
        m["words"] = Json::string(words)
        Json::object(m)
      }
      t => t
    }
  }
  let media = [
    said(thing("9/work/s-c1/after.png", 9, "Claude", "10 分钟前", { "file": file("after.png", 1170, 2532, 702000) }), "列表高度改前改后"),
    said(thing("9/work/s-c1/before.png", 9, "Claude", "10 分钟前", { "file": file("before.png", 1170, 2532, 698000) }), "列表高度改前改后"),
    said(thing("4/work/s-c1/演示录屏.mp4", 4, "Claude", "2 小时前", { "file": film_file("演示录屏.mp4", 1920, 1080, 3200000, 12000, 360) }), "录了一段滑动"),
    thing("3/work/s-c1/插画参考.png", 3, "Ana", "昨天 22:40", { "file": file("插画参考.png", 1200, 800, 245760) }),
  ]
  // (when each message was said, the day's heading and its time)
  let when : Map[Int, (String, String)] = { 9: ("今天", "19:20"), 4: ("今天", "17:05"), 3: ("昨天", "22:40") }
  let files = [
    thing("5/work/s-c1/build.log", 5, "Claude", "1 小时前", { "file": file("build.log", 0, 0, 18432) }),
    thing("3/work/s-c1/性能报告.pdf", 3, "Claude", "2 小时前", { "file": file("性能报告.pdf", 0, 0, 1048576) }),
  ]
  let links = [
    thing("https://example.com/bench/list", 6, "Claude", "40 分钟前", {
      "url": "https://example.com/bench/list",
      "site": "example.com/bench/list",
      "title": "列表滚动的性能数据",
      "count": 2,
    }),
    thing("https://example.com/review/42", 4, "Ana", "2 小时前", { "url": "https://example.com/review/42", "site": "example.com/review/42", "count": 1 }),
  ]
  let pull = fn(n : Int, seq : Int, title : String, state : String, failed : Int, when : String) -> Json {
    thing("acme/shop#\{n}", seq, "Claude", when, {
      "url": Json::string("https://github.com/acme/shop/pull/\{n}"),
      "repository": "acme/shop",
      "number": Json::number(n.to_double()),
      "title": Json::string(title),
      "state": Json::string(state),
      "count": 1,
      "checks": { "passed": 9, "failed": Json::number(failed.to_double()), "pending": 0 },
    })
  }
  let pulls = [
    pull(131, 7, "列表里的图片按需解码", "open", 1, "10 分钟前"),
    pull(128, 6, "首页列表按天分组", "merged", 0, "40 分钟前"),
    pull(127, 5, "虚拟列表：按估计高度占位", "merged", 0, "1 小时前"),
    pull(124, 3, "去掉旧的分页加载", "closed", 0, "2 小时前"),
  ]
  let pulls = if many { pulls } else { pulls[:1].to_owned() }
  let words : Array[String] = q.to_lower().split(" ").map(fn(w) { w.to_owned() }).filter(fn(w) { w != "" }).collect()
  let having = fn(list : Array[Json]) -> Json {
    Json::array(
      list.filter(fn(t) {
        let said = (text(Some(t), "title") + " " + text(field(Some(t), "file"), "name") + " " + text(Some(t), "words") + " " + text(Some(t), "url")).to_lower()
        words.iter().all(fn(w) { said.contains(w) })
      }),
    )
  }
  {
    "title": "聊天页虚拟列表",
    "whole": true,
    "counts": {
      "media": Json::number(media.length().to_double()),
      "files": Json::number(files.length().to_double()),
      "links": Json::number(links.length().to_double()),
      "pulls": Json::number(pulls.length().to_double()),
    },
    "media": having(media),
    "files": having(files),
    "links": having(links),
    "pulls": having(pulls),
    "mediaDays": media_days(having(media), when),
  }
}

///|
/// Pictures and videos (`media`, the latest first) by the day and the message they were sent with, as the core's
/// `mediaDays` (things.ts): `when` each message's day and time.
fn media_days(media : Json, when : Map[Int, (String, String)]) -> Json {
  let days : Array[(String, Array[(Int, Array[Json])])] = []
  let list = match media {
    Array(a) => a
    _ => []
  }
  for t in list {
    let seq = number(Some(t), "seq").to_int()
    let (day, _) = when.get(seq).unwrap_or(("", ""))
    if days.length() == 0 || days[days.length() - 1].0 != day {
      days.push((day, []))
    }
    let groups = days[days.length() - 1].1
    if groups.length() > 0 && groups[groups.length() - 1].0 == seq {
      groups[groups.length() - 1].1.insert(0, t)
    } else {
      groups.push((seq, [t]))
    }
  }
  Json::array(
    days.map(fn(d) {
      Json::object({
        "day": Json::string(d.0),
        "groups": Json::array(
          d.1.map(fn(g) {
            let first = Some(g.1[0])
            Json::object({
              "seq": Json::number(g.0.to_double()),
              "clock": Json::string(when.get(g.0).unwrap_or(("", "")).1),
              "by": Json::string(text(first, "by")),
              "words": Json::string(text(first, "words")),
              "items": Json::array(g.1),
            })
          }),
        ),
      })
    }),
  )
}
