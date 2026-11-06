///|
test "an old callback can change to a build-time click without retaining the callback" {
  let callback = @signals.signal(true)
  let shown = @signals.signal(true)
  let side = @signals.signal(0)
  let callback_count = Ref(0)
  let bool_count = Ref(0)
  let target = Ref(0)
  let builds = Ref(0)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(parent) {
      old(parent, fn(c) {
        side.get() |> ignore
        let part = c.id("kept part")
        c.part_nodes(part, "part", fn() {
          builds.val += 1
          let id = c.id("target")
          target.val = id
          c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  }) |> ignore
          if callback.get() {
            c.on_press(id, fn() { callback_count.val += 1 })
          } else if c.clicked(id) {
            bool_count.val += 1
          }
        }, true, own=true)
      }).height(Is(Some(40.0))) |> ignore
    })
  })
  t.draw()
  side.set(1)
  t.draw()
  t.touch(0, 20.0, 20.0)
  t.touch(2, 20.0, 20.0)
  t.draw()
  assert_eq(callback_count.val, 1)
  callback.set(false)
  t.draw()
  t.touch(0, 20.0, 20.0)
  t.touch(2, 20.0, 20.0)
  t.draw()
  assert_eq((callback_count.val, bool_count.val), (1, 1))
  assert_false(made_presses.contains(target.val))
  callback.set(true)
  t.draw()
  t.touch(0, 20.0, 20.0)
  t.touch(2, 20.0, 20.0)
  t.draw()
  assert_eq((callback_count.val, bool_count.val), (2, 1))
  shown.set(false)
  assert_false(made_presses.contains(target.val))
}

///|
test "an old focused callback takes Enter and Space at each input without repeating" {
  let immediate = @signals.signal(true)
  let seen : Array[(Int, Double)] = []
  let from_bool = Ref(0)
  let tree_root : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0, keyboard=true, time=0.0)
  set_view_app(fn(root) {
    tree_root.val = Some(root)
    old(root, fn(c) {
      let id = c.id("key target")
      let n = c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  })
      c.semantics(n, Button, id~, label="Key target", actions=[Activate, Focus])
      c.focusable(id, node=n)
      if immediate.get() {
        c.on_press(id, fn() { seen.push((1, tree_root.val.unwrap().cause_at())) })
      } else if c.clicked(id) {
        from_bool.val += 1
      }
    }).height(Is(Some(40.0))) |> ignore
  })
  t.draw()
  t.act(Button, Focus, label="Key target")
  let base = t.time()
  let delivery_delay_ms = 100.0
  t.advance(delivery_delay_ms)
  t.key_told(key_space, 0, base + 20.0)
  t.key_told(key_enter, 0, base + 30.0)
  assert_eq(seen, [(1, base + 20.0), (1, base + 30.0)])
  t.frame_at(t.time())
  assert_eq(seen.length(), 2)
  immediate.set(false)
  t.draw()
  t.key_told(key_space, 0, t.time())
  assert_eq(from_bool.val, 0)
  t.draw()
  assert_eq((seen.length(), from_bool.val), (2, 1))
}

///|
test "old focus navigation precedes an activation without a frame" {
  let seen : Array[String] = []
  let t = Tester::new(fn(c) {
    for name in ["First", "Second"] {
      let id = c.id(name)
      let n = c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  })
      c.semantics(n, Button, id~, label=name, actions=[Activate, Focus])
      c.focusable(id, node=n)
      c.on_press(id, fn() { seen.push(name) })
    }
  }, w=390.0, h=844.0, keyboard=true)
  t.draw()
  t.act(Button, Focus, label="First")
  t.key_told(key_tab, 0, t.time())
  t.key_told(key_space, 0, t.time())
  assert_eq(seen, ["Second"])
  t.draw()
  assert_eq(seen, ["Second"])
}

///|
test "a retained modal blocks an old focused callback before a frame" {
  let covered = @signals.signal(false)
  let seen = Ref(0)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0, keyboard=true)
  set_view_app(fn(root) {
    old(root, fn(c) {
      let id = c.id("under")
      let n = c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  })
      c.semantics(n, Button, id~, label="Under", actions=[Activate, Focus])
      c.focusable(id, node=n)
      c.on_press(id, fn() { seen.val += 1 })
    }).height(Is(Some(40.0))) |> ignore
    root.show(fn() { covered.get() }, fn(v) {
      v.over(Is(true)).modal(Is(true)) |> ignore
    })
  })
  t.draw()
  t.act(Button, Focus, label="Under")
  covered.set(true)
  t.key_told(key_enter, 0, t.time())
  assert_eq(seen.val, 0)
  t.draw()
  assert_eq(seen.val, 0)
}

///|
test "a removed old island immediately releases its press callback" {
  let shown = @signals.signal(true)
  let target = Ref(0)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(parent) {
      old(parent, fn(c) {
        let id = c.id("target")
        target.val = id
        c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  }) |> ignore
        c.on_press(id, fn() {  })
      }).height(Is(Some(40.0))) |> ignore
    })
  })
  t.draw()
  assert_true(made_presses.contains(target.val))
  shown.set(false)
  assert_false(made_presses.contains(target.val))
}

///|
test "old drag input callbacks leave with their build and their island" {
  let shown = @signals.signal(true)
  let callback = @signals.signal(true)
  let target = Ref(0)
  let inputs : Array[DragInput] = []
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(parent) {
      old(parent, fn(c) {
        let id = c.id("drag")
        target.val = id
        c.drag_area(id, w=Px(100.0), h=Px(40.0), fn() {  }) |> ignore
        if callback.get() { c.on_drag_input(id, fn(_, phase, _) { inputs.push(phase) }) }
      }).height(Is(Some(40.0))) |> ignore
    })
  })
  t.draw()
  assert_true(ctx_drag_inputs.contains(target.val))
  callback.set(false)
  t.draw()
  assert_false(ctx_drag_inputs.contains(target.val))
  callback.set(true)
  t.draw()
  assert_true(ctx_drag_inputs.contains(target.val))
  t.touch(0, 20.0, 20.0)
  t.touch(1, 20.0, 50.0)
  assert_eq(inputs, [DragMoved])
  shown.set(false)
  assert_false(ctx_drag_inputs.contains(target.val))
  t.touch(2, 20.0, 50.0)
  assert_eq(inputs, [DragMoved])
}

///|
test "remeasuring a staged old island drops a callback no longer built" {
  let shown = @signals.signal(false)
  let callback = @signals.signal(true)
  let host : Ref[@view.View?] = Ref(None)
  let target = Ref(0)
  let hits = Ref(0)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(parent) {
      let v = old(parent, fn(c) {
        let part = c.id("body")
        c.part_nodes(part, "body", fn() {
          let id = c.id("target")
          target.val = id
          c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  }) |> ignore
          if callback.get() { c.on_press(id, fn() { hits.val += 1 }) }
        }, true, own=true, fragment=true)
      })
      v.over(Is(true)).width(Is(Some(390.0))).height(Is(Some(844.0))) |> ignore
      host.val = Some(v)
    })
  })
  t.draw()
  let root = view_tree().unwrap().root()
  root.event_action(fn() {
    shown.set(true)
    root.after_event_action(fn() { probe_old_layer(host.val.unwrap()) })
  })
  assert_true(made_presses.contains(target.val))
  callback.set(false)
  root.event_action(fn() { probe_old_layer(host.val.unwrap()) })
  assert_false(made_presses.contains(target.val))
  t.touch(0, 20.0, 20.0)
  t.touch(2, 20.0, 20.0)
  assert_eq(hits.val, 0)
}
