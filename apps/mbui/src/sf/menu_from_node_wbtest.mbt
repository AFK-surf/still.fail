// A menu opened beside a node of the window's tree (Beside's `Node`: menu(…, from=Node(v))): beside it where it is
// drawn, following it as it moves, the focus given back to it as the menu closes; whether it is open read by what it
// opened from (presented_from), as it opens and closes.

///|
/// A wide window (a keyboard and mouse's, Large) whose tree holds, `down` under its top as that says, a button 开 that
/// opens a menu of 一 and 二 beside itself, lined up at its end, and words beside it saying whether that is open (摆着,
/// 收着: presented_from, bound); the presenters drawn over it.
fn mfn_tester(down : @signals.Signal[Double], opener : Ref[@view.View?]) -> @ui.Tester {
  set_words(fn(key, _) { key })
  let t = @ui.Tester::new(fn(_c) {  }, w=1200.0, h=800.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(col) {
      col.padding(Is((100.0, 100.0, 0.0, 0.0))) |> ignore
      col.box(fn(gap) { gap.height(By(fn() { Some(down.get()) })) |> ignore }) |> ignore
      col.box(fn(line) {
        line.row(Is(true)) |> ignore
        opener.val = Some(
          button_node(line, fn() { "开" }, fn() {
            match opener.val {
              Some(b) =>
                menu(
                  [Some(menu_item_of("一", fn() {  })), Some(menu_item_of("二", fn() {  }))],
                  from=Node(b),
                  along=End,
                )
              None => ()
            }
          }),
        )
        line.box(fn(w) {
          w
          .words(By(fn() {
            match opener.val {
              Some(b) if presented_from(Node(b)) => "摆着"
              _ => "收着"
            }
          }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    presented_nodes(root)
  })
  t.draw()
  t
}

///|
test "a menu opened beside a node stands beside it, follows it as it moves, and gives the focus back to it as it closes" {
  let down = @signals.signal(0.0)
  let opener : Ref[@view.View?] = Ref(None)
  let t = mfn_tester(down, opener)
  let (_, by, _, bh) = t.rect_of("开").unwrap()
  assert_true(t.find("收着") is Some(_))
  t.tap_text("开")
  t.run_for(@ui.move_most_ms)
  assert_true(presenting())
  assert_true(t.find("摆着") is Some(_) && t.find("收着") is None)
  // (under it, the button's whole height down at least)
  let (_, y1, _, _) = t.rect_of("一").unwrap()
  assert_true(y1 > by + bh, msg="\{Repr((by, bh, y1))}")
  // the node moved: the menu with it, as far
  down.set(80.0)
  t.run_for(@ui.move_most_ms)
  let (_, by2, _, _) = t.rect_of("开").unwrap()
  let (_, y2, _, _) = t.rect_of("一").unwrap()
  assert_true((by2 - by - 80.0).abs() < 0.5, msg="\{Repr((by, by2))}")
  assert_true((y2 - y1 - 80.0).abs() < 0.5, msg="\{Repr((y1, y2))}")
  // closed: the focus on the node that opened it
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_false(presenting())
  assert_true(t.find("收着") is Some(_) && t.find("摆着") is None)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("开"))
  presenters_reset()
}

///|
test "two openers beside the same are the same: the same node, box or rectangle; never one of another kind" {
  let opener : Ref[@view.View?] = Ref(None)
  let t = mfn_tester(@signals.signal(0.0), opener)
  t.draw()
  let b = opener.val.unwrap()
  assert_true(Beside::Node(b) == Beside::Node(b))
  assert_true(Beside::Node(b).anchor() == Anchor::Node(b))
  assert_false(Beside::Node(b) == Beside::Of(1))
  assert_true(Beside::At(1.0, 2.0, 0.0, 0.0) == at_point(1.0, 2.0))
  assert_false(Beside::Of(3) == Beside::Of(4))
  presenters_reset()
}
