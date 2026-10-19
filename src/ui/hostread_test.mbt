///|
test "host reads: under a Tester the defaults are its own, not the machine's" {
  let seen : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    seen.push(
      "\{@ui.platform()} \{@ui.system_dark()} \{@ui.window_inset()} [\{@ui.env("HOME")}] \{@ui.app_version()} \{@ui.now() == c.now()}",
    )
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  assert_eq(seen[seen.length() - 1], "0 false false [] 0 true")
  assert_false(@ui.reduced_motion())
  ignore(t)
}

///|
test "host reads: what a Tester is made with is what the app reads" {
  let seen : Array[String] = []
  let t = @ui.Tester::new(
    fn(c) {
      seen.push(
        "\{@ui.platform()} \{@ui.system_dark()} \{@ui.window_inset()} [\{@ui.env("MBUI_X")}] \{@ui.app_version()}",
      )
      c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
    },
    platform=2,
    dark=true,
    window_inset=true,
    env=[("MBUI_X", "on"), ("MBUI_REDUCE_MOTION", "1")],
    app_version=42,
  )
  assert_eq(seen[seen.length() - 1], "2 true true [on] 42")
  assert_true(@ui.reduced_motion())
  ignore(t)
}

///|
test "host reads: set while it runs, read from the next frame on" {
  let seen : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    seen.push(
      "\{@ui.system_dark()} \{@ui.window_inset()} [\{@ui.env("MBUI_X")}]",
    )
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  t.set_dark(true)
  t.set_window_inset(true)
  t.set_env("MBUI_X", "1")
  assert_true(t.settle() > 0)
  assert_eq(seen[seen.length() - 1], "true true [1]")
  t.set_env("MBUI_X", "")
  t.set_dark(false)
  t.draw()
  assert_eq(seen[seen.length() - 1], "false true []")
}

///|
test "host reads: the clock is the Tester's" {
  let t = @ui.Tester::new(fn(c) {
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  let t0 = @ui.now()
  t.frame(ms=100.0)
  assert_eq(@ui.now() - t0, 100.0)
}
