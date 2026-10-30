// A chat switched to in the wide frame's pane (Nav::shows_when): it shows once the core has given its view, the chat
// before it staying till then, LOCAL_MS at most, as a page pushed on a phone slides in once it has what it shows; not
// its messages to come breathing for the frame or two the core's answer takes.

///|
test "desk: a chat switched to shows once its view has come, the chat before it staying till then; one whose view does not come shows after the most a page waits" {
  reset()
  let base = fixture("chat")
  // what is still asked is current at once; what is asked anew, while `slow`, not answered (the core's moment)
  let asked : Map[String, Bool] = {}
  let slow = Ref(false)
  let key = fn(name : String, params : Map[String, Json]) { name + " " + Json::object(params).stringify() }
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if slow.val && !asked.contains(key(name, params)) {
        return { value: None, error: None, version: 0 }
      }
      asked[key(name, params)] = true
      (base.topic)(name, params)
    },
    leave: fn(name, params) { asked.remove(key(name, params)) },
  }
  let chat = fn(session : String) -> ChatRef { { station: "ws1/st1", session, title: "", station_name: "Studio" } }
  let read = fn(session : String) { readings.contains("ws1/st1\u{1}" + session) }
  open_chat(chat("s-c1"))
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  assert_true(read("s-c1"))
  // switched to while its view is on its way: the chat before stays
  slow.val = true
  open_chat(chat("s-k1"))
  t.frame()
  assert_true(app.nav.top() == Chat(chat("s-k1")), msg="the stack has it")
  assert_true(read("s-c1") && !read("s-k1"), msg="the chat before stays")
  // its view come: it shows, the one before left
  slow.val = false
  t.frame()
  t.frame()
  assert_true(read("s-k1") && !read("s-c1"), msg="shown once its view came")
  // one whose view does not come: the one before stays the most a page waits, then it shows, waiting
  slow.val = true
  open_chat(chat("s-k2"))
  t.frame()
  t.run_for(page_local_ms / 2.0)
  assert_true(read("s-k1"), msg="still the one before")
  t.run_for(page_local_ms)
  assert_true(!read("s-k1") && !read("s-k2"), msg="shown, its messages to come breathing")
}
