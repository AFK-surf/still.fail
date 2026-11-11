// A new chat with nothing to run it on yet (sfpages' new_chat.mbt new_first_station, new_none_up, new_blocked): no
// station, none up, a station with no profile here, none shared with the workspace, no model picked; each its words
// and its way on.

///|
/// The new chat over the `newchat-noprofile` fixture, the core's `newChat` view as `over` makes it.
fn blocked_new(over? : (Map[String, Json]) -> Unit = fn(_) {  }) -> @ui.Tester {
  new_run()
  let base = fixture("newchat-noprofile")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let tp = base.topic(name, params).get().snapshot()
      match tp.value {
        Some(Object(m)) if name == "newChat" => {
          let o = m.copy()
          over(o)
          { ..tp, value: Some(Json::object(o)) }
        }
        _ => tp
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_mode("newchat-noprofile")
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a new chat on a station with no profile here: 为 Willow 添加 Profile, and 添加 Profile opens a new profile's page for that station" {
  let t = blocked_new()
  assert_true(t.find("为 Willow 添加 Profile") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  t.click(Button, label="添加 Profile")
  t.draw()
  assert_true(app.nav.top() is Setting(@settings.Route::NewProfile("ws1/st1")))
}

///|
test "a new chat on a station none of whose profiles is shared with the workspace: says so with the core's words, nothing to add from here" {
  let t = blocked_new(over=fn(o) {
    o["blocked"] = Json::string("shared")
    o["problem"] = Json::string("请让 Willow 的所有者把 Profile 分享到星火工作室。")
  })
  assert_true(t.find("Willow 尚无可用于此 workspace 的 Profile") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  assert_true(t.find("请让 Willow 的所有者把 Profile 分享到星火工作室。") is Some(_))
  assert_true(t.find("添加 Profile") is None)
  assert_true(t.find("查看 Profile") is None)
}

///|
test "a new chat on a station whose profiles have no model picked: 查看 Profile 的模型, and 查看 Profile opens that station's profiles" {
  let t = blocked_new(over=fn(o) { o["blocked"] = Json::string("models") })
  assert_true(t.find("查看 Profile 的模型") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  t.click(Button, label="查看 Profile")
  t.draw()
  assert_true(app.nav.top() is Setting(@settings.Route::Profiles("ws1/st1")))
}

///|
test "a new chat in a workspace with no station at all: the first to add" {
  let t = blocked_new(over=fn(o) {
    o["stations"] = Json::array([])
    o.remove("station") |> ignore
    o["any"] = Json::boolean(false)
  })
  assert_true(t.find("添加第一台 station") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
}

///|
test "a new chat in a workspace whose stations are all away: 没有在线的 station" {
  let t = blocked_new(over=fn(o) {
    o.remove("station") |> ignore
    o["any"] = Json::boolean(true)
  })
  assert_true(t.find("没有在线的 station") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  assert_true(t.find("添加第一台 station") is None)
}
