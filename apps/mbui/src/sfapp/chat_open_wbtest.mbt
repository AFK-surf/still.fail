// A chat opened from Home slides in once the core has given its view, however long the core takes to read what the
// device holds (page_local_ms at most): not as its messages' bones a moment before them. Only a chat the core says
// waits on a station (none of its messages here: Source.waits) slides in at once, its messages to come breathing.

///|
/// The changes of chat_open_tester's topics, said as the core client says a subscription's (Sub.changes): set by a
/// test as what it answers changes.
let open_changes : @signals.Signal[Int] = @signals.signal(0)

///|
/// What chat_open_tester's topics answer changed (`slow` turned off).
fn open_changed() -> Unit {
  open_changes.set(open_changes.get() + 1)
}

///|
/// Home over the fixture `chat`, laid out Small; once it shows, a topic asked anew while `slow` is not answered (the core
/// reading it), and the chat's `waits` what `waiting` says.
fn chat_open_tester(slow : Ref[Bool], waiting : Ref[Bool]) -> @ui.Tester {
  reset()
  let base = fixture("chat")
  let asked : Map[String, Bool] = {}
  let key = fn(name : String, params : Map[String, Json]) { name + " " + Json::object(params).stringify() }
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      open_changes.get() |> ignore
      if slow.val && !asked.contains(key(name, params)) {
        return { value: None, error: None, version: 0 }
      }
      asked[key(name, params)] = true
      (base.topic)(name, params)
    },
    waits: fn(name, _) {
      open_changes.get() |> ignore
      name == "chat" && waiting.val
    },
    leave: fn(name, params) { asked.remove(key(name, params)) },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(first_page_ms + @ui.move_most_ms)
  slow.val = true
  t
}

///|
/// Whether the chat's composer is on the screen (its page slid in).
fn composer_shown(t : @ui.Tester) -> Bool {
  match t.find("发消息") {
    Some((x, _)) => x > 0.0 && x < 390.0
    None => false
  }
}

///|
test "a chat whose view the core reads slower than LOCAL_MS slides in with its messages, never as their bones first" {
  let slow = Ref(false)
  let waiting = Ref(false)
  let t = chat_open_tester(slow, waiting)
  assert_true(!composer_shown(t), msg="Home")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.frame()
  // the core still reading it, three times LOCAL_MS: Home as it was, nothing slid in
  t.run_for(@sf.local_ms * 3.0)
  assert_true(!composer_shown(t), msg="still waiting for the core's answer")
  // its view come: it slides in with its messages
  slow.val = false
  open_changed()
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(composer_shown(t), msg="slid in")
  assert_true(t.find("做完了：列表、跳到最新的按钮") is Some(_), msg="with its messages")
}

///|
test "a chat the core says waits on a station slides in at once, its messages to come breathing" {
  let slow = Ref(false)
  let waiting = Ref(true)
  let t = chat_open_tester(slow, waiting)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.frame()
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(composer_shown(t), msg="slid in at once")
  assert_true(t.find("做完了：列表、跳到最新的按钮") is None, msg="none of its messages")
}

///|
test "a chat whose view does not come slides in once it has waited the most a page opening waits" {
  let slow = Ref(false)
  let waiting = Ref(false)
  let t = chat_open_tester(slow, waiting)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.frame()
  t.run_for(page_local_ms / 2.0)
  assert_true(!composer_shown(t), msg="still waiting")
  t.run_for(page_local_ms / 2.0 + @ui.move_most_ms)
  assert_true(composer_shown(t), msg="slid in, its messages to come breathing")
}
