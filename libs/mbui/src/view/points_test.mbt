// What says it is pointed at alone (View::points), as an old view's box `points=true, taps=false`: pointed at as the
// pointer is over it or over what it holds that takes the pointer not, and as it is over what it holds that does;
// not where something over it takes the pointer; never pressed or held for it, what is under it taking presses as ever.

///|
priv struct PointsCase {
  tree : @view.Tree
  table : Ref[@view.View?]
  pressed : Ref[Int]
  under : Ref[Int]
  covered : @signals.Signal[Bool]
  points : @signals.Signal[Bool]
}

///|
/// A card 300 wide that takes a press (`under` counts them), holding a row of cells, a table (cells taking nothing, a
/// key 60 wide at its end, 240 to 300, taking a press: `pressed`) said to be pointed at alone while `points` holds;
/// over its left half, while `covered` says, a box that takes a press.
fn points_case() -> PointsCase {
  let table : Ref[@view.View?] = Ref(None)
  let pressed = Ref(0)
  let under = Ref(0)
  let covered = @signals.signal(false)
  let points = @signals.signal(true)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(card) {
        card.width(Is(Some(300.0))).height(Is(Some(100.0))).on_press(fn() { under.val += 1 }) |> ignore
        card.box(fn(t) {
          table.val = Some(t)
          t.row(Is(true)).points(By(fn() { points.get() })) |> ignore
          for _ in 0..<4 {
            t.box(fn(c) { c.width(Is(Some(60.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
          }
          t.box(fn(k) { k.width(Is(Some(60.0))).height(Is(Some(40.0))).on_press(fn() { pressed.val += 1 }) |> ignore })
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
  { tree, table, pressed, under, covered, points }
}

///|
/// Whether the table is pointed at (View::pointed_in) with the pointer at (x, y), the tree laid out as it is now.
fn PointsCase::at(self : PointsCase, x : Double, y : Double) -> Bool {
  self.tree.frame(390.0, 844.0) |> ignore
  self.tree.point_at(x, y)
  self.tree.frame(390.0, 844.0) |> ignore
  @signals.untracked(fn() { self.table.val.unwrap().pointed_in() })
}

///|
test "pointed at alone: the pointer over its words, it; over its key, it still; covered there, not; gone, not" {
  let k = points_case()
  let first = k.at(20.0, 20.0)
  let key = k.at(270.0, 20.0)
  k.covered.set(true)
  let covered = k.at(20.0, 20.0)
  k.covered.set(false)
  let uncovered = k.at(20.0, 20.0)
  let off = k.at(20.0, 90.0)
  assert_eq((first, key, covered, uncovered, off), (true, true, false, true, false))
}

///|
test "pointed at alone no longer under a still pointer: what is under it, the card, pointed at; again, it" {
  let k = points_case()
  let first = (k.at(20.0, 20.0), k.tree.points_now() is Some(_))
  k.points.set(false)
  let no = (k.at(20.0, 20.0), k.tree.points_now() is Some(_), k.tree.pointed_now() is Some(_))
  k.points.set(true)
  let again = (k.at(20.0, 20.0), k.tree.points_now() is Some(_))
  assert_eq((first, no, again), ((true, true), (false, false, true), (true, true)))
}

///|
test "pointed at alone, pressed for nothing: a tap on its words the card's under it; on its key, the key's" {
  let k = points_case()
  k.tree.press(20.0, 20.0) |> ignore
  let card = k.under.val
  k.tree.press(270.0, 20.0) |> ignore
  assert_eq((card, k.pressed.val, k.under.val), (1, 1, 1))
}

///|
test "pointed at alone over a card that takes a press: the pointer moved over it, it told so, the card not; still, nothing told again" {
  let moved = Ref(0)
  let card_moved = Ref(0)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(card) {
        card
        .width(Is(Some(300.0)))
        .height(Is(Some(100.0)))
        .on_press(fn() {  })
        .on_pointer_moved(fn() { card_moved.val += 1 })
        |> ignore
        card.box(fn(t) {
          t.width(Is(Some(200.0))).height(Is(Some(40.0))).points(Is(true)).on_pointer_moved(fn() { moved.val += 1 })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  tree.point_at(20.0, 20.0)
  tree.frame(390.0, 844.0) |> ignore
  let first = (moved.val, card_moved.val)
  tree.point_at(20.0, 20.0)
  tree.frame(390.0, 844.0) |> ignore
  tree.point_at(20.0, 30.0)
  tree.frame(390.0, 844.0) |> ignore
  tree.point_at(20.0, 80.0)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq((first, moved.val, card_moved.val), ((1, 0), 2, 1))
}

///|
test "covering bar (opaque ground or glass holding a control) hides both press targets and points-only nodes under it without cutting its own button's press room" {
  let row_pressed = Ref(0)
  let bar_btn_pressed = Ref(0)
  let row_ref : Ref[@view.View?] = Ref(None)
  let tag_ref : Ref[@view.View?] = Ref(None)
  let btn_ref : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(row) {
        row_ref.val = Some(row)
        row.width(Is(Some(300.0))).height(Is(Some(60.0))).on_press(fn() { row_pressed.val += 1 }) |> ignore
        row.box(fn(tag) {
          tag_ref.val = Some(tag)
          tag.width(Is(Some(120.0))).height(Is(Some(30.0))).points(Is(true)) |> ignore
        })
        |> ignore
      })
      |> ignore
      // Covering bar over the top 40px, with opaque ground and a 24x24 button at (200, 8)
      root.box(fn(bar) {
        bar
        .over(Is(true))
        .width(Is(Some(300.0)))
        .height(Is(Some(40.0)))
        .ground(Is(0xFFFFFFFFL))
        |> ignore
        bar.box(fn(btn) {
          btn_ref.val = Some(btn)
          btn
          .over(Is(true))
          .offset(Is((200.0, 8.0)))
          .width(Is(Some(24.0)))
          .height(Is(Some(24.0)))
          .on_press(fn() { bar_btn_pressed.val += 1 })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.press_least(fn() { 36.0 })
  tree.frame(390.0, 844.0) |> ignore
  // Over the bar's empty area at (20, 20): neither the row nor the points-only tag underneath is pointed or pressed
  tree.point_at(20.0, 20.0)
  tree.frame(390.0, 844.0) |> ignore
  let under_bar = (
    @signals.untracked(fn() { row_ref.val.unwrap().pointed_in() }),
    @signals.untracked(fn() { tag_ref.val.unwrap().pointed_in() }),
  )
  tree.press(20.0, 20.0) |> ignore
  // Below the bar at (20, 50): the row is pointed and pressed
  tree.point_at(20.0, 50.0)
  tree.frame(390.0, 844.0) |> ignore
  let below_bar = @signals.untracked(fn() { row_ref.val.unwrap().pointed_in() })
  tree.press(20.0, 50.0) |> ignore
  // Near the small button on the bar at (212, 36) (within its 36x36 press_room, inside the bar): reaches the button
  tree.point_at(212.0, 36.0)
  tree.frame(390.0, 844.0) |> ignore
  let on_btn_room = @signals.untracked(fn() { btn_ref.val.unwrap().pointed() })
  tree.press(212.0, 36.0) |> ignore
  assert_eq((under_bar, below_bar, row_pressed.val, on_btn_room, bar_btn_pressed.val), ((false, false), true, 1, true, 1))
}

///|
test "a small button's press reach is not stolen by an adjacent points-only sibling" {
  let btn_ref : Ref[@view.View?] = Ref(None)
  let tag_ref : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(bar) {
        bar.row(Is(true)).width(Is(Some(200.0))).height(Is(Some(40.0))) |> ignore
        bar.box(fn(btn) {
          btn_ref.val = Some(btn)
          btn.width(Is(Some(24.0))).height(Is(Some(24.0))).on_press(fn() {  }) |> ignore
        })
        |> ignore
        bar.box(fn(tag) {
          tag_ref.val = Some(tag)
          tag.width(Is(Some(80.0))).height(Is(Some(24.0))).points(Is(true)) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.press_least(fn() { 36.0 })
  tree.frame(390.0, 844.0) |> ignore
  // At x=26, y=12: 2px past the 24px button's right edge (within its 6px press_reach) and inside the points-only tag
  tree.point_at(26.0, 12.0)
  tree.frame(390.0, 844.0) |> ignore
  let near_btn = (
    @signals.untracked(fn() { btn_ref.val.unwrap().pointed() }),
    @signals.untracked(fn() { tag_ref.val.unwrap().pointed_in() }),
  )
  // At x=50, y=12: well inside the points-only tag, outside the button's reach
  tree.point_at(50.0, 12.0)
  tree.frame(390.0, 844.0) |> ignore
  let on_tag = (
    @signals.untracked(fn() { btn_ref.val.unwrap().pointed() }),
    @signals.untracked(fn() { tag_ref.val.unwrap().pointed_in() }),
  )
  assert_eq((near_btn, on_tag), ((true, false), (false, true)))
}
