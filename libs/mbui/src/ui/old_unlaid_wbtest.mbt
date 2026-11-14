// An old view as tall as what it holds (old's `natural`) in a list made as far as it shows (View::scrolls_window),
// `unlaid`: taken as tall as a screen till the old frame has laid it out, so the list makes none of its rows for room
// the old view does take; laid out, as tall as it is (none: the rows after it shown from the top).

///|
/// A list 300 by 200 whose first part is an old view as tall as what it holds (`held` tall), `unlaid` or not, then
/// rows 22 tall, each by its index: the rows ever made, and the tester.
fn unlaid_list(held : Double, unlaid : Bool) -> (Tester, Array[Int]) {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  t.check_looks(false)
  let made : Array[Int] = []
  let s = @view.Scroll::list()
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.height(Is(Some(200.0))).width(Is(Some(300.0))) |> ignore
      page.scrolls_window(s, fn() { Array::makei(30, fn(i) { i }) }, est=22.0, fn(b, i) {
        if i == 0 {
          let build = fn(c : Ctx) { c.box(w=Fill(1.0), h=Px(held), fn() {  }) |> ignore }
          if unlaid {
            old(b, build, natural=true, unlaid=fn() { b.window().1 }) |> ignore
          } else {
            old(b, build, natural=true) |> ignore
          }
        } else {
          made.push(i)
          b.box(fn(n) { n.height(Is(Some(22.0))).words(Is("行 \{i}")) |> ignore }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.draw()
  (t, made)
}

///|
test "an old view as tall as what it holds, first in a list, unlaid as tall as a screen: no row made for room it takes; as tall as it is then, the rows after it where it ends" {
  // (150 tall: of the rows only the first two and part of the third show)
  let (t, made) = unlaid_list(150.0, true)
  assert_true(made.iter().all(fn(i) { i <= 3 }), msg="\{Repr(made)}")
  assert_eq(t.rect_of("行 1").map(fn(r) { r.1 }), Some(150.0))
  // (taken as none tall at first, as it is without: rows made for the room it then takes)
  let (_, made) = unlaid_list(150.0, false)
  assert_true(made.iter().any(fn(i) { i > 3 }), msg="\{Repr(made)}")
}

///|
test "an old view first in a list, unlaid as tall as a screen, none tall as laid out: the rows after it from the list's top" {
  let (t, made) = unlaid_list(0.0, true)
  assert_true(made.contains(1) && made.contains(9), msg="\{Repr(made)}")
  assert_eq(t.rect_of("行 1").map(fn(r) { r.1 }), Some(0.0))
}
