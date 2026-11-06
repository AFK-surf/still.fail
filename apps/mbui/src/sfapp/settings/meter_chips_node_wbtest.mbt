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
  t.set_dark(true)
  t.draw()
  let dark = t.drawn_instances()
  assert_true(dark != light)
  assert_true(t.find("Memory") is Some(_) && t.find("left 5 G") is Some(_))
  t.set_dark(false)
  t.draw()
  assert_eq(t.drawn_instances(), light)
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
  t.move(x, y)
  t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
  assert_true(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Memory 27 / 32 G" && !s.hidden }))
  meters.set([disk, memory])
  t.draw()
  assert_false(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Disk 99 / 100 G" && !s.hidden }))
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
  // If the reading stops being an alert while held, its tip and its ownership leave with it.
  meters.set([meter_reading("Memory", "ok", "left 20 G", "12 / 32 G", 63)])
  t.draw()
  assert_false(t.semantics().any(fn(s) { s.role == Tooltip && !s.hidden }))
  t.touch(2, x, y)
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
