// The presenters' panel with contents made in the window's tree, at the same stack position as old presenters.

///|
fn node_panel_tester(w : Double, h : Double, platform : Int, anchor : Ref[@view.View?], field : @ui.Field) -> @ui.Tester {
  presenters_reset()
  let t = @ui.Tester::new(fn(_c) {  }, w~, h~, platform~)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    @ui.old(root, fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() { presented(c) })
    }).over(Is(true)) |> @ui.old_takes_own |> ignore
    let b = button_node(root, fn() { "打开" }, fn() {  })
    b.over(Is(true)).offset(Is((300.0, 100.0))) |> ignore
    anchor.val = Some(b)
    root.box(fn(line) {
      line.over(Is(true)).offset(Is((40.0, 100.0))).width(Is(Some(180.0))) |> ignore
      input_node(line, field, placeholder="输入") |> ignore
    }) |> ignore
    presented_nodes(root)
  })
  t.draw()
  t
}

///|
test "node panel follows its anchor and live title without remaking its contents, leaves focus, and closes successfully" {
  for (w, platform) in [(800.0, 2), (1280.0, 0)] {
    let anchor : Ref[@view.View?] = Ref(None)
    let field = @ui.Field::new()
    let t = node_panel_tester(w, 800.0, platform, anchor, field)
    t.act(TextField, Focus, label="输入")
    let (_, ay, _, ah) = t.get(Button, label="打开").rect
    let anchor_x = @signals.signal(300.0)
    anchor.val.unwrap().offset(By(fn() { (anchor_x.get(), 100.0) })) |> ignore
    let title = @signals.signal("加载中")
    let made = Ref(0)
    let dismissed = Ref(0)
    let body_button : Ref[@view.View?] = Ref(None)
    let body_box : Ref[@view.View?] = Ref(None)
    let looks : Array[Look] = []
    present_panel_node(fn() { title.get() }, fn(parent, close) {
      made.val += 1
      looks.push(look_node(parent))
      body_box.val = Some(parent)
      parent.padding(Is((0.0, 0.0, 0.0, 0.0))) |> ignore
      body_button.val = Some(button_node(parent, fn() { "完成" }, close))
    }, from=beside_node(anchor.val.unwrap()).anchor(), focus=false, gone=fn() { dismissed.val += 1 })
    let serial = last_presented()
    t.run_for(@ui.move_most_ms)
    assert_eq(@ui.view_tree().unwrap().stack_of(body_button.val.unwrap().id()), serial)
    let (px, py, _, _) = t.get(Dialog).rect
    assert_true((px - 300.0).abs() < 0.5 && py >= ay + ah, msg="panel beside its node: \{(px, py)}")
    assert_true(body_box.val.unwrap().rect().0 >= px + panel_pad - 0.5, msg="the body's own padding leaves the panel's inset intact")
    t.type_text("甲")
    assert_eq(field.text(), "甲")
    title.set("已加载")
    anchor_x.set(400.0)
    t.draw()
    assert_true(t.find("已加载") is Some(_))
    assert_true((t.get(Dialog).rect.0 - 400.0).abs() < 0.5)
    assert_eq(made.val, 1)
    assert_true(looks.length() == 1 && looks.iter().all(fn(look) { look is Wide }))
    t.tap_text("完成")
    assert_true(!presented_open_of(serial))
    t.run_for(@kit.pop_out_ms)
    assert_eq((dismissed.val, presented_drawn_of(serial)), (0, false))
  }
}

///|
test "a tall node panel may give its body the room to manage its own scrolling" {
  let anchor : Ref[@view.View?] = Ref(None)
  let t = node_panel_tester(800.0, 400.0, 0, anchor, @ui.Field::new())
  let body : Ref[@view.View?] = Ref(None)
  present_panel_node(fn() { "日志" }, fn(parent, _) {
    body.val = Some(parent)
    parent.box(fn(spacer) { spacer.grow(Is(1.0)) |> ignore }) |> ignore
    button_node(parent, fn() { "底部操作" }, fn() {  }) |> ignore
  }, from=beside_node(anchor.val.unwrap()).anchor(), tall=0.7, scrolls=false)
  t.run_for(@ui.move_most_ms)
  let (_, by, _, bh) = body.val.unwrap().rect()
  let (_, ky, _, kh) = t.get(Button, label="底部操作").rect
  assert_true(bh > 150.0 && ky + kh <= by + bh + 0.5 && ky > by + bh / 2.0,
    msg="body \{(by, bh)}, button \{(ky, kh)}")
}

///|
test "a focused node panel returns focus to the field underneath when dismissed" {
  let anchor : Ref[@view.View?] = Ref(None)
  let field = @ui.Field::new()
  let t = node_panel_tester(1280.0, 800.0, 0, anchor, field)
  t.act(TextField, Focus, label="输入")
  present_panel_node(fn() { "面板" }, fn(parent, _) {
    button_node(parent, fn() { "操作" }, fn() {  }) |> ignore
  }, from=beside_node(anchor.val.unwrap()).anchor())
  t.run_for(@ui.move_most_ms)
  t.type_text("甲")
  assert_eq(field.text(), "")
  t.key_named("escape") |> ignore
  t.run_for(@ui.move_most_ms)
  t.type_text("乙")
  assert_eq(field.text(), "乙")
}

///|
test "node panel keeps its foot in reach while its long body scrolls" {
  let anchor : Ref[@view.View?] = Ref(None)
  let t = node_panel_tester(800.0, 400.0, 0, anchor, @ui.Field::new())
  present_panel_node(fn() { "列表" }, fn(parent, _) {
    for i in 0..<30 {
      button_node(parent, fn() { "第\{i}行" }, fn() {  }, across=true) |> ignore
    }
  }, from=beside_node(anchor.val.unwrap()).anchor(), tall=0.7, foot=fn(parent, close) {
    button_node(parent, fn() { "确定" }, close) |> ignore
  })
  t.run_for(@ui.move_most_ms)
  let (x, y, w, h) = t.get(Dialog).rect
  let (_, fy, _, fh) = t.get(Button, label="确定").rect
  assert_true(y >= 0.0 && y + h <= 400.5 && fy + fh <= y + h + 0.5)
  t.wheel(x + w / 2.0, y + h / 2.0, 2500.0)
  t.run_for(@ui.move_most_ms)
  let last = t.rect_of("第29行")
  assert_true(last is Some((_, ly, _, lh)) && ly >= y && ly + lh <= fy, msg="last \{last}, foot \{fy}")
  assert_eq(t.get(Button, label="确定").rect.1, fy)
  t.tap_text("确定")
  assert_true(!presenting())
}

///|
test "node panel dismissal respects the presenter stack and tells gone once" {
  for how in ["escape", "back", "outside"] {
    let anchor : Ref[@view.View?] = Ref(None)
    let t = node_panel_tester(1280.0, 800.0, 0, anchor, @ui.Field::new())
    let gone = Ref(0)
    present_panel_node(fn() { "面板" }, fn(parent, _) {
      button_node(parent, fn() { "正文" }, fn() {  }) |> ignore
    }, from=beside_node(anchor.val.unwrap()).anchor(), gone=fn() { gone.val += 1 })
    let first = last_presented()
    t.run_for(@ui.move_most_ms)
    confirm("确认", "说明", "继续", fn() {  })
    t.run_for(@ui.move_most_ms)
    t.key_named("escape") |> ignore
    t.run_for(@ui.move_most_ms)
    assert_true(presented_open_of(first))
    match how {
      "escape" => t.key_named("escape") |> ignore
      "back" => t.back()
      _ => t.tap(20.0, 20.0)
    }
    t.run_for(@ui.move_most_ms)
    assert_eq((gone.val, presenting(), presented_drawn_of(first)), (1, false, false))
  }
}

///|
test "a node panel can close and open another presenter without a stale action opening it twice" {
  let anchor : Ref[@view.View?] = Ref(None)
  let t = node_panel_tester(1280.0, 800.0, 0, anchor, @ui.Field::new())
  let runs = Ref(0)
  present_panel_node(fn() { "面板" }, fn(parent, close) {
    button_node(parent, fn() { "下一步" }, fn() {
      runs.val += 1
      close()
      confirm("确认", "继续？", "继续", fn() {  })
    }) |> ignore
  }, from=beside_node(anchor.val.unwrap()).anchor())
  t.run_for(@ui.move_most_ms)
  let first = last_presented()
  let id = t.get(Button, label="下一步").id
  @ui.current().ask_action(id, Activate)
  @ui.current().ask_action(id, Activate)
  t.run_for(@ui.move_most_ms)
  assert_eq((runs.val, presented_open_of(first), presenting(), t.all(Button, label="继续").length()), (1, false, true, 1))
}

///|
test "an unanchored node panel uses the centred dialog, including its live description and foot" {
  let anchor : Ref[@view.View?] = Ref(None)
  let t = node_panel_tester(1280.0, 800.0, 0, anchor, @ui.Field::new())
  let description = @signals.signal("等待")
  let made = Ref(0)
  let gone = Ref(0)
  let looks : Array[Look] = []
  present_panel_node(fn() { "详情" }, fn(parent, _) {
    made.val += 1
    looks.push(look_node(parent))
    words_node(parent, fn() { "正文" }, fn() { paragraph }) |> ignore
  }, from=Unanchored, description=fn() { description.get() }, gone=fn() { gone.val += 1 },
    foot=fn(parent, close) {
      looks.push(look_node(parent))
      button_node(parent, fn() { "完成" }, close) |> ignore
    })
  t.run_for(@ui.move_most_ms)
  let (x, _, w, _) = t.get(Dialog).rect
  assert_true((x + w / 2.0 - 640.0).abs() < 0.5)
  assert_true(t.find("等待") is Some(_))
  description.set("完成加载")
  t.draw()
  assert_true(t.find("完成加载") is Some(_))
  assert_eq(made.val, 1)
  assert_true(looks.length() == 2 && looks.iter().all(fn(look) { look is Wide }))
  let (fx, fy, fw, fh) = t.get(Button, label="完成").rect
  t.tap(fx + fw / 2.0, fy + fh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq((gone.val, presenting()), (0, false))
}
