// What is pressed in a column that scrolls stays where it was pressed as what it opens or shuts round it comes or goes
// (press_stays.mbt): what says it opens or shuts, over it, under it, at the column's foot, a page's list's or a plain
// column's.

///|
priv struct PressCase {
  tree : @view.Tree
  now : Ref[Double]
  /// each row's button, by its row
  buttons : Map[Int, @view.View]
}

///|
/// A window 300 by 400 all of it a column that scrolls (a page's list where `list`, else a plain one) of 12 rows, each
/// what opens over its button (300 tall open), its button (40), what opens under it (300 tall open): the button opens
/// or shuts the one over it where `over`, else the one under it.
fn press_case(list : Bool, over : Bool) -> PressCase {
  let now = Ref(0.0)
  let buttons : Map[Int, @view.View] = Map([])
  let opened : Array[@signals.Signal[Bool]] = Array::makei(12, fn(_) {
    @signals.signal(false, same=fn(a, b) { a == b })
  })
  let row = fn(b : @view.View, k : Int) {
    let room = fn() { if opened[k].get() { Some(300.0) } else { Some(0.0) } }
    b.box(fn(o) { o.height(By(fn() { if over { room() } else { Some(0.0) } })).shrink(Is(0.0)) |> ignore }) |> ignore
    b.box(fn(p) {
      buttons[k] = p
      p
      .height(Is(Some(40.0)))
      .shrink(Is(0.0))
      .on_press(fn() { opened[k].set(!opened[k].untracked()) })
      .says(By(fn() { Some(@view.said(Button, label="row \{k}", expanded=opened[k].get())) }))
      |> ignore
    })
    |> ignore
    b.box(fn(u) { u.height(By(fn() { if over { Some(0.0) } else { room() } })).shrink(Is(0.0)) |> ignore }) |> ignore
  }
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(win) {
        win.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        if list {
          win.scrolls_window(@view.Scroll::list(), fn() { Array::makei(12, fn(i) { i }) }, est=40.0, row) |> ignore
        } else {
          win.scrolls(@view.Scroll::new(), fn(held) {
            for k in 0..<12 {
              held.box(fn(b) { row(b, k) }) |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(300.0, 400.0, now=0.0) |> ignore
  { tree, now, buttons }
}

///|
/// Row `k`'s button pressed at its middle at `at` and the frame drawn then: where it was down the window before, and
/// after.
fn PressCase::press(self : PressCase, k : Int, at : Double) -> (Double, Double) {
  let (x, y, w, h) = self.buttons[k].rect()
  self.now.val = at
  self.tree.press(x + w / 2.0, y + h / 2.0) |> ignore
  self.tree.frame(300.0, 400.0, now=at) |> ignore
  (y, self.buttons[k].rect().1)
}

///|
test "what is pressed in a column that scrolls stays where it was, what it opens over it or under it, opened and shut" {
  for list in [true, false] {
    for over in [true, false] {
      let c = press_case(list, over)
      // (the first rows' buttons, in sight: opened, then shut)
      let (was, opened) = c.press(2, 100.0)
      let (_, shut) = c.press(2, 200.0)
      assert_eq((list, over, opened, shut), (list, over, was, was))
    }
  }
}

///|
test "what is pressed at a column's foot stays where it was as what it opened there shuts: room kept under it" {
  for list in [true, false] {
    let c = press_case(list, false)
    // (at its foot, the last row opened, and at its foot again: what it opened all in sight)
    c.tree.wheel_at(150.0, 200.0, 0.0, 10000.0, 0, 50.0) |> ignore
    c.tree.frame(300.0, 400.0, now=1000.0) |> ignore
    let (was, opened) = c.press(11, 2000.0)
    assert_eq((list, opened), (list, was))
    c.tree.wheel_at(150.0, 200.0, 0.0, 10000.0, 0, 3000.0) |> ignore
    c.tree.frame(300.0, 400.0, now=4000.0) |> ignore
    let (was, shut) = c.press(11, 5000.0)
    assert_eq((list, shut), (list, was))
  }
}
