// TEMP scratch (never committed): send_flying's steps on the made-up station at its take 2's timings: the second words
// sent 150 ms after the first, the core having each 30 ms on and its message 20 ms after that, the agent's turn over
// at 284 ms after the first press (its answer to the first in before the second is, the line going with it)

///|
test "zz fly c" {
  new_run()
  fix_pace.val = (20.0, 120.0, 0.0)
  fix_core_for.val = 30.0
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("先飞的一条")
  t.run_for(@ui.move_most_ms)
  let p1 = t.time()
  @ui.zz_window.val = (p1 - 20.0, p1 + 1000.0)
  println("ZZSTEP press1 at \{p1}")
  tap_send(t)
  while t.time() < p1 + 150.0 - 1.0 {
    t.frame()
  }
  t.type_text("紧跟着的一条")
  println("ZZSTEP press2 at \{t.time()}")
  tap_send(t)
  let till = t.time() + 1000.0
  while t.time() < till {
    t.frame()
  }
  println("ZZSTEP end at \{t.time()}")
}
