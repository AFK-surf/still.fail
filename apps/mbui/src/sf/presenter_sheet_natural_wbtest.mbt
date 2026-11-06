///|
test "legacy sheet column measures changing natural height without feeding back its own height" {
  for (lists, tall) in [(true, 0.0), (false, 0.7)] {
    presenters_reset()
    let rows = @signals.signal(4)
    let held = Ref(false)
    let t = @ui.Tester::new(fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() { presented(c) })
    }, w=390.0, h=800.0, platform=2)
    t.check_looks(false)
    t.draw()
    panel("详情", fn(c, _) {
      held.val = panel_held()
      panel_column(c, "column", 360.0, @ui.css("w=Full"), fn() {
        for i in 0..<rows.get() {
          panel_text(c, fn() { c.text("第\{i}行", style=paragraph) |> ignore })
        }
      })
    }, from=Unanchored, lists~, tall~)
    let seen : Array[(Bool, Double)] = []
    for count in [4, 8, 4, 80, 4] {
      rows.set(count)
      t.run_for(@ui.move_most_ms)
      seen.push((held.val, t.get(Dialog).rect.3))
      if count == 80 {
        let before = t.rect_of("第20行").unwrap().1
        t.drag(195.0, 700.0, 195.0, 350.0)
        assert_true(t.rect_of("第20行").unwrap().1 < before, msg="the column scrolls inside the sheet")
      }
    }
    if lists {
      assert_eq(seen[0], (false, 175.0))
      assert_true(seen[1].1 > seen[0].1 && seen[1].1 < 752.0)
      assert_eq(seen[2], seen[0])
      assert_eq(seen[3], (false, 752.0))
      assert_eq(seen[4], (false, 752.0))
    } else {
      assert_eq(seen, [(false, 560.0), (false, 560.0), (false, 560.0), (false, 560.0), (false, 560.0)])
    }
  }
}

///|
test "a legacy sheet keeps its fixed foot and scrolls its column after growing and resizing" {
  presenters_reset()
  let rows = @signals.signal(4)
  let pressed = Ref(0)
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() { presented(c) })
  }, w=390.0, h=800.0, platform=2)
  t.check_looks(false)
  t.draw()
  panel("详情", fn(c, _) {
    panel_column(c, "column", 360.0, @ui.css("w=Full"), fn() {
      for i in 0..<rows.get() {
        panel_text(c, fn() { c.text("第\{i}行", style=paragraph) |> ignore })
      }
    })
  }, from=Unanchored, lists=true, foot=fn(c, _) { if button(c, "固定操作") { pressed.val += 1 } })
  t.run_for(@ui.move_most_ms)
  rows.set(80)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.get(Dialog).rect.3, 752.0)
  let foot = t.rect_of("固定操作").unwrap().1
  let row = t.rect_of("第20行").unwrap().1
  t.drag(195.0, 600.0, 195.0, 250.0)
  assert_true(t.rect_of("第20行").unwrap().1 < row)
  assert_eq(t.rect_of("固定操作").unwrap().1, foot)
  t.tap_text("固定操作")
  assert_eq(pressed.val, 1)
  t.resize(360.0, 640.0)
  t.run_for(@ui.move_most_ms)
  assert_true((t.get(Dialog).rect.3 - 640.0 * sheet_most).abs() < 1.0)
  t.tap_text("固定操作")
  assert_eq(pressed.val, 2)
}
