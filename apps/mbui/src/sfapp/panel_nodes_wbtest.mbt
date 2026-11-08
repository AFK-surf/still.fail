// A panel whose body and foot are nodes of the window's tree (@sf.panel_nodes): laid out where the old frame's body and
// foot of the same panel are (beside what opened it, and in the middle of the window), drawn by the tree, closed by
// what it is given and by Escape as an old-bodied panel is.

///|
/// Where a box of `color` is drawn (its rect: x, y, width, height), the one there is.
fn painted_at(t : @ui.Tester, color : Int64) -> (Double, Double, Double, Double) raise {
  let found = t.drawn_rects().filter(fn(r) { r.4 >> 8 == color >> 8 })
  assert_eq(found.length(), 1, msg="one box of \{color}")
  (found[0].0, found[0].1, found[0].2, found[0].3)
}

///|
let body_ink : Int64 = 0x23A1DFFFL

///|
let foot_ink : Int64 = 0xB45A29FFL

///|
/// The test's boxes' corner: concentric where they stand in a dialog's corner, 24 in from its 42 (the corner rule's).
let ink_corner : Double = 18.0

///|
/// An old body: a box 40 by 36 of body_ink.
fn old_body() -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, _) { c.box(w=Px(40.0), h=Px(36.0), bg=body_ink, radius=ink_corner, fn() {  }) |> ignore }
}

///|
/// An old foot: a box 60 by 36 of foot_ink.
fn old_foot() -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, _) { c.box(w=Px(60.0), h=Px(36.0), bg=foot_ink, radius=ink_corner, fn() {  }) |> ignore }
}

///|
/// A box `w` by `h` of `ink`, as a node in `v`.
fn ink_node(v : @view.View, w : Double, h : Double, ink : Int64) -> Unit {
  v.box(fn(b) { b.width(Is(Some(w))).height(Is(Some(h))).ground(Is(ink)).radius(Is(ink_corner)) |> ignore }) |> ignore
}

///|
/// Where the body's and the foot's boxes are drawn once the panel is in, then closed by Escape and gone.
fn body_and_foot(t : @ui.Tester) -> ((Double, Double, Double, Double), (Double, Double, Double, Double)) raise {
  t.run_for(@ui.move_most_ms)
  let at = (painted_at(t, body_ink), painted_at(t, foot_ink))
  t.key(@ui.key_escape)
  t.run_for(@kit.pop_out_ms)
  assert_false(@sf.presenter_visible(), msg="gone")
  at
}

///|
test "大屏: a panel beside what opened it whose body and foot are nodes: each where the old frame's body and foot of the same panel are" {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("面板", from=At(600.0, 300.0, 0.0, 0.0), foot=old_foot(), old_body())
  let old = body_and_foot(t)
  @sf.panel_nodes("面板", from=At(600.0, 300.0, 0.0, 0.0), foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  assert_eq(body_and_foot(t), old)
}

///|
test "大屏: an untitled panel beside what opened it whose body is nodes, ruled over its foot: each where the old frame's are" {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("", from=At(600.0, 300.0, 0.0, 0.0), ruled=true, foot=old_foot(), old_body())
  let old = body_and_foot(t)
  @sf.panel_nodes("", from=At(600.0, 300.0, 0.0, 0.0), ruled=true, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  assert_eq(body_and_foot(t), old)
}

///|
test "大屏: a panel in the middle of the window whose body and foot are nodes, titled and saying what it is: each where the old frame's are" {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("对话框", description="它说的话", from=Unanchored, foot=old_foot(), old_body())
  let old = body_and_foot(t)
  @sf.panel_nodes("对话框", description="它说的话", from=Unanchored, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  assert_eq(body_and_foot(t), old)
}

///|
test "大屏: an untitled form whose body and foot are nodes: each where the old frame's are" {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("", from=At(600.0, 300.0, 0.0, 0.0), form=true, foot=old_foot(), old_body())
  let old = body_and_foot(t)
  @sf.panel_nodes("", from=At(600.0, 300.0, 0.0, 0.0), form=true, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  assert_eq(body_and_foot(t), old)
}

///|
test "大屏: a panel whose body is nodes: drawn by the window's tree, read out a dialog by its title; what its body is given closes it, its gone not told; Escape closes it, its gone told once" {
  let t = menu_tester(1280.0, 800.0, 0)
  let gone = Ref(0)
  let close_it : Ref[() -> Unit] = Ref(fn() {  })
  @sf.panel_nodes("节点面板", from=At(600.0, 300.0, 0.0, 0.0), gone=fn() { gone.val += 1 }, fn(v, close) {
    close_it.val = close
    ink_node(v, 40.0, 36.0, body_ink)
  })
  t.run_for(@ui.move_most_ms)
  assert_true(tree_said(Dialog, "节点面板") is Some(_), msg="the tree's")
  assert_true(@sf.presenting())
  (close_it.val)()
  t.run_for(@kit.pop_out_ms)
  assert_eq((@sf.presenting(), @sf.presenter_visible(), gone.val), (false, false, 0))
  @sf.panel_nodes("节点面板", from=Unanchored, gone=fn() { gone.val += 1 }, fn(v, _) { ink_node(v, 40.0, 36.0, body_ink) })
  t.run_for(@ui.move_most_ms)
  assert_true(tree_said(Dialog, "节点面板") is Some(_), msg="the tree's, in the middle")
  t.key(@ui.key_escape)
  t.run_for(@kit.pop_out_ms)
  assert_eq((@sf.presenting(), @sf.presenter_visible(), gone.val), (false, false, 1))
}
