///|
/// A page that asks `name` of its host (in a Ctx::tell, as `ask` is set) and says its answer once it has it.
fn native_page(
  ask : Ref[Bool],
  name : String,
  took : Ref[Result[Json, String]?],
) -> (@ui.Ctx) -> Unit {
  let call : Ref[@ui.NativeCall?] = Ref::new(None)
  fn(c) {
    if ask.val {
      ask.val = false
      c.tell("ask", fn() { call.val = Some(@ui.native_call(name, { "station": "w/s" })) })
    }
    match call.val {
      Some(k) =>
        match k.got() {
          Some(r) => {
            took.val = Some(r)
            call.val = None
          }
          None => ()
        }
      None => ()
    }
    c.text(
      match took.val {
        Some(Ok(j)) => "got " + j.stringify()
        Some(Err(why)) => "refused " + why
        None => "nothing"
      },
      wrap=false,
    )
    |> ignore
  }
}

///|
test "a native call waits until the test answers it, taken the frame after; refused, why" {
  let ask = Ref::new(false)
  let took : Ref[Result[Json, String]?] = Ref::new(None)
  let t = @ui.Tester::new(native_page(ask, "adb.phone", took))
  ask.val = true
  t.draw()
  let calls = t.native_calls()
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].1, "adb.phone")
  assert_eq(calls[0].2, { "station": "w/s" })
  // not answered: awaited, not at rest
  assert_false(t.at_rest())
  assert_true(t.awaited().iter().any(fn(a) { a.contains("the native call adb.phone") }))
  t.answer_native(calls[0].0, { "wireless": true })
  // (taken the frame after it was answered)
  assert_eq(took.val, None)
  t.draw()
  assert_eq(took.val, Some(Ok({ "wireless": true })))
  assert_true(t.find("got {\"wireless\":true}") is Some(_))
  assert_true(t.at_rest())
  // refused
  took.val = None
  ask.val = true
  t.draw()
  t.refuse_native(t.native_calls()[0].0, "no such call")
  t.draw()
  assert_eq(took.val, Some(Err("no such call")))
  assert_eq(t.native_asked().length(), 2)
  t.assert_idle()
}

///|
test "a name's calls answered as they are asked, each from the frame after" {
  let ask = Ref::new(false)
  let took : Ref[Result[Json, String]?] = Ref::new(None)
  let t = @ui.Tester::new(native_page(ask, "adb.phone", took))
  t.native_answers("adb.phone", fn(p) { { "asked": p } })
  ask.val = true
  t.draw()
  assert_eq(t.native_calls().length(), 0)
  t.draw()
  assert_eq(took.val, Some(Ok({ "asked": { "station": "w/s" } })))
  t.assert_idle()
}

///|
test "a native call's answer as the app took it is kept on the tape and given again to a Tester replaying it" {
  let ask = Ref::new(false)
  let took : Ref[Result[Json, String]?] = Ref::new(None)
  let t = @ui.Tester::new(native_page(ask, "adb.phone", took))
  t.start_tape()
  let begun = t.time()
  t.frame()
  ask.val = true
  t.draw()
  t.answer_native(t.native_calls()[0].0, { "developer": false, "wifi": true })
  t.draw()
  t.frame()
  let tape = t.tape()
  assert_true(tape.contains("NATIVESAID "))
  // replayed with nothing answered: the run's answer
  let ask2 = Ref::new(false)
  let took2 : Ref[Result[Json, String]?] = Ref::new(None)
  let u = @ui.Tester::new(native_page(ask2, "adb.phone", took2), time=begun)
  ask2.val = true
  let frames = u.replay_frames(tape)
  for f in frames {
    assert_eq(f.1, f.2, msg="frame \{f.0}")
  }
  assert_eq(took2.val, Some(Ok({ "developer": false, "wifi": true })))
}
