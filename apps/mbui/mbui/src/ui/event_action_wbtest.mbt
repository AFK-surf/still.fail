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
  g().ask_action(id, Activate)
  t.draw()
  t.draw()
  assert_eq(measured, [200.0])
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
