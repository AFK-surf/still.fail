///|
test "a declared modal owner controls its hosted overlay without an intervening picture" {
  let results : Array[Bool] = []
  for first in [false, true] {
    for timed in [false, true] {
      for pointer in [false, true] {
        let histories : Array[(Bool, String?, Array[Double], Array[Double])] = []
        for framed in [false, true] {
          let modal = @signals.signal(first)
          let calls : Array[Double] = []
          let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
          let at = t.time() + 50.0
          set_view_app(fn(root) {
            root.box(fn(v) {
              v.width(Is(Some(80.0))).height(Is(Some(40.0)))
              .says(Is(Some(@view.said(Slider, label="Volume", actions=[Increment]))))
              .on_action(fn(_) { calls.push(v.cause_at()) })
              .on_press(fn() { calls.push(v.cause_at()) }) |> ignore
            }) |> ignore
            root.box(fn(v) {
              v.modal(By(fn() { modal.get() })).presses(By(fn() { modal.get() })) |> ignore
              old(v, fn(c) {
                if modal.get() {
                  c.overlay("old modal", modal=true, outside=false, fn() {
                    c.box(w=Px(400.0), h=Px(200.0), bg=0xFFFFFFFFL, fn() {
                      c.text("Modal") |> ignore
                    }) |> ignore
                  }) |> ignore
                }
              }) |> ignore
            }) |> ignore
            if timed {
              root.at_moment(at, fn() { modal.set(!first) }) |> ignore
            }
          })
          t.draw()
          let id = t.semantics().iter().find_first(fn(s) { s.role == Slider && s.label == "Volume" }).unwrap().id
          t.record_host()
          t.advance(at - t.time())
          // A host event (as for a system menu) changes the open state, or first delivers its due notification.
          host_event(fn() { if !timed { modal.set(!first) } })
          if framed { t.frame_at(at) }
          let offered = t.query(Slider, label="Volume").map(fn(s) { s.actions.contains(Increment) }).unwrap_or(false)
          let hit = t.press_target_at(20.0, 20.0).map(fn(s) { s.label })
          let stack = t.ctx().old_modal_stack()
          let layers = t.ctx().last_layers.map(fn(l) { (l.modal, t.ctx().layer_takes(l)) })
          if pointer {
            t.touch_at(0, 20.0, 20.0, at)
            t.touch_at(2, 20.0, 20.0, at)
          } else {
            t.ctx().ask_action(id, Increment)
          }
          let immediate = calls.copy()
          let before_next = t.host_frames().map(fn(f) { f.at })
          assert_eq(before_next, if framed { [at] } else { [] })
          t.draw()
          println("old modal first \{first}, due \{timed}, pointer \{pointer}, framed \{framed} at \{at}: offered \{offered}, hit \{hit}, stack \{stack}, layers \{layers}, immediate \{immediate}, after frame \{calls}")
          histories.push((offered, hit, immediate, calls.copy()))
          results.push(offered == first && hit == (if first { Some("Volume") } else { None }) &&
            immediate == (if first { [at] } else { [] }) && calls == immediate)
        }
        results.push(histories[0] == histories[1])
      }
    }
  }
  assert_true(results.all(fn(ok) { ok }), msg="the same modal cause controls the next input and semantics without waiting for a picture")
}

///|
test "an old portal gives back focus and its input at its owner's exit without rebuilding the old view" {
  for leave in [0.0, 160.0] {
    let open = @signals.signal(false)
    let calls : Array[String] = []
    let builds = Ref(0)
    let released = Ref(0)
    let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
    set_view_app(fn(root) {
      root.box(fn(v) {
        v.width(Is(Some(80.0))).height(Is(Some(40.0)))
        .focusable(Is(true)).says(Is(Some(@view.said(Button, label="page"))))
        .on_press(fn() { calls.push("page") }) |> ignore
      }) |> ignore
      root.show(fn() { open.get() }, fn(v) {
        v.over(Is(true)).modal(By(fn() { !v.leaving() })).focus_returns() |> ignore
        v.owns(fn() { released.val += 1 }) |> ignore
        old(v, fn(c) {
          builds.val += 1
          c.overlay("owned portal", modal=true, outside=false, fn() {
            let id = c.id("portal button")
            let b = c.box(id~, w=Px(80.0), h=Px(40.0), fn() { c.text("portal") |> ignore })
            c.semantics(b, Button, id~, label="portal", actions=[Activate])
            c.focusable(id, node=b)
            c.on_press(id, fn() { calls.push("portal") })
          }) |> ignore
        }) |> ignore
      }, leave~)
    })
    t.draw()
    let page = t.get(Button, label="page")
    t.ctx().ask_action(page.id, Focus)
    host_event(fn() { open.set(true) })
    t.draw()
    let portal = t.get(Button, label="portal")
    assert_eq(t.focused().map(fn(s) { s.id }), Some(portal.id))
    let made = builds.val
    let at = t.time() + 50.0
    t.advance(at - t.time())
    t.record_host()
    host_event(fn() { open.set(false) })
    assert_eq(builds.val, made, msg="an input never runs the old drawing closure")
    assert_eq(t.focused().map(fn(s) { s.id }), Some(page.id), msg="the portal gives its focus back at the owner's cause")
    assert_true(t.query(Button, label="portal") is None)
    t.ctx().ask_action(portal.id, Activate)
    assert_eq(calls, [])
    assert_eq(t.press_target_at(20.0, 20.0).map(fn(s) { s.label }), Some("page"))
    t.touch_at(0, 20.0, 20.0, at)
    t.touch_at(2, 20.0, 20.0, at)
    assert_eq(calls, ["page"])
    assert_eq(t.host_frames().length(), 0)
    assert_eq(released.val, if leave == 0.0 { 1 } else { 0 })
    let released_at = at + leave
    t.advance(released_at - t.time())
    host_event(fn() {  })
    assert_eq(released.val, 1)
    t.draw()
    assert_eq(calls, ["page"])
    assert_eq(t.ctx().old_modal_stack(), -2)
  }
}

///|
test "closing nested old portals at their owners' causes restores the surviving layer before the page" {
  let outer = @signals.signal(true)
  let inner = @signals.signal(false)
  let calls : Array[String] = []
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    for (name, open) in [("outer", outer), ("inner", inner)] {
      root.show(fn() { open.get() }, fn(v) {
        v.over(Is(true)).modal(By(fn() { !v.leaving() })).focus_returns() |> ignore
        old(v, fn(c) {
          c.overlay(name, modal=true, outside=false, fn() {
            let id = c.id(name + " button")
            let b = c.box(id~, w=Px(80.0), h=Px(40.0), fn() { c.text(name) |> ignore })
            c.semantics(b, Button, id~, label=name, actions=[Activate])
            c.focusable(id, node=b)
            c.on_press(id, fn() { calls.push(name) })
          }) |> ignore
        }) |> ignore
      }, leave=160.0)
    }
  })
  t.draw()
  let outer_id = t.get(Button, label="outer").id
  assert_eq(t.focused().map(fn(s) { s.id }), Some(outer_id))
  host_event(fn() { inner.set(true) })
  t.draw()
  let inner_id = t.get(Button, label="inner").id
  assert_eq(t.focused().map(fn(s) { s.id }), Some(inner_id))
  let at = t.time() + 50.0
  t.advance(at - t.time())
  t.record_host()
  host_event(fn() { inner.set(false) })
  assert_eq(t.focused().map(fn(s) { s.id }), Some(outer_id))
  assert_true(t.query(Button, label="inner") is None)
  t.ctx().ask_action(inner_id, Activate)
  t.ctx().ask_action(outer_id, Activate)
  assert_eq(calls, ["outer"])
  host_event(fn() { outer.set(false) })
  assert_eq(t.ctx().old_modal_stack(), -2)
  t.ctx().ask_action(outer_id, Activate)
  assert_eq(calls, ["outer"])
  assert_eq(t.host_frames().length(), 0)
}
