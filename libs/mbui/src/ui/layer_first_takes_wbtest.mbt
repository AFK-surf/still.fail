// A modal layer of the tree's that gives the focus as it opens to the first of what it holds that takes it and says
// what it asks for (View::focus_opens_first's `takes`): past a button before it, to one made only as the layout came to
// it (View::by_room), in the pass that opened the layer; none it holds saying so, its own ground; asked nothing, the
// first that takes it, as ever.

///|
/// A window with nothing on it to take the focus; while `open`, a modal layer giving the focus as it opens, holding a
/// button "按钮" and, made as its room comes to it, a field-like node "接字" (said a TextField); `takes` what the layer
/// asks of what it gives it to (none: anything that takes it), `field` whether "接字" is made.
fn takes_tester(open : @signals.Signal[Bool], takes : ((@view.Said) -> Bool)?, field : Bool) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(h) { h.grow(Is(1.0)) |> ignore }) |> ignore
    root.show(fn() { open.get() }, fn(l) {
      l.over(Is(true)).stacked(Is(2)).modal(Is(true)).presses(Is(true)).focusable(Is(true), keys=0, tab=false) |> ignore
      l.box(fn(b) {
        b
        .width(Is(Some(80.0)))
        .height(Is(Some(30.0)))
        .presses(Is(true))
        .focusable(Is(true))
        .on_press(fn() {  })
        .says(Is(Some(@view.said(Button, label="按钮"))))
        |> ignore
      })
      |> ignore
      l.by_room(fn(held, _room) {
        if field {
          held.box(fn(f) {
            f
            .width(Is(Some(80.0)))
            .height(Is(Some(30.0)))
            .presses(Is(true))
            .focusable(Is(true))
            .on_press(fn() {  })
            .says(Is(Some(@view.said(TextField, label="接字"))))
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      match takes {
        Some(f) => l.focus_opens_first(takes=f) |> ignore
        None => l.focus_opens_first() |> ignore
      }
    })
  })
  t
}

///|
fn takes_focused(t : Tester) -> String {
  t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none")
}

///|
/// What has the focus once the layer has opened (in the pass that opened it, and a frame on).
fn takes_said(takes : ((@view.Said) -> Bool)?, field : Bool) -> (String, String) {
  let open = @signals.signal(false)
  let t = takes_tester(open, takes, field)
  t.draw()
  open.set(true)
  t.draw()
  let opened = takes_focused(t)
  t.draw()
  (opened, takes_focused(t))
}

///|
let takes_field : (@view.Said) -> Bool = fn(s) { s.role == TextField }

///|
test "a layer giving the focus to the first that says what it asks for: past a button, to the one made as the layout came to it, in the pass it opened in" {
  assert_eq(takes_said(Some(takes_field), true), ("TextField 接字", "TextField 接字"))
}

///|
test "a layer giving the focus to the first that says what it asks for, holding none that does: none of what it holds, its own ground" {
  let (opened, after) = takes_said(Some(takes_field), false)
  assert_false(opened.has_prefix("Button") || opened.has_prefix("TextField"), msg=opened)
  assert_false(after.has_prefix("Button") || after.has_prefix("TextField"), msg=after)
}

///|
test "a layer giving the focus to the first that takes it, asked nothing: its first, the button, as ever" {
  assert_eq(takes_said(None, true), ("Button 按钮", "Button 按钮"))
}
