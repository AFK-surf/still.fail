// What a chat offers as Android's does, over the fixture's chat with its views edited for each case: its station's tag
// opens the station's card (PageParts.kt ChatStationChip), a notice's word installs a runtime or reports a failure,
// one about a profile leads to it, one saying a chat was opened links to it (Chat.kt SystemNotice), a waiting message's
// line installs (BlockedLine), a link to an archived chat reads as its title and its card says so (ChatRef.tsx), a
// Slack user's name in a history offers 这是我 (History.kt SlackName), and the chat's sheet opens it in Slack or Feishu.

///|
/// `v` with `more` said over its fields (an object; anything else as it is).
fn with_fields(v : Json, more : Array[(String, Json)]) -> Json {
  match v {
    Object(m) => {
      let o : Map[String, Json] = {}
      for k, x in m {
        o[k] = x
      }
      for kv in more {
        o[kv.0] = kv.1
      }
      Json::object(o)
    }
    _ => v
  }
}

///|
/// The chat view's message `seq` with `more` over it.
fn with_chat_message(chat : Json, seq : Double, more : Array[(String, Json)]) -> Json {
  let ms = match chat {
    Object(m) =>
      match m.get("messages") {
        Some(Array(a)) => a
        _ => []
      }
    _ => []
  }
  with_fields(chat, [
    (
      "messages",
      Json::array(ms.map(fn(x) { if number(Some(x), "seq") == seq { with_fields(x, more) } else { x } })),
    ),
  ])
}

///|
/// The app over the fixture in `mode`, its topics' values edited by `edit` (by the topic's name), its calls kept and
/// answered with `answer`'s (nothing by default).
fn edited_core(
  calls : Array[Made],
  mode : String,
  edit : (String, Json) -> Json,
  answer? : (String) -> Json = fn(_) { Json::object({}) },
  epoch? : Ref[Int] = Ref::new(0),
  platform? : Int = 2,
) -> @ui.Tester {
  reset()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let t = (base.topic)(name, params)
      // (a change the test makes is a new version of what the core says: made up as it is read, followed by its
      // version, as the core's by what it says)
      topic_as_read(name, params, match t.value {
        Some(v) => { ..t, value: Some(edit(name, v)), version: t.version + epoch.val }
        None => t
      })
    },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      done(Ok(answer(name)))
    },
  }
  open_fixture_over(mode, src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a chat with no agent in it: its station's tag in the bar opens the station's card" {
  let calls : Array[Made] = []
  let t = edited_core(calls, "chat", fn(name, v) {
    match name {
      "chat" => with_fields(v, [("agents", [])])
      // (a name of its own, told apart from the messages that name it)
      "stations" =>
        match v {
          Array(a) =>
            Json::array(
              a.map(fn(s) { if text(Some(s), "station") == "ws1/st1" { with_fields(s, [("name", "甲号机")]) } else { s } }),
            )
          _ => v
        }
      _ => v
    }
  })
  assert_true(!@sf.presenting())
  t.tap_text("甲号机")
  t.frame()
  assert_true(@sf.presenting(), msg="the station's card")
  assert_true(t.find("机器详情") is Some(_))
}

///|
test "a failure the viewer may report: 上报 asks first, then reports it and says what it was filed as" {
  let calls : Array[Made] = []
  let t = edited_core(
    calls,
    "chat",
    fn(name, v) {
      if name == "chat" {
        with_chat_message(v, 9.0, [
          ("text", "⚠️ 这一轮没跑完。"),
          ("notice", { "failed": true, "words": "这一轮没跑完" }),
          ("reportable", true),
        ])
      } else {
        v
      }
    },
    answer=fn(name) { if name == "chat.report" { { "number": 42, "duplicate": false } } else { Json::object({}) } },
  )
  for _ in 0..<6 {
    if t.find("这一轮没跑完") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  t.tap_text("上报")
  t.frame()
  assert_true(@sf.presenting(), msg="asked first")
  assert_true(named(calls, "chat.report").length() == 0)
  // (with a mouse: the web's confirm, come in)
  t.run_for(@kit.presence_in_ms)
  // the confirm's own 上报: its words alone on their node (the notice's is in a rich line of its own)
  let (x, y) = words_node(t, "上报").unwrap()
  t.tap(x, y)
  t.frame()
  let sent = named(calls, "chat.report")
  assert_eq(sent.length(), 1)
  assert_eq(number(Some(sent[0].params), "seq"), 9.0)
  assert_eq(number(Some(sent[0].params), "thread"), 7.0)
  assert_eq(text(Some(sent[0].params), "station"), "ws1/st1")
  t.frame()
  assert_true(t.find("已上报为 FB-42") is Some(_))
}

///|
test "a notice that a runtime is missing: its word installs it (software.update)" {
  let calls : Array[Made] = []
  let t = edited_core(calls, "chat", fn(name, v) {
    if name == "chat" {
      with_chat_message(v, 9.0, [
        ("text", "Studio 上没有 codex。"),
        ("notice", { "failed": false, "words": "Studio 上没有 codex" }),
        ("install", { "runtime": "codex", "state": "missing", "title": "codex", "action": "安装" }),
      ])
    } else {
      v
    }
  })
  for _ in 0..<6 {
    if t.find("Studio 上没有 codex") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  t.tap_text("安装")
  let sent = named(calls, "software.update")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "id"), "codex")
  assert_eq(text(Some(sent[0].params), "station"), "ws1/st1")
}

///|
test "a notice about a profile: what went wrong (after its ：) leads to the profile's page" {
  let calls : Array[Made] = []
  let t = edited_core(calls, "chat", fn(name, v) {
    if name == "chat" {
      // (the core says where the profile's link begins: after the ：)
      with_chat_message(v, 9.0, [
        ("profile", "p1"),
        ("notice", { "failed": true, "words": "Studio 上 codex 的登录已失效：请在设置里重新登录", "linkAt": 22 }),
      ])
    } else {
      v
    }
  })
  for _ in 0..<6 {
    if t.find("登录已失效") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  // (the words after the ：, the pill's last: tapped at its right end)
  let (x, y, w, h) = t.rect_of("登录已失效").unwrap()
  t.tap(x + w - 20.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::Profile("ws1/st1", "p1")))
}

///|
test "a notice that a chat was opened: its line is its Markdown drawn, the chat's chip in it, and tapped it opens that chat" {
  let calls : Array[Made] = []
  let link = "https://app.still.fail/o/ws1/st1/s-c2"
  // (as the station says it in a still.fail chat, sessions/opened.ts sayOpened, and the core's tree of its words)
  let words = "已创建对话：[共享调试：配对后连不上](\{link})"
  let t = edited_core(
    calls,
    "chat",
    fn(name, v) {
      if name == "chat" {
        with_chat_message(v, 9.0, [
          ("text", Json::string(words)),
          (
            "notice",
            {
              "failed": false,
              "words": Json::string(words),
              "md": [["p", [[0, 6], ["a", [[7, 18]], { "href": Json::string(link) }]]]],
            },
          ),
        ])
      } else {
        v
      }
    },
    answer=fn(name) { if name == "link.parse" { fixture_link_parse(link) } else { Json::object({}) } },
  )
  for _ in 0..<6 {
    if t.find("共享调试：配对后连不上") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  assert_true(t.find("已创建对话：@共享调试：配对后连不上") is Some(_), msg="the chat's chip in its line")
  assert_true(t.find("](") is None, msg="none of its Markdown")
  t.tap_run("共享调试：配对后连不上")
  assert_eq(named(calls, "link.parse").length(), 1)
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "s-c2")
    _ => fail("not a chat")
  }
}

///|
test "an agent's link to an archived chat written bare: its title as the core says it, its card saying it is archived" {
  let calls : Array[Made] = []
  let link = "https://app.still.fail/o/ws1/st1/c-old"
  let words = "看 \{link}"
  let t = edited_core(
    calls,
    "chat",
    fn(name, v) {
      if name == "chat" {
        // (the core's tree of its words, and the chats they link to as their lists have them: views.ts drawn)
        with_chat_message(v, 11.0, [
          ("text", Json::string(words)),
          ("md", [["p", [[0, 2], ["a", [[2, 40]], { "href": Json::string(link) }]]]]),
          ("chats", [{ "href": Json::string(link), "title": "旧的对话", "archived": true, "note": "已归档" }]),
        ])
      } else {
        v
      }
    },
    // (a mouse's: what a link shows while the pointer rests on it)
    platform=0,
  )
  assert_true(t.find("看 @旧的对话") is Some(_), msg="its title, not its link")
  assert_true(t.find(link) is None)
  assert_true(t.find("已归档") is None)
  let (x, y, w, h) = t.run_rects("旧的对话")[0]
  t.move(x + w / 2.0, y + h / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  assert_true(t.find("已归档") is Some(_), msg="its card: that it is archived")
}

///|
test "a Slack user's name in a history: 这是我 binds them to the viewer (slack.identity)" {
  let calls : Array[Made] = []
  // the history's first item (what it received): from a Slack user
  let slack_from = fn(it : Json) -> Json {
    let body = field(Some(it), "body")
    match body {
      Some(b) if text(body, "kind") == "received" => {
        let content = field(body, "content").unwrap_or(Json::object({}))
        let msgs = items(Some(content), "messages").map(fn(m) {
          with_fields(m, [("from", { "name": "林小满", "bound": false, "slackUser": "U1" })])
        })
        with_fields(it, [("body", with_fields(b, [("content", with_fields(content, [("messages", Json::array(msgs))]))]))])
      }
      _ => it
    }
  }
  let t = edited_core(calls, "history", fn(name, v) {
    if name == "history" {
      // (that item alone: the steps open at their newest, and it in view)
      with_fields(v, [("items", Json::array(items(Some(v), "items").map(slack_from)[:1].to_array()))])
    } else {
      v
    }
  })
  t.tap_text("林小满")
  // its menu, the presenters' sheet with a finger, up
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.find("这是我") is Some(_), msg="its menu")
  t.tap_text("这是我")
  let sent = named(calls, "slack.identity")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "user"), "U1")
  assert_true(flag(Some(sent[0].params), "bound"))
}

///|
test "the chat's sheet: one from Slack or Feishu opens there" {
  let calls : Array[Made] = []
  let t = edited_core(calls, "chat-info", fn(name, v) {
    if name == "chat" {
      with_fields(v, [
        ("slackUrl", "https://example.slack.com/archives/C1/p1"),
        ("feishuUrl", "https://example.feishu.cn/client/chat/open?openChatId=oc_1"),
      ])
    } else {
      v
    }
  })
  t.tap_text("在飞书中打开")
  assert_true(t.opened().contains("https://example.feishu.cn/client/chat/open?openChatId=oc_1"))
  t.tap_text("在 Slack 中打开")
  assert_true(t.opened().contains("https://example.slack.com/archives/C1/p1"))
}

///|
test "a station's failed update stays out of the chat bar even when its notice was open" {
  let calls : Array[Made] = []
  let t = edited_core(calls, "chat", platform=3, fn(name, v) {
    if name == "chat" {
      with_fields(v, [
        (
          "stationUpdate",
          {
            "tone": "trouble",
            "text": "Studio 更新失败",
            "label": "更新失败",
            "station": "Studio",
            "detail": "更新时正在运行的 agent 会稍后继续。",
            "from": "1.2.0",
            "to": "1.3.0",
            "version": "1.3.0",
            "open": true,
            "canUpdate": true,
            "dismissible": true,
          },
        ),
      ])
    } else {
      v
    }
  })
  assert_true(t.find("更新失败") is None)
  assert_true(t.find("1.2.0 → 1.3.0") is None)
  t.resize(1280.0, 800.0)
  t.draw()
  assert_true(t.find("更新失败") is None)
  assert_true(t.find("1.2.0 → 1.3.0") is None)
  assert_eq(named(calls, "station.updateNotice").length(), 0)
  assert_eq(named(calls, "software.update").length(), 0)
}

///|
/// The centre of a plain text node whose words are exactly `s` (Tester::find takes the first containing them, whichever
/// kind of node).
fn words_node(t : @ui.Tester, s : String) -> (Double, Double)? {
  let want = " \"" + s + "\" "
  for l in t.dump().split("\n") {
    let l = l.trim_start(chars=" ").to_string()
    if l.has_prefix("text ") && l.contains(want) {
      // "text x,y wxh \"…\" lines=n"
      let parts = l.split(" ").collect()
      let xy = parts[1].split(",").collect()
      let wh = parts[2].split("x").collect()
      let x = dump_number(xy[0].to_string())
      let y = dump_number(xy[1].to_string())
      let w = dump_number(wh[0].to_string())
      let h = dump_number(wh[1].to_string())
      return Some((x + w / 2.0, y + h / 2.0))
    }
  }
  None
}

///|
/// A dump's number, its whole part (enough to tap in the middle of words): its digits, a minus before them.
fn dump_number(s : String) -> Double {
  let mut n = 0
  let mut neg = false
  for ch in s {
    if ch == '.' {
      break
    } else if ch == '-' {
      neg = true
    } else if ch >= '0' && ch <= '9' {
      n = n * 10 + (ch.to_int() - '0'.to_int())
    }
  }
  (if neg { -n } else { n }).to_double()
}

///|
/// A failure the viewer may report, its words `words`: how wide its 上报 and the dot before it are drawn.
fn report_drawn(words : String) -> (Double, Double) {
  let calls : Array[Made] = []
  let t = edited_core(calls, "chat", fn(name, v) {
    if name == "chat" {
      with_chat_message(v, 9.0, [
        ("text", Json::string("⚠️ " + words)),
        ("notice", { "failed": true, "words": Json::string(words) }),
        ("reportable", true),
      ])
    } else {
      v
    }
  })
  for _ in 0..<6 {
    if t.find("上报") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  let w = fn(s : String) -> Double {
    let found = t.words().filter(fn(x) { x.0 == s })
    if found.length() > 0 {
      found[0].3
    } else {
      -1.0
    }
  }
  (w("上报"), w("·"))
}

///|
test "a failure the viewer may report, its words too long for the line: they are cut short before 上报, which is whole" {
  let short = report_drawn("这一轮没跑完")
  let long = report_drawn("本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发出的消息），请留意")
  assert_true(short.0 > 0.0 && short.1 > 0.0, msg="\{short}")
  assert_eq(long, short)
}
