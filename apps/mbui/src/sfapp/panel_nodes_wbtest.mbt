// A panel whose body and foot are nodes of the window's tree (@sf.panel_nodes): laid out where the old frame's body and
// foot of the same panel are (beside what opened it, and in the middle of the window), drawn by the tree, closed by
// what it is given and by Escape as an old-bodied panel is.

///|
/// Where a box of `color` is drawn (its rect: x, y, width, height), the one there is.
fn painted_at(t : @ui.Tester, color : Int64) -> (Double, Double, Double, Double) raise {
  let found = t.drawn_rects().filter(fn(r) { r.4 >> 8 == color >> 8 })
  assert_eq(found.length(), 1, msg="one box of \{color}")
  // (to a thousandth of a point: what one layout sums another way, never seen)
  let near = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
  (near(found[0].0), near(found[0].1), near(found[0].2), near(found[0].3))
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
/// Where the body's and the foot's boxes are drawn once the panel is in, and its head's words and its close button,
/// then closed by Escape and gone.
fn body_and_foot(
  t : @ui.Tester,
  close? : Bool = false,
) -> ((Double, Double, Double, Double), (Double, Double, Double, Double), Array[String], String) raise {
  t.run_for(@ui.move_most_ms)
  // (in any order: what of it is nodes listed before or after the old frame's as the tree draws it)
  let words = t.words().map(fn(w) { "\{w.0} \{@ui.rect_text(tenth4((w.1, w.2, w.3, w.4)))}" })
  words.sort()
  // (its close button where it has one: asked of what is read out only where asked, `close`)
  let close = if close { t.query(Button, label=@sf.t("common.close")).map(fn(b) { tenth4(b.rect) }) } else { None }
  let at = (painted_at(t, body_ink), painted_at(t, foot_ink), words, "\{@ui.some_text(close.map(@ui.rect_text))}")
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
  let old = body_and_foot(t, close=true)
  @sf.panel_nodes("对话框", description="它说的话", from=Unanchored, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  assert_eq(body_and_foot(t, close=true), old)
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

///|
test "大屏: an untitled panel in the middle of the window whose body and foot are nodes: its close button in its corner where the old frame's is" {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("", from=Unanchored, foot=old_foot(), old_body())
  let old = body_and_foot(t, close=true)
  @sf.panel_nodes("", from=Unanchored, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  assert_eq(body_and_foot(t, close=true), old)
}

///|
/// A panel a share of the window caps (`tall`) holding a list of one row (a box 40 by 36 of body_ink), with a foot: the
/// old frame's (its list said how tall it would be: panel_list), and the node one's as tall as what it holds up to that
/// share (`hugs`: panel_list_node). Where its body's and its foot's boxes are drawn once it is in, each; closed by
/// Escape and gone between them.
fn hugging(t : @ui.Tester) -> Array[((Double, Double, Double, Double), (Double, Double, Double, Double))] raise {
  let at = fn() raise {
    t.run_for(@ui.move_most_ms)
    let boxes = (painted_at(t, body_ink), painted_at(t, foot_ink))
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenter_visible(), msg="gone")
    boxes
  }
  @sf.panel("列表", from=Unanchored, tall=0.78, foot=old_foot(), fn(c, close) {
    @sf.panel_list(c, "hugging", 1, 40.0, fn(_) { old_body()(c, close) }) |> ignore
  })
  let old = at()
  @sf.panel_nodes("列表", from=Unanchored, tall=0.78, hugs=true, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    @sf.panel_list_node(v, fn() { [0] }, fn(b, _) { ink_node(b, 40.0, 36.0, body_ink) }, est=40.0) |> ignore
  })
  [old, at()]
}

///|
test "a panel a share of the window caps whose body is nodes, as tall as what it holds (hugs): its list's row and its foot where the old frame's are, as a sheet and in the middle of the window" {
  let sheet = hugging(menu_tester(390.0, 844.0, 2))
  assert_eq(sheet[1], sheet[0])
  let dialog = hugging(menu_tester(1280.0, 800.0, 0))
  assert_eq(dialog[1], dialog[0])
}

///|
/// The ways a panel is shown that a field it opens to be typed in has the keys in (@sf.panel_opens_in_node): `at`,
/// the window (width, height, platform) and where it is opened from: a sheet on a phone by touch and with keyboard and
/// mouse, in the middle of a fold laid open by touch, beside what opened it and in the middle of a wide window.
let field_panel_ways : Array[(String, Double, Double, Int, @sf.Anchor)] = [
  ("小屏 touch sheet", 390.0, 844.0, 2, Unanchored),
  ("中屏 touch middle", 674.0, 842.0, 2, Unanchored),
  ("小屏 keyboard sheet", 390.0, 844.0, 0, Unanchored),
  ("大屏 beside", 1280.0, 800.0, 0, At(600.0, 300.0, 0.0, 0.0)),
  ("大屏 middle", 1280.0, 800.0, 0, Unanchored),
]

///|
test "a panel whose body says its field is typed in as it opens: that field has the keys as it opens on a sheet, beside what opened it and in the window's middle (the input method up for it by touch); back where they were as it goes" {
  for way in field_panel_ways {
    let (at, w, h, platform, from) = way
    let t = menu_tester(w, h, platform)
    let was = t.focus_said()
    let name = @ui.Field::new()
    @sf.panel_nodes("面板", from~, fn(v, _) {
      v.box(fn(b) { @sf.panel_opens_in_node(@sf.input_node(b, name, placeholder="名字")) }) |> ignore
    })
    t.run_for(@ui.move_most_ms)
    assert_true(t.focus_said().has_prefix("TextField \"名字\""), msg="\{at}: \{t.focus_said()}")
    if platform == 2 {
      assert_true(t.ime().0, msg="\{at}: the input method")
    }
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenter_visible(), msg="\{at}: gone")
    assert_eq(t.focus_said(), was, msg="\{at}: given back")
  }
}

///|
test "a panel whose body says its search is at hand: that search has the keys as it opens beside what opened it and in the window's middle with keyboard and mouse, given back as it goes; on a sheet (by touch or with keyboard and mouse) and in the window's middle by touch not, no input method up" {
  for way in field_panel_ways {
    @sf.presenters_reset()
    let (at, w, h, platform, from) = way
    let t = menu_tester(w, h, platform)
    let was = t.focus_said()
    let query = @ui.Field::new()
    @sf.panel_nodes("面板", from~, fn(v, _) {
      v.box(fn(b) { @sf.panel_search_at_hand_node(@sf.input_node(b, query, placeholder="搜索")) }) |> ignore
    })
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenter_visible(), msg="\{at}: up")
    if w < 600.0 || platform == 2 {
      assert_false(t.focus_said().has_prefix("TextField \"搜索\""), msg="\{at}: \{t.focus_said()}")
      assert_false(t.ime().0, msg="\{at}: the input method")
    } else {
      assert_true(t.focus_said().has_prefix("TextField \"搜索\""), msg="\{at}: \{t.focus_said()}")
    }
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenter_visible(), msg="\{at}: gone")
    assert_eq(t.focus_said(), was, msg="\{at}: given back")
  }
}
