// A wheel at a moment and a press 7 ms after it, on a page's list: where it is after the press is a function of those
// two inputs and their moments, whether frames were drawn between them or not (the user's first rule: the same state
// and the same inputs at their moments give the same result, whatever the frames). A wheel's way set off at its own
// moment, stopped by the press where it is at the press's: a wheel's notches (eased) only a little way by then, one
// without (there at once) all of it.

///|
/// A page's list feeling as `feel`, 390 by 844, 300 rows 60 tall: wheeled 600 at 1000 ms with `mods`, pressed (a hold's
/// Down) at 1007, a frame drawn at each of `frames` between them. Where it is just after the press, and long after.
fn wheel_then_press(feel : @view.ListFeel, mods : Int, frames : Array[Double]) -> (Double, Double) {
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o
      .width(Is(Some(390.0)))
      .height(Is(Some(844.0)))
      .scrolls(scroll, fn(held) {
        for _ in 0..<300 {
          held.box(fn(r) { r.width(Is(Some(390.0))).height(Is(Some(60.0))) |> ignore }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  tree.lists_feel(fn() { (feel, 2.0) })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.wheel_at(195.0, 400.0, 0.0, 600.0, mods, 1000.0) |> ignore
  for at in frames {
    tree.frame(390.0, 844.0, now=at) |> ignore
  }
  let id = tree.claimer_of(tree.claimers_at(195.0, 400.0), 0.0, -20.0).unwrap()
  tree.drag_at(id, Down, 195.0, 400.0, 1007.0) |> ignore
  let pressed = scroll.at(tree)
  tree.advance(wheel_press_rest_at)
  (pressed, scroll.at(tree))
}

///|
/// A moment long after any wheel's way is over.
let wheel_press_rest_at : Double = 6000.0

///|
/// Each feel, with the wheel's notches and without: where it is after the press with no frame between, one, and two,
/// side by side with where it is to be.
fn wheel_press_each(mods : Int, expected : Double) -> Array[(String, (Double, Double), (Double, Double), (Double, Double), (Double, Double))] {
  let out = []
  for named in [("desktop", @view.ListFeel::Desktop), ("android", @view.ListFeel::Android), ("ios", @view.ListFeel::Ios)] {
    let (name, feel) = named
    out.push(
      (
        name,
        wheel_then_press(feel, mods, []),
        wheel_then_press(feel, mods, [1003.0]),
        wheel_then_press(feel, mods, [1002.0, 1005.0]),
        (expected, expected),
      ),
    )
  }
  out
}

///|
/// Each row's four the same: no frame, one, two between the wheel and the press, and where it is to be.
fn wheel_press_same(rows : Array[(String, (Double, Double), (Double, Double), (Double, Double), (Double, Double))]) -> Array[String] {
  rows.filter(fn(r) { r.1 != r.2 || r.1 != r.3 || r.1 != r.4 }).map(fn(r) { "\{r.0}: \{Repr(r.1)} \{Repr(r.2)} \{Repr(r.3)}, to be \{Repr(r.4)}" })
}

///|
test "a wheel's notches and a press 7 ms after them: stopped where its way is at the press, whatever frames came between" {
  // (an eased wheel's way 7 ms on: a little of its 600)
  assert_eq(wheel_press_same(wheel_press_each(@view.wheel_notch, 7.46875)), [])
}

///|
test "a wheel without notches and a press 7 ms after it: all of its 600 at once, whatever frames came between" {
  assert_eq(wheel_press_same(wheel_press_each(0, 600.0)), [])
}
