// A panel whose body and foot are nodes (@sf.panel_nodes) on 小屏: a sheet from the window's foot drawn by the window's
// tree (sf's sheet_node), held to what the host's sheet does with the same panel with an old body (@sf.panel): where
// what it holds and its foot are, its scrim, its top dragged a little (back) and further (closed), a press above it,
// Escape and the back closing it.

///|
/// How long a sheet takes to come or go at most: a way as far as the window is tall or its scrim's fade, whichever is
/// longer.
fn sheet_way_ms(t : @ui.Tester) -> Double {
  ignore(t)
  dmax(@kit.sheet_scrim_ms, @ui.move_ms(844.0)) + 2.0 * @ui.input_step_ms
}

///|
/// A 小屏 phone's window.
fn phone_tester() -> @ui.Tester {
  menu_tester(390.0, 844.0, 2)
}

///|
/// The sheet's scrim drawn over the window: its colour, the rect it covers.
fn scrim_drawn(t : @ui.Tester) -> Array[(Double, Double, Double, Double, Int64)] {
  t.drawn_rects().filter(fn(r) { r.4 == @sf.sheet_scrim && r.2 >= 390.0 && r.3 >= 844.0 }).map(fn(r) { (r.0, r.1, r.2, r.3, r.4) })
}

///|
/// What one sheet shows at rest: its body's and its foot's boxes, its scrim; then closed by `close` and gone.
fn sheet_at_rest(t : @ui.Tester, close : (@ui.Tester) -> Unit) -> ((Double, Double, Double, Double), (Double, Double, Double, Double), Int) raise {
  t.run_for(sheet_way_ms(t))
  let at = (painted_at(t, body_ink), painted_at(t, foot_ink), scrim_drawn(t).length())
  close(t)
  t.run_for(sheet_way_ms(t))
  assert_false(@sf.presenter_visible(), msg="gone")
  assert_false(@sf.presenting(), msg="closed")
  at
}

///|
/// The sheets of the same panel with an old body and with nodes, each closed by `close`: what each shows at rest.
fn both_sheets(from : @sf.Anchor, close : (@ui.Tester) -> Unit, title? : String = "面板") -> Unit raise {
  let t = phone_tester()
  @sf.panel(title, from~, foot=old_foot(), old_body())
  let old = sheet_at_rest(t, close)
  @sf.panel_nodes(title, from~, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  assert_eq(sheet_at_rest(t, close), old)
}

///|
test "小屏: a panel opened by nothing whose body and foot are nodes: a sheet whose body, foot and scrim are where the host's are; Escape closes it" {
  both_sheets(Unanchored, fn(t) { t.key(@ui.key_escape) })
}

///|
test "小屏: a panel opened by a press whose body and foot are nodes, untitled: a sheet whose body, foot and scrim are where the host's are; the back closes it" {
  both_sheets(At(100.0, 300.0, 40.0, 40.0), fn(t) { t.back() }, title="")
}

///|
test "小屏: a sheet whose body is nodes, a press above it: closed, as the host's" {
  both_sheets(Unanchored, fn(t) { t.tap(195.0, 40.0) })
}

///|
test "小屏: a sheet whose body is nodes, its top dragged down a little: back where it was, open; further: closed, as the host's" {
  let little = fn(t : @ui.Tester) -> (Double, Double, Double, Double) raise {
    let (_, y, _, _) = t.query(Dialog).unwrap().rect
    t.drag(195.0, y + 10.0, 195.0, y + 60.0)
    t.run_for(sheet_way_ms(t))
    assert_true(@sf.presenting(), msg="open still")
    painted_at(t, body_ink)
  }
  let far = fn(t : @ui.Tester) raise {
    let (_, y, _, _) = t.query(Dialog).unwrap().rect
    t.drag(195.0, y + 10.0, 195.0, y + 140.0)
    t.run_for(sheet_way_ms(t))
    assert_false(@sf.presenting(), msg="closed")
    assert_false(@sf.presenter_visible(), msg="gone")
  }
  let t = phone_tester()
  @sf.panel("面板", from=Unanchored, foot=old_foot(), old_body())
  t.run_for(sheet_way_ms(t))
  let rest = painted_at(t, body_ink)
  let old_little = little(t)
  far(t)
  @sf.panel_nodes("面板", from=Unanchored, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  t.run_for(sheet_way_ms(t))
  assert_eq(painted_at(t, body_ink), rest, msg="where the host's rests")
  assert_eq(little(t), old_little, msg="dragged a little: back where the host's goes")
  far(t)
}

///|
test "小屏: a sheet whose body is nodes: drawn by the window's tree, read out a dialog by its title; what its body is given closes it, its gone not told" {
  let t = phone_tester()
  let gone = Ref(0)
  let close_it : Ref[() -> Unit] = Ref(fn() {  })
  @sf.panel_nodes("节点面板", from=Unanchored, gone=fn() { gone.val += 1 }, fn(v, close) {
    close_it.val = close
    ink_node(v, 40.0, 36.0, body_ink)
  })
  t.run_for(sheet_way_ms(t))
  assert_true(tree_said(Dialog, "节点面板") is Some(_), msg="the tree's")
  (close_it.val)()
  t.run_for(sheet_way_ms(t))
  assert_eq((@sf.presenting(), @sf.presenter_visible(), gone.val), (false, false, 0))
}

///|
/// Where the top of the sheet up is (its Dialog's), the window's.
fn sheet_top_y(t : @ui.Tester) -> Double {
  t.query(Dialog).unwrap().rect.1
}

///|
/// A sheet that grows (`grows`), dragged and tapped as a hand would: where its top is after each, and mid-way through a
/// drag far past its most (the rubber band), then dragged under its least share: closed.
fn grows_trace(t : @ui.Tester) -> Array[Double] raise {
  let seen = []
  t.run_for(sheet_way_ms(t))
  seen.push(sheet_top_y(t))
  // up some: on to the detent it is let go nearer
  let y = sheet_top_y(t)
  t.drag(195.0, y + 10.0, 195.0, y - 300.0)
  t.run_for(sheet_way_ms(t))
  seen.push(sheet_top_y(t))
  // a tap on its grabber: to the other end
  let y = sheet_top_y(t)
  t.tap(195.0, y + 10.0)
  t.run_for(sheet_way_ms(t))
  seen.push(sheet_top_y(t))
  // held far past its most: giving way, where the finger has it
  let y = sheet_top_y(t)
  t.touch_at(0, 195.0, y + 10.0, t.time())
  t.touch_at(1, 195.0, y - 200.0, t.time() + @ui.input_step_ms)
  t.run_for(@ui.input_step_ms)
  seen.push(sheet_top_y(t))
  t.touch_at(2, 195.0, y - 200.0, t.time())
  t.run_for(sheet_way_ms(t))
  seen.push(sheet_top_y(t))
  // dragged down under its least share: closed
  let y = sheet_top_y(t)
  t.drag(195.0, y + 10.0, 195.0, 800.0)
  t.run_for(sheet_way_ms(t))
  assert_false(@sf.presenting(), msg="closed")
  assert_false(@sf.presenter_visible(), msg="gone")
  seen
}

///|
test "小屏: a sheet that grows whose body is nodes: dragged up, its grabber tapped, held past its most (giving way), dragged down under its least: where the host's is after each" {
  let t = phone_tester()
  @sf.panel("面板", from=Unanchored, grows=true, foot=old_foot(), old_body())
  let old = grows_trace(t)
  @sf.panel_nodes("面板", from=Unanchored, grows=true, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  assert_eq(grows_trace(t), old)
}

///|
/// How far apart what a sheet's way is looked at is: a quarter of the shortest Move.
let sheet_look_step_ms : Double = @ui.move_least_ms / 4.0

///|
/// Where a sheet's body is drawn as it rises from opening, sheet_look_step_ms apart till it is up, then as it sinks
/// away once closed by Escape, on the device's pixels.
fn rise_trace(t : @ui.Tester) -> Array[Double] {
  let seen = []
  let steps = (sheet_way_ms(t) / sheet_look_step_ms).ceil().to_int()
  let look = fn() {
    let y = t.drawn_rects().filter(fn(r) { r.4 >> 8 == body_ink >> 8 }).map(fn(r) { r.1 })
    // (what is under the window's foot is not seen: an old view's is not drawn there at all)
    seen.push(if y.is_empty() || y[0] >= 844.0 { -1.0 } else { (y[0] * 2.0).round() / 2.0 })
  }
  for _ in 0..<steps {
    t.run_for(sheet_look_step_ms)
    look()
  }
  t.key(@ui.key_escape)
  for _ in 0..<steps {
    t.run_for(sheet_look_step_ms)
    look()
  }
  seen
}

///|
test "小屏: a sheet whose body is nodes rising and sinking away: over the time its own height takes, where the host's is all the way, let go as the host's is" {
  let t = phone_tester()
  @sf.panel("面板", from=Unanchored, foot=old_foot(), old_body())
  let old = rise_trace(t)
  @sf.panel_nodes("面板", from=Unanchored, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  // (and let go as it has sunk away and its scrim faded, as the host's: its layer held by its sinking, View::moved_by)
  assert_eq(rise_trace(t), old)
}

///|
/// How much of the window a sheet of a share of it takes here (a long list's: the things', a job's).
let sheet_share : Double = 0.8

///|
test "小屏: a sheet a share of the window tall whose body is nodes: as tall as the host's, what it holds and its foot where the host's are; dragged up, tapped, held past its most and dragged down as the host's" {
  let t = phone_tester()
  let rested = fn() raise {
    t.run_for(sheet_way_ms(t))
    let at = (sheet_top_y(t), painted_at(t, body_ink), painted_at(t, foot_ink))
    t.key(@ui.key_escape)
    t.run_for(sheet_way_ms(t))
    assert_false(@sf.presenter_visible(), msg="gone")
    at
  }
  @sf.panel("面板", from=Unanchored, tall=sheet_share, grows=true, foot=old_foot(), old_body())
  let old = rested()
  @sf.panel_nodes("面板", from=Unanchored, tall=sheet_share, grows=true, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  assert_eq(rested(), old)
  @sf.panel("面板", from=Unanchored, tall=sheet_share, grows=true, foot=old_foot(), old_body())
  let old = grows_trace(t)
  @sf.panel_nodes("面板", from=Unanchored, tall=sheet_share, grows=true, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  assert_eq(grows_trace(t), old)
}

///|
/// A sheet whose title is as it is now (`live`): untitled, then titled, where what it holds is and where its title's words
/// are each time.
fn live_trace(t : @ui.Tester, title : @signals.Signal[String]) -> Array[((Double, Double, Double, Double), (Double, Double)?)] raise {
  let seen = []
  t.run_for(sheet_way_ms(t))
  seen.push((painted_at(t, body_ink), t.find("任务")))
  title.set("任务")
  t.run_for(@ui.move_most_ms)
  seen.push((painted_at(t, body_ink), t.find("任务")))
  title.set("")
  t.run_for(@ui.move_most_ms)
  seen.push((painted_at(t, body_ink), t.find("任务")))
  t.key(@ui.key_escape)
  t.run_for(sheet_way_ms(t))
  assert_false(@sf.presenter_visible(), msg="gone")
  seen
}

///|
test "小屏: a sheet whose title is as it is now (`live`) and whose body is nodes: headed while it has a title, what it holds where the host's is each way" {
  let t = phone_tester()
  let title = @signals.signal("")
  @sf.panel("", from=Unanchored, tall=sheet_share, live=fn() { (title.get(), "", "") }, old_body())
  let old = live_trace(t, title)
  assert_true(old[1].1 is Some(_), msg="titled")
  @sf.panel_nodes("", from=Unanchored, tall=sheet_share, live=fn() { (title.get(), "", "") }, fn(v, _) {
    ink_node(v, 40.0, 36.0, body_ink)
  })
  assert_eq(live_trace(t, title), old)
}

///|
test "小屏: a sheet whose body is nodes opened by what a sheet's button does as it closes: in that one's place, from as tall as it stood, one sheet and one scrim all the way" {
  // (`tall`, `taller`: the first sheet's and the second's share of the window; 0 as tall as what it holds)
  for case in [(0.0, 0.8), (0.8, 0.0)] {
    let (tall, taller) = case
    let t = phone_tester()
    @sf.panel("面板", from=Unanchored, tall~, fn(c, close) {
      @sf.button(c, "看更多", key="more", on_press=fn() {
        close()
        @sf.panel_nodes("更多", from=Unanchored, tall=taller, fn(v, _) { ink_node(v, 40.0, 36.0, body_ink) })
      })
    })
    t.run_for(sheet_way_ms(t))
    let top0 = sheet_tops(t)
    assert_eq(top0.length(), 1, msg="\{Repr(case)}")
    assert_eq(scrim_drawn(t).length(), 1, msg="\{Repr(case)}")
    t.tap_text("看更多")
    // (the frame it was pressed in: the next where the first stood (a page of the same sheet, sliding in over the
    // first), the window as dim)
    assert_true(t.find("更多") is Some(_), msg="\{Repr(case)}")
    assert_eq(sheet_tops(t).length(), 1, msg="\{Repr(case)}: \{Repr(sheet_tops(t))}")
    assert_true((sheet_tops(t)[0] - top0[0]).abs() < 0.5, msg="\{Repr(case)}: \{Repr(sheet_tops(t))} \{Repr(top0)}")
    assert_eq(scrim_drawn(t).length(), 1, msg="\{Repr(case)}")
    // (on its way to its own height, one way only, never two sheets, the window never brighter)
    let up = taller > tall && tall == 0.0
    let mut last = top0[0]
    for _ in 0..<40 {
      t.run_for(@ui.frame_period_default)
      let tops = sheet_tops(t)
      assert_eq(tops.length(), 1, msg="\{Repr(case)}: \{Repr(tops)}")
      assert_eq(scrim_drawn(t).length(), 1, msg="\{Repr(case)}")
      assert_true(if up { tops[0] <= last + 0.5 } else { tops[0] >= last - 0.5 }, msg="\{Repr(case)}: \{Repr(tops)} after \{last}")
      last = tops[0]
    }
    assert_true(if up { last < top0[0] - 100.0 } else { last > top0[0] + 100.0 }, msg="\{Repr(case)}: \{last} \{Repr(top0)}")
    // (a step further in from the first: back is back to that one, in its place, from as tall as this stood, one
    // sheet and one scrim all the way; back again closes it)
    t.back()
    assert_true(t.find("看更多") is Some(_), msg="\{Repr(case)}")
    assert_eq(sheet_tops(t).length(), 1, msg="\{Repr(case)}: back \{Repr(sheet_tops(t))}")
    assert_true((sheet_tops(t)[0] - last).abs() < 0.5, msg="\{Repr(case)}: back \{Repr(sheet_tops(t))} from \{last}")
    for _ in 0..<40 {
      t.run_for(@ui.frame_period_default)
      assert_eq(sheet_tops(t).length(), 1, msg="\{Repr(case)}: back \{Repr(sheet_tops(t))}")
      assert_eq(scrim_drawn(t).length(), 1, msg="\{Repr(case)}: back")
    }
    assert_true((sheet_tops(t)[0] - top0[0]).abs() < 0.5, msg="\{Repr(case)}: \{Repr(sheet_tops(t))} \{Repr(top0)}")
    t.back()
    t.run_for(sheet_way_ms(t))
    assert_false(@sf.presenter_visible(), msg="\{Repr(case)}")
  }
}

///|
/// A sheet whose body is nodes (`nodes`) or an old one, at rest; its top drawn `down` down in `steps` moves (a frame's
/// apart: as fast as that makes it) and let go: whether it is open once it has had its way.
fn sheet_let_go_open(nodes : Bool, down : Double, steps : Int) -> Bool {
  let t = phone_tester()
  if nodes {
    @sf.panel_nodes("面板", from=Unanchored, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
      ink_node(v, 40.0, 36.0, body_ink)
    })
  } else {
    @sf.panel("面板", from=Unanchored, foot=old_foot(), old_body())
  }
  t.run_for(sheet_way_ms(t))
  let (_, y, _, _) = t.query(Dialog).unwrap().rect
  t.drag(195.0, y + 10.0, 195.0, y + 10.0 + down, steps~)
  t.run_for(sheet_way_ms(t))
  @sf.presenting()
}

///|
test "小屏: a sheet let go short of its line: closed flicked down, back let go slowly; past its line closed; the same for one whose body is nodes" {
  for nodes in [false, true] {
    // (40 down a frame apart in 2 moves: 1.2 points a ms, a flick; in 8, 0.3: slowly, landing short of 80)
    assert_false(sheet_let_go_open(nodes, 40.0, 2), msg="flicked 40 down (nodes \{nodes}): closed")
    assert_true(sheet_let_go_open(nodes, 40.0, 8), msg="let go slowly 40 down (nodes \{nodes}): back, open")
    // (either side of its line, slowly: 70 and 100 down in 30 moves, 0.14 and 0.2 points a ms)
    assert_true(sheet_let_go_open(nodes, 70.0, 30), msg="let go slowly 70 down (nodes \{nodes}): back, open")
    assert_false(sheet_let_go_open(nodes, 100.0, 30), msg="let go slowly 100 down (nodes \{nodes}): closed")
  }
}

///|
test "小屏: a panel of nodes a panel of nodes closes for is a page of the same sheet: it slides in as the first slides off, the sheet going to its height; back slides the first back, made once and kept" {
  let t = phone_tester()
  let made : Ref[Int] = Ref(0)
  @sf.panel_nodes("第一页", from=Unanchored, fn(v, close) {
    made.val += 1
    ink_node(v, 40.0, 36.0, body_ink)
    @sf.button_node(v, fn() { "下一步" }, fn() {
      close()
      @sf.panel_nodes("第二页", from=Unanchored, tall=0.6, fn(v, _) { ink_node(v, 40.0, 36.0, foot_ink) })
    })
    |> ignore
  })
  t.run_for(sheet_way_ms(t))
  let top0 = sheet_tops(t)
  assert_eq(top0.length(), 1)
  let (x0, _) = t.drawn_of("第一页").unwrap()
  assert_true(t.query(Button, label="返回") is None, msg="a back key on the first page")
  t.tap_text("下一步")
  assert_true(@sf.presenting())
  // (the frame it was pressed in: one sheet where it stood, the first page in place still, the second off to its end)
  assert_eq(sheet_tops(t).length(), 1, msg="\{Repr(sheet_tops(t))}")
  assert_true((sheet_tops(t)[0] - top0[0]).abs() < 0.5, msg="\{Repr(sheet_tops(t))} \{Repr(top0)}")
  assert_eq(scrim_drawn(t).length(), 1)
  // (on the way: the first off to the start, the second in from the end, the sheet up to the second's height, never
  // two sheets, one scrim)
  let mut first_x = x0
  let mut top = top0[0]
  for _ in 0..<40 {
    t.run_for(@ui.frame_period_default)
    assert_eq(sheet_tops(t).length(), 1, msg="\{Repr(sheet_tops(t))}")
    assert_eq(scrim_drawn(t).length(), 1)
    assert_true(sheet_tops(t)[0] <= top + 0.5, msg="\{Repr(sheet_tops(t))} after \{top}")
    top = sheet_tops(t)[0]
    match t.drawn_of("第一页") {
      Some((x, _)) => {
        assert_true(x <= first_x + 0.5, msg="the first page at \{x} after \{first_x}")
        first_x = x
      }
      None => ()
    }
  }
  assert_true(first_x < x0 - 300.0, msg="the first page off to the start: \{first_x} from \{x0}")
  assert_true((top - (844.0 - 0.6 * 844.0)).abs() < 1.0, msg="as tall as the second: \{top}")
  let (x2, _) = t.drawn_of("第二页").unwrap()
  assert_true(x2 > 0.0 && x2 < 390.0, msg="the second page in place: \{x2}")
  assert_true(t.query(Button, label="返回") is Some(_), msg="no back key on the second page")
  // back: the first again where it was, as tall as it was, made once
  t.back()
  assert_true(@sf.presenting())
  for _ in 0..<40 {
    t.run_for(@ui.frame_period_default)
    assert_eq(sheet_tops(t).length(), 1, msg="back: \{Repr(sheet_tops(t))}")
    assert_eq(scrim_drawn(t).length(), 1)
  }
  assert_true((sheet_tops(t)[0] - top0[0]).abs() < 0.5, msg="\{Repr(sheet_tops(t))} \{Repr(top0)}")
  assert_true((t.drawn_of("第一页").unwrap().0 - x0).abs() < 0.5)
  assert_true(t.drawn_of("第二页") is None || t.drawn_of("第二页").unwrap().0 >= 390.0, msg="the second page gone")
  assert_eq(made.val, 1)
  // its back key (the second page's) the same; back from the first closes the sheet
  t.tap_text("下一步")
  t.run_for(sheet_way_ms(t))
  t.click(Button, label="返回")
  t.run_for(sheet_way_ms(t))
  assert_true(@sf.presenting() && t.find("下一步") is Some(_))
  assert_eq(made.val, 1)
  t.back()
  t.run_for(sheet_way_ms(t))
  assert_false(@sf.presenter_visible())
}

///|
test "小屏: an old panel an old panel closes for is a page of the same sheet: back to the first as it was left, scrolled; a press above closes all, each let go of once" {
  let t = phone_tester()
  let said : Array[String] = []
  // (its button in its foot: in reach however far what it holds is scrolled)
  let foot = fn(c : @ui.Ctx, close : () -> Unit) {
    @sf.button(c, "下一步", key="next", on_press=fn() {
      close()
      @sf.panel("第二页", from=Unanchored, tall=0.6, gone=fn() { said.push("second gone") }, fn(c, _) {
        c.text("第二页内容") |> ignore
      })
    })
    |> ignore
  }
  @sf.panel("第一页", from=Unanchored, foot~, gone=fn() { said.push("first gone") }, fn(c, _) {
    for i in 0..<40 {
      c.text("第 \{i} 行") |> ignore
    }
  })
  t.run_for(sheet_way_ms(t))
  let y0 = t.drawn_of("第 0 行").unwrap().1
  t.drag(195.0, 600.0, 195.0, 540.0)
  t.run_for(fling_over_ms)
  let y1 = t.drawn_of("第 0 行").unwrap().1
  assert_true(y1 < y0 - 30.0, msg="not scrolled: \{y0} \{y1}")
  t.tap_text("下一步")
  t.run_for(sheet_way_ms(t))
  assert_true(t.find("第二页内容") is Some(_))
  assert_true(t.find("第 0 行") is None, msg="the first page shows still")
  assert_eq(said, [])
  t.back()
  t.run_for(sheet_way_ms(t))
  assert_true(@sf.presenting())
  assert_true((t.drawn_of("第 0 行").unwrap().1 - y1).abs() < 0.5, msg="not as it was left: \{Repr(t.drawn_of("第 0 行"))} \{y1}")
  assert_eq(said, ["second gone"])
  t.tap_text("下一步")
  t.run_for(sheet_way_ms(t))
  t.tap(195.0, 40.0)
  t.run_for(sheet_way_ms(t))
  assert_false(@sf.presenter_visible())
  assert_eq(said, ["second gone", "second gone", "first gone"])
}

///|
/// How long what scrolls goes on after a finger throws it, at most: its fling over by then (what a test runs to before
/// it reads where it was left).
let fling_over_ms : Double = 3000.0
