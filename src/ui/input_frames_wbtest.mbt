// The framework asks for the frames inputs need (inputrec.mbt `took_input`, app.mbt `on_frame`), and for one asked
// between frames (Ctx::request_frame).

///|
test "every input asks the host for a frame, a key nothing under the pointer takes too" {
  let t = Tester::new(fn(c) { c.text("x") |> ignore }, w=100.0, h=100.0)
  t.settle() |> ignore
  t.fake.wants = false
  // Enter with no field focused and no list under the pointer: before, nothing asked for a frame
  on_key(key_enter, 0)
  assert_true(t.fake.wants)
}

///|
test "the frame after an input is followed by one more, for what read it late" {
  let t = Tester::new(fn(c) { c.text("x") |> ignore }, w=100.0, h=100.0)
  t.settle() |> ignore
  on_key(key_enter, 0)
  t.frame()
  assert_true(g().wants_frame)
  t.frame()
  assert_true(!g().wants_frame)
}

///|
test "a frame asked for between frames reaches the host" {
  let t = Tester::new(fn(c) { c.text("x") |> ignore }, w=100.0, h=100.0)
  t.settle() |> ignore
  t.fake.wants = false
  g().request_frame()
  assert_true(t.fake.wants)
}
