// A link's card reads what it shows while it is pointed at and let go of once it has gone, so the next time it shows
// it is read again (peeks.mbt peek_read): a pull request's card said the checks it first read for as long as the app
// ran.

///|
test "a link's card is read as the pointer comes onto it and let go of once it has gone, read again the next time" {
  @sfbase.reset()
  let href = "https://github.com/AFK-surf/Cue/pull/4466"
  let read : Array[String] = []
  let left : Array[String] = []
  let made = @sfbase.made_source()
  let src : Source = {
    ..made,
    topic_read: fn(name, params) {
      if name == "linkPreview" && read.last() != Some(name) {
        read.push(name)
      }
      made.topic(name, params).get().snapshot()
    },
    leave: fn(name, _, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      left.push(name)
      read.push("left")
    },
    release: fn(name, _) {
      left.push(name)
      read.push("left")
    },
  }
  let t = @ui.Tester::new(
    fn(c) {
      @sfbase.held_build()
      c.after_build("held/end", fn() { @sfbase.held_end() })
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        c.column(pad=40.0, fn() {
          let link = @kit.button(c, "PR #4466", key="pr", variant=Ghost)
          web_peek(c, src, "st", href, "PR #4466", link.id)
        })
        |> ignore
      })
    },
    w=800.0,
    h=800.0,
    native=Mouse,
    pointing=Mouse,
  )
  t.draw()
  assert_eq(read, [])
  let (x, y, w, h) = t.get(@ui.Role::Button, label="PR #4466").rect
  // pointed at: read, and its card opens over it
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(hover_open_ms * 2.0)
  assert_eq(read, ["linkPreview"])
  assert_eq(left, [])
  // the pointer gone, the card goes; once it has, what it read is let go of, once
  t.move_to(700.0, 700.0)
  t.run_for((hover_close_ms + hover_out_ms) * 2.0)
  assert_eq(left, ["linkPreview"])
  t.run_for((hover_close_ms + hover_out_ms) * 2.0)
  assert_eq(left, ["linkPreview"])
  // pointed at again: read again
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(hover_open_ms * 2.0)
  assert_eq(read, ["linkPreview", "left", "linkPreview"])
}

///|
/// A chat's link's card alone, with the core's reading of links, for what `said` says of a message.
fn chat_card_tester(href : String, linked : LinkedChat?, said : (Map[String, Json]) -> Json?) -> @ui.Tester {
  @sfbase.reset()
  let made = @sffixture.fixture("rich-chat")
  let src : Source = {
    ..made,
    topic_read: fn(name, params) {
      if name == "messagePeek" {
        match said(params) {
          Some(v) => { value: Some(v), error: None, version: 1 }
          None => { value: None, error: None, version: 0 }
        }
      } else {
        made.topic(name, params).get().snapshot()
      }
    },
  }
  @ui.Tester::new(
    fn(c) {
      @sfbase.held_build()
      c.after_build("held/end", fn() { @sfbase.held_end() })
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { c.column(pad=40.0, fn() { chat_card(c, src, "card", "ws1/st1", href, linked) }) |> ignore })
    },
    w=800.0,
    h=800.0,
    native=Mouse,
    pointing=Mouse,
  )
}

///|
test "a link to one message of a chat: its card says that message, who said it and when, not the chat's last words" {
  let asked : Array[(Double, Double)] = []
  let t = chat_card_tester("https://app.still.fail/o/ws1/st1/s-c2?message=2", None, fn(params) {
    match (params.get("thread"), params.get("seq")) {
      (Some(Number(thread, ..)), Some(Number(seq, ..))) => if !asked.contains((thread, seq)) { asked.push((thread, seq)) }
      _ => ()
    }
    Some(@sffixture.fixture_message_peek())
  })
  t.draw()
  t.draw()
  assert_eq(asked.length(), 1)
  assert_eq(asked[0].1, 2.0)
  assert_true(t.find("首页的列表改成按天分组") is Some(_), msg="the chat's title")
  assert_true(t.find("林小满 · 5 分钟前") is Some(_), msg="who said it and when")
  assert_true(t.find("列表按天分组做好了") is Some(_), msg="its words")
}

///|
test "a link to a chat alone reads no message; one archived or gone says so" {
  let asked = Ref(0)
  let ask = fn(_ : Map[String, Json]) -> Json? {
    asked.val += 1
    None
  }
  let t = chat_card_tester("https://app.still.fail/o/ws1/st1/s-c2", None, ask)
  t.draw()
  t.draw()
  assert_eq(asked.val, 0)
  // archived, its message still read, by the thread its message says it has
  let archived : LinkedChat = { href: "", title: "归档的对话", archived: true, note: "已归档", thread: Some(7.0) }
  let t = chat_card_tester("https://app.still.fail/o/ws1/st1/s-old?message=3", Some(archived), fn(_) { Some(@sffixture.fixture_message_peek()) })
  t.draw()
  t.draw()
  assert_true(t.find("已归档") is Some(_))
  assert_true(t.find("列表按天分组做好了") is Some(_))
  // no such message: said so, not left in its bones
  let t = chat_card_tester("https://app.still.fail/o/ws1/st1/s-c2?message=999", None, fn(_) { Some(Json::null()) })
  t.draw()
  t.draw()
  assert_true(t.find(@sf.t("web-main.chatRef.previewMessageGone")) is Some(_))
}

///|
test "a file is read on every entry, including while its card is still open" {
  @sfbase.reset()
  hovered_file.val = None
  let reads = Ref(0)
  let active = Ref(false)
  let made = @sfbase.made_source()
  let src : Source = {
    ..made,
    topic_read: fn(name, params) {
      if name == "filePeek" && !active.val {
        active.val = true
        reads.val += 1
      }
      made.topic(name, params).get().snapshot()
    },
    leave: fn(name, _, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      if name == "filePeek" { active.val = false } },
    release: fn(name, _) { if name == "filePeek" { active.val = false } },
    refresh: fn(name, _) { if name == "filePeek" && active.val { reads.val += 1 } },
  }
  let t = @ui.Tester::new(
    fn(c) {
      @sfbase.held_build()
      c.after_build("held/end", fn() { @sfbase.held_end() })
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        c.column(pad=40.0, fn() {
          let link = @kit.button(c, "src/a.ts", key="file", variant=Ghost)
          file_peek(c, src, "st", "session", "src/a.ts", None, link.id)
        }) |> ignore
      })
    },
    w=800.0,
    h=800.0,
    native=Mouse,
    pointing=Mouse,
  )
  // (its card's made-up file while it is read, in its bones: none of its code coloured, nothing asked of the core)
  let inked = Ref(0)
  let kept = @sf.kept_call.val
  @sf.kept_call.val = Some(fn(name, params, bytes) {
    if name == "code.ink" {
      inked.val += 1
    }
    match kept {
      Some(k) => k(name, params, bytes)
      None => None
    }
  })
  t.draw()
  let (x, y, w, h) = t.get(@ui.Role::Button, label="src/a.ts").rect
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(hover_open_ms * 2.0)
  assert_eq(reads.val, 1)
  // Leave and return before the card closes; it still must re-read the file.
  t.move_to(700.0, 700.0)
  t.frame()
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.frame()
  assert_eq(reads.val, 2)
  @sf.kept_call.val = kept
  assert_eq(inked.val, 0, msg="code coloured in its bones")
}

///|
fn file_card_refresh_case(intermediate : Bool) -> Unit raise {
  @sfbase.reset()
  hovered_file.val = None
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let made = @sfbase.made_source()
  let src : Source = {
    ..made,
    topic_read: fn(name, params) {
      let sub = client.follow_topic(name, params~)
      { value: sub.value, error: sub.error, version: sub.version }
    },
    waits: fn(name, params) { client.follow_topic(name, params~).waiting },
    leave: fn(name, params, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      client.leave_topic(name, params~) },
    release: fn(name, params) { client.release_topic(name, params~) },
    refresh: fn(name, params) { client.refresh_topic(name, params~) },
  }
  let t = @ui.Tester::new(
    fn(c) {
      @sfbase.held_build()
      c.after_build("held/end", fn() { @sfbase.held_end() })
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        c.column(pad=40.0, fn() {
          let link = @kit.button(c, "src/a.ts", key="file", variant=Ghost)
          file_peek(c, src, "ws/st", "session", "src/a.ts", Some(12), link.id)
        }) |> ignore
      })
    },
    w=800.0,
    h=800.0,
    native=Mouse,
    pointing=Mouse,
  )
  t.draw()
  let (x, y, w, h) = t.get(@ui.Role::Button, label="src/a.ts").rect
  let entered = t.time()
  t.move_to(x + w / 2.0, y + h / 2.0)
  assert_eq(sent.length(), 1)
  assert_true(sent[0].contains("\"topic\":\"filePeek\""))
  assert_true(sent[0].contains("\"station\":\"ws/st\""))
  assert_true(sent[0].contains("\"key\":\"session\""))
  assert_true(sent[0].contains("\"path\":\"src/a.ts\""))
  assert_true(sent[0].contains("\"line\":12"))
  t.frame_at(entered + hover_open_ms)
  client.receive_json({ "id": 1, "value": { "kind": "dir", "name": "a.ts", "path": "src/a.ts", "entries": ["before-entry"] } })
  t.frame()
  assert_true(t.find("before-entry") is Some(_))
  t.move_to(700.0, 700.0)
  t.frame()
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.frame()
  assert_eq(sent.length(), 3)
  assert_true(sent[1].contains("\"id\":1") && sent[1].contains("\"unsubscribe\":true"))
  assert_true(sent[2].contains("\"id\":2") && sent[2].contains("\"subscribe\""))
  assert_true(t.find("before-entry") is Some(_), msg="the card stays open with its old value while refreshing")
  client.receive_json({ "id": 1, "value": { "kind": "dir", "name": "a.ts", "path": "src/a.ts", "entries": ["late-entry"] } })
  t.frame()
  assert_true(t.find("before-entry") is Some(_))
  assert_true(t.find("late-entry") is None)
  client.receive_json({ "id": 2, "value": { "kind": "dir", "name": "a.ts", "path": "src/a.ts", "entries": ["after-entry"] } })
  t.frame()
  assert_true(t.find("after-entry") is Some(_))
  let left = t.time()
  t.move_to(700.0, 700.0)
  assert_eq(sent.length(), 3, msg="the open card still holds the topic")
  t.frame_at(left + hover_close_ms)
  assert_eq(sent.length(), 3, msg="the leaving card still holds the topic")
  if intermediate { t.frame_at(left + hover_close_ms + hover_out_ms / 2.0) }
  t.frame_at(left + hover_close_ms + hover_out_ms)
  t.frame()
  assert_eq(sent.length(), 4)
  assert_true(sent[3].contains("\"id\":2") && sent[3].contains("\"unsubscribe\":true"))
  assert_true(client.peek_topic("filePeek", params=file_peek_params("ws/st", "session", "src/a.ts", Some(12))) is None)
  @ui.run_let_go()
}

///|
test "a file card refreshes its real subscription on re-entry and keeps showing the old value until the answer" {
  file_card_refresh_case(false)
  file_card_refresh_case(true)
}
