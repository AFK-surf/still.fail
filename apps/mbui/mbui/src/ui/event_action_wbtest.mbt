///|
test "an old island's input tells a size-based event after its build" {
  let tall = @signals.signal(120.0)
  let open = @signals.signal(true)
  let sink = @signals.signal(0.0)
  let measured = Ref(0.0)
  let sheet : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    let extent : Ref[@view.View?] = Ref(None)
    root.box(fn(held) {
      held.height(Is(Some(40.0))) |> ignore
      old(held, fn(c) {
        let id = c.id("close")
        if c.clicked(id) {
          c.tell_input("close", fn() {
            root.event_action(fn() {
              measured.val = extent.val.unwrap().laid_size().1
              sink.set(measured.val)
              open.set(false)
            })
          })
        }
        c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  }) |> ignore
      }).height(Is(Some(40.0))) |> ignore
    }) |> ignore
    root.show(fn() { open.get() }, leave_by=fn(v) { sink.get() }, fn(v) {
      sheet.val = Some(v)
      extent.val = Some(v)
      v.height(By(fn() { Some(tall.get()) })) |> ignore
    })
  })
  t.draw()
  tall.set(200.0)
  t.press_at(20.0, 20.0)
  t.release(20.0, 20.0)
  t.draw()
  assert_eq(measured.val, 200.0)
  assert_false(open.get())
  assert_eq(sheet.val.unwrap().leaves_at(), t.time() + 200.0)
}

///|
test "an old island's accessibility action tells a size-based event once" {
  let tall = @signals.signal(120.0)
  let measured : Array[Double] = []
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    let extent = root.box(fn(v) {
      v.over(Is(true)).height(By(fn() { Some(tall.get()) })) |> ignore
    })
    old(root, fn(c) {
      let id = c.id("accessible snapshot")
      if c.action_asked(id, Activate) {
        c.tell_input("accessible snapshot", fn() {
          root.event_action(fn() { measured.push(extent.laid_size().1) })
        })
      }
      let node = c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  })
      c.semantics(node, Button, id~, label="Snapshot", actions=[Activate])
    }).height(Is(Some(40.0))) |> ignore
  })
  t.draw()
  let id = t.get(Button, label="Snapshot").id
  tall.set(200.0)
  assert_false(inputs_taken.val)
  t.post(@hostapi.a11y_channel, "{\"id\":\{id},\"action\":\"activate\"}")
  t.draw()
  t.draw()
  assert_eq(measured, [200.0])
}

///|
test "an old island's accessibility press snapshots at the action's moment without a frame" {
  let tall = @signals.signal(120.0)
  let got : Array[(Double, Double)] = []
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0, time=0.0)
  set_view_app(fn(root) {
    let extent = root.box(fn(v) {
      v.over(Is(true)).height(By(fn() { Some(tall.get()) })) |> ignore
    })
    old(root, fn(c) {
      let id = c.id("accessible press")
      c.on_press(id, fn() {
        root.event_action(fn() { got.push((root.cause_at(), extent.laid_size().1)) })
      })
      let node = c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  })
      c.semantics(node, Button, id~, label="Snapshot", actions=[Activate])
    }).height(Is(Some(40.0))) |> ignore
  })
  t.draw()
  let id = t.get(Button, label="Snapshot").id
  tall.set(200.0)
  let request_delay_ms = 30.0
  let no_frame_after_request_ms = 100.0
  let at = t.time() + request_delay_ms
  t.advance(request_delay_ms)
  g().ask_action(id, Activate)
  assert_eq(got, [(at, 200.0)])
  t.advance(no_frame_after_request_ms)
  t.draw()
  assert_eq(got, [(at, 200.0)])
}

///|
test "an old island's host accessibility press snapshots once when its message is delivered" {
  let tall = @signals.signal(120.0)
  let got : Array[(Double, Double)] = []
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    let extent = root.box(fn(v) {
      v.over(Is(true)).height(By(fn() { Some(tall.get()) })) |> ignore
    })
    old(root, fn(c) {
      let id = c.id("host accessible press")
      c.on_press(id, fn() {
        root.event_action(fn() { got.push((root.cause_at(), extent.laid_size().1)) })
      })
      let node = c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  })
      c.semantics(node, Button, id~, label="Snapshot", actions=[Activate])
    }).height(Is(Some(40.0))) |> ignore
  })
  t.draw()
  let id = t.get(Button, label="Snapshot").id
  tall.set(200.0)
  t.post(@hostapi.a11y_channel, "{\"id\":\{id},\"action\":\"activate\"}")
  t.draw()
  assert_eq(got.length(), 1)
  assert_eq(got[0].1, 200.0)
  t.draw()
  assert_eq(got.length(), 1)
}

///|
test "an old accessibility press cannot activate a disabled or covered widget" {
  let covered = @signals.signal(false)
  let seen : Array[String] = []
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      for (key, disabled) in [("enabled", false), ("disabled", true)] {
        let id = c.id(key)
        c.on_press(id, fn() { seen.push(key) })
        let node = c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  })
        c.semantics(node, Button, id~, label=key, disabled~, actions=[Activate])
      }
    }).height(Is(Some(80.0))) |> ignore
    root.show(fn() { covered.get() }, fn(v) { v.over(Is(true)).modal(Is(true)) |> ignore })
  })
  t.draw()
  let enabled = t.get(Button, label="enabled").id
  let disabled = t.get(Button, label="disabled").id
  g().ask_action(disabled, Activate)
  g().ask_action(enabled, Increment)
  g().ask_action(enabled, Activate)
  covered.set(true)
  g().ask_action(enabled, Activate)
  covered.set(false)
  g().ask_action(enabled, Activate)
  assert_eq(seen, ["enabled", "enabled"])
}

///|
test "an action requested by an old build is not a host input" {
  let first = Ref(true)
  let presses = Ref(0)
  let requests = Ref(0)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      let id = c.id("synthetic action")
      c.on_press(id, fn() { presses.val += 1 })
      if first.val {
        first.val = false
        c.ask_action(id, Activate)
      }
      if c.action_asked(id, Activate) { requests.val += 1 }
      let node = c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  })
      c.semantics(node, Button, id~, label="Synthetic", actions=[Activate])
    }).height(Is(Some(40.0))) |> ignore
  })
  t.draw()
  assert_false(inputs_taken.val)
  assert_eq(presses.val, 0)
  t.draw()
  assert_eq((presses.val, requests.val), (0, 1))
}

///|
test "an action requested by a normal frame message is not a host input" {
  let target = Ref(0)
  let presses = Ref(0)
  let requests = Ref(0)
  let channel = "test/frame-action"
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  on_message(channel, fn(_, _) { g().ask_action(target.val, Activate) })
  set_view_app(fn(root) {
    old(root, fn(c) {
      let id = c.id("message action")
      target.val = id
      c.on_press(id, fn() { presses.val += 1 })
      if c.action_asked(id, Activate) { requests.val += 1 }
      let node = c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  })
      c.semantics(node, Button, id~, label="Message", actions=[Activate])
    }).height(Is(Some(40.0))) |> ignore
  })
  t.draw()
  t.post(channel, "{}")
  t.draw()
  assert_false(inputs_taken.val)
  assert_eq((presses.val, requests.val), (0, 1))
  message_handlers.remove(channel) |> ignore
}

///|
test "an old hosted press snapshots both retained sizes at the original input time" {
  let first = @signals.signal(120.0)
  let second = @signals.signal(150.0)
  let got : Ref[(Double, Double, Double)?] = Ref(None)
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0, time=0.0)
  set_view_app(fn(root) {
    let a : @view.View = root.box(fn(v) { v.over(Is(true)).height(By(fn() { Some(first.get()) })) |> ignore })
    let b : @view.View = root.box(fn(v) { v.over(Is(true)).height(By(fn() { Some(second.get()) })) |> ignore })
    old(root, fn(c) {
      let id = c.id("snapshot")
      c.on_press(id, fn() {
        root.event_action(fn() { got.val = Some((root.cause_at(), a.laid_size().1, b.laid_size().1)) })
      })
      c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  }) |> ignore
    }).over(Is(true)) |> ignore
  })
  t.draw()
  first.set(200.0)
  second.set(300.0)
  let host_delivery_delay_ms = 100.0
  t.advance(host_delivery_delay_ms)
  t.touch_at(0, 20.0, 20.0, 30.0)
  t.touch_at(2, 20.0, 20.0, 40.0)
  assert_eq(got.val, Some((40.0, 200.0, 300.0)))
}

///|
test "panic an old build cannot tell an input action without an input" {
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    old(root, fn(c) { c.tell_input("no input", fn() {  }) }) |> ignore
  })
  t.draw()
}

///|
test "panic an old input action cannot read layout inside a computed" {
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    root.box(fn(held) {
      held.height(Is(Some(40.0))) |> ignore
      old(held, fn(c) {
        let id = c.id("close")
        if c.clicked(id) {
          c.tell_input("close", fn() {
            let tracked = @signals.computed(fn(_) {
              root.event_action(fn() { root.laid_size() |> ignore })
              0
            })
            tracked.get() |> ignore
          })
        }
        c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  }) |> ignore
      }).height(Is(Some(40.0))) |> ignore
    }) |> ignore
  })
  t.draw()
  t.press_at(20.0, 20.0)
  t.release(20.0, 20.0)
  t.draw()
}

///|
test "panic a host accessibility press cannot read layout inside a computed" {
  let t = Tester::new(fn(_) {  }, w=390.0, h=844.0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      let id = c.id("accessible computed")
      c.on_press(id, fn() {
        let tracked = @signals.computed(fn(_) {
          root.event_action(fn() { root.laid_size() |> ignore })
          0
        })
        tracked.get() |> ignore
      })
      let node = c.box(w=Px(100.0), h=Px(40.0), id~, fn() {  })
      c.semantics(node, Button, id~, label="Snapshot", actions=[Activate])
    }).height(Is(Some(40.0))) |> ignore
  })
  t.draw()
  let id = t.get(Button, label="Snapshot").id
  t.post(@hostapi.a11y_channel, "{\"id\":\{id},\"action\":\"activate\"}")
  t.draw()
}
