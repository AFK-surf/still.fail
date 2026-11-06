// A chat read up to its top: the page before comes in above what is read, there at once, nothing in it coming or
// changing with a motion (it was said long ago: only brought now).

///|
/// Chat s-c1 as the core gives it from entry `first` on to 200: one of its messages said again and again by its author
/// (each after the first joined to the one before), more before it while `first` is past the first.
fn older_chat(base : Json, first : Int) -> Json {
  guard base is Object(chat) else { return base }
  let template = items(Some(base), "messages")
    .iter()
    .find_first(fn(m) { !flag(Some(m), "system") && !flag(Some(m), "mine") })
    .unwrap_or(Json::object({}))
  guard template is Object(t) else { return base }
  let messages : Array[Json] = []
  for n in first..=200 {
    let m = t.copy()
    m["seq"] = Json::number(n.to_double())
    m["ts"] = Json::string("older-\{n}")
    m["joined"] = Json::boolean(n > first)
    m.remove("said")
    messages.push(Json::object(m))
  }
  let changed = chat.copy()
  changed["messages"] = Json::array(messages)
  changed["more"] = Json::boolean(first > 1)
  changed["newer"] = Json::boolean(false)
  changed["firstEntry"] = Json::number(first.to_double())
  changed["lastEntry"] = Json::number(200.0)
  changed.remove("unreadLine")
  Json::object(changed)
}

///|
test "a chat read up to its top: the page before is there at once, nothing in it nor the row it joins moving" {
  new_run()
  let base = fixture("chat")
  let first = @signals.signal(171)
  let asked : Array[Int] = []
  let held : Array[() -> Unit] = []
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      guard name == "chat" && got.value is Some(v) else { return got }
      { ..got, value: Some(older_chat(v, first.get())), version: first.get() }
    },
    call: fn(name, params, done) {
      if name == "chat.older" {
        asked.push(first.get())
        held.push(fn() {
          first.set(first.get() - 30)
          done(Ok(Json::boolean(true)))
        })
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let rd = @sfbase.reading_of(r.station + "\u{1}" + r.session)
  // pulled down a little at a time until the page before is asked for
  for _ in 0..<300 {
    if asked.length() > 0 {
      break
    }
    t.drag(195.0, 200.0, 195.0, 700.0, steps=40)
  }
  assert_eq(asked, [171])
  t.run_for(@ui.move_most_ms)
  // the page comes in
  for h in held {
    h()
  }
  t.frame()
  t.frame()
  let moving = rd.rows.sized().by.keys().collect()
  assert_eq(moving, [], msg="rows coming or changing as the page before came in")
}

///|
test "the page before that does not come is offered again on its row, not asked for again each frame" {
  new_run()
  let base = fixture("chat")
  let first = @signals.signal(171)
  let asked : Array[Int] = []
  let fails = Ref::new(true)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      guard name == "chat" && got.value is Some(v) else { return got }
      { ..got, value: Some(older_chat(v, first.get())), version: first.get() }
    },
    call: fn(name, params, done) {
      if name == "chat.older" {
        asked.push(first.get())
        if fails.val {
          done(Err({ "code": "mesh", "message": "unreachable" }))
        } else {
          first.set(first.get() - 30)
          done(Ok(Json::boolean(true)))
        }
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  for _ in 0..<300 {
    if asked.length() > 0 {
      break
    }
    t.drag(195.0, 200.0, 195.0, 700.0, steps=40)
  }
  // on up to its top, and there a while: nothing more asked, the row offers it again
  for _ in 0..<10 {
    t.drag(195.0, 300.0, 195.0, 600.0, steps=20)
  }
  // (a few of the longest motions' lengths: frames enough for a retry each frame to have shown)
  for _ in 0..<5 {
    t.run_for(@ui.move_most_ms)
  }
  assert_eq(asked, [171])
  assert_true(t.find(@sf.t("common.retry")) is Some(_))
  fails.val = false
  t.tap_text(@sf.t("common.retry"))
  t.run_for(@ui.move_most_ms)
  assert_eq(asked.length() >= 2, true)
  assert_eq(asked[1], 171)
  assert_true(first.get() < 171)
}
