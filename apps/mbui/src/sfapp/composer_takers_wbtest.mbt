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

///|
/// Chat s-c1 open `w` wide (`platform` 0 a desk's: switching chats makes the other's composer anew; 2 a phone's: the
/// first kept under the second in the stack).
fn takers_tester(w : Double, platform : Int) -> @ui.Tester {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a file picked for one chat, another opened before the picker answers: never in the other's draft; in its own once, back on it" {
  for at in [(1280.0, 0), (390.0, 2)] {
    let (width, platform) = at
    let t = takers_tester(width, platform)
    let a = @sfbase.writings.get("ws1/st1:s-c1").unwrap()
    let a_before = a.files.get().length()
    t.picks([("a.png", b"\x89PNG\r\n\x1a\n")])
    @sfpages.pick_files(a)
    open_chat({ station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Willow" })
    t.run_for(@ui.move_most_ms * 2.0)
    let b_files = @sfbase.writings.get("ws1/st1:s-c2").map(fn(w) { w.files.get().length() }).unwrap_or(0)
    assert_eq(b_files, 0, msg="\{width}: none of it in the other chat's draft")
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    t.run_for(@ui.move_most_ms * 2.0)
    assert_eq(a.files.get().length(), a_before + 1, msg="\{width}: in its own draft, once")
    t.run_for(@ui.move_most_ms)
    assert_eq(a.files.get().length(), a_before + 1, msg="\{width}: not again")
  }
}

///|
test "a file picked for a chat, the picker answering as the frame begins and the chat left for another as that frame begins too, after: in its own draft once, never in the other's" {
  for at in [(1280.0, 0), (390.0, 2)] {
    let (width, platform) = at
    new_run()
    let src = fixture("chat")
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    let root : Ref[@view.View?] = Ref(None)
    let t = @ui.Tester::new(
      fn(c) { view(c, src) },
      tree=fn(v) {
        app_tree(src)(v)
        root.val = Some(v)
      },
      w=width,
      h=844.0,
      platform~,
    )
    t.run_for(@ui.move_most_ms)
    let a = @sfbase.writings.get("ws1/st1:s-c1").unwrap()
    let a_before = a.files.get().length()
    // (what the host has once, held after the composer's: said as the same frame begins, after the picker's answer is
    // taken, another chat opened at that moment, as what the host hands on does: nothing written as it is handed on)
    let armed = Ref(false)
    let r = root.val.unwrap()
    @ui.on_host_said(r, kind="test-another", fn() { if armed.val { Some(()) } else { None } }, fn(_) {
      armed.val = false
      r.at_moment(r.cause_at(), fn() {
        open_chat({ station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Willow" })
      })
      |> ignore
    })
    t.picks([("a.png", b"\x89PNG\r\n\x1a\n")])
    @sfpages.pick_files(a)
    armed.val = true
    t.frame()
    assert_eq(a.files.get().length(), a_before + 1, msg="\{width}: in its own draft, by the frame it was answered")
    assert_true(!@sfbase.shared_into.contains("ws1/st1:s-c1"), msg="\{width}: nothing left waiting")
    t.run_for(@ui.move_most_ms * 2.0)
    let b_files = @sfbase.writings.get("ws1/st1:s-c2").map(fn(w) { w.files.get().length() }).unwrap_or(0)
    assert_eq(b_files, 0, msg="\{width}: none of it in the other chat's draft")
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    t.run_for(@ui.move_most_ms * 2.0)
    assert_eq(a.files.get().length(), a_before + 1, msg="\{width}: once, back on it")
  }
}

///|
test "a file quoted and a file shared into a chat while its station is offline: left for its composer, taken once as the station is back, the same composer" {
  let calls : Array[Made] = []
  let off = @signals.signal(true)
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" || !off.get() {
      return tp
    }
    match tp.value {
      Some(Object(o)) => {
        let o2 = o.copy()
        o2["offline"] = Json::boolean(true)
        { ..tp, value: Some(Json::object(o2)) }
      }
      _ => tp
    }
  })
  let draft = "ws1/st1:s-c1"
  let w = @sfbase.writings.get(draft).unwrap()
  let quotes = w.quotes.get().length()
  let adds = fn() { named(calls, "composer.add").length() }
  let adds_before = adds()
  @sfbase.quote_file_into(draft, "林", "1.0", "user", Json::object({ "name": Json::string("plan.md"), "size": Json::number(1200.0) }))
  @sfbase.shared_into[draft] = [{ name: "a.png", bytes: b"\x89PNG\r\n\x1a\n", held: 0, size: 8.0, src: "" }]
  @sfbase.draft_given_to(draft)
  t.run_for(@ui.move_most_ms)
  assert_eq(w.quotes.get().length(), quotes, msg="no quote put in while offline")
  assert_eq(adds(), adds_before, msg="no file put in while offline")
  assert_true(@sfbase.quoted_into.contains(draft) && @sfbase.shared_into.contains(draft), msg="both left for the composer")
  off.set(false)
  t.run_for(@ui.move_most_ms)
  assert_eq(w.quotes.get().length(), quotes + 1, msg="the quote in the draft once the station is back")
  assert_eq(adds(), adds_before + 1, msg="the file put in once the station is back")
  assert_true(!@sfbase.quoted_into.contains(draft) && !@sfbase.shared_into.contains(draft), msg="nothing left waiting")
  t.run_for(@ui.move_most_ms)
  assert_eq(w.quotes.get().length(), quotes + 1, msg="not again")
  assert_eq(adds(), adds_before + 1, msg="not again")
}
