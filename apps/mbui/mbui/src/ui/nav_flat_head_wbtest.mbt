// A stack drawn flat with what the frame puts over each page (nav_flat_view's `head`: a panel's bar, the tree's): the
// stack's back over the whole page, the head and the page's own view (Nav::backs_over), after what the page's view says
// takes back itself; a swipe from its edge begun on the head the stack's; none of it the stack's while it is in place.

///|
/// A stack drawn flat, each page under a head 40 tall of the tree's; page "c"'s own view taking back itself while
/// `own` says so (its count told in `took`).
fn flat_headed(own : @signals.Signal[Bool], took : Ref[Int]) -> (Tester, Nav[String]) {
  let nav = Nav::new("a")
  let t = Tester::new(fn(_c) {  }, w=390.0, h=600.0)
  set_view_app(fn(root) {
    nav_flat_view(
      root,
      nav,
      fn(c, p) {
        if p == "c" && own.get() {
          c.on_back(fn() { took.val += 1 })
        }
        c.text(p, size=12.0) |> ignore
      },
      fn(_) { true },
      0.0,
      bg=fn() { 0xFFFFFFFFL },
      head=fn(b, _, _) { b.box(fn(h) { h.height(Is(Some(40.0))) |> ignore }) |> ignore },
    )
    |> ignore
  })
  t.draw()
  (t, nav)
}

///|
test "a flat stack with heads: back the page's own first where it takes it, then the stack's; a swipe begun on the head takes it off" {
  let own = @signals.signal(true)
  let took = Ref(0)
  let (t, nav) = flat_headed(own, took)
  nav.push("b")
  t.draw()
  nav.push_over("c")
  t.draw()
  t.run_for(move_ms(390.0) * 2.0)
  // (the page's own first: the stack as it was)
  assert_true(t.ctx().back())
  t.run_for(move_ms(390.0) * 2.0)
  assert_eq((took.val, nav.pages()), (1, ["a", "b", "c"]))
  // (taking none of its own: the stack's)
  own.set(false)
  t.draw()
  assert_true(t.ctx().back())
  t.run_for(move_ms(390.0) * 2.0)
  assert_eq(nav.pages(), ["a", "b"])
  // (in place: none of the stack's)
  assert_false(t.ctx().back())
  // (pushed over again, swiped from its edge on the head: off)
  nav.push_over("c")
  t.draw()
  t.run_for(move_ms(390.0) * 2.0)
  t.drag(4.0, 20.0, 300.0, 20.0)
  t.run_for(move_ms(390.0) * 2.0)
  assert_eq(nav.pages(), ["a", "b"])
}
