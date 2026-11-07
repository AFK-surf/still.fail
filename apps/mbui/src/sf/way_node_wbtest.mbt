// A way in the retained tree: its changing path and room, the hidden steps, and every way of pressing them.

///|
fn way_node_look(large : Bool) -> WayLook {
  {
    line: @ui.css("row w=Full align=ACenter"),
    step: @ui.css("px=S1 py=S0_5 radius=Lg hovered{bg=Hover}"),
    words: if large { @ui.text_style(size=Ui, color=Muted, wrap=false) } else { @ui.text_style(size=Meta, color=Muted, wrap=false) },
    here: @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false),
    chevron: if large { 16.0 } else { 12.0 },
    chevron_ink: theme().p.subtle,
  }
}

///|
fn way_node_case(
  path : @signals.Signal[Array[String]],
  room : @signals.Signal[Double],
  large : @signals.Signal[Bool],
  went : Array[Int],
  last_link? : Bool = false,
  platform? : Int = 0,
) -> @ui.Tester {
  presenters_reset()
  set_dark(None)
  let t = @ui.Tester::new(fn(_c) {  }, w=1000.0, h=600.0, platform~)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(body) {
      body.padding(Is((16.0, 16.0, 16.0, 16.0))) |> ignore
      way_line_node(body, fn() { path.get() }, fn() { way_node_look(large.get()) }, fn(i) { went.push(i) },
        last_link~, width=fn() { Some(room.get()) }) |> ignore
    }) |> ignore
    @ui.old(root, fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() { presented(c) })
    }).over(Is(true)) |> @ui.old_takes_own |> ignore
    presented_nodes(root)
  })
  t.draw()
  t
}

///|
fn way_node_links(t : @ui.Tester) -> Array[String] {
  t.semantics().filter(fn(s) { s.role == Link && !s.hidden }).map(fn(s) { s.label })
}

///|
test "a way's path and room change: ancestors leave from after the first, return, and the last alone can be cut" {
  let path = @signals.signal(["Home", "Projects", "Reports", "Quarterly", "Drafts", "Final notes"], same=fn(a, b) { a == b })
  let room = @signals.signal(700.0)
  let large = @signals.signal(false)
  let went : Array[Int] = []
  let t = way_node_case(path, room, large, went)
  assert_eq(way_node_links(t), ["Home", "Projects", "Reports", "Quarterly", "Drafts"])
  assert_eq(t.lines_of("Final notes"), ["Final notes"])
  room.set(260.0)
  t.draw()
  let shown = way_node_links(t)
  assert_true(shown.contains("Home") && !shown.contains("Projects"), msg="\{shown}")
  assert_eq(t.lines_of("Final notes"), ["Final notes"])
  assert_eq(t.lines_of(way_more), [way_more])
  room.set(95.0)
  t.draw()
  assert_eq(way_node_links(t), [])
  assert_true(t.lines_of("Final")[0].has_suffix("…"))
  room.set(700.0)
  path.set(["Home", "New", "Here"])
  t.draw()
  assert_eq(way_node_links(t), ["Home", "New"])
  assert_eq(t.lines_of("Here"), ["Here"])
  assert_eq(t.lines_of(way_more), [])
  path.set([])
  t.draw()
  assert_eq(way_node_links(t), [])
  assert_eq(t.lines_of("Here"), [])
}

///|
test "a way in a row takes the room left beside another control as that room changes" {
  presenters_reset()
  let room = @signals.signal(800.0)
  let path = ["Home", "Projects", "Reports", "Quarterly", "Final notes"]
  let t = @ui.Tester::new(fn(_c) {  }, w=1000.0, h=600.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(row) {
      row.row(Is(true)).width(By(fn() { Some(room.get()) })).lines_up(Is(Some(Middle))) |> ignore
      way_line_node(row, fn() { path }, fn() { way_node_look(false) }, fn(_) {  }, in_row=true) |> ignore
      row.box(fn(other) { other.width(Is(Some(200.0))).height(Is(Some(36.0))) |> ignore }) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_eq(way_node_links(t), ["Home", "Projects", "Reports", "Quarterly"])
  room.set(350.0)
  t.draw()
  assert_true(way_node_links(t).length() < 4)
  assert_eq(t.lines_of(way_more), [way_more])
  room.set(800.0)
  t.draw()
  assert_eq(way_node_links(t), ["Home", "Projects", "Reports", "Quarterly"])
}

///|
test "a way's hidden steps open in order and go to the chosen index; changing its path closes an open menu" {
  let path = @signals.signal(["Home", "Projects", "Reports", "Quarterly", "Drafts", "Final notes"], same=fn(a, b) { a == b })
  let room = @signals.signal(260.0)
  let went : Array[Int] = []
  let t = way_node_case(path, room, @signals.signal(false), went)
  t.tap_text(way_more)
  t.run_for(@ui.move_most_ms)
  let (px, py) = t.find_last("Projects").unwrap()
  let (_, ry) = t.find_last("Reports").unwrap()
  assert_true(py < ry)
  t.tap(px, py)
  assert_eq(went, [1])
  t.tap_text(way_more)
  assert_true(presenting())
  path.set(["Elsewhere", "Different", "Last"])
  t.draw()
  assert_false(presenting())
  assert_eq(went, [1])
}

///|
test "a way closes its hidden steps menu when a wider line brings those steps back" {
  let path = @signals.signal(["Home", "Projects", "Reports", "Quarterly", "Drafts", "Final notes"], same=fn(a, b) { a == b })
  let room = @signals.signal(260.0)
  let t = way_node_case(path, room, @signals.signal(false), [])
  let more = t.get(Button).label
  assert_eq(t.get(Button, label=more).expanded, Some(false))
  t.act(Button, Focus, label=more)
  t.enter()
  assert_true(presenting())
  room.set(700.0)
  t.draw()
  assert_false(presenting())
  assert_eq(way_node_links(t), ["Home", "Projects", "Reports", "Quarterly", "Drafts"])
}

///|
test "a way's links take pointer, touch, keyboard and screen reader activation, including an optionally linked last" {
  for platform in [0, 2] {
    let path = @signals.signal(["Home", "Projects"], same=fn(a, b) { a == b })
    let went : Array[Int] = []
    let t = way_node_case(path, @signals.signal(500.0), @signals.signal(false), went, last_link=true, platform~)
    assert_eq(way_node_links(t), ["Home", "Projects"])
    t.tap_text("Home")
    t.act(Link, Focus, label="Projects")
    t.enter()
    t.act(Link, Activate, label="Projects")
    assert_eq(went, [0, 1, 1], msg="platform \{platform}")
  }
}

///|
test "a way follows its look without being remade and updates a step that becomes last" {
  let path = @signals.signal(["Home", "Projects", "Reports"], same=fn(a, b) { a == b })
  let large = @signals.signal(false)
  let went : Array[Int] = []
  let t = way_node_case(path, @signals.signal(700.0), large, went)
  let before = t.rect_of("Home").unwrap().2
  let home_id = t.get(Link, label="Home").id
  t.act(Link, Focus, label="Home")
  large.set(true)
  t.draw()
  assert_true(t.rect_of("Home").unwrap().2 > before)
  assert_eq(t.get(Link, label="Home").id, home_id)
  assert_true(t.get(Link, label="Home").focused)
  t.set_dark(true)
  set_dark(Some(true))
  t.draw()
  assert_eq(t.get(Link, label="Home").id, home_id)
  assert_true(t.get(Link, label="Home").focused)
  path.set(["Home", "Projects"])
  t.draw()
  assert_eq(way_node_links(t), ["Home"])
  assert_true(t.query(Text, label="Projects") is Some(_))
  t.tap_text("Projects")
  assert_eq(went, [])
  set_dark(None)
}

///|
test "a way's hover style follows the pointer or a finger held on a link" {
  for platform in [0, 2] {
    let path = @signals.signal(["Home", "Projects"], same=fn(a, b) { a == b })
    let went : Array[Int] = []
    let t = way_node_case(path, @signals.signal(500.0), @signals.signal(false), went, platform~)
    let (x, y, w, h) = t.rect_of("Home").unwrap()
    let (cx, cy) = (x + w / 2.0, y + h / 2.0)
    if platform == 0 {
      t.move(cx, cy)
    } else {
      t.touch(0, cx, cy)
    }
    t.draw()
    let hover = @ui.tree_theme().color(Hover)
    assert_true(t.drawn_rects().iter().any(fn(r) {
      r.4 == hover && r.0 <= x && r.1 <= y && r.0 + r.2 >= x + w && r.1 + r.3 >= y + h
    }), msg="platform \{platform}")
    t.set_dark(true)
    set_dark(Some(true))
    t.draw()
    let dark_hover = @ui.tree_theme().color(Hover)
    assert_true(dark_hover != hover)
    assert_true(t.drawn_rects().iter().any(fn(r) {
      r.4 == dark_hover && r.0 <= x && r.1 <= y && r.0 + r.2 >= x + w && r.1 + r.3 >= y + h
    }), msg="dark platform \{platform}")
    if platform == 2 {
      t.touch(2, cx, cy)
      assert_eq(went, [0])
    }
    set_dark(None)
  }
}

///|
test "a way lets go of its open menu when removed" {
  presenters_reset()
  let visible = @signals.signal(true)
  let t = @ui.Tester::new(fn(_c) {  }, w=1000.0, h=600.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.show(fn() { visible.get() }, fn(body) {
      way_line_node(body, fn() { ["Home", "Projects", "Reports", "Quarterly", "Final notes"] },
        fn() { way_node_look(false) }, fn(_) {  }, width=fn() { Some(200.0) }) |> ignore
    })
    @ui.old(root, fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() { presented(c) })
    }).over(Is(true)) |> @ui.old_takes_own |> ignore
    presented_nodes(root)
  })
  t.draw()
  t.tap_text(way_more)
  assert_true(presenting())
  visible.set(false)
  assert_false(presenting())
}
