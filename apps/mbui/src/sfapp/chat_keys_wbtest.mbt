// The open chat's own keys on 大屏 (sfdesk's chat_page.mbt chat_keys, keymap.ts): ⌘. its agents at work stopped, ⌘⇧H
// its first agent's history beside it and away again, ⌘⇧E into the archive, Space the composer; what it cannot do then
// passes the key on.

///|
/// The fixture's chat on 大屏 with a Mac's keys, its calls kept in `calls` and answered; its agents' `status` as given.
fn keyed_chat(
  calls : Array[Made],
  status? : String = "idle",
  mode? : String = "chat",
  watch? : String = "",
  newer? : Bool = false,
  h? : Double = 800.0,
) -> @ui.Tester {
  new_run()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      if name.has_prefix("composer.") {
        (base.call)(name, params, done)
      } else {
        done(Ok(Json::object({})))
      }
    },
    topic_read: fn(name, params) {
      let tp = base.topic(name, params).get().snapshot()
      match tp.value {
        Some(Object(m)) if name == "chat" && newer => {
          let o = m.copy()
          o["newer"] = Json::boolean(true)
          { ..tp, value: Some(Json::object(o)) }
        }
        Some(Object(m)) if name == "chat" && watch != "" => {
          let o = m.copy()
          o["watch"] = { "ask": Json::string(watch) }
          { ..tp, value: Some(Json::object(o)) }
        }
        Some(Object(m)) if name == "chat" && status != "idle" => {
          let o = m.copy()
          o["agents"] = Json::array(
            items(Some(Json::object(m)), "agents").map(fn(a) {
              match a {
                Object(am) => {
                  let w = am.copy()
                  w["status"] = Json::string(status)
                  Json::object(w)
                }
                _ => a
              }
            }),
          )
          { ..tp, value: Some(Json::object(o)) }
        }
        _ => tp
      }
    },
  }
  decide_src.val = Some(src)
  open_fixture_over(mode, src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h~, platform=0)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "⌘. stops each of the chat's agents at work (session.stop by its key), an agent at rest asked nothing" {
  for status in ["running", "queued"] {
    let calls : Array[Made] = []
    let t = keyed_chat(calls, status~)
    t.key(@ui.key_of_char('.'), mods=@ui.mod_cmd)
    t.draw()
    let made = named(calls, "session.stop")
    assert_eq(made.length(), 1, msg=status)
    assert_eq(text(Some(made[0].params), "station"), "ws1/st1")
    assert_eq(text(Some(made[0].params), "key"), "s-c1")
  }
  let calls : Array[Made] = []
  let t = keyed_chat(calls)
  t.key(@ui.key_of_char('.'), mods=@ui.mod_cmd)
  t.draw()
  assert_eq(named(calls, "session.stop").length(), 0)
}

///|
test "⌘⇧H opens the chat's first agent's history beside it; again, with it in front, closes the panel" {
  let calls : Array[Made] = []
  let t = keyed_chat(calls)
  t.key(@ui.key_of_char('h'), mods=@ui.mod_cmd | @ui.mod_shift_key)
  t.draw()
  let opened = named(calls, "chat.tabs.open")
  assert_eq(opened.length(), 1)
  assert_eq(text(Some(opened[0].params), "tab"), "s-c1")
  // (its history in front, as the core keeps the panel: the fixture's chat-history-side)
  let calls : Array[Made] = []
  let t = keyed_chat(calls, mode="chat-history-side")
  t.key(@ui.key_of_char('h'), mods=@ui.mod_cmd | @ui.mod_shift_key)
  t.draw()
  assert_eq(named(calls, "chat.tabs.clear").length(), 1)
  assert_eq(named(calls, "chat.tabs.open").length(), 0)
}

///|
test "⌘⇧E puts the chat in the archive (chat.archive), says so by its title with 撤销, and the page goes on to another chat" {
  let calls : Array[Made] = []
  let t = keyed_chat(calls)
  t.key(@ui.key_of_char('e'), mods=@ui.mod_cmd | @ui.mod_shift_key)
  t.draw()
  let made = named(calls, "chat.archive")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "session"), "s-c1")
  assert_true(field(Some(made[0].params), "archived") is Some(True))
  t.run_for(@ui.move_most_ms)
  assert_eq(app.toast.get().words, "已归档「整理发布清单」")
  // (no longer the chat in front: on to its neighbour in the list, or the list)
  assert_true(
    match app.nav.top() {
      Chat(r) => r.session != "s-c1"
      _ => true
    },
  )
}

///|
test "Space with no field focused: the chat's composer says 按空格输入, and Space puts the cursor in it" {
  let calls : Array[Made] = []
  let t = keyed_chat(calls)
  let focused = fn() { t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none") }
  t.ctx().blur()
  t.run_for(film_step_ms)
  assert_true(t.find("按空格输入") is Some(_), msg="before: \{focused()}")
  t.key(@ui.key_space)
  t.run_for(film_step_ms)
  assert_eq(focused(), "TextField 发消息")
  assert_true(t.find("按空格输入") is None)
}

///|
test "⌘⇧E on a chat keeping watch asks first, in the core's words: 取消 keeps it, 归档 puts it in the archive" {
  let watch = "这个对话还在盯着 CI，归档后就不再盯了。"
  let calls : Array[Made] = []
  let t = keyed_chat(calls, watch~)
  t.key(@ui.key_of_char('e'), mods=@ui.mod_cmd | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("归档「整理发布清单」？") is Some(_))
  assert_true(t.find(watch) is Some(_))
  assert_eq(named(calls, "chat.archive").length(), 0)
  t.tap_text("取消")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("归档「整理发布清单」？") is None)
  assert_eq(named(calls, "chat.archive").length(), 0)
  // asked again, and confirmed
  t.key(@ui.key_of_char('e'), mods=@ui.mod_cmd | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  guard t.query(Button, label="归档") is Some(b) else { fail("no 归档 in the dialog") }
  let (bx, by, bw, bh) = b.rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 1)
  assert_eq(app.toast.get().words, "已归档「整理发布清单」")
}

///|
test "⌘⇧E on a chat already in the archive asks the core nothing" {
  let calls : Array[Made] = []
  let t = keyed_chat(calls, mode="chat-archived")
  t.key(@ui.key_of_char('e'), mods=@ui.mod_cmd | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 0)
}

///|
test "Escape in a chat with its side panel open closes all of its tabs (chat.tabs.clear)" {
  let calls : Array[Made] = []
  let t = keyed_chat(calls, mode="chat-history-side")
  t.key(@ui.key_escape)
  t.draw()
  assert_eq(named(calls, "chat.tabs.clear").length(), 1)
}

///|
test "Escape with ⌘F's bar open closes that bar and nothing else (no panel asked to close)" {
  let calls : Array[Made] = []
  let t = keyed_chat(calls, mode="chat-find")
  assert_true(@sfpages.find_chat() != "")
  t.key(@ui.key_escape)
  t.draw()
  assert_eq(@sfpages.find_chat(), "")
  assert_eq(named(calls, "chat.tabs.clear").length(), 0)
}

///|
test "⌘↓ in a chat short of its end asks the core for its latest page (chat.latest by its thread)" {
  let calls : Array[Made] = []
  let t = keyed_chat(calls, newer=true)
  t.key(@ui.key_code_down, mods=@ui.mod_cmd)
  t.draw()
  let made = named(calls, "chat.latest")
  assert_eq(made.length(), 1)
  assert_eq(number(Some(made[0].params), "thread"), 7.0)
}

///|
test "⌘↓ in a chat scrolled up from its end takes the list back to its end, asking the core nothing" {
  let calls : Array[Made] = []
  // (a window lower than the chat: it scrolls)
  let t = keyed_chat(calls, h=480.0)
  let last = "做完了：列表、跳到最新的按钮、加载更早的消息都好了，截图也换了。"
  t.move_to(640.0, 240.0)
  t.wheel(640.0, 240.0, -1200.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(last) is None, msg="still at the end")
  t.key(@ui.key_code_down, mods=@ui.mod_cmd)
  t.draw()
  // (back at its end by the list's own rest: a glide solved in time)
  let rest = t.rest_of("a list")
  assert_true(rest < @double.infinity, msg="no glide set off")
  if rest > t.time() {
    t.run_for(rest - t.time())
  }
  assert_true(t.find(last) is Some(_))
  assert_eq(named(calls, "chat.latest").length(), 0)
}
