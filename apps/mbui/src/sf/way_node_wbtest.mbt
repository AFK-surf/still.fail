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
  large.set(true)
  t.draw()
  assert_true(t.rect_of("Home").unwrap().2 > before)
  path.set(["Home", "Projects"])
  t.draw()
  assert_eq(way_node_links(t), ["Home"])
  t.tap_text("Projects")
  assert_eq(went, [])
}
