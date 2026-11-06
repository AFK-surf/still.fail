// A legacy layer whose body is built independently of a frame must keep the actual portal, input and focus state it
// made, so a later frame can use that same result without running its body a second time.

///|
test "a new old layer can be built and measured at an event without a frame" {
  let open = @signals.signal(false)
  let built = Ref(0)
  let told = Ref(0)
  let after = Ref(0)
  let host : Ref[@view.View?] = Ref(None)
  let fit = Ref(0)
  let height = Ref(0.0)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = old(layer, fn(c) {
        built.val += 1
        c.tell("made", fn() { told.val += 1 })
        c.after_build("made", fn() { after.val += 1 })
        c.overlay("sheet", modal=true, initial_focus=0, fn() {
          fit.val = c.id("fit")
          c.box(w=Px(200.0), h=Px(120.0), id=fit.val, label="Sheet", fn() {  }) |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() {
    open.set(true)
    root.after_event_action(fn() {
      probe_old_layer(host.val.unwrap())
      for i in 0..<g().count {
        if g().nodes[i].id == fit.val { height.val = g().nodes[i].fh }
      }
    })
  })
  // after_build belongs to a frame's final build, so staging alone must not tell it.
  assert_eq((built.val, height.val, told.val, after.val), (1, 120.0, 0, 0))
  t.drawn_now()
  assert_eq((built.val, told.val, after.val), (1, 1, 1))
  assert_true(t.query(Button, label="Sheet") is Some(_))
}

///|
test "an old layer remeasures changed content before a frame and leaves only its latest portal" {
  let open = @signals.signal(false)
  let tall = @signals.signal(100.0)
  let built = Ref(0)
  let host : Ref[@view.View?] = Ref(None)
  let fit = Ref(0)
  let sizes : Array[Double] = []
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = old(layer, fn(c) {
        built.val += 1
        c.overlay("sheet", modal=true, initial_focus=0, fn() {
          fit.val = c.id("fit")
          c.box(w=Px(200.0), h=Px(tall.get()), id=fit.val, label="Sheet", fn() {  }) |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  let snapshot = fn() {
    probe_old_layer(host.val.unwrap())
    for i in 0..<g().count {
      if g().nodes[i].id == fit.val { sizes.push(g().nodes[i].fh) }
    }
  }
  t.draw()
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() {
    open.set(true)
    root.after_event_action(snapshot)
  })
  let pause_between_actions_ms = 50.0
  t.advance(pause_between_actions_ms)
  root.tree.event(t.time(), fn() {
    tall.set(220.0)
    root.event_action(snapshot)
  })
  assert_eq(sizes, [100.0, 220.0])
  assert_eq(built.val, 2)
  let portals : Array[Int] = []
  let mut i = g().nodes[0].first
  while i >= 0 {
    let n = g().nodes[i]
    if n.portal { portals.push(i) }
    i = n.next
  }
  assert_eq(portals.length(), 1)
}

///|
test "an event-staged old layer retains its editor and capped content" {
  let open = @signals.signal(false)
  let built = Ref(0)
  let host : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0, keyboard=true)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) { c.editor("page", placeholder="Page field") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = old(layer, fn(c) {
        built.val += 1
        c.overlay("sheet", modal=true, fn() {
          c.capped("body", 300.0, fn() {
            c.editor("query", placeholder="Query") |> ignore
            c.box(w=Px(200.0), h=Px(400.0), fn() {  }) |> ignore
          }) |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() {
    open.set(true)
    root.after_event_action(fn() { probe_old_layer(host.val.unwrap()) })
  })
  let built_at_event = built.val
  let reasons : Array[String] = []
  kept_nodes.each(fn(id, part) { reasons.push("\{id}, \{part.named}: \{part.why}, causal=\{part.causal_layer}, n=\{part.n}") })
  t.frame_now()
  assert_eq(built.val, built_at_event, msg="built=\{built.val}, at event=\{built_at_event}, \{reasons}")
  assert_true(t.query(TextField, label="Query") is Some(_))
}

///|
test "an event-staged old editor takes text before its first frame" {
  let open = @signals.signal(false)
  let field = Field::new()
  let host : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0, keyboard=true)
  set_view_app(fn(root) {
    old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = old(layer, fn(c) {
        c.overlay("sheet", modal=true, fn() {
          c.editor("query", field~, placeholder="Query") |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() {
    open.set(true)
    root.after_event_action(fn() { probe_old_layer(host.val.unwrap()) })
  })
  assert_true(t.ime().0, msg="the newly focused old field owns the input method")
  t.text_told("hello", t.time())
  assert_eq(field.text(), "hello")
  t.frame_now()
  assert_eq(field.text(), "hello")
}

///|
test "an event-staged old layer exposes its accessible press before its first frame" {
  let open = @signals.signal(false)
  let host : Ref[@view.View?] = Ref(None)
  let presses = Ref(0)
  let actions = Ref(0)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = old(layer, fn(c) {
        c.overlay("sheet", modal=true, initial_focus=0, fn() {
          let id = 1234567
          let i = c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  })
          c.semantics(i, Button, id~, label="Staged button", actions=[Activate])
          c.on_press(id, fn() { presses.val += 1 })
          if c.action_asked(id, Activate) { actions.val += 1 }
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() {
    open.set(true)
    root.after_event_action(fn() { probe_old_layer(host.val.unwrap()) })
  })
  let target = t.query(Button, label="Staged button")
  assert_true(target is Some(_), msg="the staged portal must be available to accessibility")
  g().ask_action(target.unwrap().id, Activate)
  assert_eq(presses.val, 1)
  root.tree.event(t.time(), fn() { open.set(false) })
  assert_true(t.query(Button, label="Staged button") is None, msg="a removed layer cannot remain accessible")
  g().ask_action(target.unwrap().id, Activate)
  assert_eq(presses.val, 1, msg="a removed layer cannot receive a stale accessibility action")
  root.tree.event(t.time(), fn() {
    open.set(true)
    root.after_event_action(fn() { probe_old_layer(host.val.unwrap()) })
  })
  t.frame_now()
  assert_eq(presses.val, 1)
  assert_eq(actions.val, 0, msg="the old layer's queued action cannot reach its replacement")
}

///|
test "an old modal reopened without a frame gives and returns focus each time" {
  let open = @signals.signal(false)
  let page = Field::new()
  let modal = Field::new()
  let host : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0, keyboard=true)
  set_view_app(fn(root) {
    old(root, fn(c) { c.editor("page", field=page, placeholder="Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    let v = old(root, fn(c) {
      if open.get() {
        c.overlay("sheet", modal=true, fn() { c.editor("modal", field=modal, placeholder="Modal") |> ignore }) |> ignore
      }
    })
    v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
    host.val = Some(v)
  })
  t.draw()
  host_event(fn() { g().focus_field(page) })
  let page_focus = g().focused_id()
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() { open.set(true); probe_old_layer(host.val.unwrap()) })
  let modal_focus = g().focused_id()
  assert_true(modal_focus != 0 && modal_focus != page_focus)
  root.tree.event(t.time(), fn() { open.set(false); probe_old_layer(host.val.unwrap()) })
  assert_eq(g().focused_id(), page_focus)
  root.tree.event(t.time(), fn() { open.set(true); probe_old_layer(host.val.unwrap()) })
  assert_eq(g().focused_id(), modal_focus)
}

///|
test "an event-staged old modal returns focus on system back before its first frame" {
  let open = @signals.signal(false)
  let field = Field::new()
  let closed = Ref(0)
  let host : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0, keyboard=true, platform=2)
  set_view_app(fn(root) {
    old(root, fn(c) { c.editor("page", field~, placeholder="Page field") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = old(layer, fn(c) {
        c.with_dismissed(fn(_) { closed.val += 1; open.set(false) }, fn() {
          c.overlay("sheet", modal=true, fn() {
            let id = c.id("sheet button")
            c.box(w=Px(100.0), h=Px(40.0), id~, label="Sheet button", fn() {  }) |> ignore
            c.focusable(id)
          }) |> ignore
        })
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  host_event(fn() { g().focus_field(field) })
  assert_true(t.ime().0)
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() {
    open.set(true)
    root.after_event_action(fn() { probe_old_layer(host.val.unwrap()) })
  })
  assert_false(t.ime().0)
  t.back_raw(2, 0.0, t.time())
  assert_eq(closed.val, 1)
  assert_eq(t.backs_out(), 0)
  assert_true(t.ime().0, msg="the previous field regains the input method")
  t.text_told("ok", t.time())
  assert_eq(field.text(), "ok")
}

///|
test "a refreshed staged layer leaves exactly one system back for the page" {
  let open = @signals.signal(false)
  let closed = Ref(0)
  let page_backs = Ref(0)
  let host : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0, platform=2)
  set_view_app(fn(root) {
    root.takes_back(fn() { page_backs.val += 1 }) |> ignore
    old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = old(layer, fn(c) {
        c.with_dismissed(fn(_) { closed.val += 1; open.set(false) }, fn() {
          c.overlay("sheet", modal=true, initial_focus=0, fn() {
            let id = c.id("sheet button")
            c.box(w=Px(100.0), h=Px(40.0), id~, label="Sheet button", fn() {  }) |> ignore
            c.on_press(id, fn() {  })
          }) |> ignore
        })
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() {
    open.set(true)
    root.after_event_action(fn() { probe_old_layer(host.val.unwrap()) })
  })
  let pause_between_actions_ms = 50.0
  t.advance(pause_between_actions_ms)
  t.touch(0, 20.0, 20.0)
  t.touch(2, 20.0, 20.0)
  t.back_raw(2, 0.0, t.time())
  t.back_raw(2, 0.0, t.time())
  assert_eq((closed.val, page_backs.val, t.backs_out()), (1, 1, 0))
}

///|
test "programmatically removing a staged modal restores page hits before a frame" {
  let open = @signals.signal(false)
  let page_hits = Ref(0)
  let host : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(40.0)))
        .on_press(fn() { page_hits.val += 1 }) |> ignore
    }) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = old(layer, fn(c) {
        c.overlay("sheet", modal=true, initial_focus=0, fn() {
          c.box(w=Px(100.0), h=Px(40.0), fn() {  }) |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() {
    open.set(true)
    root.after_event_action(fn() { probe_old_layer(host.val.unwrap()) })
  })
  root.tree.event(t.time(), fn() { open.set(false) })
  t.touch(0, 20.0, 20.0)
  t.touch(2, 20.0, 20.0)
  assert_eq(page_hits.val, 1)
}

///|
test "an old staged modal removed by layout returns the previous field's focus" {
  let shown = @signals.signal(false)
  let page = Field::new()
  let modal = Field::new()
  let host : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0, keyboard=true)
  set_view_app(fn(root) {
    old(root, fn(c) { c.editor("page", field=page, placeholder="Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.box(fn(b) {
      b.over(Is(true)).height(Is(Some(844.0))).layout_box(By(fn() { shown.get() }), fn(l, visible) {
        if visible {
          let owner = l.child("legacy", fn(v) {
            let content = old(v, fn(c) {
              c.overlay("modal", modal=true, fn() { c.editor("modal", field=modal, placeholder="Modal") |> ignore }) |> ignore
            })
            content.width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
            host.val = Some(content)
          })
          l.measure(owner, l.width) |> ignore
          l.place(owner, 0.0, 0.0)
        }
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  host_event(fn() { g().focus_field(page) })
  assert_true(t.ime().0)
  let page_focus = g().focused_id()
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() { shown.set(true); root.laid_size() |> ignore })
  root.tree.event(t.time(), fn() { probe_old_layer(host.val.unwrap()) })
  t.text_told("modal", t.time())
  assert_eq(modal.text(), "modal")
  let last = g().last_layers.map(fn(l) { (l.id, l.owner == Some(host.val.unwrap().id()), g().layer_return.get(l.id)) })
  root.tree.event(t.time(), fn() {
    shown.set(false)
    root.laid_size() |> ignore
  })
  assert_false(host.val.unwrap().alive(), msg="the layout removed the old island")
  assert_eq(g().focused_id(), page_focus, msg="old modal should return focus: page=\{page_focus}, now=\{g().focused_id()}, layers=\{last}")
  assert_true(t.ime().0, msg="page field regains the input method")
  t.text_told("page", t.time())
  assert_eq(page.text(), "page")
}

///|
test "an event-staged modal layer takes focus and touch before a frame" {
  let open = @signals.signal(false)
  let hits = Ref(0)
  let target = Ref(0)
  let host : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0, keyboard=true)
  set_view_app(fn(root) {
    old(root, fn(c) { c.editor("page", placeholder="Page field") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = old(layer, fn(c) {
        c.overlay("sheet", modal=true, fn() {
          let id = c.id("sheet button")
          target.val = id
          c.box(w=Px(100.0), h=Px(40.0), id~, label="Sheet button", fn() {  }) |> ignore
          c.focusable(id)
          c.on_press(id, fn() { hits.val += 1 })
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() {
    open.set(true)
    root.after_event_action(fn() { probe_old_layer(host.val.unwrap()) })
  })
  assert_eq(g().focus, target.val, msg="modal takes focus before a frame")
  t.touch(0, 20.0, 20.0)
  t.touch(2, 20.0, 20.0)
  assert_eq(hits.val, 1, msg="new layer takes a press before a frame")
}

///|
test "an event-staged old sheet resolves its own natural-height readback" {
  let open = @signals.signal(false)
  let asked = Ref(0.0)
  let body_calls = Ref(0)
  let tells = Ref(0)
  let host : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = old(layer, fn(c) {
        c.tell("sheet created", fn() { tells.val += 1 })
        let fit = c.id("sheet fit")
        asked.val = c.laid_size(fit).map(fn(x) { x.1 }).unwrap_or(422.0)
        c.overlay("sheet", modal=true, initial_focus=0, fn() {
          body_calls.val += 1
          c.box(w=Px(200.0), h=Px(120.0), id=fit, fn() {  }) |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() {
    open.set(true)
    root.after_event_action(fn() { probe_old_layer(host.val.unwrap()) })
  })
  assert_eq(asked.val, 120.0, msg="the sheet's requested height, body calls=\{body_calls.val}")
  assert_eq(tells.val, 0)
  t.frame_now()
  assert_eq(tells.val, 1, msg="an event-staged tell is not repeated by the following frame; got \{tells.val}")
}

///|
test "a staged layer removed before any frame must not leak an unseen tell" {
  let open = @signals.signal(false)
  let told = Ref(0)
  let host : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    old(root, fn(c) { c.text("Page") |> ignore }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      let v = old(layer, fn(c) {
        c.tell("unseen", fn() { told.val += 1 })
        c.overlay("sheet", modal=true, initial_focus=0, fn() {
          c.box(w=Px(200.0), h=Px(120.0), fn() {  }) |> ignore
        }) |> ignore
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  let root = view_tree().unwrap().root()
  root.tree.event(t.time(), fn() {
    open.set(true)
    root.after_event_action(fn() { probe_old_layer(host.val.unwrap()) })
  })
  root.tree.event(t.time(), fn() { open.set(false) })
  t.frame_now()
  assert_eq(told.val, 0, msg="an unshown, removed layer's build must not tell")
}
