// What a test's or a scripted run's steps find of the window's tree (Tester::locate: what shows there, by its words or
// what it draws called by name, View::drawn_as) and which of it a finger reaches (Tester::reachable: what a press there
// goes to is it or holds it, as the tree takes presses then, under what of the old views is over it).

///|
/// A tool 40 by 40 at (20, 20) drawing what `icon` calls it, taking presses while `takes` (counted in `pressed`); an old view over it (a box of
/// its own taking presses, as a sheet over it would) while `covered`.
fn located_tester(
  icon : @signals.Signal[String],
  takes : @signals.Signal[Bool],
  covered : @signals.Signal[Bool],
  pressed : Ref[Int],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=1)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .over(Is(true))
      .offset(Is((20.0, 20.0)))
      .width(Is(Some(40.0)))
      .height(Is(Some(40.0)))
      .presses(By(fn() { takes.get() }))
      .on_press(fn() { pressed.val += 1 })
      |> ignore
      b.box(fn(i) {
        i
        .width(Is(Some(18.0)))
        .height(Is(Some(18.0)))
        .shapes(Is([shape_of([([0.0, 0.0, 18.0, 0.0, 18.0, 18.0], true)], fill=0x333333FFL)]))
        .drawn_as(By(fn() { "/icon/" + icon.get() + "/" }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    root.show(fn() { covered.get() }, fn(o) {
      o.over(Is(true)) |> ignore
      old(o, fn(c) {
        let id = c.id("over it")
        ignore(c.clicked(id))
        c.box(w=Px(300.0), h=Px(200.0), id~, fn() {  }) |> ignore
      }).over(Is(true))
      |> ignore
    })
  })
  t.draw()
  t
}

///|
test "locate and reachable on the window's tree: what a tool draws found by its name and reached where it is drawn; seen but out of reach as it takes no press, or under an old view over it; its old name gone as it draws another" {
  let icon = @signals.signal("copy", same=fn(a, b) { a == b })
  let takes = @signals.signal(true, same=fn(a, b) { a == b })
  let covered = @signals.signal(false, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let t = located_tester(icon, takes, covered, pressed)
  assert_eq(t.locate("icon:copy").length(), 1, msg="seen")
  assert_eq(t.reachable("icon:copy").length(), 1, msg="reached")
  // (a finger where it is reached: the tool pressed)
  let (x, y) = t.reachable("icon:copy")[0]
  t.tap(x, y)
  assert_eq(pressed.val, 1, msg="pressed where it is reached")
  // (taking no press: still seen, reached no more)
  takes.set(false)
  t.draw()
  assert_eq(t.locate("icon:copy").length(), 1, msg="taking no press: seen")
  assert_eq(t.reachable("icon:copy").length(), 0, msg="taking no press: not reached")
  takes.set(true)
  // (an old view over it: seen, not reached)
  covered.set(true)
  t.draw()
  assert_eq(t.locate("icon:copy").length(), 1, msg="covered: seen")
  assert_eq(t.reachable("icon:copy").length(), 0, msg="covered: not reached")
  covered.set(false)
  t.draw()
  assert_eq(t.reachable("icon:copy").length(), 1, msg="uncovered: reached again")
  // (another icon: found by it, the old name by nothing)
  icon.set("check")
  t.draw()
  assert_eq(t.locate("icon:copy").length(), 0, msg="its old name gone")
  assert_eq(t.reachable("icon:check").length(), 1, msg="found by its new one")
}
