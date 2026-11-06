///|
/// All three inputs name the real info row. Focus is prepared before the compared interval; the action itself
/// is delivered at its end without drawing a following frame.
fn info_action_input(t : @ui.Tester, role : @ui.Role, label : String, how : String, hz : Int) -> Double raise {
  let s = t.get(role, label~)
  assert_true(s.actions.contains(Activate), msg="the real info row offers Activate")
  assert_false(s.hidden || s.disabled)
  if how == "pointer" {
    return info_release(t, label, hz, role~)
  }
  if how != "activate" {
    t.ctx().ask_action(s.id, Focus)
    t.draw()
    assert_eq(t.focused().map(fn(n) { n.id }), Some(s.id), msg="the key belongs to the info row, not the composer")
  }
  let start = t.time()
  let at = start + 50.0
  let frames : Array[Double] = []
  t.record_host()
  if hz > 0 {
    let period = 1000.0 / hz.to_double()
    let mut i = 1
    while i.to_double() * period < 50.0 {
      let frame = start + i.to_double() * period
      t.frame_at(frame)
      frames.push(frame)
      i += 1
    }
  }
  t.advance(at - t.time())
  if how == "activate" {
    t.ctx().ask_action(s.id, Activate)
  } else {
    assert_eq(t.focused().map(fn(n) { n.id }), Some(s.id))
    t.key_told(if how == "enter" { @ui.key_code_enter } else { @ui.key_space }, 0, at)
  }
  assert_eq(t.host_frames().map(fn(f) { f.at }), frames)
  at
}

///|
test "a real info button acts once at Activate, Enter, Space or release before any following frame" {
  let results : Array[(Bool, Bool)] = []
  for how in ["activate", "enter", "space", "pointer"] {
    for hz in [0, 60, 120] {
      let calls : Array[Made] = []
      let at_calls : Array[Double] = []
      let t = wide_tester(calls, mode="chat", wrap=fn(base) {
        { ..base, call: fn(name, params, done) {
          if name == "chat.tabs.open" { at_calls.push(@ui.view_tree().unwrap().logic_at()) }
          (base.call)(name, params, done)
        } }
      })
      t.run_for(@ui.move_most_ms)
      t.click(Button, label="对话信息")
      t.run_for(@kit.pop_ms)
      let at = info_action_input(t, Button, "Station 文件", how, hz)
      let immediate = (!@sfdesk.chat_pops_open().0, named(calls, "chat.tabs.open").length(), at_calls.copy())
      t.run_for(@ui.move_most_ms)
      let final = (!@sfdesk.chat_pops_open().0, named(calls, "chat.tabs.open").length())
      println("info action button \{how}, \{hz} Hz at \{at}: immediate \{immediate}, following frames \{final}")
      results.push((immediate == (true, 1, [at]), final == (true, 1)))
    }
  }
  assert_true(results.all(fn(r) { r.0 && r.1 }), msg="every input acts exactly once in its own event")
}

///|
test "real info links open the page or URL once at their input and keep the new chat focus" {
  let results : Array[(Bool, Bool)] = []
  for opener in [true, false] {
    for how in ["activate", "enter", "space", "pointer"] {
      for hz in [0, 60, 120] {
        let t = wide_tester([], mode=if opener { "chat-opener" } else { "chat" })
        t.run_for(@ui.move_most_ms)
        t.click(Button, label="对话信息")
        t.run_for(@kit.pop_ms)
        let depth = app.nav.depth()
        let label = if opener { "由「和 Ana 一起看新版的引导页」创建" } else { "列表里的图片按需解码" }
        let at = info_action_input(t, Link, label, how, hz)
        let read = fn() {
          let session = match app.nav.top() { Chat(r) => r.session; _ => "" }
          (!@sfdesk.chat_pops_open().0, session, app.nav.depth(), t.opened().copy(),
            t.focused().map(fn(n) { (n.role, n.label) }))
        }
        let immediate = read()
        t.run_for(@ui.move_most_ms)
        let final = read()
        println("info action link \{opener} \{how}, \{hz} Hz at \{at}: immediate \{immediate}, following frames \{final}")
        if opener {
          let expected : (Bool, String, Int, Array[String], (@ui.Role, String)?) = (true, "s-c6", depth, [], Some((TextField, "发消息")))
          results.push((immediate == expected, final == expected))
        } else {
          results.push((immediate.0 && immediate.3 == ["https://github.com/acme/shop/pull/131"],
            final.0 && final.3 == ["https://github.com/acme/shop/pull/131"]))
        }
      }
    }
  }
  assert_true(results.all(fn(r) { r.0 && r.1 }), msg="links act in their input, keep focus and never replay")
}

///|
test "covered and dismissed real info rows cannot be activated through their remembered semantic ids" {
  let rows : Array[(@ui.Role, String)] = [(Button, "Station 文件"), (Link, "列表里的图片按需解码")]
  for (role, label) in rows {
    let calls : Array[Made] = []
    let t = wide_tester(calls, mode="chat")
    t.run_for(@ui.move_most_ms)
    t.click(Button, label="对话信息")
    t.run_for(@kit.pop_ms)
    let s = t.get(role, label~)
    assert_true(s.actions.contains(Activate))
    t.ctx().ask_action(s.id, Focus)
    t.draw()
    assert_eq(t.focused().map(fn(n) { n.id }), Some(s.id))
    // The info is an over-all control popover. Put the test's modal over that same layer, not an ordinary
    // page dialog beneath it, and prove that the real row is actually excluded before asking its old id.
    let covered = @signals.signal(true)
    @ui.view_tree().unwrap().root().show(fn() { covered.get() }, fn(layer) {
      layer.over_all(Is(true)).over(Is(true)).modal(Is(true)).presses(Is(true)).focus_returns()
        .says(Is(Some(@view.said(Dialog, label="覆盖信息")))) |> ignore
    }) |> ignore
    t.draw()
    assert_true(t.query(role, label~) is None, msg="the modal hides the row from accessibility")
    t.ctx().ask_action(s.id, Activate)
    t.key_told(@ui.key_code_enter, 0, t.time())
    t.key_told(@ui.key_space, 0, t.time())
    assert_true(@sfdesk.chat_pops_open().0)
    assert_eq(named(calls, "chat.tabs.open").length(), 0)
    assert_eq(t.opened(), [])
    t.run_for(@ui.move_most_ms)
    assert_true(@sfdesk.chat_pops_open().0)
    assert_eq(named(calls, "chat.tabs.open").length(), 0)
    assert_eq(t.opened(), [])
    covered.set(false)
    t.run_for(@ui.move_most_ms)
    assert_eq(t.focused().map(fn(n) { n.id }), Some(s.id), msg="the covering modal returns the info row's focus")
    t.key_told(@ui.key_escape, 0, t.time())
    assert_false(@sfdesk.chat_pops_open().0)
    assert_true(t.query(role, label~) is None, msg="a closing row stops offering its action before the exit frame")
    t.ctx().ask_action(s.id, Activate)
    assert_eq(named(calls, "chat.tabs.open").length(), 0)
    assert_eq(t.opened(), [])
    t.run_for(@ui.move_most_ms)
    t.ctx().ask_action(s.id, Activate)
    t.draw()
    assert_eq(named(calls, "chat.tabs.open").length(), 0)
    assert_eq(t.opened(), [])
  }
}
