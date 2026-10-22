// What is sent is on screen first (chat.mbt LocalSent, flight.mbt): in the list the frame it is sent, whatever the
// core, the list or anything else in it is doing; the core's row goes on from it once it comes.

///|
/// The keys of chat s-c1's rows as last built.
fn sent_rows() -> Array[String] {
  let rd = reading_of("ws1/st1\u{1}s-c1")
  rd.sending.map(fn(l) { "o:" + l.row.id })
}

///|
test "words sent are in the list the frame they are sent, the core not answering at all, and fly there at once" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("先上屏")
  tap_send(t)
  // (the core never answers chat.send here: nothing of it is waited for)
  assert_eq(named(calls, "chat.send").length(), 1)
  assert_eq(sent_rows(), ["o:local:1"])
  let rd = reading_of("ws1/st1\u{1}s-c1")
  assert_true(rd.known.contains("o:local:1"))
  // laid out in that frame: the words set off from the field the frame after
  t.draw()
  match send_flight.val {
    Some(f) => {
      assert_eq(f.key, "o:local:1")
      assert_true(f.placed)
    }
    None => fail("nothing flies")
  }
  t.run_for(flight_ms)
  assert_true(send_flight.val is None)
  // still there, as sent, till the core has it
  assert_eq(sent_rows(), ["o:local:1"])
  assert_true(t.find("先上屏") is Some(_))
  t.run_for(composer_morph_ms)
  t.assert_idle()
}

///|
test "refused by the core: what was sent leaves the list, the words back in the field" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("先上屏")
  tap_send(t)
  assert_eq(sent_rows(), ["o:local:1"])
  (named(calls, "chat.send")[0].done)(
    Err({ "code": Json::string("invalid_params"), "message": Json::string("太长了") }),
  )
  t.draw()
  assert_eq(sent_rows(), [])
  let (_, words, _, _) = t.ime()
  assert_eq(words, "先上屏")
}

///|
test "the core's row goes on from what was sent: the words fly on to it, it does not rise in again" {
  reset()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.run_for(@ui.nav_push_ms)
  t.tap_text("发消息")
  t.type_text("先上屏")
  tap_send(t)
  t.draw()
  t.draw()
  // the core's outbox has it: the row is its, what flies goes on to it
  let rd = reading_of("ws1/st1\u{1}s-c1")
  assert_eq(sent_rows(), [])
  match send_flight.val {
    Some(f) => {
      assert_true(f.key != "o:local:1")
      assert_true(rd.known.contains(f.key))
      assert_false(rd.rises.contains(f.key))
    }
    None => fail("nothing flies")
  }
  t.run_for(flight_ms)
  assert_true(send_flight.val is None)
  assert_true(t.find("先上屏") is Some(_))
  fix_clock.val = None
}
