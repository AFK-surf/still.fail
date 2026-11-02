///|
test "a completed preview stays interactive after its scripted steps" {
  let taps = Ref(0)
  let t = Tester::new(fn(c) {
    let button = c.id("tap")
    c.box(id=button, w=Px(120.0), h=Px(40.0), fn() { c.text("Tap") |> ignore }) |> ignore
    if c.clicked(button) { taps.val += 1 }
  }, w=200.0, h=100.0, env=[("MBUI_DRIVE_KEEP_OPEN", "1")])
  let logs = t.drive("tap Tap\nexit")
  assert_true(logs.iter().any(fn(line) { line == "DRIVE PASS" }), msg=logs.join("\n"))
  assert_true(logs.iter().all(fn(line) { !line.has_prefix("EXIT ") }), msg=logs.join("\n"))
  assert_eq(taps.val, 1)
  t.tap(20.0, 20.0)
  assert_eq(taps.val, 2)
}

///|
test "a failed preview script still ends with an error" {
  let t = Tester::new(fn(c) { c.text("Present") |> ignore }, env=[("MBUI_DRIVE_KEEP_OPEN", "1")])
  let logs = t.drive("no-such-step\nexit")
  assert_true(logs.iter().any(fn(line) { line == "EXIT 1" }), msg=logs.join("\n"))
  assert_true(logs.iter().all(fn(line) { line != "DRIVE PASS" }), msg=logs.join("\n"))
}

///|
test "a normal scripted run still ends on success" {
  let t = Tester::new(fn(c) { c.text("Present") |> ignore })
  let logs = t.drive("exit")
  assert_true(logs.iter().any(fn(line) { line == "EXIT 0" }), msg=logs.join("\n"))
}
