// A single retained station meter follows its reading, including the full and brief figures and its fill.

///|
fn meter_node_reading(left : Int, big : String, unit : String, remaining : String) -> Json? {
  Some({
    "short": "Memory",
    "label": "Memory",
    "value": "27 / 32 G",
    "level": "amber",
    "left": Json::number(left.to_double()),
    "big": Json::string(big),
    "unit": Json::string(unit),
    "remaining": Json::string(remaining),
  })
}

///|
fn meter_node_tester(meter : @signals.Signal[Json?], brief : Bool) -> @ui.Tester {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    let tips = TipLayer::new(fn() { Some(root) })
    root.box(fn(row) {
      row.padding(Is((20.0, 20.0, 0.0, 0.0))) |> ignore
      meter_chip_node(row, fn() { meter.get() }, brief~, tips~) |> ignore
    }) |> ignore
  })
  t.draw()
  t
}

///|
test "a meter node draws the same full and brief readings as the original meter chip" {
  for m in [
    meter_node_reading(16, "5.0", "GB", "left 5 G"),
    Some({ "short": "CPU", "remaining": "idle 78%", "left": 78, "level": "ok", "big": "78", "unit": "%" }),
    Some({ "short": "Disk", "remaining": "left 1 G", "left": 1, "level": "red", "big": "1", "unit": "GB" }),
  ] {
    for brief in [false, true] {
      let (old, made) = drawn_both(fn(c) { meter_chip(c, m, brief~) }, fn(parent) {
        meter_chip_node(parent, fn() { m }, brief~) |> ignore
      })
      assert_eq(made, old, msg="meter \{m}, brief \{brief}")
    }
  }
}

///|
test "a meter node follows its full figure and mark as its reading changes" {
  let meter = @signals.signal(meter_node_reading(16, "5.0", "GB", "left 5 G"), same=fn(a, b) { a == b })
  let t = meter_node_tester(meter, false)
  assert_true(t.find("Memory") is Some(_) && t.find("left 5 G") is Some(_))
  meter.set(Some({ "short": "CPU", "remaining": "idle 78%", "left": 78, "level": "ok" }))
  t.draw()
  assert_true(t.find("CPU") is Some(_) && t.find("idle 78%") is Some(_))
  assert_true(t.find("Memory") is None && t.find("left 5 G") is None)
}

///|
test "a brief meter node uses the short unit, keeps percent, and falls back to remaining" {
  let meter = @signals.signal(meter_node_reading(16, "5.0", "GB", "left 5 G"), same=fn(a, b) { a == b })
  let t = meter_node_tester(meter, true)
  assert_true(t.find("5.0G") is Some(_))
  assert_true(t.find("left 5 G") is None)
  meter.set(meter_node_reading(80, "80", "%", "idle 80%"))
  t.draw()
  assert_true(t.find("80%") is Some(_))
  meter.set(meter_node_reading(80, "", "%", "idle 80%"))
  t.draw()
  assert_true(t.find("idle 80%") is Some(_))
}

///|
test "a meter node's fill follows used capacity and clamps readings outside zero to one hundred" {
  let meter = @signals.signal(meter_node_reading(-20, "5.0", "GB", "left 5 G"), same=fn(a, b) { a == b })
  let t = meter_node_tester(meter, false)
  let below = t.drawn_instances()
  meter.set(meter_node_reading(0, "5.0", "GB", "left 5 G"))
  t.draw()
  assert_eq(t.drawn_instances(), below)
  meter.set(meter_node_reading(50, "5.0", "GB", "left 5 G"))
  t.draw()
  let half = t.drawn_instances()
  assert_true(half != below)
  meter.set(meter_node_reading(100, "5.0", "GB", "left 5 G"))
  t.draw()
  let empty = t.drawn_instances()
  assert_true(empty != half)
  meter.set(meter_node_reading(120, "5.0", "GB", "left 5 G"))
  t.draw()
  assert_eq(t.drawn_instances(), empty)
}

///|
test "a meter node's tip follows its label, value and optional note" {
  let meter : @signals.Signal[Json?] = @signals.signal(Some({
    "short": "Memory", "label": "Memory", "value": "27 / 32 G", "note": "swap 2 G",
    "remaining": "left 5 G", "left": 16, "level": "amber",
  }), same=fn(a, b) { a == b })
  let t = meter_node_tester(meter, false)
  guard t.find("Memory") is Some((x, y)) else { fail("no meter: \{t.drawn_text()}") }
  t.move(x, y)
  t.run_for(tip_delay_ms + @ui.move_most_ms)
  assert_true(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Memory 27 / 32 G · swap 2 G" && !s.hidden }))
  meter.set(Some({
    "short": "Memory", "label": "Memory", "value": "28 / 32 G",
    "remaining": "left 4 G", "left": 13, "level": "amber",
  }))
  t.draw()
  assert_true(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Memory 28 / 32 G" && !s.hidden }))
  meter.set(Some({ "short": "Memory", "remaining": "left 4 G", "left": 13, "level": "amber" }))
  t.draw()
  assert_false(t.semantics().any(fn(s) { s.role == Tooltip && s.label.contains("Memory 28") && !s.hidden }))
  t.run_for(@kit.pop_out_ms * 2.0)
  assert_false(t.semantics().any(fn(s) { s.role == Tooltip && !s.hidden }))
}
