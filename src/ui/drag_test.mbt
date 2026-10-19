// A drag area lying in a list (drag.mbt `in_list`): a row swiped away across a list that scrolls up and down.

///|
/// A list of rows, the second a drag area across; what it was moved by, and whether it was tapped, kept.
fn swipe_view(moved : Ref[Double], tapped : Ref[Bool]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      c.list("rows", 30, 40.0, fn(i) {
        if i == 1 {
          let id = c.id("swiped")
          c.drag_area(id, axis=Horizontal, in_list=true, w=Fill(1.0), h=Px(40.0), fn() {
            c.text("swipe me", size=10.0) |> ignore
          })
          |> ignore
          match c.drag_of(id) {
            Some(d) => {
              moved.val = moved.val + d.take_move().0
              if d.take_tap() {
                tapped.val = true
              }
            }
            None => ()
          }
        } else {
          c.box(h=Px(40.0), fn() { c.text("row \{i}", size=10.0) |> ignore }) |> ignore
        }
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
}

///|
test "a drag area in a list: across first, it is the drag's and the list holds still; up or down first, the list's" {
  let moved = Ref::new(0.0)
  let tapped = Ref::new(false)
  let t = swipe_view(moved, tapped)
  t.draw()
  let (_, y, _, _) = t.rect_of("swipe me").unwrap()
  t.drag(250.0, y + 5.0, 100.0, y + 5.0)
  t.draw()
  assert_true(moved.val < -100.0)
  assert_eq(t.list_offset(), 0.0)
  moved.val = 0.0
  t.drag(150.0, y + 5.0, 150.0, y - 115.0)
  t.draw()
  assert_true(t.list_offset() > 80.0)
  assert_eq(moved.val, 0.0)
  assert_true(!tapped.val)
}
