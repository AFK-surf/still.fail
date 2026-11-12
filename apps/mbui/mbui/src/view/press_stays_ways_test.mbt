// What is pressed in a page's list stays where it was (press_stays.mbt) as what the press opens or shuts round it makes
// its way, over it or under it: what is over it read as tall as its way has it at each moment, not measured whole (as
// it was till 2026-11-12: the button went down with what opened over it). Looked at at moments it declares (rc_walk,
// list_rows_come_test's), the press told at its moment, in one jump and at 60, 120, 24 and 7 a second.

///|
/// How tall what opens over each row's button.
let ps_ways_open : Double = 300.0

///|
/// How long after the press it is looked at, past the end of any way it set off.
let ps_ways_look_ms : Double = 1500.0

///|
/// A page's list of 12 rows, 300 wide and 400 tall: each a button 40 tall saying it opens or shuts (`expanded`) a show
/// `open` tall, over it where `over`, under it where not; with each row's button.
fn ps_ways_list(open : Double, over : Bool) -> (@view.Tree, Map[Int, @view.View]) {
  let buttons : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(win) {
      win.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      win.scrolls_window(@view.Scroll::list(), fn() { Array::makei(12, fn(i) { i }) }, est=40.0, fn(b, k) {
        let on = @signals.signal(false, same=fn(a, b) { a == b })
        let opens = fn() {
          b.show(fn() { on.get() }, fn(o) { o.height(Is(Some(open))) |> ignore }) |> ignore
        }
        if over {
          opens()
        }
        b.box(fn(p) {
          buttons[k] = p
          p
          .height(Is(Some(40.0)))
          .shrink(Is(0.0))
          .words(Is("行\{k}"))
          .on_press(fn() { on.set(!on.untracked()) })
          .says(By(fn() { Some(@view.said(Button, label="row \{k}", expanded=on.get())) }))
          |> ignore
        })
        |> ignore
        if !over {
          opens()
        }
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  (tree, buttons)
}

///|
/// Row `k`'s button in `buttons` pressed in the middle (told at its moment: rc_walk's events).
fn ps_ways_press(tree : @view.Tree, buttons : Map[Int, @view.View], k : Int) -> Unit {
  let (x, y, w, h) = buttons[k].rect()
  tree.press(x + w / 2.0, y + h / 2.0) |> ignore
}

///|
test "a page's list, a row's button pressed opening 300 over it or under it: what was pressed stays where it was at every moment of the way, the same at every rate" {
  let looks = []
  let mut at = rc_at
  while at <= rc_at + ps_ways_look_ms {
    looks.push(at)
    at = at + rc_look_ms
  }
  for over in [true, false] {
    let by_rate = rc_rates.map(fn(rate) {
      let (tree, buttons) = ps_ways_list(ps_ways_open, over)
      let was = rc_y(tree, "行3")
      let got = rc_walk(tree, [(rc_at, fn() { ps_ways_press(tree, buttons, 3) })], looks, rate, fn() {
        rc_y(tree, "行3")
      })
      (was, got)
    })
    for i, rate in rc_rates {
      let (was, got) = by_rate[i]
      assert_eq(was, 120.0, msg="over \{over} at \{rate} a second")
      assert_true(got.iter().all(fn(y) { y == was }), msg="over \{over} at \{rate} a second: \{was} \{Repr(got)}")
      assert_eq(got, by_rate[0].1, msg="over \{over} at \{rate} a second")
    }
  }
}
