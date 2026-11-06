// The choice row follows state in place, and its row and independently actionable end take only their own presses.

///|
test "choice row follows its label, note, ink, selection and busy state without remaking the row or its trail" {
  for look in [Narrow, Wide] {
    let label = @signals.signal("Model")
    let note = @signals.signal("")
    let ink = @signals.signal(0x445566FFL)
    let chosen = @signals.signal(false)
    let disabled = @signals.signal(false)
    let busy = @signals.signal(false)
    let there = @signals.signal(true)
    let released = Ref(0)
    let row : Ref[@view.View?] = Ref(None)
    let trail : Ref[@view.View?] = Ref(None)
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=320.0, h=300.0, platform=2)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      look_lent(root, look)
      root.show(fn() { there.get() }, fn(p) {
        row.val = Some(choice_row_node(p, fn() { label.get() }, fn() { chosen.get() }, fn() {  },
          note=fn() { note.get() }, ink=fn() { ink.get() }, disabled=fn() { disabled.get() }, busy=fn() { busy.get() },
          lead=fn(l) { l.width(Is(Some(18.0))).height(Is(Some(18.0))) |> ignore },
          tag=fn(v) { words_node(v, fn() { "Station" }, fn() { row_tag }) |> ignore },
          trail=fn(v) {
            trail.val = Some(button_node(v, fn() { "Repick" }, fn() {  }, tone=Ghost))
            trail.val.unwrap().owns(fn() { released.val += 1 }) |> ignore
          }))
      })
    })
    t.draw()
    let tree = @ui.view_tree().unwrap()
    let row_id = row.val.unwrap().id()
    let trail_id = trail.val.unwrap().id()
    assert_eq(t.get(Button, label="Model").selected, Some(false))
    assert_eq(tree.drawn().iter().find_first(fn(d) { d.words == "Model" }).map(fn(d) { d.ink }), Some(0x445566FFL))
    assert_false(tree.drawn().iter().any(fn(d) { tree.drawn_name(d.id) == "/icon/check/" }))
    label.set("Renamed")
    note.set("A note below")
    ink.set(0x778899FFL)
    chosen.set(true)
    t.draw()
    assert_eq((row.val.unwrap().id(), trail.val.unwrap().id()), (row_id, trail_id))
    assert_eq(t.get(Button, label="Renamed").selected, Some(true))
    assert_eq(tree.drawn().iter().find_first(fn(d) { d.words == "Renamed" }).map(fn(d) { d.ink }), Some(0x778899FFL))
    assert_true(t.find("A note below") is Some(_))
    assert_true(tree.drawn().iter().any(fn(d) { tree.drawn_name(d.id) == "/icon/check/" }))
    disabled.set(true)
    t.draw()
    assert_true(t.get(Button, label="Renamed").disabled)
    assert_eq(tree.drawn().iter().find_first(fn(d) { d.words == "Renamed" }).map(fn(d) { d.ink }), Some(theme().p.subtle))
    disabled.set(false)
    t.draw()
    assert_eq(tree.drawn().iter().find_first(fn(d) { d.words == "Renamed" }).map(fn(d) { d.ink }), Some(0x778899FFL))
    busy.set(true)
    t.draw()
    assert_true(t.get(Button, label="Renamed").disabled)
    assert_false(t.get(Button, label="Repick").disabled)
    assert_false(tree.drawn().iter().any(fn(d) { tree.drawn_name(d.id) == "/icon/check/" }))
    busy.set(false)
    note.set("")
    t.draw()
    assert_eq((row.val.unwrap().id(), trail.val.unwrap().id()), (row_id, trail_id))
    assert_true(tree.drawn().iter().any(fn(d) { tree.drawn_name(d.id) == "/icon/check/" }))
    there.set(false)
    t.draw()
    assert_eq(released.val, 1)
  }
}

///|
test "a choice's custom body replaces its words while its label and selection stay live" {
  for look in [Narrow, Wide] {
    let label = @signals.signal("Font")
    let chosen = @signals.signal(false)
    let builds = Ref(0)
    let unused = Ref(0)
    let body : Ref[@view.View?] = Ref(None)
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=320.0, h=180.0, platform=2)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      look_lent(root, look)
      choice_row_node(root, fn() { label.get() }, fn() { chosen.get() }, fn() {  },
        note=fn() { "This note is replaced" },
        lead=fn(_) { unused.val += 1 }, tag=fn(_) { unused.val += 1 },
        body=fn(p) {
          builds.val += 1
          body.val = Some(words_node(p, fn() { "Custom face" }, fn() { desk_list_title }))
        }) |> ignore
    })
    t.draw()
    let tree = @ui.view_tree().unwrap()
    let body_id = body.val.unwrap().id()
    assert_eq((builds.val, unused.val), (1, 0))
    assert_true(t.find("Custom face") is Some(_))
    assert_true(t.find("This note is replaced") is None)
    assert_eq(t.get(Button, label="Font").selected, Some(false))
    label.set("Typeface")
    chosen.set(true)
    t.draw()
    assert_eq((builds.val, body.val.unwrap().id()), (1, body_id))
    assert_eq(t.get(Button, label="Typeface").selected, Some(true))
    assert_true(tree.drawn().iter().any(fn(d) { tree.drawn_name(d.id) == "/icon/check/" }))
  }
}

///|
test "choice row and its trail take their own mouse, finger, keyboard and accessibility presses, including when the row is off" {
  for look in [Narrow, Wide] {
    let off = @signals.signal(false)
    let busy = @signals.signal(false)
    let rows = Ref(0)
    let trails = Ref(0)
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=360.0, h=300.0, platform=0)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      look_lent(root, look)
      choice_row_node(root, fn() { "Automatic" }, fn() { true }, fn() { rows.val += 1 },
        disabled=fn() { off.get() }, busy=fn() { busy.get() },
        trail=fn(v) { button_node(v, fn() { "Repick" }, fn() { trails.val += 1 }, tone=Ghost) |> ignore }) |> ignore
    })
    t.draw()
    let choice = t.get(Button, label="Automatic")
    let end = t.get(Button, label="Repick")
    let (x, y) = (choice.rect.0 + 4.0, choice.rect.1 + choice.rect.3 / 2.0)
    let (tx, ty) = (end.rect.0 + end.rect.2 / 2.0, end.rect.1 + end.rect.3 / 2.0)
    t.touch(0, x, y); t.touch(2, x, y)
    t.touch_raw(0, 1, x, y, t.time()); t.touch_raw(2, 1, x, y, t.time())
    t.touch(0, tx, ty); t.touch(2, tx, ty)
    t.touch_raw(0, 1, tx, ty, t.time()); t.touch_raw(2, 1, tx, ty, t.time())
    assert_eq((rows.val, trails.val), (2, 2), msg="\{look}: pointer and finger")
    t.act(Button, Focus, label="Automatic")
    t.key_told(7, 0, t.time())
    t.key_told(@ui.key_space, 0, t.time())
    t.ctx().ask_action(choice.id, Activate)
    assert_eq(rows.val, 5, msg="\{look}: keyboard and reader")
    off.set(true)
    assert_true(t.get(Button, label="Automatic").disabled)
    assert_false(t.get(Button, label="Repick").disabled)
    assert_false(t.focused().map(fn(s) { s.label == "Automatic" }).unwrap_or(false))
    t.key_told(7, 0, t.time())
    t.ctx().ask_action(choice.id, Activate)
    t.touch(0, x, y); t.touch(2, x, y)
    t.touch(0, tx, ty); t.touch(2, tx, ty)
    assert_eq((rows.val, trails.val), (5, 3), msg="\{look}: disabled row")
    off.set(false)
    busy.set(true)
    t.touch_raw(0, 1, x, y, t.time()); t.touch_raw(2, 1, x, y, t.time())
    t.touch_raw(0, 1, tx, ty, t.time()); t.touch_raw(2, 1, tx, ty, t.time())
    assert_eq((rows.val, trails.val), (5, 4), msg="\{look}: busy row")
  }
}

///|
test "choice row follows a panel's changing reach, words inset and small-panel corner without replacing the row" {
  for look in [Narrow, Wide] {
    let where_ : @signals.Signal[PanelRowContext] = @signals.signal({ sides_in: 24.0, rows_out: 8.0, words_in: 0.0, small: false })
    let held : Ref[@view.View?] = Ref(None)
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=320.0, h=300.0, platform=2)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      look_lent(root, look)
      root.padding(Is((20.0, 0.0, 20.0, 0.0))) |> ignore
      panel_rows_lent(root, fn() { where_.get() })
      held.val = Some(choice_row_node(root, fn() { "Choice" }, fn() { false }, fn() {  }))
    })
    t.draw()
    let tree = @ui.view_tree().unwrap()
    let id = held.val.unwrap().id()
    let row = fn() { tree.drawn_of(id).unwrap() }
    let words = fn() { tree.drawn().iter().find_first(fn(d) { d.words == "Choice" }).unwrap() }
    assert_eq((row().x, row().w, words().x), (12.0, 296.0, 20.0), msg="\{look}: reach")
    where_.set({ sides_in: 24.0, rows_out: 8.0, words_in: 20.0, small: false })
    t.draw()
    assert_eq((row().x, row().w, words().x), (20.0, 280.0, 40.0), msg="\{look}: words inset")
    where_.set({ sides_in: 24.0, rows_out: 0.0, words_in: 0.0, small: true })
    t.draw()
    assert_eq((row().x, row().w, words().x), (20.0, 280.0, 20.0 + text_in), msg="\{look}: small panel")
    assert_eq(row().radius, small_panel_inner(r_menu), msg="\{look}: small-panel corner")
    assert_eq(held.val.unwrap().id(), id)
  }
}

///|
test "choice rows in either kind of panel group keep their own inset" {
  for look in [Narrow, Wide] {
    for card in [false, true] {
      let where_ : @signals.Signal[PanelRowContext] = @signals.signal({ sides_in: 24.0, rows_out: 8.0, words_in: 20.0, small: false })
      let held : Ref[@view.View?] = Ref(None)
      let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=300.0, platform=2)
      @ui.set_view_app(fn(root) {
        @ui.set_tree_theme(ui_theme_now)
        look_lent(root, look)
        panel_rows_lent(root, fn() { where_.get() })
        group_node(root, fn(g) {
          held.val = Some(choice_row_node(g, fn() { "Choice" }, fn() { false }, fn() {  }))
        }, card~)
      })
      let inset = fn() {
        let tree = @ui.view_tree().unwrap()
        let row = tree.drawn_of(held.val.unwrap().id()).unwrap()
        let title = tree.drawn().iter().find_first(fn(d) { d.words == "Choice" }).unwrap()
        title.x - row.x
      }
      t.draw()
      assert_eq(inset(), text_in, msg="\{look}, card=\{card}: card inset")
      where_.set({ sides_in: 32.0, rows_out: 8.0, words_in: 30.0, small: false })
      t.draw()
      assert_eq(inset(), text_in, msg="\{look}, card=\{card}: changing panel inset")
    }
  }
}

///|
test "choice row keeps its lead and end on the first line above a note and gives its title room beside a tag" {
  for look in [Narrow, Wide] {
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=320.0, h=300.0, platform=2)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      look_lent(root, look)
      choice_row_node(root, fn() { "A long model name" }, fn() { true }, fn() {  }, note=fn() { "A note under the title" },
        lead=fn(l) { l.width(Is(Some(18.0))).height(Is(Some(18.0))).ground(Is(0x123456FFL)) |> ignore },
        tag=fn(v) { words_node(v, fn() { "Station" }, fn() { row_tag }) |> ignore },
        trail=fn(v) { button_node(v, fn() { "Repick" }, fn() {  }, tone=Ghost) |> ignore }) |> ignore
    })
    t.draw()
    let tree = @ui.view_tree().unwrap()
    let title = tree.drawn().iter().find_first(fn(d) { d.words == "A long model name" }).unwrap()
    let note = tree.drawn().iter().find_first(fn(d) { d.words == "A note under the title" }).unwrap()
    let tag = tree.drawn().iter().find_first(fn(d) { d.words == "Station" }).unwrap()
    let lead = tree.drawn().iter().find_first(fn(d) { d.ground == 0x123456FFL }).unwrap()
    let end = t.get(Button, label="Repick").rect
    assert_true(lead.x + lead.w <= title.x, msg="\{look}: lead precedes title")
    assert_true(title.x + title.w <= tag.x, msg="\{look}: tag follows title")
    assert_true(tag.x + tag.w <= end.0, msg="\{look}: end follows tag")
    assert_true(note.y >= title.y + title.h, msg="\{look}: note below first line")
    assert_true(end.1 < note.y, msg="\{look}: end on first line")
  }
}

///|
test "a wide choice puts its tag just after a short title" {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=360.0, h=160.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    look_lent(root, Wide)
    choice_row_node(root, fn() { "A" }, fn() { false }, fn() {  },
      tag=fn(v) { words_node(v, fn() { "Station" }, fn() { row_tag }) |> ignore }) |> ignore
  })
  t.draw()
  let drawn = @ui.view_tree().unwrap().drawn()
  let title = drawn.iter().find_first(fn(d) { d.words == "A" }).unwrap()
  let tag = drawn.iter().find_first(fn(d) { d.words == "Station" }).unwrap()
  assert_true(title.w < 30.0, msg="the title keeps its natural width")
  assert_eq(tag.x, title.x + title.w + 6.0, msg="the tag follows the title")
}
