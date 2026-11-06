// The compact bar made once: the changing words and insets, its separate controls, and its place above a scrolling page.

///|
test "compact bar: dynamic words and inset, centred title, separate actions, and fixed above the scrolling page" {
  let back = @signals.signal("Settings")
  let title = @signals.signal("Shared debugging")
  let sub = @signals.signal("Station one")
  let top = @signals.signal(24.0)
  let ground = @signals.signal(0x123456FFL)
  let copy_shown = @signals.signal(true)
  let went = Ref(0)
  let copied = Ref(0)
  let bar : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=300.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    bar.val = Some(nav_bar_node(
      root,
      fn() { back.get() },
      fn() { title.get() },
      fn() { went.val += 1 },
      top=fn() { top.get() },
      bg=fn() { ground.get() },
      sub=fn(v) { nav_bar_subtitle_node(v, fn() { sub.get() }) |> ignore },
      trailing=fn(v) {
        v.show(fn() { copy_shown.get() }, fn(slot) {
          icon_button_node(slot, "copy", fn() { "Copy" }, fn() { copied.val += 1 }, size=32.0) |> ignore
        })
      },
    ))
    root.box(fn(sc) {
      sc.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      sc.scrolls(@view.Scroll::list(), fn(body) {
        for i in 0..<20 {
          body.box(fn(row) { row.height(Is(Some(50.0))).words(Is("row \{i}")) |> ignore }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let a = t.rect_of("Shared debugging").unwrap()
  let b = t.get(Button, label="Settings").rect
  let back_id = t.get(Button, label="Settings").id
  let copy = t.get(Button, label="Copy").rect
  assert_true((a.0 + a.2 / 2.0 - 195.0).abs() < 0.5, msg="the title stays in the middle")
  assert_true(b.0 + b.2 <= a.0 && a.0 + a.2 <= copy.0, msg="the two controls keep clear of the title")
  assert_eq(bar.val.unwrap().rect().3, 88.0, msg="24 inset + 6 + 32 + 16 + 10")
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x123456FFL }), msg="the ground includes the inset")
  t.click(Button, label="Settings")
  t.click(Button, label="Copy")
  assert_eq((went.val, copied.val), (1, 1))
  t.drag(195.0, 260.0, 195.0, 120.0)
  assert_eq(t.rect_of("Shared debugging").unwrap().1, a.1, msg="the bar did not scroll")
  back.set("Station")
  title.set("Choose model")
  sub.set("Station two")
  top.set(0.0)
  ground.set(0x654321FFL)
  copy_shown.set(false)
  t.draw()
  assert_true(t.rect_of("Station two") is Some(_))
  assert_true(t.query(Button, label="Copy") is None, msg="the independent action can leave without removing back")
  assert_eq(t.get(Button, label="Station").id, back_id, msg="changing the words keeps the control")
  let changed = t.rect_of("Choose model").unwrap()
  assert_true((changed.0 + changed.2 / 2.0 - 195.0).abs() < 0.5)
  assert_eq(bar.val.unwrap().rect().3, 64.0)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x654321FFL }))
  t.act(Button, Focus, label="Station")
  t.enter()
  t.key(@ui.key_space)
  assert_eq(went.val, 3, msg="the current back label remains keyboard accessible")
  t.act(Button, Activate, label="Station")
  assert_eq(went.val, 4, msg="a screen reader can activate the same action")
}

///|
test "compact bar: a back word that exceeds its dynamic limit is left out whole and remains the button's name" {
  let max = @signals.signal(40.0)
  let went = Ref(0)
  let word = "A folder with a long name"
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=800.0, h=200.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    nav_bar_node(root, fn() { word }, fn() { "Files" }, fn() { went.val += 1 }, back_max=fn() { max.get() }) |> ignore
  })
  t.draw()
  assert_true(t.rect_of(word) is None, msg="the word is not cut into an unrecognisable fragment")
  assert_true(t.get(Button, label=word).rect.2 > 0.0, msg="the button still says where back goes")
  t.click(Button, label=word)
  assert_eq(went.val, 1)
  max.set(300.0)
  t.draw()
  assert_true(t.rect_of(word) is Some(_), msg="the same word returns when it fits")
}

///|
test "compact bar: a finger press draws feedback and activates back once" {
  let went = Ref(0)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=200.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    nav_bar_node(root, fn() { "Back" }, fn() { "Title" }, fn() { went.val += 1 }) |> ignore
  })
  t.draw()
  t.touch(0, 20.0, 20.0)
  t.advance(@motion.ripple_enter_ms / 2.0)
  t.draw()
  assert_true(t.drawn_shadows().length() > 0, msg="the press has a ripple")
  t.touch(2, 20.0, 20.0)
  t.draw()
  assert_eq(went.val, 1)
}

///|
test "compact bar: removing the page during a press cancels it" {
  let shown = @signals.signal(true)
  let went = Ref(0)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=200.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.show(fn() { shown.get() }, fn(page) {
      nav_bar_node(page, fn() { "Back" }, fn() { "Title" }, fn() { went.val += 1 }) |> ignore
    })
  })
  t.draw()
  t.touch(0, 20.0, 20.0)
  shown.set(false)
  t.draw()
  t.touch(2, 20.0, 20.0)
  t.draw()
  assert_eq(went.val, 0)
  assert_true(t.query(Button, label="Back") is None)
  assert_true(!@ui.view_tree().unwrap().clock_read(), msg="the removed bar leaves no ripple ticking")
}
