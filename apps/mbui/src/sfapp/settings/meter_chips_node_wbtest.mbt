// A station's retained meter row: readings and alerts follow the host, and each shown reading keeps its own tip.

///|
fn meter_reading(short : String, level : String, remaining : String, value : String, left : Int) -> Json {
  {
    "short": Json::string(short),
    "label": Json::string(short),
    "level": Json::string(level),
    "remaining": Json::string(remaining),
    "value": Json::string(value),
    "left": Json::number(left.to_double()),
  }
}

///|
fn meter_row_tester(
  meters : @signals.Signal[Array[Json]],
  alerts : Bool,
  platform : Int,
  pressed? : Ref[Int],
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=500.0, h=200.0, platform~)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let tips = @sf.TipLayer::new(fn() { Some(root) })
    root.box(fn(row) {
      row.padding(Is((24.0, 24.0, 0.0, 0.0))) |> ignore
      match pressed {
        Some(count) => @sf.presses_node(row, fn() { count.val += 1 })
        None => ()
      }
      meter_chips_node(row, fn() { meters.get() }, tips~, alerts~)
    }) |> ignore
  })
  t.draw()
  t
}

///|
test "station meter nodes follow readings, order, and alerts as levels change" {
  let cpu = meter_reading("CPU", "ok", "idle 70%", "30%", 70)
  let memory = meter_reading("Memory", "amber", "left 5 G", "27 / 32 G", 16)
  let disk = meter_reading("Disk", "red", "left 1 G", "99 / 100 G", 1)
  let meters = @signals.signal([cpu, memory, disk], same=fn(a, b) { a == b })
  let t = meter_row_tester(meters, true, 0)
  assert_true(t.find("CPU") is None)
  assert_true(t.find("Memory") is Some(_))
  assert_true(t.find("Disk") is Some(_))
  // Changing which entries are alerts preserves the other reading and its displayed value.
  meters.set([meter_reading("CPU", "red", "idle 2%", "98%", 2), meter_reading("Memory", "ok", "left 20 G", "12 / 32 G", 63), disk])
  t.draw()
  assert_true(t.find("CPU") is Some(_))
  assert_true(t.find("idle 2%") is Some(_))
  assert_true(t.find("Memory") is None)
  assert_true(t.find("Disk") is Some(_))
  meters.set([])
  t.draw()
  assert_true(t.find("CPU") is None && t.find("Disk") is None)
  meters.set([memory, cpu])
  t.draw()
  assert_true(t.find("Memory") is Some(_))
  assert_true(t.find("CPU") is None)
}

///|
test "station meter nodes without alert filtering show all levels, including equal marks" {
  let meters = @signals.signal([
    meter_reading("CPU", "ok", "idle 70%", "30%", 70),
    meter_reading("CPU", "amber", "idle 20%", "80%", 20),
  ], same=fn(a, b) { a == b })
  let t = meter_row_tester(meters, false, 0)
  assert_true(t.find("idle 70%") is Some(_))
  assert_true(t.find("idle 20%") is Some(_))
  assert_true(
    t.words_said().any(fn(w) { w.0.contains("idle 70%") }) ||
    t.semantics().any(fn(s) { !s.hidden && s.label.contains("idle 70%") }),
    msg="the reading is available to a screen reader",
  )
  meters.set([meter_reading("CPU", "red", "idle 1%", "99%", 1)])
  t.draw()
  assert_true(t.find("idle 1%") is Some(_))
  assert_true(t.find("idle 70%") is None && t.find("idle 20%") is None)
}

///|
test "station meter nodes keep the row's eight-point gap" {
  let meters = @signals.signal([
    meter_reading("CPU", "ok", "idle 70%", "30%", 70),
    meter_reading("Memory", "amber", "left 5 G", "27 / 32 G", 16),
  ], same=fn(a, b) { a == b })
  let t = meter_row_tester(meters, false, 0)
  guard t.rect_of("idle 70%") is Some((x, _, w, _)) else { fail("no CPU figure: \{t.drawn_text()}") }
  guard t.rect_of("Memory") is Some((next_x, _, _, _)) else { fail("no memory mark: \{t.drawn_text()}") }
  // Each chip has eight points of inner padding, with eight between the chips.
  let gap = next_x - (x + w)
  assert_true(gap >= 23.9 && gap <= 24.1, msg="between figures: \{gap}")
}

///|
test "station meter alerts give way inside a narrow row and keep their full accessible readings" {
  let room = @signals.signal(180.0, same=fn(a, b) { a == b })
  let memory = meter_reading("Memory", "amber", "left 5.0 GB", "27 / 32 GB", 16)
  let disk = meter_reading("Disk", "red", "left 1.0 GB", "99 / 100 GB", 1)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=500.0, h=160.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let tips = @sf.TipLayer::new(fn() { Some(root) })
    root.box(fn(holder) {
      holder.width(By(fn() { Some(room.get()) })) |> ignore
      meter_chips_node(holder, fn() { [memory, disk] }, tips~, alerts=true)
    }) |> ignore
  })
  t.draw()
  let m = t.get(Text, label="Memory left 5.0 GB · Memory 27 / 32 GB")
  let d = t.get(Text, label="Disk left 1.0 GB · Disk 99 / 100 GB")
  let (mx, _, mw, _) = m.rect
  let (dx, _, dw, _) = d.rect
  assert_true(mx >= 0.0 && mw > 0.0 && dx > mx && dx + dw <= 180.0, msg=t.semantics_dump())
  room.set(500.0)
  t.draw()
  assert_true(t.find("left 5.0 GB") is Some(_) && t.find("left 1.0 GB") is Some(_), msg=t.drawn_text())
}

///|
test "a station meter follows its level's tint without changing its words or fill" {
  let meters = @signals.signal([meter_reading("Memory", "amber", "left 5 G", "27 / 32 G", 16)], same=fn(a, b) { a == b })
  let t = meter_row_tester(meters, false, 0)
  let amber = t.drawn_instances()
  t.draw()
  assert_eq(t.drawn_instances(), amber)
  meters.set([meter_reading("Memory", "red", "left 5 G", "27 / 32 G", 16)])
  t.draw()
  let red = t.drawn_instances()
  meters.set([meter_reading("Memory", "ok", "left 5 G", "27 / 32 G", 16)])
  t.draw()
  let ok = t.drawn_instances()
  assert_true(amber != red && red != ok && amber != ok)
}

///|
test "a station meter follows the window's light and dark themes" {
  let meters = @signals.signal([meter_reading("Memory", "amber", "left 5 G", "27 / 32 G", 16)], same=fn(a, b) { a == b })
  let t = meter_row_tester(meters, false, 0)
  let light = t.drawn_instances()
  @sf.set_dark(Some(true))
  t.draw()
  let dark = t.drawn_instances()
  assert_true(dark != light)
  assert_true(t.find("Memory") is Some(_) && t.find("left 5 G") is Some(_))
  @sf.set_dark(Some(false))
  t.draw()
  assert_eq(t.drawn_instances(), light)
  @sf.set_dark(None)
}

///|
test "station alert filtering keeps a reading with an unrecognized level" {
  let meters = @signals.signal([meter_reading("Fan", "", "unknown", "unknown", 50)], same=fn(a, b) { a == b })
  let t = meter_row_tester(meters, true, 0)
  assert_true(t.find("Fan") is Some(_))
}

///|
test "station meter node tips follow their reading and disappear with it" {
  let meters = @signals.signal([meter_reading("Memory", "amber", "left 5 G", "27 / 32 G", 16)], same=fn(a, b) { a == b })
  let t = meter_row_tester(meters, true, 0)
  guard t.find("Memory") is Some((x, y)) else { fail("no meter: \{t.drawn_text()}") }
  t.move(x, y)
  t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
  assert_true(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Memory 27 / 32 G" && !s.hidden }))
  meters.set([meter_reading("Memory", "red", "left 1 G", "31 / 32 G", 3)])
  t.draw()
  assert_true(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Memory 31 / 32 G" && !s.hidden }))
  meters.set([meter_reading("Memory", "ok", "left 20 G", "12 / 32 G", 63)])
  t.draw()
  assert_false(t.semantics().any(fn(s) { s.role == Tooltip && !s.hidden }))
}

///|
test "reordering station meters does not transfer an open tip to a different reading" {
  let memory = meter_reading("Memory", "amber", "left 5 G", "27 / 32 G", 16)
  let disk = meter_reading("Disk", "red", "left 1 G", "99 / 100 G", 1)
  let meters = @signals.signal([memory, disk], same=fn(a, b) { a == b })
  let t = meter_row_tester(meters, true, 0)
  guard t.find("Memory") is Some((x, y)) else { fail("no meter: \{t.drawn_text()}") }
  let before = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == "Memory" })[0].id
  t.move(x, y)
  t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
  assert_true(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Memory 27 / 32 G" && !s.hidden }))
  meters.set([disk, memory])
  t.draw()
  let after = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == "Memory" })[0].id
  assert_true(before == after, msg="the memory reading keeps its node as it moves")
  // The disk is now under the stationary pointer, so it can acquire its own tip. Point to memory at its new position.
  guard t.find("Memory") is Some((new_x, new_y)) else { fail("no moved meter: \{t.drawn_text()}") }
  t.move(new_x, new_y)
  t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
  assert_true(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Memory 27 / 32 G" && !s.hidden }))
}

///|
test "a station meter lets its row be tapped and shows its tip on a finger's hold" {
  let meters = @signals.signal([meter_reading("Memory", "amber", "left 5 G", "27 / 32 G", 16)], same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let t = meter_row_tester(meters, true, 1, pressed~)
  guard t.find("Memory") is Some((x, y)) else { fail("no meter: \{t.drawn_text()}") }
  t.touch(0, x, y)
  t.touch(2, x, y)
  assert_eq(pressed.val, 1, msg="a tap on a meter reaches the row")
  t.touch(0, x, y)
  t.run_for(@ui.long_press_ms + @ui.move_most_ms)
  assert_true(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Memory 27 / 32 G" && !s.hidden }))
  t.touch(2, x, y)
  t.draw()
  assert_eq(pressed.val, 1, msg="a hold does not also activate the row")
  t.touch(0, x, y)
  t.run_for(@ui.long_press_ms + @ui.move_most_ms)
  t.touch(3, x, y)
  t.run_for(@ui.move_most_ms)
  assert_false(t.semantics().any(fn(s) { s.role == Tooltip && !s.hidden }), msg="a cancelled touch closes the tip")
  t.touch(0, x, y)
  t.run_for(@ui.long_press_ms + @ui.move_most_ms)
  // If the reading stops being an alert while held, its tip and its ownership leave with it.
  meters.set([meter_reading("Memory", "ok", "left 20 G", "12 / 32 G", 63)])
  t.draw()
  assert_false(t.semantics().any(fn(s) { s.role == Tooltip && !s.hidden }))
  t.touch(2, x, y)
}

///|
/// Drag a scroll from a meter, before or after holding its tip open.
fn meter_row_scroll_touch(hold : Bool) -> (Bool, Double, Int, Bool) raise {
  let scroll = @view.Scroll::new()
  let pressed = Ref(0)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=200.0, platform=1)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let tips = @sf.TipLayer::new(fn() { Some(root) })
    root.box(fn(view) {
      view.width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
      view.scrolls(scroll, slop=@ui.touch_slop(), fn(content) {
        content.box(fn(row) {
          row.row(Is(true)).height(Is(Some(60.0))).padding(Is((20.0, 20.0, 0.0, 0.0))) |> ignore
          @sf.presses_node(row, fn() { pressed.val += 1 })
          meter_chips_node(row, fn() { [meter_reading("Memory", "amber", "left 5 G", "27 / 32 G", 16)] }, tips~)
        }) |> ignore
        content.box(fn(space) { space.height(Is(Some(300.0))) |> ignore }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  guard t.find("Memory") is Some((x, y)) else { fail("no meter: \{t.drawn_text()}") }
  t.touch(0, x, y)
  if hold { t.run_for(@ui.long_press_ms + @ui.move_most_ms) }
  let shown = t.semantics().any(fn(s) { s.role == Tooltip && !s.hidden })
  t.touch(1, x, y - 25.0)
  t.touch(1, x, y - 50.0)
  t.draw()
  let offset = scroll.at(@ui.view_tree().unwrap())
  t.touch(2, x, y - 50.0)
  t.run_for(@ui.move_most_ms)
  (shown, offset, pressed.val, t.semantics().any(fn(s) { s.role == Tooltip && !s.hidden }))
}

///|
test "a station meter lets its row scroll before or after a finger holds its tip" {
  for hold in [false, true] {
    let (shown, offset, pressed, remains) = meter_row_scroll_touch(hold)
    assert_eq(shown, hold)
    assert_true(offset > 0.0, msg="the scroll takes the drag")
    assert_eq(pressed, 0)
    assert_false(remains, msg="a drag closes the tip")
  }
}

///|
test "station meters leave the row's keyboard focus and activation with the row" {
  let meters = @signals.signal([meter_reading("Memory", "amber", "left 5 G", "27 / 32 G", 16)], same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let t = meter_row_tester(meters, true, 0, pressed~)
  t.key(@ui.key_tab)
  t.key(7) // Enter
  assert_eq(pressed.val, 1)
}
