// Back on the wide frame, a node of the window's tree (sfdesk's wide_takes_back): off the tape (Large) the entry before in
// the history or a page popped, what is over the whole window put away, what is shown over it first; the history's entries
// made at their causes; whether the app takes back told the host as it changes; each at its event's moment, frames or
// none.

///|
/// How far apart the events of these come.
let wide_step_ms : Double = 16.0

///|
let chat_a : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }

///|
let chat_b : ChatRef = { station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Studio" }

///|
let chat_c : ChatRef = { station: "ws1/st1", session: "s-c3", title: "", station_name: "Studio" }

///|
/// The source of the last made (wide_backs).
let wide_src : Ref[Source?] = Ref(None)

///|
/// 大屏 (a finger's, 1280 wide), chat A in view, its clock from `t0` on: `to(at)` takes it to `t0 + at`, frames every
/// 16 ms on the way (`framed`) or none.
fn wide_backs(framed : Bool) -> (@ui.Tester, Double, (Double) -> Unit) {
  new_run()
  let src = fixture("chat")
  wide_src.val = Some(src)
  open_chat(chat_a)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=840.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let t0 = t.time() + between_frames_ms
  let to = fn(at : Double) {
    if framed {
      while t.time() + 16.0 < t0 + at {
        t.frame_at(t.time() + 16.0)
      }
    }
    t.advance(t0 + at - t.time())
  }
  (t, t0, to)
}

///|
/// The session of the chat on top (another page: its name).
fn top_session() -> String {
  match app.nav.top() {
    Chat(r) => r.session
    _ => "other"
  }
}

///|
/// 大屏, chat B opened over A (a person's act: an entry of the history), then back with no gesture at once; frames all
/// along (`framed`) or none: the chat on top and whether the host was told the app takes back as B came, the chat on top
/// just after back, before a frame.
fn wide_history_back(framed : Bool) -> (String, Bool, String) {
  let (t, t0, to) = wide_backs(framed)
  to(0.0)
  open_chat(chat_b)
  let came = (top_session(), t.takes_back())
  to(wide_step_ms * 3.0)
  t.back_raw(2, 0.0, t0 + wide_step_ms * 3.0)
  (came.0, came.1, top_session())
}

///|
test "大屏: another chat opened, then back at once, before a frame: the chat before it, as the history has it, as with frames all along" {
  let along = wide_history_back(true)
  assert_eq(wide_history_back(false), along)
  assert_eq(along, ("s-c2", true, "s-c1"))
}

///|
/// 大屏, A then B opened, the system's back gesture begun (its entry: A's) and, as it goes, C opened; gone through
/// (`through`) or called off; frames all along or none: the chat on top as it ends, before a frame.
fn wide_history_gesture(framed : Bool, through : Bool) -> String {
  let (t, t0, to) = wide_backs(framed)
  to(0.0)
  open_chat(chat_b)
  gesture(t, t0, to, wide_step_ms * 3.0, end=if through { 2 } else { 3 }, between=fn() { open_chat(chat_c) }) |> ignore
  top_session()
}

///|
test "大屏: back's entry chosen as its gesture begins: another chat opened as it goes, gone through, the one it began from (A); called off, the one opened stays; frames or none" {
  for framed in [false, true] {
    assert_eq(wide_history_gesture(framed, true), "s-c1", msg="framed \{framed}")
    assert_eq(wide_history_gesture(framed, false), "s-c3", msg="framed \{framed}")
  }
}

///|
/// 大屏, A, then B and C opened one after another (two acts), frames all along or none: the tops of the history's entries
/// (before, now), and the chat on top after back twice with no frame between.
fn wide_entries(framed : Bool) -> ((Array[String], String), String) {
  let (t, t0, to) = wide_backs(framed)
  to(0.0)
  open_chat(chat_b)
  to(wide_step_ms * 3.0)
  open_chat(chat_c)
  let name = fn(p : Page) {
    match p {
      Chat(r) => r.session
      _ => "other"
    }
  }
  let (before, now) = @sfbase.history_tops()
  let entries = (before.map(name), now.map(name).unwrap_or(""))
  to(wide_step_ms * 6.0)
  t.back_raw(2, 0.0, t0 + wide_step_ms * 6.0)
  t.back_raw(2, 0.0, t0 + wide_step_ms * 6.0)
  (entries, top_session())
}

///|
test "大屏: two chats opened one after the other with no frame between: an entry each, as with frames; back twice, the first" {
  let along = wide_entries(true)
  assert_eq(wide_entries(false), along)
  assert_eq(along.0.1, "s-c3")
  assert_eq(along.0.0[along.0.0.length() - 2:].to_array(), ["s-c1", "s-c2"])
  assert_eq(along.1, "s-c1")
}

///|
/// 中屏 on the tape (a finger's, the page in use), a station's screen opened over the whole window, then back with no
/// gesture at once; frames all along (`framed`) or none: whether the app takes back as it is opened, before a frame,
/// what is on top after back, the panel in use.
fn screen_closed(framed : Bool) -> (Bool, Bool, @sfdesk.TapePane) {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  page_over(t, 690.0)
  let t0 = t.time() + between_frames_ms
  if framed {
    t.frame_at(t0)
  } else {
    t.advance(t0 - t.time())
  }
  @sfbase.open_page(Screen({ station: "ws1/st1", screen: "desktop", title: "Studio 的桌面", until_gone: false }))
  let taken = t.takes_back()
  if framed {
    t.frame_at(t0 + wide_step_ms)
    t.frame_at(t0 + wide_step_ms * 2.0)
  } else {
    t.advance(t0 + wide_step_ms * 3.0 - t.time())
  }
  t.back_raw(2, 0.0, t.time())
  (taken, app.nav.top() is Screen(_), @sfdesk.wide.tape_at.get())
}

///|
test "中屏: a station's screen over the whole window and back at once, before a frame: the screen put away, the page still in use, as with frames" {
  assert_eq(screen_closed(false), screen_closed(true))
  assert_eq(screen_closed(false), (true, false, @sfdesk.TapePane::Page))
}

///|
test "大屏: a question shown over the frame takes back first: closed, the chat opened still on top; back again, the history's" {
  let (t, _, _) = wide_backs(true)
  open_chat(chat_b)
  t.run_for(@ui.move_most_ms)
  @sf.confirm("删除", "删除这个对话？", "删除", fn() {  })
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenting())
  assert_eq(top_session(), "s-c2")
  t.back()
  assert_eq(top_session(), "s-c1")
}

///|
test "大屏: a chat's menu shown in the sidebar takes back first: closed, the chat opened still on top; back again, the history's" {
  let (t, _, _) = wide_backs(true)
  open_chat(chat_b)
  t.run_for(@ui.move_most_ms)
  let (x, y, _, h) = t.rect_of("整理发布清单").unwrap()
  t.right_click(x + 4.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting(), msg="its menu")
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenting())
  assert_eq(top_session(), "s-c2")
  t.back()
  assert_eq(top_session(), "s-c1")
}

///|
test "中屏: the settings' sidebar opened from the chats' (back the system's there): back the app's at once; back to the chats', the system's at once; no frame between" {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_false(t.takes_back())
  @sfdesk.open_settings()
  assert_eq((@sfdesk.lit_place(), t.takes_back()), ("settings", true))
  @sfbase.go_place("chats") |> ignore
  assert_eq((@sfdesk.lit_place(), t.takes_back()), ("chats", false))
}

///|
/// The tops of the history's entries, by chat (another page: its name): before the one now, the one now.
fn entries_now() -> (Array[String], String) {
  let name = fn(p : Page) {
    match p {
      Chat(r) => r.session
      Settings | Setting(_) => "settings"
      _ => "other"
    }
  }
  let (before, now) = @sfbase.history_tops()
  (before.map(name), now.map(name).unwrap_or(""))
}

///|
/// 大屏, A then B opened, back by `how` (0: the shell's back, go_back, called as a page's bar calls it; 1: the stack's
/// own, back_pop; 2: the system's back, an event of the tree's), then forward (go_forward): the chat on top after back
/// and after forward, and the entries then, no frame between.
fn back_forward(how : Int) -> (String, String, (Array[String], String)) {
  let (t, t0, _) = wide_backs(false)
  open_chat(chat_b)
  match how {
    0 => @sfbase.go_back() |> ignore
    1 => @sfbase.back_pop()
    _ => t.back_raw(2, 0.0, t0)
  }
  let back = top_session()
  @sfbase.go_forward(wide_src.val.unwrap()) |> ignore
  (back, top_session(), entries_now())
}

///|
test "大屏: back then forward, no frame between, by the shell's back, the stack's own, the system's: forward to the chat back left" {
  let by_event = back_forward(2)
  assert_eq(by_event.1, "s-c2", msg="\{by_event}")
  for how in [0, 1] {
    let got = back_forward(how)
    assert_eq(got.1, "s-c2", msg="how \{how}: \{got}")
  }
  assert_eq(back_forward(0), by_event)
}

///|
test "大屏: the settings opened from a chat (another place, its pages), back and forward, no frame between: the entries and the page on top each way" {
  let (_, _, _) = wide_backs(false)
  let at_first = entries_now()
  @sfdesk.open_settings()
  let opened = entries_now()
  assert_eq(opened, ([..at_first.0, "s-c1"], "settings"))
  @sfbase.go_back() |> ignore
  assert_eq((entries_now(), top_session()), (at_first, "s-c1"))
  @sfbase.go_forward(wide_src.val.unwrap()) |> ignore
  assert_eq(entries_now(), opened)
  assert_true(@sfdesk.lit_place() == "settings")
}

///|
test "大屏: the chat on top opened again: no entry for it; another opened then, one entry, the chat before it" {
  let (_, _, _) = wide_backs(false)
  open_chat(chat_b)
  let was = entries_now()
  open_chat(chat_b)
  assert_eq(entries_now(), was)
  open_chat(chat_c)
  assert_eq(entries_now(), ([..was.0, "s-c2"], "s-c3"))
}

///|
/// 中屏 on the tape (a finger's), the page in use, chat B opened over it (the page's own stack: Nav::push_over), then
/// back by the stack's own (back_pop, as the shell calls it, no event of the tree's around it) and forward, no frame
/// between: the chat on top after back, after forward, and the entries then.
fn tape_back_forward() -> (String, String, (Array[String], String)) raise {
  new_run()
  let src = fixture("chat")
  open_chat(chat_a)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=690.0, h=840.0, platform=2)
  say_room(t, "medium", "medium")
  t.run_for(@ui.move_most_ms)
  page_over(t, 690.0)
  open_chat(chat_b)
  assert_eq(app.nav.depth(), 3)
  @sfbase.back_pop()
  let back = top_session()
  @sfbase.go_forward(src) |> ignore
  (back, top_session(), entries_now())
}

///|
test "中屏: a chat opened over the page, the stack's own back then forward, no frame between: back to the one under it, forward to it again" {
  let got = tape_back_forward()
  assert_eq((got.0, got.1), ("s-c1", "s-c2"), msg="\{got}")
}

///|
/// 大屏, from chat A (workspace ws1), a chat opened from outside (a notification, a link: open_item) in workspace
/// `ws` at `station`/`session`, a chat opened over A first (`over`); then back (the system's) and forward (go_forward),
/// frames all along (`framed`) or none: the entries added by it, and after it, after back and after forward, the
/// workspace picked and the chat on top.
fn item_back_forward(framed : Bool, ws : String, station : String, session : String, over~ : Bool = false) -> (
  Int,
  Array[(String, String)],
) {
  let (t, t0, to) = wide_backs(framed)
  if over {
    @sfbase.open_page_over(Chat(chat_c))
  }
  to(wide_step_ms)
  let before = entries_now().0.length()
  @sfbase.open_item(wide_src.val.unwrap(), ws, station, session, None, None)
  let added = entries_now().0.length() - before
  let seen = [(app.picked.get(), top_session())]
  to(wide_step_ms * 3.0)
  t.back_raw(2, 0.0, t0 + wide_step_ms * 3.0)
  seen.push((app.picked.get(), top_session()))
  to(wide_step_ms * 5.0)
  @sfbase.go_forward(wide_src.val.unwrap()) |> ignore
  seen.push((app.picked.get(), top_session()))
  (added, seen)
}

///|
test "大屏: a chat of another workspace opened from outside, no frame between it, back and forward: one entry, back to A in its workspace, forward to it in its, as with frames" {
  let along = item_back_forward(true, "ws2", "ws2/st9", "s-x")
  assert_eq(item_back_forward(false, "ws2", "ws2/st9", "s-x"), along)
  assert_eq(along, (1, [("ws2", "s-x"), ("ws1", "s-c1"), ("ws2", "s-x")]))
}

///|
test "大屏: a chat of the same workspace opened from outside over a chat opened over another, no frame between: one entry, back to the one over, forward to it, as with frames" {
  let along = item_back_forward(true, "ws1", "ws1/st1", "s-c2", over=true)
  assert_eq(item_back_forward(false, "ws1", "ws1/st1", "s-c2", over=true), along)
  assert_eq(along.0, 1)
  assert_eq(along.1.map(fn(s) { s.1 }), ["s-c2", "s-c3", "s-c2"])
}

///|
/// 大屏, from chat A in ws1, the second workspace picked (pick_workspace: the page on top as it was), inside an event of
/// the window's tree (`in_event`: as what a node's press does is) or not; then back and forward, no frame between: the
/// entries added, and the workspace picked after it, after back, after forward.
fn picked_back_forward(in_event : Bool) -> (Int, Array[String]) {
  let (t, t0, _) = wide_backs(false)
  let before = entries_now().0.length()
  let pick = fn() { @sfbase.pick_workspace(wide_src.val.unwrap(), "ws2") }
  if in_event {
    @ui.view_tree().unwrap().event(t0, pick)
  } else {
    pick()
  }
  let added = entries_now().0.length() - before
  let seen = [app.picked.get()]
  t.back_raw(2, 0.0, t0)
  seen.push(app.picked.get())
  @sfbase.go_forward(wide_src.val.unwrap()) |> ignore
  seen.push(app.picked.get())
  (added, seen)
}

///|
test "大屏: another workspace picked, in an event of the tree's or not, no frame between it, back and forward: one entry, back to the first, forward to the second" {
  let alone = picked_back_forward(false)
  assert_eq(picked_back_forward(true), alone)
  assert_eq(alone, (1, ["ws2", "ws1", "ws2"]))
}
