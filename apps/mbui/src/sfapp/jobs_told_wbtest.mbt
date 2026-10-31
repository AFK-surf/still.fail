// The services and jobs left up long on 大屏 (sfdesk's lists.mbt: 运行中 at the lists' foot, a popover over it)
// dismissed by the hand: Escape, a press on the page: closed as that input is taken, at its moment, no frame after it;
// the frame after closing nothing more, opened again from its chip its own.

///|
/// 大屏, a mouse's, with what is left up long (the home-jobs fixture): the popover opened from 运行中, dismissed by
/// `how` (as the host hands it on, no frame after it): whether it is open then, once a frame is drawn, as its chip opens
/// it again and a frame after.
fn jobs_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] raise {
  let t = jobs_tester()
  t.host_says_finger(Some(false))
  t.draw()
  guard t.query(Button, label="长时间运行的服务和任务") is Some(s) else { fail("no chip") }
  let (bx, by, bw, bh) = s.rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  let seen = [@sfdesk.wide.jobs_open.get()]
  how(t)
  seen.push(@sfdesk.wide.jobs_open.get())
  t.draw()
  seen.push(@sfdesk.wide.jobs_open.get())
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  seen.push(@sfdesk.wide.jobs_open.get())
  t.draw()
  seen.push(@sfdesk.wide.jobs_open.get())
  seen
}

///|
test "大屏: what is left up long, its popover dismissed by Escape: closed as the key is taken; the frame after closes nothing more, opened again its own" {
  assert_eq(jobs_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false, true, true])
}

///|
test "大屏: what is left up long, its popover dismissed by a press on the page: closed as it goes down; the frame after closes nothing more, opened again its own" {
  let down : Array[Bool] = []
  let seen = jobs_dismissed(fn(t) {
    t.touch_at(0, 900.0, 300.0, t.time())
    down.push(@sfdesk.wide.jobs_open.get())
    t.touch_at(2, 900.0, 300.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false, true, true]))
}

///|
/// 大屏 (1280 wide, a mouse's) over the home-jobs fixture, the rail kept without the bell (对话, 文件: what is left up
/// long at the lists' foot, not in 待处理's panel).
fn jobs_tester() -> @ui.Tester {
  new_run()
  let base = fixture("home-jobs")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      match (name, (base.topic)(name, params).value) {
        ("prefs", Some(Object(m))) => {
          let p = m.copy()
          // (the core's railView: ws1's own rail, 对话 and 文件)
          let view = match p.get("railView") {
            Some(Object(v)) => v.copy()
            _ => {}
          }
          view["by"] = { "ws1": { "items": ["chats", "files"] } }
          p["railView"] = Json::object(view)
          { value: Some(Json::object(p)), error: None, version: 1 }
        }
        _ => (base.topic)(name, params)
      }
    },
  }
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
}

///|
/// 大屏, a mouse's, the chat open (the chat-jobs fixture: its services in its bar): `label` in its bar pressed (对话信息:
/// its info's popover; 服务和后台任务: its services'), dismissed by `how` (as the host hands it on, no frame after it):
/// whether that one is open then, once a frame is drawn, as the button opens it again and a frame after.
fn chat_pop_dismissed(label : String, how : (@ui.Tester) -> Unit) -> Array[Bool] raise {
  let t = wide_tester([], mode="chat-jobs")
  t.host_says_finger(Some(false))
  t.draw()
  guard t.query(Button, label~) is Some(s) else { fail("no \{label}") }
  let (bx, by, bw, bh) = s.rect
  let open = fn() {
    let (info, jobs) = @sfdesk.chat_pops_open()
    if label == "对话信息" { info } else { jobs }
  }
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  let seen = [open()]
  how(t)
  seen.push(open())
  t.draw()
  seen.push(open())
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  seen.push(open())
  t.draw()
  seen.push(open())
  seen
}

///|
test "大屏: a chat's info's popover dismissed by Escape: closed as the key is taken; the frame after closes nothing more, opened again its own" {
  assert_eq(chat_pop_dismissed("对话信息", fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false, true, true])
}

///|
test "大屏: a chat's services' popover dismissed by a press on the chat: closed as it goes down; the frame after closes nothing more, opened again its own" {
  let down : Array[Bool] = []
  let seen = chat_pop_dismissed("服务和后台任务", fn(t) {
    t.touch_at(0, 700.0, 500.0, t.time())
    down.push(@sfdesk.chat_pops_open().1)
    t.touch_at(2, 700.0, 500.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false, true, true]))
}

///|
/// `t` with a popover open from the button at `label` (`open` whether it is): that button pressed and let go (as the
/// host hands it on: what closes it), a frame drawn after where `frames`, then Escape at once: whether it is open as
/// the button is let go, as Escape is taken, and once a frame is drawn after.
fn button_then_escape(t : @ui.Tester, label : String, open : () -> Bool, frames : Bool) -> Array[Bool] raise {
  t.host_says_finger(Some(false))
  t.draw()
  guard t.query(Button, label~) is Some(s) else { fail("no \{label}") }
  let (x, y) = (s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
  t.tap(x, y)
  t.frame()
  assert_true(open(), msg="opened")
  t.touch_at(0, x, y, t.time())
  t.touch_at(2, x, y, t.time())
  let seen = [open()]
  if frames {
    t.frame()
  }
  t.key_told(@ui.key_escape, 0, t.time())
  seen.push(open())
  t.draw()
  seen.push(open())
  seen
}

///|
test "大屏: 运行中 pressed again with its popover open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  let open = fn() { @sfdesk.wide.jobs_open.get() }
  let none = button_then_escape(jobs_tester(), "长时间运行的服务和任务", open, false)
  let framed = button_then_escape(jobs_tester(), "长时间运行的服务和任务", open, true)
  assert_eq((none, framed), ([false, false, false], [false, false, false]))
}

///|
test "大屏: a chat's 服务和后台任务 pressed again with its popover open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  let open = fn() { @sfdesk.chat_pops_open().1 }
  let none = button_then_escape(wide_tester([], mode="chat-jobs"), "服务和后台任务", open, false)
  let framed = button_then_escape(wide_tester([], mode="chat-jobs"), "服务和后台任务", open, true)
  assert_eq((none, framed), ([false, false, false], [false, false, false]))
}

///|
test "大屏: a chat's 对话信息 pressed again with its popover open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  let open = fn() { @sfdesk.chat_pops_open().0 }
  let none = button_then_escape(wide_tester([], mode="chat-jobs"), "对话信息", open, false)
  let framed = button_then_escape(wide_tester([], mode="chat-jobs"), "对话信息", open, true)
  assert_eq((none, framed), ([false, false, false], [false, false, false]))
}
