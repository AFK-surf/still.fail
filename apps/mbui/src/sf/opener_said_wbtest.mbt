// What opens a menu or a pick says it is open while that is drawn (Opener: `expanded`), and a toggle says whether it is
// on (`pressed`): what a screen reader says of them, and what a sweep of a screen's switches finds to press in two steps
// (the opener, then each choice it shows not chosen).

///|
/// A choice of three (select_node) and a toggle (toggle_chip_node) in a window wide enough for a pick beside it, what
/// is presented drawn by the window's tree as the app's is.
fn opener_tester(value : @signals.Signal[String], on : @signals.Signal[Bool]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=900.0, h=500.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.padding(Is((20.0, 20.0, 20.0, 20.0))).gap(Is(20.0)) |> ignore
    select_node(root, fn() { value.get() }, fn() { [("a", "甲"), ("b", "乙"), ("c", "丙")] }, fn(v) { value.set(v) }, label=fn() {
      "选"
    })
    toggle_chip_node(root, fn() { "只看" }, fn() { on.get() }, fn() { on.set(!on.get()) }) |> ignore
    @ui.old(root, fn(c) { presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
    presented_nodes(root)
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "an opener says it is open while what it opened is drawn; a toggle says whether it is on" {
  let value = @signals.signal("a")
  let on = @signals.signal(false)
  let t = opener_tester(value, on)
  let opener = fn() { t.semantics().filter(fn(s) { s.role == Button && s.label.has_prefix("选") }) }
  assert_eq(opener().map(fn(s) { (s.label, s.expanded) }), [("选: 甲", Some(false))], msg="shut")
  let (x, y, w, h) = opener()[0].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(opener().map(fn(s) { s.expanded }), [Some(true)], msg="its pick open")
  let items = t.semantics().filter(fn(s) { !s.hidden && (s.role == MenuItemRadio || s.role == MenuItem) })
  assert_eq(
    items.map(fn(s) { (s.label, s.check) }),
    [("甲", Some(@ui.Check::On)), ("乙", Some(@ui.Check::Off)), ("丙", Some(@ui.Check::Off))],
    msg="its choices, the chosen one on: \{Repr(items)}",
  )
  let (x, y, w, h) = items[1].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq((value.get(), opener().map(fn(s) { (s.label, s.expanded) })), ("b", [("选: 乙", Some(false))]), msg="乙 chosen, shut")
  let chip = fn() { t.semantics().filter(fn(s) { s.role == Button && s.label == "只看" }).map(fn(s) { s.pressed }) }
  assert_eq(chip(), [Some(false)], msg="the toggle off")
  let c = t.semantics().filter(fn(s) { s.label == "只看" })[0].rect
  t.tap(c.0 + c.2 / 2.0, c.1 + c.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(chip(), [Some(true)], msg="the toggle on")
}
