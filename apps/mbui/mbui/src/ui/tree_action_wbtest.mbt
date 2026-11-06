// A node's declared accessibility actions, from what the host reads out through Ctx::ask_action to its callback.

///|
let said_action_step_ms : Double = 50.0

///|
test "declared actions are read out and taken at each request's moment, with no frame between" {
  let more = @signals.signal(true)
  let seen : Array[(@view.Action, Double)] = []
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.set_a11y(true)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(80.0))).height(Is(Some(40.0)))
      .says(By(fn() {
        Some(@view.said(Slider, label="Volume", actions=if more.get() { [Increment, Decrement] } else { [Decrement] }))
      }))
      .on_action(fn(a) { seen.push((a, v.cause_at())) })
      |> ignore
    }) |> ignore
  })
  t.draw()
  let t0 = t.time()
  let s = t.get(Slider, label="Volume")
  assert_eq(s.actions, [Increment, Decrement])
  let lines = t.a11y_said().split("\n").map(fn(l) { l.split("\u{1F}").map(fn(v) { v.to_string() }).to_array() }).to_array()
  let slider = lines.filter(fn(f) { f.length() == 16 && f[3] == "Slider" && f[9] == "Volume" })
  assert_eq(slider.length(), 1)
  assert_eq(slider[0][15], "id")
  t.advance(said_action_step_ms)
  g().ask_action(s.id, Increment)
  t.advance(said_action_step_ms)
  g().ask_action(s.id, Decrement)
  assert_eq(seen, [(Increment, t0 + said_action_step_ms), (Decrement, t0 + 2.0 * said_action_step_ms)])
  // The declaration changed, but no frame has been drawn. An old request is refused; the remaining action still runs.
  more.set(false)
  g().ask_action(s.id, Increment)
  g().ask_action(s.id, Decrement)
  assert_eq(seen.length(), 3)
  assert_eq(seen[2].0, Decrement)
}

///|
/// The node changes whether it takes input at a due moment before the request, with no frame in between.
fn action_after_timed_flip(first : Bool) -> Int raise {
  let taking = @signals.signal(first)
  let count = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  let t0 = t.time()
  set_view_app(fn(root) {
    root.box(fn(v) {
      v.presses(By(fn() { taking.get() }))
      .says(Is(Some(@view.said(Slider, label="Volume", actions=[Increment]))))
      .on_action(fn(_) { count.val += 1 }) |> ignore
      v.at_moment(t0 + said_action_step_ms, fn() { taking.set(!first) }) |> ignore
    }) |> ignore
  })
  t.draw()
  let id = t.get(Slider, label="Volume").id
  t.advance(t0 + 2.0 * said_action_step_ms - t.time())
  g().ask_action(id, Increment)
  count.val
}

///|
test "a due change before an accessibility request is taken at its moment, with no frame" {
  assert_eq(action_after_timed_flip(true), 0)
  assert_eq(action_after_timed_flip(false), 1)
}

///|
test "a declared action is refused while disabled, hidden, unsaid or under a tree modal, without a frame" {
  let taking = @signals.signal(true)
  let off = @signals.signal(false)
  let hidden = @signals.signal(false)
  let says = @signals.signal(true)
  let modal = @signals.signal(false)
  let count = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(holder) {
      holder.presses(By(fn() { taking.get() })).hides(By(fn() { hidden.get() })) |> ignore
      holder.box(fn(v) {
        v.width(Is(Some(80.0))).height(Is(Some(40.0)))
        .turned_off(By(fn() { off.get() }))
        .says(By(fn() { if says.get() { Some(@view.said(Slider, label="Volume", actions=[Increment])) } else { None } }))
        .on_action(fn(_) { count.val += 1 })
        |> ignore
      }) |> ignore
    }) |> ignore
    root.show(fn() { modal.get() }, fn(v) { v.over(Is(true)).modal(Is(true)) |> ignore })
  })
  t.draw()
  let id = t.get(Slider, label="Volume").id
  taking.set(false)
  g().ask_action(id, Increment)
  taking.set(true)
  off.set(true)
  g().ask_action(id, Increment)
  off.set(false)
  hidden.set(true)
  g().ask_action(id, Increment)
  hidden.set(false)
  says.set(false)
  g().ask_action(id, Increment)
  says.set(true)
  modal.set(true)
  g().ask_action(id, Increment)
  assert_eq(count.val, 0)
  modal.set(false)
  g().ask_action(id, Increment)
  assert_eq(count.val, 1)
}

///|
test "a removed node's id cannot act on its replacement" {
  let first = @signals.signal(true)
  let second = @signals.signal(false)
  let seen : Array[String] = []
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.show(fn() { first.get() }, fn(v) {
      v.says(Is(Some(@view.said(Slider, label="First", actions=[Increment]))))
      .on_action(fn(_) { seen.push("first") }) |> ignore
    })
    root.show(fn() { second.get() }, fn(v) {
      v.says(Is(Some(@view.said(Slider, label="Second", actions=[Increment]))))
      .on_action(fn(_) { seen.push("second") }) |> ignore
    })
  })
  t.draw()
  let id = t.get(Slider, label="First").id
  first.set(false)
  second.set(true)
  g().ask_action(id, Increment)
  assert_eq(seen, [])
  let next = t.get(Slider, label="Second").id
  assert_true(next != id)
  g().ask_action(next, Increment)
  assert_eq(seen, ["second"])
}

///|
test "an old frame modal blocks a tree node's action until closed" {
  let modal = @signals.signal(false)
  let count = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v.says(Is(Some(@view.said(Slider, label="Volume", actions=[Increment]))))
      .on_action(fn(_) { count.val += 1 }) |> ignore
    }) |> ignore
    root.box(fn(v) {
      old(v, fn(c) {
        if modal.get() {
          c.overlay("modal", modal=true, fn() { c.text("Modal") |> ignore }) |> ignore
        }
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let id = t.get(Slider, label="Volume").id
  modal.set(true)
  t.draw()
  g().ask_action(id, Increment)
  assert_eq(count.val, 0)
  modal.set(false)
  t.draw()
  g().ask_action(id, Increment)
  assert_eq(count.val, 1)
}

///|
test "built-in press and focus take precedence and declared SetText matches its request's words" {
  let pressed = Ref(0)
  let seen : Array[@view.Action] = []
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v.focusable(Is(true)).on_press(fn() { pressed.val += 1 })
      .says(Is(Some(@view.said(Button, label="Control", actions=[Activate, Focus, SetText("")]))))
      .on_action(fn(a) { seen.push(a) }) |> ignore
    }) |> ignore
  })
  t.draw()
  let s = t.get(Button, label="Control")
  assert_eq(s.actions, [Activate, Focus, SetText("")])
  g().ask_action(s.id, Activate)
  g().ask_action(s.id, Focus)
  g().ask_action(s.id, SetText("hello"))
  assert_eq(pressed.val, 1)
  assert_eq(t.focused().map(fn(s) { s.id }), Some(s.id))
  assert_eq(seen, [SetText("hello")])
}

///|
test "a tree field advertises SetText and refuses it while its holder is disabled or hidden" {
  let taking = @signals.signal(true)
  let hidden = @signals.signal(false)
  let f = Field::new(text="draft")
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(200.0))).presses(By(fn() { taking.get() })).hides(By(fn() { hidden.get() })) |> ignore
      field(v, f, font_size=10.0, max_lines=1) |> ignore
    }) |> ignore
  })
  t.draw()
  let s = t.get(TextField)
  assert_true(s.actions.contains(SetText("")))
  taking.set(false)
  g().ask_action(s.id, SetText("disabled"))
  taking.set(true)
  hidden.set(true)
  g().ask_action(s.id, SetText("hidden"))
  assert_eq(f.text(), "draft")
  hidden.set(false)
  g().ask_action(s.id, SetText("allowed"))
  assert_eq(f.text(), "allowed")
}
