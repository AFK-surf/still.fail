///|
test "changing the source for a chat on the same frame tree reads the new source's error" {
  new_run()
  let base = fixture("chat")
  let first : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "chat" {
        { value: None, error: Some(Json::string("first")), version: 1 }
      } else {
        (base.topic)(name, params)
      }
    },
  }
  let second : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "chat" {
        { value: None, error: Some(Json::string("second")), version: 1 }
      } else {
        (base.topic)(name, params)
      }
    },
  }
  let selected = @signals.signal(false)
  let error : Ref[Json?] = Ref(None)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  let t = @ui.Tester::new(fn(_) {
    let src = if selected.get() { second } else { first }
    error.val = view_of_chat(src, r).2
  })
  t.draw()
  assert_eq(error.val, Some(Json::string("first")))
  selected.set(true)
  t.draw()
  assert_eq(error.val, Some(Json::string("second")))
}

///|
test "a chat view still watched after the page leaves follows the topic's next change" {
  new_run()
  let base = fixture("chat")
  let changed = @signals.signal(0)
  let marked = Ref(0)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "chat" {
        let version = changed.get()
        { value: None, error: Some(Json::number(version.to_double())), version }
      } else {
        (base.topic)(name, params)
      }
    },
    leave: fn(_, _) {  },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  let watcher = @signals.watch(fn() { marked.val += 1 })
  let t = @ui.Tester::new(fn(_) { watcher.read(fn() { view_of_chat(src, r) |> ignore }) })
  t.draw()
  chat_left(src, r)
  marked.val = 0
  changed.set(1)
  assert_true(marked.val > 0, msg="another consumer still watching the chat must hear the change")
  watcher.stop()
}
