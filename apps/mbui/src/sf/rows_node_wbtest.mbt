// A long list's fixed filter, row column and foot in a page's own arrangement, including a pane and a changing inset.

///|
fn rows_columns_at(w : Double, pane : Bool) -> ((Double, Double), (Double, Double)) {
  let t = @ui.Tester::new(fn(_c) {  }, w~, h=400.0)
  let filter : Ref[@view.View?] = Ref(None)
  let row : Ref[@view.View?] = Ref(None)
  @ui.set_view_app(fn(root) {
    root.box(fn(page) {
      look_lent(page, look_for(w))
      if pane { page.lends(pane_lent, true) |> ignore }
      over_rows_node(page, fn(f) {
        // A filter supplies its own vertical room; this must not replace the page's side insets.
        f.padding(Is((0.0, 8.0, 0.0, 4.0))) |> ignore
        f.box(fn(content) {
          filter.val = Some(content)
          content.height(Is(Some(40.0))) |> ignore
        })
        |> ignore
      })
      page.box(fn(r) {
        rows_column_node(r, fn(col) {
          col.box(fn(content) {
            row.val = Some(content)
            content.height(Is(Some(40.0))) |> ignore
          })
          |> ignore
        })
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (fx, _, fw, _) = filter.val.unwrap().placed_window_now()
  let (rx, _, rw, _) = row.val.unwrap().placed_window_now()
  ((fx, fw), (rx, rw))
}

///|
test "rows nodes: a fixed filter and scrolling rows keep their own narrow room, or share the centred wide column, including in a pane" {
  assert_eq(rows_columns_at(390.0, false), ((12.0, 366.0), (0.0, 390.0)))
  assert_eq(rows_columns_at(500.0, true), ((16.0, 468.0), (0.0, 500.0)))
  assert_eq(rows_columns_at(700.0, false), ((24.0, 652.0), (24.0, 652.0)))
  assert_eq(rows_columns_at(1200.0, false), ((204.0, 792.0), (204.0, 792.0)))
  assert_eq(rows_columns_at(700.0, true), ((16.0, 668.0), (16.0, 668.0)))
  assert_eq(rows_columns_at(1200.0, true), ((204.0, 792.0), (204.0, 792.0)))
}

///|
test "rows nodes: a fixed filter keeps its node, focus and keyboard as the page changes arrangement, in a window or pane" {
  for pane in [false, true] {
    for platform in [0, 2] {
      let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=400.0, platform~)
      let width = @signals.signal(390.0)
      let filter = @ui.Field::new()
      let filter_room : Ref[@view.View?] = Ref(None)
      let row_room : Ref[@view.View?] = Ref(None)
      @ui.set_view_app(fn(root) {
        @ui.set_tree_theme(ui_theme_now)
        root.box(fn(page) {
          if pane { page.lends(pane_lent, true) |> ignore }
          over_rows_node(page, fn(f) {
            filter_room.val = Some(f)
            input_node(f, filter, placeholder="筛选") |> ignore
          }, width=fn() { width.get() })
          // The rows may be made anew as the page's arrangement changes; the filter above stays put.
          page.pick(fn() { look_for(width.get()) }, fn(rows, look) {
            look_lent(rows, look)
            rows_column_node(rows, fn(r) {
              row_room.val = Some(r)
              r.height(Is(Some(40.0))) |> ignore
            })
          })
        })
        |> ignore
      })
      let columns = fn() {
        let (fx, _, fw, _) = filter_room.val.unwrap().placed_window_now()
        let (rx, _, rw, _) = row_room.val.unwrap().placed_window_now()
        ((fx, fw), (rx, rw))
      }
      t.draw()
      let narrow = if pane { (16.0, 358.0) } else { (12.0, 366.0) }
      let middle = if pane { (16.0, 668.0) } else { (24.0, 652.0) }
      assert_eq(columns(), (narrow, (0.0, 390.0)))
      let field = t.get(TextField, label="筛选")
      let (x, y, w, h) = field.rect
      t.tap(x + w / 2.0, y + h / 2.0)
      t.type_text("模型")
      assert_eq(t.focused().map(fn(s) { s.id }), Some(field.id))
      for (w, fixed, row, typed) in [
        (700.0, middle, middle, "二"),
        (900.0, (54.0, 792.0), (54.0, 792.0), "三"),
        (390.0, narrow, (0.0, 390.0), "四"),
      ] {
        width.set(w)
        t.resize(w, 400.0)
        t.draw()
        assert_eq((columns(), t.get(TextField, label="筛选").id, t.focused().map(fn(s) { s.id })), ((fixed, row), field.id, Some(field.id)), msg="pane \{pane}, platform \{platform}, width \{w}")
        if platform == 2 { assert_true(t.ime().0) }
        t.type_text(typed)
      }
      assert_eq(filter.text(), "模型二三四")
    }
  }
}

///|
test "rows foot: follows the system inset, leaves a pane's card room, and lets a frame give its own narrow foot" {
  for pane in [false, true] {
    for wide in [false, true] {
      let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=400.0)
      let marker : Ref[@view.View?] = Ref(None)
      let page_at : Ref[@view.View?] = Ref(None)
      let extra = @signals.signal(13.0)
      @ui.set_view_app(fn(root) {
        root.box(fn(page) {
          page_at.val = Some(page)
          look_lent(page, if wide { Wide } else { Narrow })
          if pane { page.lends(pane_lent, true) |> ignore }
          rows_foot_node(page)
          page.box(fn(m) {
            marker.val = Some(m)
            m.height(Is(Some(10.0))) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      t.draw()
      let (_, before, _, _) = marker.val.unwrap().placed_window_now()
      t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":24,\"left\":0,\"right\":0}}")
      t.draw()
      let (_, after, _, _) = marker.val.unwrap().placed_window_now()
      let own = rows_foot(page_at.val.unwrap(), narrow_foot=fn() { extra.get() })
      assert_eq(before, if wide { 80.0 } else if pane { 6.0 } else { 0.0 })
      assert_eq(after, if wide { 80.0 } else { 24.0 })
      assert_eq(own, if wide { 80.0 } else { 13.0 })
      extra.set(31.0)
      assert_eq(rows_foot(page_at.val.unwrap(), narrow_foot=fn() { extra.get() }), if wide { 80.0 } else { 31.0 })
    }
  }
}

///|
test "rows nodes: typing and scrolling with a finger or a pointer keep the filter fixed and its words, with the usual focus for each input" {
  for platform in [0, 2] {
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=400.0, platform~)
    let filter = @ui.Field::new()
    let sc = @view.Scroll::list()
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(page) {
        page.height(Is(Some(400.0))) |> ignore
        look_lent(page, Narrow)
        over_rows_node(page, fn(f) { input_node(f, filter, placeholder="筛选") |> ignore })
        page.box(fn(list) {
          list.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          list.scrolls_window(sc, fn() { Array::makei(30, fn(i) { i }) }, est=40.0, foot_room=fn() { rows_foot(list) }, fn(r, k) {
            rows_column_node(r, fn(col) {
              col.height(Is(Some(40.0))).words(Is("row \{k}")) |> ignore
            })
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    t.draw()
    let before = t.get(TextField, label="筛选").rect
    let (x, y, w, h) = before
    t.tap(x + w / 2.0, y + h / 2.0)
    t.type_text("模型")
    let had_focus = t.focused().map(fn(s) { s.label })
    let had_keyboard = t.ime().0
    if platform == 2 {
      t.drag(195.0, 350.0, 195.0, 150.0)
    } else {
      t.wheel(195.0, 300.0, 200.0)
    }
    t.run_for(@ui.move_most_ms)
    let after = t.get(TextField, label="筛选").rect
    let moved = match @ui.view_tree() {
      Some(tree) => sc.at(tree)
      None => 0.0
    }
    // A finger scrolling a list dismisses the keyboard, as for old and new fields; a wheel keeps the focus.
    let focus_after = if platform == 2 { None } else { Some("筛选") }
    assert_eq((had_focus, after, filter.text(), t.focused().map(fn(s) { s.label })), (Some("筛选"), before, "模型", focus_after), msg="platform \{platform}")
    if platform == 2 { assert_eq((had_keyboard, t.ime().0), (true, false)) }
    assert_true(moved > 0.0, msg="platform \{platform}")
    t.tap(x + w / 2.0, y + h / 2.0)
    t.type_text("二")
    assert_eq((filter.text(), t.focused().map(fn(s) { s.label })), ("模型二", Some("筛选")), msg="platform \{platform}")
  }
}

///|
test "rows foot in a windowed list follows a changed system inset without a spacer row" {
  for pane in [false, true] {
    let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=400.0)
    let sc = @view.Scroll::list()
    @ui.set_view_app(fn(root) {
      root.box(fn(list) {
        list.height(Is(Some(400.0))) |> ignore
        look_lent(list, Narrow)
        if pane { list.lends(pane_lent, true) |> ignore }
        list.scrolls_window(sc, fn() { Array::makei(30, fn(i) { i }) }, est=40.0, foot_room=fn() { rows_foot(list) }, fn(r, _) {
          r.height(Is(Some(40.0))) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    t.draw()
    let before = sc.most()
    t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":24,\"left\":0,\"right\":0}}")
    t.draw()
    assert_eq(sc.most() - before, if pane { 18.0 } else { 24.0 })
  }
}
