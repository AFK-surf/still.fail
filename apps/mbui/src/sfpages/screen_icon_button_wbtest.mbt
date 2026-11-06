// Screen's old 40/20 round button and the reusable tree button it can move to.

///|
test "a Screen icon button follows its icon, label and chosen state with the old round button's chosen ground" {
  for dark in [false, true] {
    @sf.set_dark(Some(dark))
    let on = @signals.signal(false)
    let icon = @signals.signal("more")
    let label = @signals.signal("Open tools")
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
    t.check_looks(false)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.row(Is(true)) |> ignore
      root.box(fn(g) { g.width(Is(Some(60.0))) |> ignore }) |> ignore
      root.box(fn(h) {
        h.width(Is(Some(100.0))).height(Is(Some(100.0))) |> ignore
        @ui.old(h, fn(c) {
          c.with_theme(@sf.ui_theme(), fn() {
            round_button(c, "old-screen-tools", icon.get(), "old " + label.get(), on=on.get()) |> ignore
          })
        }).grow(Is(1.0)) |> ignore
      }) |> ignore
      root.box(fn(h) {
        h.width(Is(Some(100.0))).height(Is(Some(100.0))) |> ignore
        @sf.icon_button_node(
          h,
          "more",
          fn() { "new " + label.get() },
          fn() {  },
          size=40.0,
          icon_size=20.0,
          icon_now=fn() { icon.get() },
          on=fn() { on.get() },
          ink=fn() { @sf.theme().p.text },
          quiet=fn() { @sf.theme().p.text },
          selected_alpha=0.10,
          hover_alpha=0.0,
        ) |> ignore
      }) |> ignore
    })
    t.draw()
    let old = t.get(Button, label="old Open tools")
    let node = t.get(Button, label="new Open tools")
    assert_eq((old.rect.2, old.rect.3, node.rect.2, node.rect.3), (40.0, 40.0, 40.0, 40.0))
    assert_eq((old.pressed, node.pressed), (Some(false), Some(false)))
    let grounds_at = fn(rect : (Double, Double, Double, Double)) {
      t.drawn_rects().filter(fn(r) { r.0 == rect.0 && r.1 == rect.1 && r.2 == 40.0 && r.3 == 40.0 }).map(fn(r) { r.4 })
    }
    t.move(old.rect.0 + 20.0, old.rect.1 + 20.0)
    t.run_for(@sf.dur_ms)
    let old_hover = grounds_at(old.rect)
    t.move(node.rect.0 + 20.0, node.rect.1 + 20.0)
    t.run_for(@sf.dur_ms)
    assert_eq(grounds_at(node.rect), old_hover, msg="Screen has no separate hover ground")
    let before = t.drawlist()
    icon.set("close")
    t.draw()
    assert_true(before != t.drawlist(), msg="the icon changes without remaking the button")
    label.set("Close tools")
    on.set(true)
    t.draw()
    let old = t.get(Button, label="old Close tools")
    let node = t.get(Button, label="new Close tools")
    assert_eq((old.pressed, node.pressed), (Some(true), Some(true)))
    let grounds = t.drawn_rects().filter(fn(r) { r.2 == 40.0 && r.3 == 40.0 })
    let old_ground = grounds.filter(fn(r) { r.0 == old.rect.0 && r.1 == old.rect.1 })
    let node_ground = grounds.filter(fn(r) { r.0 == node.rect.0 && r.1 == node.rect.1 })
    assert_eq(old_ground.length(), 1)
    assert_eq(node_ground.length(), 1)
    assert_eq(old_ground[0].4, node_ground[0].4, msg="Screen's chosen 10% Fg ground")
    t.move(node.rect.0 + 20.0, node.rect.1 + 20.0)
    t.run_for(@sf.dur_ms)
    let hovered = t.drawn_rects().filter(fn(r) { r.0 == node.rect.0 && r.1 == node.rect.1 && r.2 == 40.0 && r.3 == 40.0 })
    assert_eq(hovered.length(), 1)
    assert_eq(hovered[0].4, node_ground[0].4, msg="hover does not replace the chosen ground")
  }
  @sf.set_dark(None)
}
