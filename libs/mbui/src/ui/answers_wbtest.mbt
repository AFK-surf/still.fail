// What the host brings the app later (hostcall.mbt's outside: a pick, marks drawn, an update downloading), waited on
// as the runtime's tickets until it is taken; an answer told asks for a frame of its own, so no view looks for it frame
// after frame.

///|
/// How long the person takes to pick (any while).
let picking_while : Double = 100.0

///|
test "a pick is waited on from its ask until its answer is taken, as the person answers it; read the frame after" {
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
  // (the person takes their while: answered as the test says, not as it is asked)
  t.picks_by_hand()
  asked.val = true
  // asked in this frame: awaited, with what it is
  t.frame(ms=0.0)
  assert_true(runtime().awaited().iter().any(fn(a) { a.0.contains("a pick") }))
  t.run_for(picking_while)
  assert_true(runtime().awaited().iter().any(fn(a) { a.0.contains("a pick") }))
  // answered: taken as its event comes, no longer awaited, read by the frame after
  t.pick_answer(1)
  t.draw()
  assert_true(took.val)
  assert_eq(runtime().awaiting(), 0)
  t.assert_idle()
}

///|
test "what waits on a pick follows its answer, as a signal: a computed of it worked out again as the answer comes" {
  let t = Tester::new(fn(c) { c.text("files", wrap=false) |> ignore })
  t.picks([("a.txt", b"hi")])
  let p = pick(Files).unwrap()
  let runs = Ref(0)
  let got = @signals.computed(fn(_) {
    runs.val += 1
    match p.files() {
      Some(files) => files.length()
      None => -1
    }
  })
  assert_eq(got.get(), -1)
  // (nothing changed: not worked out again)
  assert_eq(got.get(), -1)
  assert_eq(runs.val, 1)
  // the answer comes with the next frame, as a host's event brings it: the computed follows it
  t.draw()
  assert_eq(got.get(), 1)
  assert_eq(runs.val, 2)
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
test "a pick's answer someone reads (an old view's build): told at the moment its event comes, a frame asked, read in that frame" {
  let ask : Ref[Pick?] = Ref(None)
  let seen : Array[Int] = []
  let t = Tester::new(fn(c) {
    match ask.val {
      Some(p) =>
        match p.files() {
          Some(fs) => {
            seen.push(fs.length())
            c.text("picked \{fs.length()}", wrap=false) |> ignore
          }
          None => c.text("picking", wrap=false) |> ignore
        }
      None => c.text("nothing", wrap=false) |> ignore
    }
  })
  t.picks([("a.txt", b"hi"), ("b.txt", b"yo")])
  t.draw()
  // (its answer not there till its event: the fake's pickers answer as they are asked otherwise)
  t.picks_by_hand()
  ask.val = pick(Files)
  t.draw()
  assert_true(t.find("picking") is Some(_))
  assert_false(t.fake.wants || g().wants_frame)
  // the system answers: its event, between frames
  t.fake.pick_asks[0].said = true
  on_outside(outside_pick, 1, 1)
  // told: the build that read it is to be built again, a frame asked for it
  assert_true(t.fake.wants)
  assert_eq(seen, [])
  t.draw()
  assert_eq(seen, [2])
  assert_true(t.find("picked 2") is Some(_))
  t.assert_idle()
}

///|
test "a pick's answer nobody reads asks for no frame: taken, nothing built again for it" {
  let t = Tester::new(fn(c) { c.text("x", wrap=false) |> ignore })
  t.draw()
  t.assert_idle()
  on_outside(outside_pick, 9, 1)
  assert_false(t.fake.wants || g().wants_frame)
  t.assert_idle()
}
