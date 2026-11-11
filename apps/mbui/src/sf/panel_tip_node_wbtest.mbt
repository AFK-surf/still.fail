// A key a page makes itself in a panel's body showing its name by it (panel_tip_node): in the panel's layer of tips,
// as the pointer rests on it; Escape shuts the tip first, then the panel. Outside a panel, none.

///|
/// A panel of nodes (a dialog in the middle of a window 1200 by 800, with keyboard and mouse) holding a key of its own,
/// 24 round, named 转一转, its tip by it; opened.
fn tip_panel_tester() -> @ui.Tester {
  presenters_reset()
  let open = fn(_from : Anchor) {
    panel_nodes("有键的面板", from=Unanchored, fn(v, _) {
      v.box(fn(k) {
        k.width(Is(Some(24.0))).height(Is(Some(24.0))).radius(Is(12.0)) |> ignore
        presses_node(k, fn() {  })
        k.says(Is(Some(@view.said(Button, label="转一转")))) |> ignore
        panel_tip_node(k, fn() { "转一转" })
      })
      |> ignore
    })
  }
  let t = @ui.Tester::new(@ui.old_views_here, tree=presented_tree(presenting_view(open)), w=1200.0, h=800.0, platform=0)
  t.check_looks(false)
  t.draw()
  t.tap_text("打开")
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a key of a panel's own shows its name by it as the pointer rests on it, over the panel; Escape shuts the tip, then the panel" {
  let t = tip_panel_tester()
  let tips = fn() { t.semantics().filter(fn(s) { s.role == Tooltip && s.label == "转一转" }) }
  assert_true(presenter_visible(), msg="up")
  assert_eq(tips().length(), 0, msg="none till the pointer rests on it")
  let k = t.get(Button, label="转一转")
  t.move_to(k.rect.0 + 12.0, k.rect.1 + 12.0)
  t.run_for(tip_delay_ms + tip_settled_ms)
  assert_eq(tips().length(), 1, msg="shown")
  // (by it: under it, across its middle)
  let tip = tips()[0].rect
  assert_true(tip.1 >= k.rect.1 + k.rect.3, msg="under the key: \{Repr(tip)}, the key \{Repr(k.rect)}")
  assert_true((tip.0 + tip.2 / 2.0 - (k.rect.0 + k.rect.2 / 2.0)).abs() < 1.0, msg="across its middle: \{Repr(tip)}, the key \{Repr(k.rect)}")
  t.key(@ui.key_escape)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(tips().length(), 0, msg="Escape: the tip shut")
  assert_true(presenter_visible(), msg="Escape: the panel still up")
  t.key(@ui.key_escape)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_false(presenter_visible(), msg="Escape again: the panel closed")
}

///|
test "a key outside a panel said to show its name by it shows none" {
  presenters_reset()
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(k) {
      k.width(Is(Some(24.0))).height(Is(Some(24.0))) |> ignore
      presses_node(k, fn() {  })
      k.says(Is(Some(@view.said(Button, label="转一转")))) |> ignore
      panel_tip_node(k, fn() { "转一转" })
    })
    |> ignore
  })
  t.draw()
  let k = t.get(Button, label="转一转")
  t.move_to(k.rect.0 + 12.0, k.rect.1 + 12.0)
  t.run_for(tip_delay_ms + tip_settled_ms)
  assert_eq(t.semantics().filter(fn(s) { s.role == Tooltip }).length(), 0)
}
