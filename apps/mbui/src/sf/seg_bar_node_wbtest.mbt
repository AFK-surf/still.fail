// The segmented choice in a bar: its own-sized options stay together as the bar's room changes, while its words and
// selected option follow the caller. Its input and semantics are those of a roving radio group.

///|
fn seg_bar_tester(
  room : @signals.Signal[Double],
  labels : @signals.Signal[Array[String]],
  chosen : @signals.Signal[Int],
  shown : @signals.Signal[Bool],
  choices : Array[Int],
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=160.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.padding(Is((20.0, 20.0, 20.0, 20.0))) |> ignore
    root.box(fn(line) {
      line.row(Is(true)).width(By(fn() { Some(room.get()) })).height(Is(Some(44.0))) |> ignore
      line.show(fn() { shown.get() }, fn(slot) {
        segmented_node(slot, fn() { labels.get() }, fn() { chosen.get() }, fn(k) {
          choices.push(k)
          chosen.set(k)
        }, said="Screen mode", bar=true)
      })
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a bar choice uses each word's width and keeps it when its room is narrow" {
  let room = @signals.signal(300.0)
  let labels = @signals.signal(["Look", "Take control"])
  let chosen = @signals.signal(0)
  let choices : Array[Int] = []
  @ui.set_haptics(true)
  let t = seg_bar_tester(room, labels, chosen, @signals.signal(true), choices)
  let radios = fn() { seg_shown(t, Radio) }
  let group = fn() { seg_shown(t, RadioGroup) }
  let c = @ui.current()
  let widths = fn() {
    let size = c.sp(theme().t.meta)
    labels.get().map(fn(l) { choice_words_w(c, l, size, weight=500, tree=true) + 2.0 * segmented_bar_in })
  }
  assert_eq(radios().map(fn(s) { s.rect.2 }), widths(), msg="each word has its own column")
  assert_true(widths()[1] > widths()[0])
  assert_eq(group().map(fn(s) { (s.label, s.rect.3) }), [("Screen mode", icon_button_side)])
  assert_eq(radios().map(fn(s) { s.rect.3 }), [28.0, 28.0])
  assert_eq(group()[0].rect.2, widths()[0] + widths()[1] + segmented_gap + 2.0 * segmented_bar_pad)
  room.set(40.0)
  t.draw()
  assert_eq(radios().map(fn(s) { s.rect.2 }), widths(), msg="the bar does not compress its choice")
  assert_eq(seg_shown(t, Button).length(), 0, msg="no pick replaces the options")
  t.host_says_finger(Some(true))
  let (x, y, w, h) = radios()[1].rect
  t.touch(0, x + w / 2.0, y + h / 2.0)
  assert_eq(choices, [], msg="a finger has not chosen before release")
  t.touch(2, x + w / 2.0, y + h / 2.0)
  t.draw()
  assert_eq((chosen.get(), choices), (1, [1]), msg="the option remains clickable")
  assert_eq(t.haptics(), [TextHandleMove], msg="the new choice is felt once")
  let (x, y, w, h) = radios()[0].rect
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.touch(3, x + w / 2.0, y + h / 2.0)
  t.draw()
  assert_eq((chosen.get(), choices, t.haptics()), (1, [1], [TextHandleMove]), msg="a cancelled touch does not choose")
}

///|
test "a bar choice follows words, font size and selection without replacing its focused option" {
  let room = @signals.signal(300.0)
  let labels = @signals.signal(["Look", "Control"])
  let chosen = @signals.signal(0)
  let choices : Array[Int] = []
  let t = seg_bar_tester(room, labels, chosen, @signals.signal(true), choices)
  t.key(@ui.key_tab)
  t.draw()
  let first = t.focused().unwrap().id
  labels.set(["只看", "控制屏幕"])
  t.set_font_scale(1.5)
  t.draw()
  assert_eq(t.focused().map(fn(s) { (s.id, s.label) }), Some((first, "只看")))
  let c = @ui.current()
  let size = c.sp(theme().t.meta)
  let widths = labels.get().map(fn(l) { choice_words_w(c, l, size, weight=500, tree=true) + 2.0 * segmented_bar_in })
  assert_eq(seg_shown(t, Radio).map(fn(s) { s.rect.2 }), widths)
  chosen.set(1)
  t.draw()
  assert_eq(seg_radios(t), [("只看", Some(@ui.Check::Off)), ("控制屏幕", Some(@ui.Check::On))])
  assert_eq(choices, [], msg="a caller's selection is not sent back as a new choice")
  t.act(Radio, Activate, label="只看")
  assert_eq((chosen.get(), choices), (0, [0]), msg="a screen reader chooses")
  t.act(Radio, Activate, label="只看")
  assert_eq(choices, [0], msg="activating the selected option does not choose again")
}

///|
test "a bar choice moves and resizes its thumb between differently sized options" {
  let chosen = @signals.signal(0)
  let t = seg_bar_tester(
    @signals.signal(300.0),
    @signals.signal(["Look", "Take control"]),
    chosen,
    @signals.signal(true),
    [],
  )
  let thumb = fn() { t.drawn_rects().filter(fn(d) { d.4 == @ui.tree_theme().lifted && d.3 == 28.0 })[0] }
  let start = thumb()
  t.act(Radio, Activate, label="Take control")
  t.advance(@ui.drag_step_ms)
  t.draw()
  let middle = thumb()
  let destination = seg_shown(t, Radio)[1].rect
  assert_true(middle.0 > start.0 && middle.0 < destination.0, msg="the thumb moves from the first option")
  assert_true(middle.2 > start.2 && middle.2 < destination.2, msg="both edges move, not just the position")
  t.act(Radio, Activate, label="Look")
  let turned = thumb()
  assert_true((turned.0 - middle.0).abs() < 0.01 && (turned.2 - middle.2).abs() < 0.01, msg="a new choice continues from the thumb's current bounds")
  t.run_for(@ui.move_most_ms)
  let back = thumb()
  assert_true((back.0 - start.0).abs() < 0.01 && (back.2 - start.2).abs() < 0.01)
}

///|
test "a bar choice moves focus and selection with the keyboard, and releases them when removed" {
  let room = @signals.signal(300.0)
  let labels = @signals.signal(["Look", "Control"])
  let chosen = @signals.signal(0)
  let shown = @signals.signal(true)
  let choices : Array[Int] = []
  let t = seg_bar_tester(room, labels, chosen, shown, choices)
  t.key(@ui.key_tab)
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Look"))
  t.key(@ui.key_code_right)
  t.draw()
  assert_eq((chosen.get(), t.focused().map(fn(s) { s.label })), (1, Some("Control")))
  t.key(@ui.key_code_home)
  t.draw()
  assert_eq((chosen.get(), t.focused().map(fn(s) { s.label })), (0, Some("Look")))
  shown.set(false)
  t.draw()
  assert_eq(seg_shown(t, Radio).length(), 0)
  t.key(@ui.key_code_right)
  assert_eq(choices, [1, 0], msg="a removed group no longer takes arrows")
  shown.set(true)
  t.draw()
  t.act(Radio, Activate, label="Control")
  assert_eq((chosen.get(), choices), (1, [1, 0, 1]), msg="the remade group chooses once")
}
