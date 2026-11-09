// What says it is pointed at alone (View::points), as an old view's box `points=true, taps=false`: pointed at as the
// pointer is over it or over what it holds that takes the pointer not, and as it is over what it holds that does;
// not where something over it takes the pointer; never pressed or held for it, what is under it taking presses as ever;
// in a row that scrolls across, the wheel and a hold across still the row's.

///|
priv struct PointsAcross {
  tree : @view.Tree
  table : Ref[@view.View?]
  pressed : Ref[Int]
  under : Ref[Int]
  across : @view.Scroll
  covered : @signals.Signal[Bool]
}

///|
/// A card 300 wide that takes a press (`under` counts them), holding a row that scrolls across 600 of cells, in it a
/// table (cells taking nothing, a key 40 wide at its end taking a press: `pressed`) said to be pointed at alone; over
/// its left half, while `covered` says, a box that takes a press.
fn points_across() -> PointsAcross {
  let table : Ref[@view.View?] = Ref(None)
  let pressed = Ref(0)
  let under = Ref(0)
  let across = @view.Scroll::across()
  let covered = @signals.signal(false)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(card) {
        card.width(Is(Some(300.0))).height(Is(Some(100.0))).on_press(fn() { under.val += 1 }) |> ignore
        card.box(fn(r) {
          r.scrolls(across, fn(held) {
            held.box(fn(t) {
              table.val = Some(t)
              t.row(Is(true)).points(Is(true)) |> ignore
              for _ in 0..<9 {
                t.box(fn(c) { c.width(Is(Some(60.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
              }
              t.box(fn(k) { k.width(Is(Some(60.0))).height(Is(Some(40.0))).on_press(fn() { pressed.val += 1 }) |> ignore })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      root.show(fn() { covered.get() }, fn(o) {
        // (over the card's left half: laid over what holds them both, from its corner, drawn after it)
        o.over(Is(true)).width(Is(Some(150.0))).height(Is(Some(100.0))).on_press(fn() {  })
        |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  { tree, table, pressed, under, across, covered }
}

///|
test "pointed at alone in a row that scrolls across: the pointer over its words, it; over its key, it still; covered there, not; gone, not" {
  let k = points_across()
  let t = k.table.val.unwrap()
  let at = fn(x : Double, y : Double) {
    // (laid out as it is now, then pointed at there)
    k.tree.frame(390.0, 844.0) |> ignore
    k.tree.point_at(x, y)
    k.tree.frame(390.0, 844.0) |> ignore
    @signals.untracked(fn() { t.pointed_in() })
  }
  let first = at(20.0, 20.0)
  // (the row scrolled to its end: its key at 240 to 300)
  k.tree.wheel_at(150.0, 20.0, 300.0, 0.0, 0, 10.0) |> ignore
  let key = at(270.0, 20.0)
  k.covered.set(true)
  let covered = at(20.0, 20.0)
  k.covered.set(false)
  let uncovered = at(20.0, 20.0)
  let off = at(20.0, 90.0)
  assert_eq((first, k.across.at(k.tree), key, covered, uncovered, off), (true, 300.0, true, false, true, false))
}

///|
test "pointed at alone in a row that scrolls across, pressed for nothing: a tap on its words the card's under it; on its key, the key's; held across, the row's" {
  let k = points_across()
  k.tree.press(20.0, 20.0) |> ignore
  let card = k.under.val
  let id = k.tree.claimer_of(k.tree.claimers_at(150.0, 20.0), -20.0, 0.0)
  k.tree.wheel_at(150.0, 20.0, 300.0, 0.0, 0, 20.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  k.tree.press(270.0, 20.0) |> ignore
  assert_eq((card, id is Some(_), k.pressed.val, k.under.val), (1, true, 1, 1))
}
