///|
test "old press callbacks take accessibility and keyboard inputs in their event, once, with and without a retained host" {
  let results : Array[Bool] = []
  for hosted in [false, true] {
    for how in ["activate", "enter", "space"] {
      let calls : Array[(Double, Bool)] = []
      let build = fn(c : Ctx) {
        let id = c.id("press")
        let b = c.box(id~, w=Px(100.0), h=Px(40.0), fn() { c.text("press") |> ignore })
        c.focusable(id, node=b)
        c.semantics(b, Button, id~, label="press", actions=[Activate])
        c.on_press(id, fn() { calls.push((h_now(), building.val)) })
      }
      let t = Tester::new(if hosted { fn(_c) {  } } else { build }, w=200.0, h=100.0)
      if hosted {
        set_view_app(fn(root) { old(root, build) |> ignore })
        t.draw()
      }
      let s = t.get(Button, label="press")
      t.ctx().ask_action(s.id, Focus)
      t.draw()
      assert_eq(t.focused().map(fn(n) { n.id }), Some(s.id))
      let at = t.time() + 50.0
      t.advance(at - t.time())
      t.record_host()
      if how == "activate" {
        t.ctx().ask_action(s.id, Activate)
      } else {
        t.key_told(if how == "enter" { key_enter } else { key_space }, 0, at)
      }
      assert_eq(t.host_frames().length(), 0)
      let immediate = calls.copy()
      t.draw()
      println("press input \{how}, retained host \{hosted}: immediate \{immediate}, following frame \{calls}")
      results.push(immediate == [(at, false)] && calls == [(at, false)])
    }
  }
  assert_true(results.all(fn(ok) { ok }), msg="callbacks belong to their input outside a build, and no following frame replays them")
}

///|
test "a remembered old callback cannot be activated when disabled, hidden, unoffered or no longer built" {
  for state in [1, 2, 3, 4] {
    let stage = @signals.signal(0)
    let calls = Ref(0)
    let t = Tester::new(fn(c) {
      let make = fn() {
        let id = c.id("press")
        let b = c.box(id~, w=Px(100.0), h=Px(40.0), fn() { c.text("press") |> ignore })
        c.semantics(b, Button, id~, label="press", disabled=stage.get() == 1,
          actions=if stage.get() == 3 { [] } else { [Activate] })
        c.on_press(id, fn() { calls.val += 1 })
      }
      match stage.get() {
        2 => c.hidden_from_semantics(make)
        4 => ()
        _ => make()
      }
    }, w=200.0, h=100.0)
    let id = t.get(Button, label="press").id
    stage.set(state)
    t.draw()
    t.ctx().ask_action(id, Activate)
    assert_eq(calls.val, 0, msg="state \{state}, before a frame")
    t.draw()
    assert_eq(calls.val, 0, msg="state \{state}, after a frame")
  }
}

///|
test "an old callback only consumes the keys its focus stop accepts" {
  let calls = Ref(0)
  let t = Tester::new(fn(c) {
    let id = c.id("space")
    let b = c.box(id~, w=Px(100.0), h=Px(40.0), fn() { c.text("space") |> ignore })
    c.focusable(id, node=b, keys=press_space)
    c.semantics(b, Button, id~, label="space", actions=[Activate])
    c.on_press(id, fn() { calls.val += 1 })
  }, w=200.0, h=100.0)
  t.act(Button, Focus, label="space")
  t.key_told(key_enter, 0, t.time())
  assert_eq(calls.val, 0)
  t.key_told(key_space, mod_cmd, t.time())
  assert_eq(calls.val, 0)
  t.key_told(key_space, 0, t.time())
  assert_eq(calls.val, 1)
  t.draw()
  assert_eq(calls.val, 1)
}
