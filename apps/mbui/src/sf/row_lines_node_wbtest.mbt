// The row's lines made once: their room, gap and the controls in its first line as its contents and width change.

///|
test "row lines keep the first line's actions and give the lines below the whole room at narrow and wide widths" {
  for spaced in [false, true] {
    let width = @signals.signal(360.0)
    let title = @signals.signal("A short file name")
    let failed = @signals.signal(false)
    let row : Ref[@view.View?] = Ref(None)
    let first : Ref[@view.View?] = Ref(None)
    let name : Ref[@view.View?] = Ref(None)
    let close : Ref[@view.View?] = Ref(None)
    let retry : Ref[@view.View?] = Ref(None)
    let path : Ref[@view.View?] = Ref(None)
    let detail : Ref[@view.View?] = Ref(None)
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=500.0, h=300.0, platform=2)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(line) {
        line.row(Is(true)).width(By(fn() { Some(width.get()) })).gap(Is(12.0)) |> ignore
        line.box(fn(mark) { mark.width(Is(Some(24.0))).height(Is(Some(24.0))) |> ignore }) |> ignore
        row.val = Some(row_lines_node(line, spaced~, fn(h) {
          first.val = Some(h)
          name.val = Some(words_node(h, fn() { title.get() }, fn() { desk_list_title.then(cut_words) }))
          name.val.unwrap().grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          h.show(fn() { failed.get() }, fn(end) {
            retry.val = Some(icon_button_node(end, "retry", fn() { "Retry" }, fn() {  }, size=34.0))
          })
          close.val = Some(icon_button_node(h, "close", fn() { "Close" }, fn() {  }, size=34.0))
        }, fn(b) {
          path.val = Some(words_node(b, fn() { "The destination contains a long path and a message that needs room to wrap." }, fn() { pg_note }))
          detail.val = Some(b.box(fn(d) { d.height(Is(Some(20.0))) |> ignore }))
        }))
      })
      |> ignore
    })
    t.draw()
    let check = fn(expected_width : Double, has_retry : Bool) {
      let (x, _, w, _) = row.val.unwrap().rect()
      let (hx, hy, hw, hh) = first.val.unwrap().rect()
      let (nx, _, nw, _) = name.val.unwrap().rect()
      let (cx, cy, cw, ch) = close.val.unwrap().rect()
      let (px, py, pw, ph) = path.val.unwrap().rect()
      let (dx, dy, dw, _) = detail.val.unwrap().rect()
      let gap = if spaced { 2.0 } else { 0.0 }
      assert_eq((x, w), (36.0, expected_width - 36.0))
      assert_eq((hx, hw, px, pw, dx, dw), (x, w, x, w, x, w))
      assert_eq((py - hy - hh, dy - py - ph), (gap, gap))
      assert_eq((cw, cx + cw), (34.0, expected_width))
      assert_true((cy + ch / 2.0 - hy - hh / 2.0).abs() < 0.5, msg="the action is centered on the first line")
      assert_true(nx + nw <= cx - 12.0, msg="title \{name.val.unwrap().rect()}, close \{close.val.unwrap().rect()}")
      if has_retry {
        let (rx, _, rw, _) = retry.val.unwrap().rect()
        assert_eq((rw, cx - rx - rw), (34.0, 12.0))
        assert_true(nx + nw <= rx - 12.0, msg="title \{name.val.unwrap().rect()}, retry \{retry.val.unwrap().rect()}")
      }
    }
    check(360.0, false)
    width.set(220.0)
    title.set("A very long file name that must give its room to the retry and close buttons.txt")
    failed.set(true)
    t.draw()
    check(220.0, true)
    let narrow_path_h = path.val.unwrap().rect().3
    width.set(420.0)
    t.draw()
    check(420.0, true)
    assert_true(narrow_path_h > path.val.unwrap().rect().3, msg="the line under the title wraps when its room narrows")
    t.set_font_scale(2.0)
    width.set(220.0)
    t.draw()
    check(220.0, true)
  }
}

///|
test "row lines retain their children as words change and leave their actions reachable by touch, keyboard and accessibility" {
  let title = @signals.signal("Uploading")
  let visible = @signals.signal(true)
  let pressed = Ref(0)
  let row : Ref[@view.View?] = Ref(None)
  let close : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=300.0, h=200.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.row(Is(true)) |> ignore
    root.show(fn() { visible.get() }, fn(host) {
      host.row(Is(true)).grow(Is(1.0)) |> ignore
      row.val = Some(row_lines_node(host, fn(h) {
        words_node(h, fn() { title.get() }, fn() { desk_list_title.then(cut_words) })
        .grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        close.val = Some(icon_button_node(h, "close", fn() { "Close" }, fn() { pressed.val += 1 }, size=34.0))
      }, fn(b) {
        words_node(b, fn() { "The file path" }, fn() { pg_note }) |> ignore
      }))
    })
  })
  t.draw()
  let row_id = row.val.unwrap().id()
  let close_id = close.val.unwrap().id()
  title.set("Upload failed with a longer explanation")
  t.draw()
  assert_eq((row.val.unwrap().id(), close.val.unwrap().id()), (row_id, close_id))
  assert_true(t.semantics().iter().any(fn(s) { s.role == Button && s.label == "Close" }))
  t.tab()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Close"))
  t.enter()
  let (x, y, w, h) = close.val.unwrap().rect()
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.touch(2, x + w / 2.0, y + h / 2.0)
  t.touch_raw(0, 1, x + w / 2.0, y + h / 2.0, t.time())
  t.touch_raw(2, 1, x + w / 2.0, y + h / 2.0, t.time())
  assert_true(@ui.view_tree().unwrap().activate_at(close_id, t.time()))
  assert_eq(pressed.val, 4)
  visible.set(false)
  t.draw()
  assert_false(@ui.view_tree().unwrap().activate_at(close_id, t.time()))
  assert_false(t.semantics().iter().any(fn(s) { s.role == Button && s.label == "Close" }))
}
