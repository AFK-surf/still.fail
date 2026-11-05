///|
test "zz dbg quote send" {
  let (t, x, y) = image_in_chat("compare.png")
  hold_quote(t, x, y)
  t.run_for(@ui.move_most_ms)
  println("DBG before vis=\{t.visible()} end=\{t.at_end()}")
  tap_send(t)
  for i in 0..<10 {
    t.run_for(100.0)
    println("DBG +\{(i + 1) * 100} vis=\{t.visible()} end=\{t.at_end()} glide=\{t.moving()} rows=\{t.rows()}")
  }
}
