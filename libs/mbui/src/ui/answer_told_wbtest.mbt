// What the host answers a pick or a native call with is taken as its event comes (hostcall.mbt's outside_take), into a
// signal what waits on it reads (Pick::files, NativeCall::got): a node's binding or `reacts` told at that moment, at any
// frame rate; while it waits, nothing of it asks for a frame. The host's event is said here as a host says it
// (on_outside, between frames), its answer given it the moment before.

///|
/// How long the test runs before it asks (any while), and between what it does (past what a frame drawn for the last
/// needs, at the slowest rate).
let told_before : Double = 100.0

///|
let told_between : Double = 400.0

///|
/// The host's answer for native call `id` (Tester::native_calls) there to take now, its event said by the test (not
/// told by the fake host at its own moment, as Tester::answer_native has it): as a host that tells it by its event has
/// it.
fn native_there(t : Tester, id : Int, r : Result[Json, String]) -> Unit {
  let a = t.fake.dev.natives[id - 1]
  a.answer = Some(r)
  a.said = true
}

///|
/// While what was asked waits: no frame asked between frames, nothing for the clock, and at the default rate no frame
/// drawn but the one run_for draws at its end (the moment it looks at: tester_time.mbt's run_for; on its way it draws
/// one only as the app asks, Tester::asks_frames, or as something is due). At a rate (MBUI_TEST_FPS) run_for draws the
/// rate's frames on its way while the ask is awaited: the wait's ticket keeps the run from its rest (Ctx::at_rest reads
/// the runtime's `unsettled`, awaited among it) and asks_frames reads that rest, where a device's host draws none for
/// it; there the test holds the moment and what was told, not the frames (xfer h-pr2.md, the gap: till the fake host
/// answers all it answers at a moment of its own, FakeHost::due, the frames on the way are what bring those answers).
fn waits_quietly(t : Tester) -> Unit raise {
  assert_false(t.fake.wants)
  let on = t.frames_on()
  let drawn = t.ctx().frame_no
  t.run_for(told_between)
  if !test_at_a_rate() {
    assert_eq(t.ctx().frame_no, drawn + 1)
  }
  assert_false(t.fake.wants)
  assert_eq(t.frames_on(), on)
}

///|
test "a native call's answer: what reads it in the tree told at the moment the host's event says it came, at any rate" {
  let call : @signals.Signal[NativeCall?] = @signals.signal(None)
  let told : Array[(String, Double)] = []
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .words(By(fn() {
        match call.get().map(fn(c) { c.got() }) {
          Some(Some(Ok(j))) => "got " + j.stringify()
          Some(Some(Err(why))) => "refused " + why
          _ => "asking"
        }
      }))
      |> ignore
      n.reacts(fn() { call.get().map(fn(c) { c.got() }) }, fn(r) {
        match r {
          Some(Some(Ok(j))) => told.push((j.stringify(), n.cause_at()))
          _ => ()
        }
      })
    })
    |> ignore
  })
  t.run_for(told_before)
  call.set(Some(native_call("adb.phone", { "station": "w/s" })))
  t.run_for(told_before)
  assert_true(t.find("asking") is Some(_))
  let id = t.native_calls()[0].0
  waits_quietly(t)
  // the host answers: its event, now
  native_there(t, id, Ok({ "wireless": true }))
  let came = t.time()
  on_outside(outside_native, id, 1)
  t.run_for(told_between)
  assert_eq(told, [("{\"wireless\":true}", came)])
  assert_true(t.find("got {\"wireless\":true}") is Some(_))
  // read again, the same: nothing taken twice, nothing told again
  assert_eq(call.get().unwrap().got(), Some(Ok({ "wireless": true })))
  t.run_for(told_between)
  assert_eq(told.length(), 1)
  assert_eq(runtime().awaiting(), 0)
  t.assert_idle()
}

///|
test "a pick's answer: what reads it in the tree told at the moment the host's event says it came, at any rate" {
  let asked : @signals.Signal[Pick?] = @signals.signal(None)
  let told : Array[(Int, Double)] = []
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .words(By(fn() {
        match asked.get().map(fn(p) { p.files() }) {
          Some(Some(files)) => "picked \{files.length()}"
          _ => "picking"
        }
      }))
      |> ignore
      n.reacts(fn() { asked.get().map(fn(p) { p.files().map(fn(f) { f.length() }) }) }, fn(r) {
        match r {
          Some(Some(n_files)) => told.push((n_files, n.cause_at()))
          _ => ()
        }
      })
    })
    |> ignore
  })
  t.picks([("a.txt", b"hi"), ("b.txt", b"yo")])
  t.run_for(told_before)
  // (its host's answer not there till the test says so: the fake's pickers answer as they are asked otherwise)
  t.picks_by_hand()
  asked.set(pick(Files))
  t.run_for(told_before)
  assert_true(t.find("picking") is Some(_))
  waits_quietly(t)
  // the system answers: its event, now
  t.fake.pick_asks[0].said = true
  let came = t.time()
  on_outside(outside_pick, 1, 1)
  t.run_for(told_between)
  assert_eq(told, [(2, came)])
  assert_true(t.find("picked 2") is Some(_))
  assert_eq(asked.get().unwrap().files().map(fn(f) { f.length() }), Some(2))
  t.run_for(told_between)
  assert_eq(told.length(), 1)
  assert_eq(runtime().awaiting(), 0)
  t.assert_idle()
}


///|
test "two native calls asked by one press, each its own on_got given its answer once, at the moment its event comes" {
  let got : Array[(String, String, Double)] = []
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .width(Is(Some(120.0)))
      .height(Is(Some(44.0)))
      .says(Is(Some(@view.said(Button, label="Ask"))))
      .on_press(fn() {
        for name in ["adb.switch", "adb.open"] {
          native_call(name, {}, on_got=fn(r) {
            got.push((name, if r is Ok(_) { "ok" } else { "refused" }, view_moment()))
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  t.run_for(told_before)
  t.tap(20.0, 20.0)
  t.run_for(told_before)
  let calls = t.native_calls()
  assert_eq(calls.map(fn(c) { c.1 }), ["adb.switch", "adb.open"])
  assert_eq(got, [])
  // the second answered first, then the first refused
  native_there(t, calls[1].0, Ok({ "open": true }))
  let second = t.time()
  on_outside(outside_native, calls[1].0, 1)
  t.run_for(told_between)
  native_there(t, calls[0].0, Err("no"))
  let first = t.time()
  on_outside(outside_native, calls[0].0, -1)
  t.run_for(told_between)
  assert_eq(got, [("adb.open", "ok", second), ("adb.switch", "refused", first)])
  // (told again: nothing given again)
  on_outside(outside_native, calls[0].0, -1)
  t.run_for(told_between)
  assert_eq(got.length(), 2)
  t.assert_idle()
}

///|
/// A node reading native call `call`'s answer (its words, and a `reacts` recording what it was told and when).
fn native_read_by(call : @signals.Signal[NativeCall?], told : Array[(String, Double)]) -> Unit {
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .words(By(fn() {
        match call.get().map(fn(c) { c.got() }) {
          Some(Some(Ok(j))) => "got " + j.stringify()
          Some(Some(Err(why))) => "refused " + why
          _ => "asking"
        }
      }))
      |> ignore
      n.reacts(fn() { call.get().map(fn(c) { c.got() }) }, fn(r) {
        match r {
          Some(Some(Ok(j))) => told.push((j.stringify(), n.cause_at()))
          Some(Some(Err(why))) => told.push(("refused " + why, n.cause_at()))
          _ => ()
        }
      })
    })
    |> ignore
  })
}

///|
test "the test's own answer to a native call told at the moment it gives it, at any rate (Tester::answer_native, refuse_native)" {
  let call : @signals.Signal[NativeCall?] = @signals.signal(None)
  let told : Array[(String, Double)] = []
  let t = Tester::new(fn(_c) {  })
  native_read_by(call, told)
  t.run_for(told_before)
  call.set(Some(native_call("adb.phone", Json::object(Map([])))))
  t.run_for(told_before)
  let id = t.native_calls()[0].0
  waits_quietly(t)
  let came = t.time()
  t.answer_native(id, { "wireless": true })
  t.run_for(told_between)
  assert_eq(told, [("{\"wireless\":true}", came)])
  assert_true(t.find("got {\"wireless\":true}") is Some(_))
  // refused, at its own moment
  call.set(Some(native_call("adb.phone", Json::object(Map([])))))
  t.run_for(told_before)
  let refused = t.time()
  t.refuse_native(t.native_calls()[0].0, "no")
  t.run_for(told_between)
  assert_eq(told, [("{\"wireless\":true}", came), ("refused no", refused)])
  assert_eq(runtime().awaiting(), 0)
  t.assert_idle()
}

///|
test "a native call the test answers as it is asked told at the moment it is asked, at any rate (Tester::native_answers)" {
  let call : @signals.Signal[NativeCall?] = @signals.signal(None)
  let told : Array[(String, Double)] = []
  let t = Tester::new(fn(_c) {  })
  t.native_answers("adb.phone", fn(_) { { "wireless": false } })
  native_read_by(call, told)
  t.run_for(told_before)
  let asked = t.time()
  call.set(Some(native_call("adb.phone", Json::object(Map([])))))
  t.run_for(told_between)
  assert_eq(told, [("{\"wireless\":false}", asked)])
  assert_true(t.find("got {\"wireless\":false}") is Some(_))
  assert_eq(runtime().awaiting(), 0)
  t.assert_idle()
}

///|
test "what the test's pickers give told at the moment of the ask, or of the answer it says, at any rate (Tester::picks, pick_answer)" {
  let asked : @signals.Signal[Pick?] = @signals.signal(None)
  let told : Array[(Int, Double)] = []
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .words(By(fn() {
        match asked.get().map(fn(p) { p.files() }) {
          Some(Some(files)) => "picked \{files.length()}"
          _ => "picking"
        }
      }))
      |> ignore
      n.reacts(fn() { asked.get().map(fn(p) { p.files().map(fn(f) { f.length() }) }) }, fn(r) {
        match r {
          Some(Some(n_files)) => told.push((n_files, n.cause_at()))
          _ => ()
        }
      })
    })
    |> ignore
  })
  t.picks([("a.txt", b"hi"), ("b.txt", b"yo")])
  t.run_for(told_before)
  // answered as it is asked
  let first = t.time()
  asked.set(pick(Files))
  t.run_for(told_between)
  assert_eq(told, [(2, first)])
  assert_true(t.find("picked 2") is Some(_))
  // answered as the test says, the person having taken a while
  t.picks_by_hand()
  t.picks([("c.txt", b"c")])
  asked.set(pick(Files))
  t.run_for(told_before)
  assert_true(t.find("picking") is Some(_))
  waits_quietly(t)
  let second = t.time()
  t.pick_answer(2)
  t.run_for(told_between)
  assert_eq(told, [(2, first), (1, second)])
  assert_true(t.find("picked 1") is Some(_))
  assert_eq(runtime().awaiting(), 0)
  t.assert_idle()
}

///|
test "a pick and pick_photos asked by a press: on_got given what was picked in order, once, at the moment the last host event comes" {
  let got : Array[(String, Array[String], Double)] = []
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .width(Is(Some(120.0)))
      .height(Is(Some(44.0)))
      .says(Is(Some(@view.said(Button, label="Pick"))))
      .on_press(fn() {
        pick(Files, on_got=fn(files) { got.push(("files", files.map(fn(f) { f.name }), view_moment())) }) |> ignore
      })
      |> ignore
    })
    |> ignore
    root.box(fn(n) {
      n
      .width(Is(Some(120.0)))
      .height(Is(Some(44.0)))
      .says(Is(Some(@view.said(Button, label="Gallery"))))
      .on_press(fn() {
        pick_photos(
          ["content://media/1", "content://media/2"],
          on_got=fn(files) { got.push(("photos", files.map(fn(f) { f.name }), view_moment())) },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.run_for(told_before)
  t.picks_by_hand()
  t.tap(20.0, 20.0)
  t.run_for(told_before)
  waits_quietly(t)
  t.picks([("one.png", b"1")])
  let first = t.time()
  t.pick_answer(1)
  t.run_for(told_between)
  assert_eq(got, [("files", ["one.png"], first)])
  // pick_photos asks two gallery reads: on_got waits until both are answered, then gives them in order
  t.tap(20.0, 60.0)
  t.run_for(told_before)
  waits_quietly(t)
  t.picks([("second.jpg", b"2")])
  t.pick_answer(3)
  t.run_for(told_between)
  assert_eq(got.length(), 1)
  t.picks([("first.jpg", b"1")])
  let both = t.time()
  t.pick_answer(2)
  t.run_for(told_between)
  assert_eq(got, [("files", ["one.png"], first), ("photos", ["first.jpg", "second.jpg"], both)])
  on_outside(outside_pick, 2, 1)
  t.run_for(told_between)
  assert_eq(got.length(), 2)
  assert_eq(runtime().awaiting(), 0)
  t.assert_idle()
}
