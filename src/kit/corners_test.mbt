// still.fail's corner rule (ui/corners.mbt) over the components drawn open: what lies in a rounded thing's corner is
// as far from both its edges, and concentric.

///|
test "corners: a dialog, an alert dialog" {
  let t = @ui.Tester::new(fn(c) {
    dialog(c, "d", true, "Edit profile", description="How others see you.", fn() {
      text_field(c, "name", placeholder="Name") |> ignore
    })
    |> ignore
  })
  t.settle() |> ignore
  assert_eq(t.corner_faults(), [])
  let t = @ui.Tester::new(fn(c) {
    alert_dialog(c, "a", true, "Delete the chat?", "Delete", description="It cannot be undone.", danger=true) |> ignore
  })
  t.settle() |> ignore
  assert_eq(t.corner_faults(), [])
}

///|
test "corners: a menu, a select's list, a popover, a tooltip" {
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=8.0, pad=20.0, fn() {
      let tr = button(c, "File", key="file")
      dropdown_menu(c, "m", true, tr.id, [
        menu_label("File"),
        menu_item("new", label="New tab", shortcut="⌘T"),
        menu_separator(),
        menu_check("bar", true, label="Show bookmarks"),
      ])
      |> ignore
    })
    |> ignore
  })
  t.settle() |> ignore
  t.press("Down")
  assert_eq(t.corner_faults(), [])
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=20.0, fn() {
      let tr = button(c, "Filters", key="f")
      popover(c, "p", true, tr.id, fn() { c.text("Filters") |> ignore }) |> ignore
      tooltip(c, "tip", tr.id, "Words") |> ignore
    })
    |> ignore
  })
  t.settle() |> ignore
  t.tab()
  t.settle() |> ignore
  assert_eq(t.corner_faults(), [])
}

///|
test "corners: toasts, fields, segmented choices, a toolbar" {
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=12.0, pad=20.0, fn() {
      password_field(c, "pw", false, placeholder="Password") |> ignore
      toggle_group(c, "g", [item("a", label="Left"), item("b", label="Right")], ["a"]) |> ignore
      toolbar(c, "tb", fn() {
        toggle(c, "B", true, key="b") |> ignore
        toggle(c, "I", false, key="i") |> ignore
      })
      tabs(c, "tabs", [item("x", label="One"), item("y", label="Two")], "x", fn(_) {  }) |> ignore
    })
    |> ignore
    toaster(c, "toasts", [toast("a", "Saved"), toast("b", "Sent", description="To the team", action="Undo")]) |> ignore
  })
  t.settle() |> ignore
  // pointed at: the password's button shows its ground
  let (x, y, w, h) = t.get(@ui.Button, label="显示").rect
  t.move(x + w / 2.0, y + h / 2.0)
  assert_eq(t.corner_faults(), [])
}
