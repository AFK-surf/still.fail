// A scripted run's `done X` (drive.mbt): what the runner says it has done, as its host posts it (done_watch.h).

///|
/// `script` run over a page, the host taken to watch the runner's directory and the runner saying `said` of "freeze"
/// in the twentieth frame: what the run logged.
fn done_run(script : String, said : String) -> Array[String] {
  let t = Tester::new(fn(c) { c.text("page", wrap=false) |> ignore })
  t.fake.logs.clear()
  drive_start(script, "")
  driver.val = driver.val.map(fn(d) { { ..d, watching: true } })
  let mut n = 0
  while driver.val is Some(d) && n < 300 {
    if n == 20 {
      runner_said(d.runner_done, "{\"done\":\"freeze\",\"said\":\"\{said}\"}")
    }
    t.frame()
    n = n + 1
  }
  t.fake.logs.copy()
}

///|
test "done waits for the runner's word of it, then goes on" {
  let log = done_run("done freeze\nexit", "ok\\n")
  let said = log.search_by(fn(l) { l.has_prefix("DRIVE runner done freeze") }).unwrap()
  let ok = log.search_by(fn(l) { l.has_prefix("DRIVE ok done freeze") }).unwrap()
  assert_true(said < ok, msg=log.join("\n"))
  assert_true(log.iter().any(fn(l) { l.contains("DRIVE PASS") }), msg=log.join("\n"))
}

///|
test "done fails the run where the runner says it went wrong, saying what" {
  let log = done_run("done freeze\nexit", "the station would not stop")
  assert_true(
    log.iter().any(fn(l) { l.contains("DRIVE FAIL") && l.contains("the station would not stop") }),
    msg=log.join("\n"),
  )
}

///|
test "done fails at once where the host watches no runner's directory (a Tester's)" {
  let t = Tester::new(fn(c) { c.text("page", wrap=false) |> ignore })
  let log = t.drive("done freeze\nexit", max=5)
  assert_true(log.iter().any(fn(l) { l.contains("DRIVE FAIL") && l.contains("watches no directory") }), msg=log.join("\n"))
}
