// A sheet can hold an old view while callers move their content to the retained tree.

///|
test "a tree sheet closed before its first frame does not build its old island" {
  let open = @signals.signal(false)
  let built = Ref(0)
  let told = Ref(0)
  let gone = Ref(0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, time=0.0, tree=fn(root : @view.View) {
    @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, gone=fn() { gone.val += 1 }, fn(sheet) {
      @ui.old(sheet, natural=true, fn(c) {
        built.val += 1
        c.tell("old sheet body", fn() { told.val += 1 })
        c.box(h=Px(100.0), fn() { c.text("Old sheet body") |> ignore }) |> ignore
      }) |> ignore
    })
  })
  t.draw()
  open.set(true)
  t.advance(sheet_test_100_ms)
  open.set(false)
  assert_eq((built.val, told.val, gone.val), (0, 0, 0))
  t.frame_at(t.time())
  assert_eq((built.val, told.val), (0, 0))
  assert_eq(gone.val, 0, msg="the sheet still retains its closing lifecycle")
  t.run_for(sheet_test_late_ms)
  assert_eq((built.val, told.val, gone.val), (0, 0, 1))
}

///|
test "a tree sheet retains an already built old island as it leaves" {
  let open = @signals.signal(false)
  let built = Ref(0)
  let pressed = Ref(0)
  let outside = @ui.Field::new()
  let inside = @ui.Field::new()
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, time=0.0, tree=fn(root : @view.View) {
    @ui.field(root, outside, placeholder="Page field") |> ignore
    @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, fn(sheet) {
      @ui.old(sheet, natural=true, fn(c) {
        built.val += 1
        let id = c.id("old sheet button")
        c.on_press(id, fn() { pressed.val += 1 })
        c.box(id~, h=Px(80.0), fn() { c.text("Old sheet button") |> ignore }) |> ignore
        c.editor("old-sheet-field", field=inside, placeholder="Old sheet field") |> ignore
      }) |> ignore
    })
  })
  t.draw()
  t.tap_text("Page field")
  let focus_before = t.ctx().focused_id()
  assert_true(focus_before != 0)
  open.set(true)
  t.run_for(sheet_test_late_ms)
  assert_true(built.val > 0)
  t.tap_text("Old sheet button")
  assert_eq(pressed.val, 1)
  t.tap_text("Old sheet field")
  assert_true(t.ctx().focused_id() != focus_before)
  open.set(false)
  assert_eq(t.ctx().focused_id(), focus_before)
  t.advance(sheet_test_100_ms)
  t.frame_at(t.time())
  assert_true(t.drawn_text().contains("Old sheet button"))
}

///|
test "an old island outside a tree sheet retains the normal leaving behavior" {
  let open = @signals.signal(false)
  let built = Ref(0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, time=0.0, tree=fn(root : @view.View) {
    root.show(fn() { open.get() }, leave=sheet_test_late_ms, fn(layer) {
      @ui.old(layer, natural=true, fn(c) {
        built.val += 1
        c.box(h=Px(100.0), fn() { c.text("Unscoped old content") |> ignore }) |> ignore
      }) |> ignore
    })
  })
  t.draw()
  open.set(true)
  open.set(false)
  t.frame_at(t.time())
  assert_true(built.val > 0)
}

///|
test "an unbuilt old island builds when its leaving tree sheet reopens" {
  let open = @signals.signal(false)
  let built = Ref(0)
  let gone = Ref(0)
  let t = @ui.Tester::new(fn(c) { @ui.old_views_here(c) }, time=0.0, tree=fn(root : @view.View) {
    @kit.sheet_node(root, fn() { open.get() }, fn() { open.set(false) }, gone=fn() { gone.val += 1 }, fn(sheet) {
      @ui.old(sheet, natural=true, fn(c) {
        built.val += 1
        c.box(h=Px(100.0), fn() { c.text("Reopened old content") |> ignore }) |> ignore
      }) |> ignore
    })
  })
  t.draw()
  open.set(true)
  t.advance(sheet_test_100_ms)
  open.set(false)
  t.frame_at(t.time())
  assert_eq(built.val, 0)
  open.set(true)
  t.run_for(sheet_test_late_ms)
  assert_true(built.val > 0)
  assert_true(t.drawn_text().contains("Reopened old content"))
  assert_eq(gone.val, 0)
  open.set(false)
  t.run_for(sheet_test_late_ms)
  assert_eq(gone.val, 1)
}
