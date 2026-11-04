// The chat's whole picture at a declared moment, after the same inputs and core changes. Intermediate display
// frames may be dense, sparse, absent, or sampled ahead of the host's clock. All of the page is compared, including
// the list, composer, bar and flying copies, not only the last bubble or the final resting frame.

///|
enum ChatMoment {
  Edit
  Send
  Quote
  Arrive
  Read
  Switch
} derive(Eq, Show)

///|
/// Extra frames only: input times and the observed moment do not move with the display's cadence.
fn chat_extra_frames(mode : Int, until : Double) -> Array[Double] {
  match mode {
    1 => Array::makei((until / (1000.0 / 60.0)).to_int(), fn(i) { (i + 1).to_double() * (1000.0 / 60.0) })
    2 => Array::makei((until / (1000.0 / 120.0)).to_int(), fn(i) { (i + 1).to_double() * (1000.0 / 120.0) })
    3 => [7.0, 49.0, 137.0, 263.0, 517.0, 811.0].filter(fn(at) { at < until })
    _ => []
  }
}

///|
/// One actual frame's visible drawing. drawn_text names glyphs and images independently of their allocation;
/// positions use its 1/64-point precision. The first different line makes a failed comparison reviewable.
fn chat_picture_difference(was : String, now : String) -> String {
  let a = was.split("\n").collect()
  let b = now.split("\n").collect()
  for i in 0..<a.length() {
    if i >= b.length() { break }
    if a[i] != b[i] { return "line \{i}: before \{a[i]}; after \{b[i]}" }
  }
  "line count \{a.length()} / \{b.length()}"
}

///|
fn chat_at_moment(kind : ChatMoment, width : Double, platform : Int, mode : Int, at : Double) -> String raise {
  println("MOMENT \{kind} \{width} \{platform} \{mode} \{at} begin")
  new_run()
  let clock = Ref(0.0)
  fix_clock.val = Some(fn() { clock.val })
  let base = fixture("chat")
  let messages = Array::makei(30, fn(i) { said(i + 1, "消息 \{i + 1}，留在阅读的位置") })
  let version = @signals.signal(1)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if (kind == Arrive || kind == Read) && name == "chat" && params.get("session") == Some(Json::string("s-c1")) {
        let v = version.get()
        { value: Some({ "title": "整理发布清单", "thread": { "id": 1 }, "messages": Json::array(messages), "agents": [], "people": [] }), error: None, version: v }
      } else {
        (base.topic)(name, params)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=width, h=844.0, platform~)
  println("MOMENT tester made")
  t.run_for(@ui.move_most_ms)
  println("MOMENT opened")
  if width >= 600.0 && width < 840.0 { page_over(t, width); t.run_for(@ui.move_most_ms) }
  if kind == Send || kind == Quote {
    t.tap_text("发消息")
    t.type_text("把这次检查的结果记下来")
    t.run_for(@ui.move_most_ms)
  }
  let tree = @ui.view_tree().unwrap()
  let start = t.time()
  let frames = chat_extra_frames(mode, at)
  let mut f = 0
  for step, event_at in [10.0, 110.0, 210.0, 410.0] {
    if event_at > at { break }
    while f < frames.length() && frames[f] < event_at {
      t.frame_at(start + frames[f])
      f += 1
    }
    if mode == 4 { t.frame_shown_at(start + event_at, start + event_at + 40.0) }
    t.advance(start + event_at - t.time())
    println("MOMENT event \{step} \{event_at}")
    match kind {
      Edit => match step {
        0 => { t.tap_text("发消息"); t.type_text("第一行") }
        1 => t.type_text("\n第二行，把输入框展开\n第三行，列表跟着留出空间")
        2 => { t.key(@ui.key_code_select_all); t.backspace() }
        _ => t.keyboard_gone()
      }
      Send => match step {
        0 => tap_send(t)
        1 => tree.event(t.time(), fn() { fix_clock_set(clock, fix_deliver_ms) })
        2 => tree.event(t.time(), fn() { fix_clock_set(clock, fix_deliver_ms + fix_answer_ms) })
        _ => tree.event(t.time(), fn() { fix_clock_set(clock, fix_deliver_ms + fix_answer_ms + @sffixture.fix_turn_end_ms) })
      }
      Quote => match step {
        0 => tree.event(t.time(), fn() {
          @sfbase.writing_quote(src, @sfbase.writing(src, "ws1/st1:s-c1"), { "author": "Claude", "text": "引用的内容在发送前后保持同一排法", "ts": "ts8" })
        })
        1 => tap_send(t)
        2 => tree.event(t.time(), fn() { fix_clock_set(clock, fix_deliver_ms) })
        _ => ()
      }
      Arrive => tree.event(t.time(), fn() {
        if step < 2 { messages.push(said(31 + step, "新消息 \{step + 1}")) }
        else if step == 2 { messages[messages.length() - 1] = said(32, "新消息已经更新") }
        version.set(version.get() + 1)
      })
      Read => match step {
        0 => t.wheel(width / 2.0, 400.0, -260.0)
        1 => tree.event(t.time(), fn() { messages.push(said(31, "阅读时到达的新消息")); version.set(2) })
        2 => { t.click(Button, label=@sf.t("web-main.chat.toLatest")) }
        _ => ()
      }
      Switch => tree.event(t.time(), fn() {
        match step {
          0 => open_chat({ station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Willow" })
          1 => open_chat(r)
          2 => open_chat({ station: "ws1/st1", session: "s-c3", title: "夜里的构建又失败了", station_name: "Willow" })
          _ => open_chat(r)
        }
      })
    }
  }
  while f < frames.length() && frames[f] < at {
    t.frame_at(start + frames[f])
    f += 1
  }
  t.frame_at(start + at)
  println("MOMENT shown")
  if at == 900.0 {
    match kind {
      Arrive => assert_true(t.find("新消息已经更新") is Some(_), msg="the updated message is drawn")
      Read => assert_true(t.find("阅读时到达的新消息") is Some(_), msg="jump to latest shows the new message")
      Send | Quote => assert_true(t.find("把这次检查的结果记下来") is Some(_), msg="the sent words stay visible")
      Switch => assert_true(app.nav.top() is Chat({ session: "s-c1", .. }), msg="the last chat opened owns the page")
      Edit => ()
    }
  }
  let picture = t.drawn_text()
  fix_clock.val = None
  picture
}

///|
fn chat_moments_same(kind : ChatMoment) -> Unit raise {
  for width in [390.0, 740.0, 1280.0] {
    for platform in [0, 2] {
      for at in [70.0, 270.0, 900.0] {
        let expected = chat_at_moment(kind, width, platform, 0, at)
        for mode in [1, 2, 3, 4] {
          let actual = chat_at_moment(kind, width, platform, mode, at)
          assert_true(actual == expected, msg="\{kind}, width \{width}, input \{platform}, at \{at}, frames \{mode}: \{chat_picture_difference(expected, actual)}")
        }
      }
    }
  }
}

///|
test "chat: editing and folding the composer has the same whole picture at each moment whatever frames came between" { chat_moments_same(Edit) }

///|
test "chat: a send, delivery and answer have the same whole picture at each moment whatever frames came between" { chat_moments_same(Send) }

///|
test "chat: a quote added and sent has the same whole picture at each moment whatever frames came between" { chat_moments_same(Quote) }

///|
test "chat: messages arriving and changing have the same whole picture at each moment whatever frames came between" { chat_moments_same(Arrive) }

///|
test "chat: reading away from the end and returning to news has the same whole picture at each moment whatever frames came between" { chat_moments_same(Read) }

///|
test "chat: switching chats during their transitions has the same whole picture at each moment whatever frames came between" { chat_moments_same(Switch) }

///|
test "chat moment diagnosis" { chat_at_moment(Edit, 390.0, 2, 4, 270.0) |> ignore }

///|
test "a chat in its own panel keeps its header room while the composer opens and closes" {
  chat_at_moment(Edit, 740.0, 0, 0, 270.0) |> ignore
}
