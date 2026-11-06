// The shared station-meter line retains whole alert readings as its room and the readings themselves change.

///|
fn meter_line_reading(short : String, level : String, big : String, unit : String) -> Json {
  {
    "short": Json::string(short), "label": Json::string(short), "level": Json::string(level),
    "value": Json::string(big + unit), "big": Json::string(big), "unit": Json::string(unit),
    "remaining": Json::string(big + unit), "left": 50,
  }
}

///|
test "a station meter line drops non-alerts from the end and brings the same readings back" {
  let cpu = meter_line_reading("C", "ok", "78", "%")
  let memory = meter_line_reading("M", "amber", "9", "GB")
  let disk = meter_line_reading("D", "ok", "5", "GB")
  let meters = @signals.signal([cpu, memory, disk], same=fn(a, b) { a == b })
  let room = @signals.signal(400.0, same=fn(a, b) { a == b })
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=500.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(holder) {
      holder.row(Is(true)).width(By(fn() { Some(room.get()) })) |> ignore
      meter_chips_node(holder, fn() { meters.get() }, brief=true)
    }) |> ignore
  })
  t.draw()
  assert_true(t.find("78%") is Some(_) && t.find("9G") is Some(_) && t.find("5G") is Some(_))
  room.set(100.0)
  t.draw()
  assert_true(t.find("78%") is Some(_) && t.find("9G") is Some(_), msg=t.drawn_text())
  assert_true(t.find("5G") is None, msg=t.drawn_text())
  assert_false(t.semantics().any(fn(s) { !s.hidden && s.label.contains("D 5G") }), msg="a dropped chip is not read out")
  room.set(40.0)
  t.draw()
  assert_true(t.find("78%") is None && t.find("9G") is Some(_) && t.find("5G") is None, msg=t.drawn_text())
  meters.set([cpu, meter_line_reading("M", "ok", "9", "GB"), meter_line_reading("D", "red", "5", "GB")])
  t.draw()
  assert_true(t.find("9G") is None && t.find("5G") is Some(_), msg=t.drawn_text())
  room.set(400.0)
  t.draw()
  assert_true(t.find("78%") is Some(_) && t.find("9G") is Some(_) && t.find("5G") is Some(_))
}

///|
test "a station meter line does not shorten an alert figure even when there is no room" {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=200.0, h=100.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(holder) {
      holder.row(Is(true)).width(Is(Some(1.0))) |> ignore
      meter_chips_node(holder, fn() { [meter_line_reading("Disk", "red", "12345", "GB")] }, brief=true)
    }) |> ignore
  })
  t.draw()
  assert_true(t.find("12345G") is Some(_), msg=t.drawn_text())
}
