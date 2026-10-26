// A scripted run's `outside_done NAME`, `shown` and `decoded` by a prefix (drive.mbt): each waits for its own named
// thing, none for a motion.

///|
/// `script` run over a page, the frames counted, `at(n)` told at the start of the n-th: what the run logged.
fn outside_run(script : String, at : (Int) -> Unit) -> Array[String] {
  let t = Tester::new(fn(c) { c.text("page", wrap=false) |> ignore })
  t.fake.logs.clear()
  drive_start(script, "")
  let mut n = 0
  while driver.val is Some(_) && n < 300 {
    at(n)
    t.frame()
    n = n + 1
  }
  t.fake.logs.copy()
}

///|
test "outside_done waits for the work outside it names to be done, a frame drawn after it" {
  let ticket = Ref(-1)
  let log = outside_run("timeout 3000\noutside_done an update downloading\nexit", fn(n) {
    if n == 10 {
      ticket.val = runtime().outside_start("an update downloading")
    }
    if n == 20 {
      runtime().outside_end(ticket.val)
    }
  })
  let ok = log.search_by(fn(l) { l.has_prefix("DRIVE ok outside_done an update downloading") }).unwrap()
  assert_true(ok >= 0, msg=log.join("\n"))
  assert_true(log.iter().any(fn(l) { l.contains("DRIVE PASS") }), msg=log.join("\n"))
}

///|
test "outside_done fails where its name names more than one thing done" {
  let a = Ref(-1)
  let b = Ref(-1)
  let log = outside_run("timeout 3000\noutside_done image\nexit", fn(n) {
    if n == 10 {
      a.val = runtime().outside_start("image 1 a.png")
      b.val = runtime().outside_start("image 2 b.png")
    }
    if n == 20 {
      runtime().outside_end(a.val)
      runtime().outside_end(b.val)
    }
  })
  assert_true(
    log.iter().any(fn(l) { l.contains("DRIVE FAIL") && l.contains("names more than one") }),
    msg=log.join("\n"),
  )
}

///|
test "ends waits for the host to end the app, moving on to nothing; past its timeout the run fails" {
  // (300 frames of the Tester's are more than its 1000 ms)
  let log = outside_run("timeout 1000\nends\nexit", fn(_) {  })
  assert_false(log.iter().any(fn(l) { l.contains("DRIVE PASS") }), msg=log.join("\n"))
  assert_true(
    log.iter().any(fn(l) { l.contains("DRIVE FAIL line 2: ends: the app did not end by itself within 1000 ms") }),
    msg=log.join("\n"),
  )
}

///|
test "shown waits for the host's word that the app is shown again after it was not" {
  let log = outside_run("timeout 3000\nshown\nexit", fn(n) {
    // (another app's page over it, then gone)
    if n == 10 {
      on_app_state(0)
    }
    if n == 20 {
      on_app_state(3)
    }
  })
  let ok = log.search_by(fn(l) { l.has_prefix("DRIVE ok shown") }).unwrap()
  let back = log.search_by(fn(l) { l.contains("the app is 3") }).unwrap()
  assert_true(back < ok, msg=log.join("\n"))
}

///|
test "a run keeps the app shown and in front till `hosted`, then it is as the host says (put away, going on)" {
  let seen : Array[(Bool, Bool, Bool)] = []
  let log = outside_run("timeout 3000\nhosted\nexit", fn(n) {
    // (put away before the step, as the host says it: kept shown and in front)
    if n == 0 {
      on_app_state(4)
      seen.push((app_visible(), app_focused(), app_awake()))
    }
  })
  assert_true(log.iter().any(fn(l) { l.has_prefix("DRIVE ok hosted") }), msg=log.join("\n"))
  assert_eq(seen, [(true, true, true)])
  // the step taken: as the host said, not shown, not in front, going on
  assert_eq((app_visible(), app_focused(), app_awake()), (false, false, true))
  app_state_taken(3)
}

///|
test "decoded takes a source by its end or by its beginning (a gallery's content://)" {
  let what = "image 4 content://media/external/images/media/31"
  assert_true(outside_named("decoded", "content://media/", what))
  assert_true(outside_named("decoded", "media/31", what))
  assert_false(outside_named("decoded", "e2e-photo.jpg", what))
}
