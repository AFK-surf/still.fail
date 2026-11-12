// What a chat's bar on 中屏 and 大屏 opens under it (sfdesk's chat_pops_node): its info (chat_info_node), its services'
// popover (jobs_pop_node), each a panel of the presenters' beside its button (or the system's bars' mark), and archiving
// a chat that keeps watch asked first (the presenters' confirm). Laid out as the old view's popovers were (the two
// compared word by word and rectangle by rectangle as they were made of nodes); here what each of their presses does,
// how they close, where the focus goes, and what the checks say of them. Each with the chat's page made with its inside nodes
// (sfbase's chat_page_nodes, wide_bar_at's `nodes`): with it off the old page draws its old popovers.

///|
/// The windows the popovers are held to: a Mac's 1280 × 800 (大屏), 720 wide (中屏: the chat in the page's panel of the
/// tape).
// kept across runs: a value
let pops_windows : Array[(String, Double)] = [("大屏", 1280.0), ("中屏", 720.0)]

///|
/// The audit's faults made in the popovers' own files.
fn pops_faults(t : @ui.Tester) -> Array[String] {
  t.audit().filter(fn(f) { f.contains("chat_info_node") || f.contains("jobs_pop_node") || f.contains("chat_pops_node") })
}

///|
/// The bar's button said `label` pressed, its popover in.
fn pops_open(t : @ui.Tester, label : String) -> (Double, Double, Double, Double) raise {
  guard wide_bar_button(t, label) is Some(b) else { fail("no \{label}") }
  wide_bar_tap(t, b)
  b
}

///|
/// The fixture's services' popover (chat-jobs-pop: its job 盯 CI open in it) on window `w`: on 中屏 opened from its
/// button once the chat's panel is brought into use (the fixture's, open as the tape came, took the press that brings it,
/// a panel of the presenters' taking a press outside it whole).
fn pops_jobs_at(calls : Array[Made], w : Double) -> @ui.Tester raise {
  let t = wide_bar_at(calls, nodes=true, w~, mode="chat-jobs-pop")
  if @sfdesk.wide.tape.get() {
    if @sfdesk.chat_pops_open().1 {
      t.key(@ui.key_escape)
      t.run_for(@ui.move_most_ms)
    }
    page_over(t, w)
    pops_open(t, @sf.t("web-pages.chat.services")) |> ignore
  }
  t
}

///|
/// The rows of the popover open (its Dialog's, the topmost), as a screen reader finds them.
fn pops_rows(t : @ui.Tester) -> Array[@ui.SemNode] {
  match t.all(Dialog) {
    [] => []
    ds => {
      let (dx, dy, dw, dh) = ds[ds.length() - 1].rect
      t
      .semantics()
      .filter(fn(s) {
        let (x, y, _, _) = s.rect
        !s.hidden && (s.role is Button || s.role is Link) && x >= dx && x < dx + dw && y >= dy && y < dy + dh
      })
    }
  }
}

///|
test "大屏, 中屏: each row of the chat's info does what it says and closes it; under its button, its end at the button's" {
  for win in pops_windows {
    // (each row by what a screen reader calls it, and the call it makes: what the old view's rows made)
    let rows = [
      ("列表里的图片按需解码", "link.parse", "url", "https://github.com/acme/shop/pull/131"),
      ("首页列表按天分组", "link.parse", "url", "https://github.com/acme/shop/pull/128"),
      ("虚拟列表：按估计高度占位", "link.parse", "url", "https://github.com/acme/shop/pull/127"),
      ("全部 4 个 PR", "chat.tabs.open", "tab", "things"),
      ("图片、文件和链接", "chat.tabs.open", "tab", "things"),
      ("Station 文件", "chat.tabs.open", "tab", "files"),
    ]
    for row in rows {
      let calls : Array[Made] = []
      let t = wide_bar_at(calls, nodes=true, w=win.1)
      let b = pops_open(t, @sf.t("web-pages.chat.info"))
      assert_eq(@sfdesk.chat_pops_open(), (true, false), msg=win.0)
      guard wide_bar_dialog(t) is Some(d) else { fail("\{win.0}: no info") }
      assert_true(wide_bar_under(d, b), msg="\{win.0}: under its button: \{Repr(d)} \{Repr(b)}")
      guard pops_rows(t).iter().find_first(fn(s) { s.label == row.0 }) is Some(s) else {
        fail("\{win.0}: no \{row.0} in \{Repr(pops_rows(t).map(fn(s) { s.label }))}")
      }
      wide_bar_tap(t, s.rect)
      let made = calls.filter(fn(c) { c.name == row.1 && text(Some(c.params), row.2) == row.3 })
      assert_eq(made.length(), 1, msg="\{win.0} \{row.0}: \{Repr(calls.map(fn(c) { c.name }))}")
      assert_eq(@sfdesk.chat_pops_open(), (false, false), msg="\{win.0} \{row.0}: closed")
      assert_true(!@sf.presenting(), msg="\{win.0} \{row.0}: nothing left presented")
      assert_eq(pops_faults(t), [], msg=win.0)
    }
  }
}

///|
test "大屏: the info of a chat another's agent made says that chat, pressed it opens; of one whose agent made chats, their menu beside it; its letters beside the chat" {
  // (who made it: 由「…」创建, a link to that chat)
  let calls : Array[Made] = []
  let t = wide_bar_at(calls, nodes=true, mode="chat-opener-pop")
  t.click(Link, label="由「和 Ana 一起看新版的引导页」创建")
  t.run_for(@ui.move_most_ms)
  assert_true(
    match app.nav.top() {
      Chat(r) => r.session == "s-c6"
      _ => false
    },
  )
  assert_eq(@sfdesk.chat_pops_open(), (false, false))
  // (what its agent made: 创建了 3 个对话, their menu beside it, the info still open under it)
  let t = wide_bar_at(calls, nodes=true, mode="chat-opened-pop")
  t.click(Button, label="创建了 3 个对话")
  t.run_for(@ui.move_most_ms)
  assert_true(t.all(Menu).length() > 0, msg="its menu")
  assert_eq(@sfdesk.chat_pops_open(), (true, false))
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.chat_pops_open(), (false, false))
  // (what its agents and other chats' wrote each other: agent 往来, beside the chat)
  let t = wide_bar_at(calls, nodes=true, mode="chat-letters-pop")
  t.click(Button, label="agent 往来")
  t.run_for(@ui.move_most_ms)
  assert_true(calls.iter().any(fn(c) { c.name == "chat.tabs.open" && text(Some(c.params), "tab") == "letters" }))
  assert_eq(@sfdesk.chat_pops_open(), (false, false))
  assert_eq(pops_faults(t), [])
}

///|
test "大屏, 中屏: the bar's popovers close by Escape, a press outside and their button again; the focus back on the button; Tab stays in them (Tab held to the popover alone)" {
  for win in pops_windows {
    for which in ["web-pages.chat.info", "web-pages.chat.services"] {
      let open = fn() {
        let (i, j) = @sfdesk.chat_pops_open()
        if which == "web-pages.chat.info" {
          i
        } else {
          j
        }
      }
      let ways : Array[(String, (@ui.Tester, (Double, Double, Double, Double)) -> Unit)] = [
        ("Escape", fn(t, _) { t.key(@ui.key_escape) }),
        ("a press outside", fn(t, _) { t.tap(win.1 / 2.0, 500.0) }),
        ("its button again", fn(t, b) { t.tap(b.0 + b.2 / 2.0, b.1 + b.3 / 2.0) }),
      ]
      for way in ways {
        let calls : Array[Made] = []
        let t = wide_bar_at(calls, nodes=true, w=win.1, over=wide_bar_jobs("fail"))
        let label = @sf.t(which)
        let b = pops_open(t, label)
        assert_true(open(), msg="\{win.0} \{label}")
        // (Tab from the first of it to the next and on: never out of it while it is open)
        guard wide_bar_dialog(t) is Some(d) else { fail("\{win.0} \{label}: no popover") }
        for _ in 0..<4 {
          t.tab()
          t.run_for(@ui.move_most_ms)
          match t.focused() {
            Some(f) => {
              let (fx, fy, _, _) = f.rect
              assert_true(fx >= d.0 && fx < d.0 + d.2 && fy >= d.1 && fy < d.1 + d.3, msg="\{win.0} \{label}: Tab to \{f.label}")
            }
            None => ()
          }
        }
        (way.1)(t, b)
        t.run_for(@ui.move_most_ms)
        assert_true(!open(), msg="\{win.0} \{label}: closed by \{way.0}")
        assert_true(!@sf.presenting(), msg="\{win.0} \{label}: \{way.0}")
        if way.0 == "Escape" {
          assert_eq(t.focused().map(fn(s) { s.label }), Some(label), msg="\{win.0}: the focus back on \{label}")
        }
        assert_eq(pops_faults(t), [], msg=win.0)
      }
    }
  }
}

///|
test "大屏, 中屏: the services' popover: a service opens 任务 beside the chat; a job opens in place and closes, stopped from there; all of them in 任务" {
  for win in pops_windows {
    let presses = [
      ("web", "chat.tabs.open", false),
      ("停止", "job.stop", true),
      ("在侧栏查看", "chat.tabs.open", false),
      ("全部 2 个 · 在侧栏查看", "chat.tabs.open", false),
    ]
    for p in presses {
      let calls : Array[Made] = []
      let t = pops_jobs_at(calls, win.1)
      t.click(Button, label=p.0)
      t.run_for(@ui.move_most_ms)
      assert_true(calls.iter().any(fn(c) { c.name == p.1 }), msg="\{win.0} \{p.0}: \{Repr(calls.map(fn(c) { c.name }))}")
      assert_eq(@sfdesk.chat_pops_open().1, p.2, msg="\{win.0} \{p.0}: open after")
      if p.2 {
        t.key(@ui.key_escape)
        t.run_for(@ui.move_most_ms)
      }
      assert_eq(pops_faults(t), [], msg=win.0)
    }
    // (盯 CI pressed: closed in place, its rows after it come up, the popover shorter; pressed again, open)
    let calls : Array[Made] = []
    let t = pops_jobs_at(calls, win.1)
    guard wide_bar_dialog(t) is Some(d) else { fail("\{win.0}: no popover") }
    assert_true(t.find("第 3 步通过：单元测试全部通过") is Some(_), msg=win.0)
    let opened = named(calls, "chat.tabs.open").length()
    t.click(Button, label="盯 CI")
    t.run_for(@ui.move_most_ms)
    guard wide_bar_dialog(t) is Some(d2) else { fail("\{win.0}: closed") }
    assert_true(d2.3 < d.3, msg="\{win.0}: shorter: \{Repr(d)} \{Repr(d2)}")
    assert_true(t.find("第 3 步通过：单元测试全部通过") is None, msg=win.0)
    assert_eq(named(calls, "chat.tabs.open").length(), opened, msg="\{win.0}: 盯 CI opens nothing beside the chat")
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    assert_eq(pops_faults(t), [], msg=win.0)
  }
}

///|
test "大屏: the services' popover opened on a job, the job closed from outside it (a fixture's): drawn as it is, its frames built whole" {
  // (the old view's popover, on main 2026-11-12, painted a few frames at the height it had with the job open (356)
  // after the job was closed, its old view not built again for a field no signal: rc11-4, frame_watch)
  let calls : Array[Made] = []
  let t = wide_bar_at(calls, nodes=true, mode="chat-jobs-pop")
  guard wide_bar_dialog(t) is Some(d) else { fail("no popover") }
  @sfdesk.open_job_pop("")
  t.run_for(@ui.move_most_ms)
  guard wide_bar_dialog(t) is Some(d2) else { fail("closed") }
  assert_true(d2.3 < d.3, msg="shorter: \{Repr(d)} \{Repr(d2)}")
  assert_true(t.find("第 3 步通过：单元测试全部通过") is None)
  assert_eq(pops_faults(t), [])
}

///|
test "大屏, 中屏: 归档 on a chat keeping watch asks first, in the core's words; 取消 archives nothing, 归档 archives it" {
  for win in pops_windows {
    for say in ["取消", "归档"] {
      let calls : Array[Made] = []
      let t = wide_bar_at(
        calls,
        nodes=true,
        w=win.1,
        over=wide_bar_both(
          wide_bar_chat_field("archivable", fn(_) { Json::boolean(true) }),
          wide_bar_chat_field("watch", fn(_) { { "ask": "它还在盯着 CI，归档后就不盯了。" } }),
        ),
      )
      pops_open(t, @sf.t("web-pages.chat.archive")) |> ignore
      assert_true(t.find("它还在盯着 CI，归档后就不盯了。") is Some(_), msg=win.0)
      assert_true(t.find("归档「整理发布清单」？") is Some(_), msg=win.0)
      assert_eq(named(calls, "chat.archive").length(), 0)
      guard t.all(Dialog).iter().find_first(fn(s) { s.label == "归档「整理发布清单」？" }) is Some(d) else {
        fail("\{win.0}: no confirm")
      }
      t.click(Button, label=say, within=d)
      t.run_for(@ui.move_most_ms)
      assert_eq(named(calls, "chat.archive").length(), if say == "归档" { 1 } else { 0 }, msg="\{win.0} \{say}")
      assert_true(!@sf.presenting(), msg="\{win.0} \{say}: closed")
      assert_true(t.find("它还在盯着 CI，归档后就不盯了。") is None, msg=win.0)
      assert_eq(pops_faults(t), [], msg=win.0)
    }
  }
}

///|
test "大屏 beside the system's bars: the chat's info opens at their mark and closes as the window turns" {
  let calls : Array[Made] = []
  let t = wide_bar_at(calls, nodes=true, w=951.0, h=669.0, platform=1, able=true)
  t.post(@hostapi.system_channel, "{\"nav\":\"page/chat/info\",\"at\":[867,40,84,44]}")
  t.frames_owed()
  assert_eq(@sfdesk.chat_pops_open(), (true, false))
  guard wide_bar_dialog(t) is Some(d) else { fail("no info") }
  assert_true(d.0 + d.2 <= 867.0 && d.1 >= 40.0 && d.1 < 84.0, msg="by the mark: \{Repr(d)}")
  t.run_for(@ui.move_most_ms)
  t.resize(1100.0, 700.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.chat_pops_open(), (false, false))
  assert_true(!@sf.presenting())
  assert_eq(pops_faults(t), [])
}

///|
test "大屏, 中屏: the chat's info and its services' popover at the system's words set to 1.3: nothing outgrows its box" {
  for win in pops_windows {
    for which in ["web-pages.chat.info", "web-pages.chat.services"] {
      let calls : Array[Made] = []
      let t = if which == "web-pages.chat.services" { pops_jobs_at(calls, win.1) } else { wide_bar_at(calls, nodes=true, w=win.1) }
      t.set_font_scale(1.3)
      t.run_for(@ui.move_most_ms)
      if !(@sfdesk.chat_pops_open().0 || @sfdesk.chat_pops_open().1) {
        pops_open(t, @sf.t(which)) |> ignore
      }
      assert_true(wide_bar_dialog(t) is Some(_), msg="\{win.0} \{which}")
      assert_eq(t.fixed_outgrown().filter(fn(f) { f.contains("chat_info_node") || f.contains("jobs_pop_node") }), [], msg="\{win.0} \{which}")
      assert_eq(pops_faults(t), [], msg="\{win.0} \{which}")
    }
  }
}

///|
test "中屏 beside the system's bars (an iPhone's): 对话信息 chosen there opens the chat's info, drawn at their mark" {
  // (its bar has no buttons of its own here: what it stands beside is the mark; the old view's popover stood there too)
  let calls : Array[Made] = []
  let t = wide_bar_at(calls, nodes=true, w=820.0, h=1180.0, platform=1, able=true)
  t.post(@hostapi.system_channel, "{\"nav\":\"page/chat/info\",\"at\":[736,40,84,44]}")
  t.frames_owed()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.chat_pops_open(), (true, false))
  guard wide_bar_dialog(t) is Some(d) else { fail("no info drawn") }
  assert_true(d.0 + d.2 <= 736.0 && d.1 >= 40.0 && d.1 < 84.0, msg="by the mark: \{Repr(d)}")
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_true(!@sf.presenting())
  assert_eq(pops_faults(t), [])
}

///|
test "大屏, 中屏: a popover of the bar's is the presenters' panel, modal: what is under it is not pressed, read, lit or keyed while it is open" {
  // (each as the library's other panels from a button: the old view's popovers let a press through to what was under
  // them, left the page under them read out, its button lit under the pointer and ⌥↓ to the next chat)
  for win in pops_windows {
    let calls : Array[Made] = []
    let t = wide_bar_at(calls, nodes=true, w=win.1, over=wide_bar_jobs("fail"))
    guard wide_bar_button(t, @sf.t("web-pages.chat.services")) is Some(jobs) else { fail("\{win.0}: no services") }
    let b = pops_open(t, @sf.t("web-pages.chat.info"))
    assert_eq(@sfdesk.chat_pops_open(), (true, false), msg=win.0)
    // (its button, the pointer still on it, not lit)
    assert_true(!wide_bar_lit(t, b), msg="\{win.0}: its button lit")
    // (the bar's other buttons not read out)
    let more = @sf.t("common.more")
    assert_eq(t.semantics().filter(fn(s) { s.label == more && s.rect.1 < 90.0 && !s.hidden }).length(), 0, msg="\{win.0}: 更多 read")
    // (⌥↓: still this chat)
    let was = app.nav.top()
    t.key(@ui.key_code_down, mods=@ui.mod_alt)
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == was, msg="\{win.0}: ⌥↓ went on")
    // (a press on 服务: the info closed, nothing else opened)
    wide_bar_tap(t, jobs)
    assert_eq(@sfdesk.chat_pops_open(), (false, false), msg="\{win.0}: the press went through")
    assert_true(!@sf.presenting(), msg=win.0)
    assert_eq(pops_faults(t), [], msg=win.0)
  }
}
