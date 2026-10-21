// What the host brings the app later (hostcall.mbt's outside: a pick, marks drawn, an update downloading), waited on
// as the runtime's tickets until it is taken; an answer told asks for a frame of its own, so no view looks for it frame
// after frame.

///|
test "a pick is waited on from its ask until its answer is taken, the frame after" {
  let ask : Ref[Pick?] = Ref(None)
  let asked = Ref(false)
  let took = Ref(false)
  let t = Tester::new(fn(c) {
    if asked.val && ask.val is None {
      ask.val = pick(Files)
    }
    match ask.val {
      Some(p) =>
        if p.files() is Some(_) {
          took.val = true
          ask.val = None
          asked.val = false
        }
      None => ()
    }
    c.text("files", wrap=false) |> ignore
  })
  t.picks([("a.txt", b"hi")])
  asked.val = true
  // asked in this frame: awaited, with what it is
  t.frame(ms=0.0)
  assert_true(runtime().awaited().iter().any(fn(a) { a.0.contains("a pick") }))
  // its answer the frame after, taken: no longer awaited
  t.draw()
  assert_true(took.val)
  assert_eq(runtime().awaiting(), 0)
  t.assert_idle()
}

///|
test "marks drawn are waited on until the PNG is taken" {
  let m : Ref[MarkedImage?] = Ref(None)
  let png : Ref[Bytes?] = Ref(None)
  let go = Ref(false)
  let t = Tester::new(fn(c) {
    if go.val {
      go.val = false
      m.val = draw_marks(b"img", "{\"w\":1,\"h\":1,\"marks\":[]}")
    }
    match m.val {
      Some(x) =>
        match x.made() {
          Some(b) => {
            png.val = Some(b)
            m.val = None
          }
          None => ()
        }
      None => ()
    }
    c.text("marks", wrap=false) |> ignore
  })
  go.val = true
  t.frame(ms=0.0)
  assert_true(runtime().awaited().iter().any(fn(a) { a.0.contains("marks drawn") }))
  t.draw()
  assert_true(png.val is Some(_))
  assert_eq(runtime().awaiting(), 0)
  t.assert_idle()
}

///|
test "an update downloading is waited on while the host says it works at it, each word of it a frame" {
  let t = Tester::new(fn(c) { c.text("update", wrap=false) |> ignore })
  t.draw()
  // how it goes changed: held, a frame asked for
  on_outside(outside_update, 1, 0)
  assert_true(runtime().awaited().iter().any(fn(a) { a.0.contains("an update downloading") }))
  assert_true(t.fake.wants || g().wants_frame)
  t.draw()
  on_outside(outside_update, 1, 0)
  assert_eq(runtime().awaiting(), 1)
  // handed to the installer: no longer the host's work
  on_outside(outside_update, 1, 1)
  assert_eq(runtime().awaiting(), 0)
  t.assert_idle()
}

///|
test "an answer told (a pick's) asks for a frame" {
  let t = Tester::new(fn(c) { c.text("x", wrap=false) |> ignore })
  t.draw()
  t.assert_idle()
  on_outside(outside_pick, 9, 1)
  assert_true(t.fake.wants || g().wants_frame)
  t.draw()
  t.assert_idle()
}
