// The previous and next chat follow the list in view, including an order held while its core view changes.

///|
test "chat neighbours: a list held under the pointer is traversed in its displayed order" {
  new_run()
  let clock = Ref::new(0.0)
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("home-motion")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.tap_text("给设置页加一个深色模式开关")
  let (x, y) = t.find("给设置页加一个深色模式开关").unwrap()
  t.move(x, y)
  t.frame()
  // The core moves CI to the top, while the list keeps it below the current row under the pointer.
  clock.val = 2001.0
  t.frame()
  assert_true(t.find("给设置页加一个深色模式开关").unwrap().1 < t.find("盯着 CI，绿了告诉我").unwrap().1)
  @settings.ask_action("chat.next")
  t.frame()
  assert_eq(open_title(), "盯着 CI，绿了告诉我")
  t.key(@ui.key_code_up, mods=@ui.mod_alt)
  assert_eq(open_title(), "给设置页加一个深色模式开关")
  fix_clock.val = None
}

///|
/// One field changed on a fixture value.
fn neighbour_field(value : Json, key : String, field : Json) -> Json {
  match value {
    Object(m) => {
      let copy = m.copy()
      copy[key] = field
      Json::object(copy)
    }
    _ => value
  }
}

///|
test "chat neighbours: a newly made chat still matches the client key its page opened with" {
  new_run()
  let base = fixture("home")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      match (name, got.value) {
        ("chats", Some(v)) => {
          let days = items(Some(v), "days").map(fn(day) {
            let rows = items(Some(day), "items").map(fn(row) {
              if text(Some(row), "id") == "c2" {
                neighbour_field(row, "clientKey", Json::string("new:chat-1"))
              } else {
                row
              }
            })
            neighbour_field(day, "items", Json::array(rows))
          })
          { ..got, value: Some(neighbour_field(v, "days", Json::array(days))) }
        }
        _ => got
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_chat({ station: "ws1/st1", session: "new:chat-1", title: "首页的列表改成按天分组", station_name: "Studio" })
  t.frame()
  t.key(@ui.key_code_down, mods=@ui.mod_alt)
  assert_eq(open_title(), "夜里的构建又失败了")
  t.key(@ui.key_code_up, mods=@ui.mod_alt)
  assert_eq(open_title(), "首页的列表改成按天分组")
}

///|
test "chat neighbours: with no current row or no neighbour, the page stays where it is" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  assert_true(app.nav.top() == NewChat)
  t.key(@ui.key_code_down, mods=@ui.mod_alt)
  assert_true(app.nav.top() == NewChat)
  open_chat({ station: "ws1/st1", session: "not-in-the-list", title: "未列出的对话", station_name: "Studio" })
  t.frame()
  t.key(@ui.key_code_down, mods=@ui.mod_alt)
  assert_eq(open_title(), "未列出的对话")
  t.key(@ui.key_code_up, mods=@ui.mod_alt)
  assert_eq(open_title(), "未列出的对话")
  t.tap_text("整理发布清单")
  t.key(@ui.key_code_up, mods=@ui.mod_alt)
  assert_eq(open_title(), "整理发布清单")
}
