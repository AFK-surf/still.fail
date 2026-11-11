// What a screen reader's host is told as the window's tree changes (a11y.mbt): only the nodes that changed, each whole;
// a column scrolled, only the node what it scrolls is held in; one gone, what held it; all of it again where the host
// asks. What the host has after each, held by the Tester to what is read out (Tester::hold_a11y_whole).

///|
/// How long nothing is done (nothing told meanwhile), a wheel's notches are eased over, a glide is looked at under way.
let still_ms : Double = 500.0

///|
let wheel_eased_ms : Double = 1000.0

///|
let glide_under_way_ms : Double = 300.0

///|
/// The nodes an update tells (a11y.mbt's head): each one's role and label, in its order.
fn told_nodes(update : String) -> Array[(String, String)] {
  let out = []
  for l in update.split("\n") {
    let f = l.split("\u{1F}").map(fn(v) { v.to_owned() }).to_array()
    if f.length() >= 17 && f[0] == "N" {
      out.push((f[2], f[8]))
    }
  }
  out
}

///|
/// Whether an update is whole (its head's `full`).
fn told_whole(update : String) -> Bool {
  update.has_prefix("T\u{1F}1")
}

///|
/// A row of three buttons, the middle one named as `name` says, the last there while `last` says.
fn three_buttons(name : @signals.Signal[String], last : @signals.Signal[Bool]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.set_a11y(true)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    let button = fn(v : @view.View, label : () -> String) {
      v
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .on_press(fn() {  })
      .says(By(fn() { Some(@view.said(Button, label=label())) }))
      |> ignore
    }
    root.box(fn(b) { button(b, fn() { "一" }) }) |> ignore
    root.box(fn(b) { button(b, fn() { name.get() }) }) |> ignore
    root.show(fn() { last.get() }, fn(b) { button(b, fn() { "三" }) })
  })
  t.draw()
  t
}

///|
test "the first told whole; one renamed, it alone told" {
  let name = @signals.signal("二")
  let t = three_buttons(name, @signals.signal(true))
  assert_true(t.a11y_said().contains("\u{1F}二\u{1F}"))
  name.set("二二")
  t.draw()
  let u = t.a11y_update()
  assert_false(told_whole(u))
  assert_eq(told_nodes(u), [("Button", "二二")])
}

///|
test "one gone: what held it told, and the host has it no more" {
  let last = @signals.signal(true)
  let t = three_buttons(@signals.signal("二"), last)
  last.set(false)
  t.draw()
  let u = t.a11y_update()
  // (the view's own, holding two now)
  assert_eq(told_nodes(u), [("Group", "")])
  assert_false(t.a11y_said().contains("\u{1F}三\u{1F}"))
  last.set(true)
  t.draw()
  assert_eq(told_nodes(t.a11y_update()), [("Group", ""), ("Button", "三")])
}

///|
test "nothing changed: nothing told" {
  let t = three_buttons(@signals.signal("二"), @signals.signal(true))
  let u = t.a11y_update()
  t.run_for(still_ms)
  assert_eq(t.a11y_update(), u)
}

///|
test "the host asks for all again: told whole" {
  let t = three_buttons(@signals.signal("二"), @signals.signal(true))
  t.post(@hostapi.a11y_channel, "{\"action\":\"resend\"}")
  t.draw()
  let u = t.a11y_update()
  assert_true(told_whole(u))
  assert_eq(told_nodes(u).length(), 4)
}

///|
/// A column of the tree's scrolling as a page's list (Scroll::list) or not, holding 40 buttons 50 high.
fn scrolled_buttons(list : Bool) -> Tester {
  let s = if list { @view.Scroll::list() } else { @view.Scroll::new() }
  let t = Tester::new(fn(_c) {  }, platform=2, w=390.0, h=600.0)
  t.set_a11y(true)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col
      .width(Is(Some(390.0)))
      .height(Is(Some(600.0)))
      .scrolls(s, fn(body) {
        for i in 0..<40 {
          body.box(fn(row) {
            row
            .height(Is(Some(50.0)))
            .on_press(fn() {  })
            .says(Is(Some(@view.said(Button, label="row \{i}"))))
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a column scrolled by the wheel: only what it scrolls is held in told, its rows where they were in it" {
  for list in [false, true] {
    let t = scrolled_buttons(list)
    t.wheel(200.0, 300.0, 120.0)
    t.run_for(wheel_eased_ms)
    let u = t.a11y_update()
    assert_eq(told_nodes(u), [("ScrollArea", "")], msg="list \{list}")
    // (the host's rows where the window draws them: Tester::hold_a11y_whole held it each frame)
    assert_true(t.a11y_said().contains("row 5"))
  }
}

///|
test "a column flung: each frame of its glide told only what it scrolls is held in" {
  let t = scrolled_buttons(true)
  let told : Array[Array[(String, String)]] = []
  t.each_frame(Some(fn() { told.push(told_nodes(t.a11y_update())) }))
  t.drag(200.0, 500.0, 200.0, 200.0, steps=4)
  t.run_for(glide_under_way_ms)
  t.each_frame(None)
  for one in told[told.length() - 3:] {
    assert_eq(one, [("ScrollArea", "")])
  }
}
