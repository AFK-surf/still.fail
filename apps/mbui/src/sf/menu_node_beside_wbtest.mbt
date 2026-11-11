// A menu that is not modal (menu_node's `modal` false: a submenu's, beside the row that opened it): what is under it its
// own, a press outside it closing it and going on to what it lands on, a press on what opened it not; the arrow key back
// toward what opened it closing it. Beside the same menu modal, which takes all of them.

///|
/// A window with a button 开 that opens a menu at its Right (`modal` or not), and a button 下面 under it, each counting its
/// presses (`under`), the menu's closings unchosen counted in `cancels`.
fn side_menu_tester(modal : Bool, open : @signals.Signal[Bool], cancels : Ref[Int], under : Ref[Int]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=600.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.padding(Is((100.0, 100.0, 0.0, 0.0))).gap(Is(40.0)) |> ignore
    let opener = root.box(fn(o) {
      o
      .width(Is(Some(120.0)))
      .height(Is(Some(36.0)))
      .presses(Is(true))
      .on_press(fn() { open.set(true) })
      .says(Is(Some(@view.said(Button, label="开"))))
      |> ignore
    })
    root.box(fn(u) {
      u
      .width(Is(Some(120.0)))
      .height(Is(Some(36.0)))
      .presses(Is(true))
      .on_press(fn() { under.val += 1 })
      .says(Is(Some(@view.said(Button, label="下面"))))
      |> ignore
    })
    |> ignore
    root.box(fn(l) {
      l.over(Is(true)) |> ignore
      menu_node(
        l,
        fn() { open.get() },
        fn(_) { opener },
        fn() { [Some(menu_item_of("一", fn() {  })), Some(menu_item_of("二", fn() {  }))] },
        "",
        Start,
        8.0,
        false,
        false,
        fn(_) { open.set(false) },
        fn() {
          cancels.val += 1
          open.set(false)
        },
        side=Right,
        modal~,
      )
    })
    |> ignore
  })
  t.draw()
  open.set(true)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The middle of the button `label` (开 or 下面), where side_menu_tester lays it out: 100 in, 100 down, 120 by 36, 40
/// apart (by where it is, not by what is read out: a modal menu hides what is under it from that).
fn side_button(label : String) -> (Double, Double) {
  if label == "开" {
    (160.0, 118.0)
  } else {
    (160.0, 194.0)
  }
}

///|
test "a menu not modal: a press outside its panel closes it as it goes down, and what it lands on is pressed; modal, the press its own" {
  for modal in [false, true] {
    let open = @signals.signal(false)
    let (cancels, under) = (Ref(0), Ref(0))
    let t = side_menu_tester(modal, open, cancels, under)
    assert_true(t.query(Menu) is Some(_), msg="modal \{modal}: open")
    let (x, y) = side_button("下面")
    t.tap(x, y)
    t.run_for(@ui.move_most_ms)
    assert_eq((cancels.val, under.val, t.query(Menu) is None), (1, if modal { 0 } else { 1 }, true), msg="modal \{modal}")
  }
}

///|
test "a menu not modal: a press on what opened it leaves it open" {
  let open = @signals.signal(false)
  let (cancels, under) = (Ref(0), Ref(0))
  let t = side_menu_tester(false, open, cancels, under)
  let (x, y) = side_button("开")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq((cancels.val, t.query(Menu) is Some(_)), (0, true))
}

///|
test "a menu not modal at its opener's Right: Left (back toward it) closes it; modal, Left closes nothing" {
  for modal in [false, true] {
    let open = @signals.signal(false)
    let (cancels, under) = (Ref(0), Ref(0))
    let t = side_menu_tester(modal, open, cancels, under)
    t.key(@ui.key_code_left)
    t.run_for(@ui.move_most_ms)
    assert_eq((cancels.val, t.query(Menu) is None), if modal { (0, false) } else { (1, true) }, msg="modal \{modal}")
  }
}
