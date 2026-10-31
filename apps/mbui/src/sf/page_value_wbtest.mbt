// A setting row's current value answers a change without replacing its words in one frame.

///|
fn row_value_alpha(t : @ui.Tester, words : String) -> Double {
  let found = t.words().filter(fn(w) { w.0 == words })
  if found.is_empty() { 0.0 } else { found[0].5 }
}

///|
test "a setting row fades its previous value out before the new one in" {
  let value = @signals.signal("$1", same=fn(a, b) { a == b })
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() {
      group(c, fn() { link_row(c, "amount", "Threshold", value=value.get(), note="Estimated") |> ignore })
    })
  }, w=390.0, h=300.0, platform=2)
  t.draw()
  assert_eq(row_value_alpha(t, "$1"), 1.0)
  value.set("$2")
  t.frame()
  assert_eq(row_value_alpha(t, "$1"), 1.0, msg="the previous value starts leaving where it was")
  assert_eq(row_value_alpha(t, "$2"), 0.0, msg="the new value does not overlap the old")
  t.run_for(dur_ms / 8.0)
  let fading = row_value_alpha(t, "$1")
  assert_true(fading > 0.0 && fading < 1.0, msg="the old value fades, got \{fading}")
  t.run_for(dur_ms * 2.0)
  assert_eq(row_value_alpha(t, "$1"), 0.0)
  assert_eq(row_value_alpha(t, "$2"), 1.0)
  assert_eq(t.get(Link, label="Threshold").value, "$2", msg="the chosen value is available to a screen reader")
}

///|
test "a setting row retargeted during its value's fade keeps the words and opacity it showed" {
  let value = @signals.signal("$1", same=fn(a, b) { a == b })
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() {
      group(c, fn() { link_row(c, "amount", "Threshold", value=value.get()) |> ignore })
    })
  }, w=390.0, h=300.0, platform=2)
  t.draw()
  value.set("$2")
  t.frame()
  t.run_for(dur_ms / 8.0)
  let before = row_value_alpha(t, "$1")
  value.set("$3")
  // Compare at the same moment: frame() advances the display clock and the existing fade would naturally move on.
  t.frame_at(t.time())
  assert_true((row_value_alpha(t, "$1") - before).abs() < 0.001, msg="retargeted without a flash")
  t.run_for(dur_ms * 2.0)
  assert_eq(row_value_alpha(t, "$3"), 1.0)
  assert_eq(row_value_alpha(t, "$2"), 0.0)
}

///|
test "a setting row retargeted as its new value appears keeps that value visible" {
  let value = @signals.signal("$1", same=fn(a, b) { a == b })
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() {
      group(c, fn() { link_row(c, "amount", "Threshold", value=value.get()) |> ignore })
    })
  }, w=390.0, h=300.0, platform=2)
  t.draw()
  value.set("$2")
  t.frame()
  t.run_for(dur_ms)
  let before = row_value_alpha(t, "$2")
  assert_true(before > 0.0 && before < 1.0, msg="the new value is appearing")
  value.set("$3")
  t.frame_at(t.time())
  assert_true((row_value_alpha(t, "$2") - before).abs() < 0.001, msg="retargeted without a flash")
  t.run_for(dur_ms * 2.0)
  assert_eq(row_value_alpha(t, "$3"), 1.0)
}

///|
test "a setting row returns with its current value, without replaying changes while absent" {
  let value = @signals.signal("$1", same=fn(a, b) { a == b })
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() {
      if shown.get() {
        group(c, fn() { link_row(c, "amount", "Threshold", value=value.get()) |> ignore })
      }
    })
  }, w=390.0, h=300.0, platform=2)
  t.draw()
  shown.set(false)
  t.frame()
  value.set("$2")
  t.frame()
  shown.set(true)
  t.frame()
  assert_eq(row_value_alpha(t, "$1"), 0.0)
  assert_eq(row_value_alpha(t, "$2"), 1.0)
}
