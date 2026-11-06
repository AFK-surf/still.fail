// The library's empty room as nodes: the old room's layout and its body's own live words and actions.

///|
// kept across runs: a value (no field of it changes)
let empty_test_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true)

///|
test "empty as nodes: 40 in and 6 apart, centred in the room left below a header" {
  let first : Ref[@view.View?] = Ref(None)
  let second : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=600.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(col) {
      col.width_share(Is(1.0)).height_share(Is(1.0)) |> ignore
      col.box(fn(head) { head.height(Is(Some(60.0))) |> ignore }) |> ignore
      empty_node(col, fn(room) {
        first.val = Some(room.box(fn(b) { b.width_share(Is(1.0)).height(Is(Some(18.0))) |> ignore }))
        second.val = Some(room.box(fn(b) { b.width(Is(Some(40.0))).height(Is(Some(30.0))) |> ignore }))
      })
    }) |> ignore
  })
  t.draw()
  assert_eq(first.val.unwrap().rect(), (40.0, 303.0, 310.0, 18.0))
  assert_eq(second.val.unwrap().rect(), (175.0, 327.0, 40.0, 30.0))
  assert_eq(t.old_views_hosted(), 0)
  t.resize(800.0, 600.0)
  t.draw()
  assert_eq(first.val.unwrap().rect(), (40.0, 303.0, 720.0, 18.0))
  assert_eq(second.val.unwrap().rect(), (380.0, 327.0, 40.0, 30.0))
}

///|
test "empty as nodes: live words and action survive resize, accept touch and keyboard, and leave with their room" {
  let words = @signals.signal("No folders")
  let there = @signals.signal(true)
  let releases = Ref(0)
  let pressed = Ref(0)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=600.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(col) {
      col.width_share(Is(1.0)).height_share(Is(1.0)) |> ignore
      col.box(fn(before) {
        before.height(Is(Some(60.0))).presses(Is(true)).focusable(Is(true))
        .says(Is(Some(@view.said(Button, label="Before")))).on_press(fn() {  }) |> ignore
      }) |> ignore
      col.show(fn() { there.get() }, fn(slot) {
        slot.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
        slot.owns(fn() { releases.val += 1 }) |> ignore
        empty_node(slot, fn(room) {
          words_node(room, fn() { words.get() }, fn() { empty_test_words }).words_centered(Is(true)) |> ignore
          button_node(room, fn() { "Add folder" }, fn() { pressed.val += 1 }, tone=Primary) |> ignore
        })
      })
    }) |> ignore
  })
  t.draw()
  t.act(Button, Focus, label="Before")
  t.tab()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Add folder"))
  t.enter()
  t.key(@ui.key_space)
  let (x, y, w, h) = t.get(Button, label="Add folder").rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(pressed.val, 3)
  words.set("The station has no folders")
  t.resize(600.0, 420.0)
  t.draw()
  assert_true(t.find("The station has no folders") is Some(_))
  let (x2, _, w2, _) = t.get(Button, label="Add folder").rect
  assert_true((x2 + w2 / 2.0 - 300.0).abs() < 0.01)
  there.set(false)
  t.draw()
  assert_eq(releases.val, 1)
  assert_true(t.find("Add folder") is None)
  assert_true(t.focused().map(fn(s) { s.label }) != Some("Add folder"))
  assert_eq(t.old_views_hosted(), 0)
}
