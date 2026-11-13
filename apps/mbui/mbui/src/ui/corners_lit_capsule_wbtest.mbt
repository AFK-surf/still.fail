// The corner rule of a capsule whose ground shows only under the hand (a chooser's), in a card's foot corner: a card
// 320×142, 26 round; in its bottom right a capsule 150×28, 14 round, `dx` from its right and `dy` from its foot. 23/12
// and 11/12 are neither as far from both edges nor concentric (26 − 12 = 14 would be: 12/12). The old view's (its
// ground a style's hovered{}: state_ground) and the window's tree's (its ground while pointed at, taking presses),
// each held to the rule at rest; the tree's said as all is lit too (Tester::lit_all_faults).

///|
/// The old view's card with the capsule `dx`, `dy` in from its bottom right.
fn lit_capsule_old(dx : Double, dy : Double) -> Tester {
  Tester::new(
    fn(c) {
      c.box(w=Px(320.0), h=Px(142.0), radius=26.0, bg=0x333333FFL, pr=dx, pb=dy, align=AEnd, justify=JEnd, fn() {
        let id = c.id("capsule")
        c.on_press(id, fn() {  })
        c.box(id~, style=css("hovered{bg=Hover}"), w=Px(150.0), h=Px(28.0), radius=14.0, fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
    platform=0,
    corners_held=false,
  )
}

///|
/// The window's tree's card with the capsule `dx`, `dy` in from its bottom right.
fn lit_capsule_tree(dx : Double, dy : Double) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, corners_held=false)
  set_view_app(fn(root) {
    root.box(fn(card) {
      card
      .width(Is(Some(320.0)))
      .height(Is(Some(142.0)))
      .padding(Is((0.0, 0.0, dx, dy)))
      .lines_up(Is(Some(End)))
      .lies_along(Is(End))
      .ground(Is(0x333333FFL))
      .radius(Is(26.0))
      |> ignore
      card.box(fn(k) {
        k
        .width(Is(Some(150.0)))
        .height(Is(Some(28.0)))
        .radius(Is(14.0))
        .ground(By(fn() { if k.pointed() { 0xEEEEEEFFL } else { 0L } }))
        .presses(Is(true))
        .on_press(fn() {  })
        .says(Is(Some(@view.said(Button, label="how long"))))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a capsule whose ground shows under the hand, in a card's bottom right corner 23/12 and 11/12 from its edges: said at rest by the old view's rule and by the window's tree's alike" {
  let said : Array[String] = []
  for at in [(23.0, 12.0), (11.0, 12.0)] {
    let old = lit_capsule_old(at.0, at.1)
    old.draw()
    let o = old.corner_faults()
    let tree = lit_capsule_tree(at.0, at.1)
    let n = tree.corner_faults()
    let lit = tree.lit_all_faults()
    said.push("\{at.0}/\{at.1}: old \{o.length()}, tree at rest \{n.length()}, tree all lit \{lit.length()}")
  }
  assert_eq(
    said.join(" | "),
    "23/12: old 1, tree at rest 1, tree all lit 1 | 11/12: old 1, tree at rest 1, tree all lit 1",
  )
}

///|
test "press_corner_faults catches square lit grounds and 0.0 ripples inside rounded containers" {
  let bad_old = Tester::new(
    fn(c) {
      c.box(w=Px(320.0), h=Px(180.0), radius=26.0, bg=0x333333FFL, padx=20.0, pady=20.0, fn() {
        let a = c.id("sq-ground")
        c.on_press(a, fn() {  })
        c.box(id=a, style=css("hovered{bg=Hover}"), w=Px(200.0), h=Px(44.0), fn() {  }) |> ignore
        let b = c.id("sq-ripple")
        c.on_press(b, fn() {  })
        c.box(id=b, w=Px(200.0), h=Px(44.0), fn() { c.note_ripple(b, 0.0) }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
    platform=0,
    corners_held=false,
  )
  bad_old.draw()
  assert_eq(bad_old.press_corner_faults().length(), 2)
  assert_eq(bad_old.lit_all_press_faults().1.length(), 2)

  let ok_old = Tester::new(
    fn(c) {
      c.box(w=Px(320.0), h=Px(180.0), radius=26.0, bg=0x333333FFL, padx=20.0, pady=20.0, fn() {
        let a = c.id("round-ground")
        c.on_press(a, fn() {  })
        c.box(id=a, style=css("hovered{bg=Hover}"), w=Px(200.0), h=Px(44.0), radius=12.0, fn() {  }) |> ignore
        let b = c.id("round-ripple")
        c.on_press(b, fn() {  })
        c.box(id=b, w=Px(200.0), h=Px(44.0), radius=12.0, fn() { c.note_ripple(b, 12.0) }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
    platform=0,
    corners_held=false,
  )
  ok_old.draw()
  assert_eq(ok_old.press_corner_faults(), [])

  let bad_tree = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, corners_held=false)
  set_view_app(fn(root) {
    root.box(fn(card) {
      card.width(Is(Some(320.0))).height(Is(Some(180.0))).pad(Is(20.0)).ground(Is(0x333333FFL)).radius(Is(26.0))
      |> ignore
      card.box(fn(row) {
        row
        .width(Is(Some(200.0)))
        .height(Is(Some(44.0)))
        .ground(By(fn() { if row.pointed() { 0xEEEEEEFFL } else { 0L } }))
        .presses(Is(true))
        .on_press(fn() {  })
        |> ignore
      })
      |> ignore
      card.box(fn(row2) {
        row2.width(Is(Some(200.0))).height(Is(Some(44.0))).presses(Is(true)).on_press(fn() {  }) |> ignore
        row2.note_ripple(Is(0.0))
      })
      |> ignore
    })
    |> ignore
  })
  bad_tree.draw()
  assert_eq(bad_tree.lit_all_press_faults().1.length(), 2)
}
