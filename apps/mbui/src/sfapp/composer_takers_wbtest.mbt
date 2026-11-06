// What is put into a chat's draft from elsewhere taken by its composer of the window's tree as it is put there, by
// what puts it (sfbase's draft_given_to: a 文件 row sent to the chat, a file quoted into it), in that same event:
// no frame between, nothing left in a signal for an effect to take later.

///|
test "a 文件 row sent to an open chat: in its composer's draft as it is sent, no frame between" {
  let t = chat_tester("chat")
  let draft = "ws1/st1:s-c1"
  let w = @sfbase.writings.get(draft).unwrap()
  let before = w.files.get().length()
  let d : @sfbase.Dragged = {
    station: "ws1/st1",
    station_name: "Willow",
    root: "/srv",
    path: "notes/plan.md",
    abs: "/srv/notes/plan.md",
    name: "plan.md",
    size: 1200.0,
    dir: false,
  }
  @sfbase.files_into(draft, d)
  assert_eq(w.files.get().length(), before + 1, msg="in the draft as it is sent")
  assert_true(@sfbase.files_taken(draft).is_empty(), msg="nothing left waiting for the composer")
  t.frame()
  assert_eq(w.files.get().length(), before + 1, msg="once, not again as the frame after is built")
}

///|
test "a message's file quoted into an open chat: its quote in the composer's draft as it is quoted, no frame between" {
  let _ = chat_tester("chat")
  let draft = "ws1/st1:s-c1"
  let w = @sfbase.writings.get(draft).unwrap()
  let before = w.quotes.get().length()
  @sfbase.quote_file_into(draft, "林", "1.0", "user", Json::object({ "name": Json::string("plan.md"), "size": Json::number(1200.0) }))
  assert_eq(w.quotes.get().length(), before + 1, msg="its quote in the draft as it is quoted")
}

///|
/// A 文件 row as the files' tab carries it, named `name`.
fn row_dragged(name : String) -> @sfbase.Dragged {
  { station: "ws1/st1", station_name: "Willow", root: "/srv", path: "notes/" + name, abs: "/srv/notes/" + name, name, size: 1200.0, dir: false }
}

///|
test "put into a chat's draft before its composer is made: taken once as the composer comes, none again after" {
  new_run()
  let src = fixture("chat")
  let draft = "ws1/st1:s-c1"
  // (put there while no composer of the chat's is there: left for it)
  @sfbase.files_into(draft, row_dragged("early.md"))
  @sfbase.quote_file_into(draft, "林", "1.0", "user", Json::object({ "name": Json::string("early.md"), "size": Json::number(1.0) }))
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let w = @sfbase.writings.get(draft).unwrap()
  let named = fn() { w.files.get().filter(fn(f) { text(Some(f), "name") == "early.md" }).length() }
  assert_eq(named(), 1, msg="its file in the draft once the composer came")
  assert_eq(w.quotes.get().length(), 1, msg="its quote in the draft once")
  t.run_for(@ui.move_most_ms)
  assert_eq(named(), 1, msg="not again as frames go on")
  assert_eq(w.quotes.get().length(), 1)
}

///|
test "a 文件 row sent to a chat left for another: not in the other's draft; back on the first, in its draft once" {
  let t = chat_tester("chat")
  let first = "ws1/st1:s-c1"
  open_chat({ station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Willow" })
  t.run_for(@ui.move_most_ms * 2.0)
  let other = @sfbase.writings.get("ws1/st1:s-c2")
  let other_before = other.map(fn(w) { w.files.get().length() }).unwrap_or(0)
  @sfbase.files_into(first, row_dragged("late.md"))
  t.frame()
  assert_eq(other.map(fn(w) { w.files.get().length() }).unwrap_or(0), other_before, msg="not in the chat shown's draft")
  t.back()
  t.run_for(@ui.move_most_ms * 2.0)
  let w = @sfbase.writings.get(first).unwrap()
  assert_eq(w.files.get().filter(fn(f) { text(Some(f), "name") == "late.md" }).length(), 1, msg="in its own draft, once")
}
