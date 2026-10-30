// What is sent is on screen first (sfbase's sent.mbt LocalSent, flight.mbt): in the list the frame it is sent,
// whatever the core, the list or anything else in it is doing; the core's row goes on from it once it comes.

///|
/// The keys of chat s-c1's rows as last built.
fn sent_rows() -> Array[String] {
  sending_of("ws1/st1\u{1}s-c1").map(fn(l) { "o:" + l.row.id })
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
  match send_flight.get() {
    Some(f) => {
      assert_eq(f.key, "o:local:1")
      assert_true(f.placed)
    }
    None => fail("nothing flies")
  }
  t.run_for(@sfbase.flight_most_ms)
  assert_true(send_flight.get() is None)
  // still there, as sent, till the core has it
  assert_eq(sent_rows(), ["o:local:1"])
  assert_true(t.find("先上屏") is Some(_))
  t.run_for(@ui.move_most_ms)
  t.assert_idle()
}

///|
test "words sent from a window short of the chat's end: its latest page asked for, the list at its end as it comes" {
  let short = Ref(true)
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" || !short.val {
      return tp
    }
    match tp.value {
      Some(Object(m)) => {
        let o = m.copy()
        o["newer"] = Json::boolean(true)
        { ..tp, value: Some(Json::object(o)), version: tp.version + 1 }
      }
      _ => tp
    }
  })
  t.tap_text("发消息")
  t.type_text("先上屏")
  tap_send(t)
  assert_eq(named(calls, "chat.latest").length(), 1)
  // read up there meanwhile; the latest page comes: the list at its end
  t.move(195.0, 400.0)
  t.wheel(195.0, 400.0, -900.0)
  assert_true(!t.at_end())
  short.val = false
  t.draw()
  t.draw()
  assert_true(t.at_end())
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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("先上屏")
  tap_send(t)
  t.draw()
  t.draw()
  // the core's outbox has it: the row is its, by the key it was sent as (one row from the press on), what flies goes
  // on to it
  let rd = reading_of("ws1/st1\u{1}s-c1")
  assert_eq(sent_rows(), [])
  match send_flight.get() {
    Some(f) => {
      assert_true(f.key == "o:local:1")
      assert_true(rd.known.contains(f.key))
      assert_false(rd.rises.contains(f.key))
    }
    None => fail("nothing flies")
  }
  t.run_for(@sfbase.flight_most_ms)
  assert_true(send_flight.get() is None)
  assert_true(t.find("先上屏") is Some(_))
  fix_clock.val = None
}

///|
/// Not seen: not there, or drawn at no opacity (an answer laid out where it comes in, its avatar on its way to it).
fn not_seen(t : @ui.Tester, words : String) -> Bool {
  match t.look_of(words) {
    Some((_, _, alpha)) => alpha == 0.0
    None => true
  }
}

///|
test "words sent while an answer comes out of its avatar fly at once; the answer comes in once they have landed" {
  let clock = Ref::new(0.0)
  let t = emit_core(clock)
  t.tap_text("发消息")
  t.type_text("再看一下按钮")
  // the answer to the first words taken: its agent's activity folding, the avatar on its way
  clock.val = clock.val + fix_answer_ms
  t.draw()
  t.run_for(Pose::Fold.ms() + 200.0)
  let sent_at = t.time()
  tap_send(t)
  t.draw()
  let landing = match send_flight.get() {
    Some(f) => {
      assert_true(f.placed)
      f.way.ends()
    }
    None => fail("nothing flies")
  }
  // the avatar there before the words have landed: the answer waits for them (in the list where it comes in since the
  // avatar set out for it, not drawn), the words' row not moved under them; the avatar where the answer comes in, over
  // the words sent (not yet the chat's: under the messages)
  t.run_for(sent_at + Pose::Float.ms() - 200.0 + 60.0 - t.time())
  assert_true(not_seen(t, "收到：「看一下列表」"))
  let em = emits_of("ws1/st1\u{1}s-c1")
  let agents = match em.current.get() {
    Some(turn) => {
      // not there before them, waiting: still on its way down, to come down as they land
      assert_true(turn.pose == Float)
      assert_true(turn.clock.moving())
      assert_true((turn.clock.ends() - landing).abs() < 0.001)
      [turn.agent]
    }
    None => fail("no answer comes out")
  }
  match (emit_flight(t.ctx(), "ws1/st1\u{1}s-c1", em, agents), t.drawn_of("再看一下按钮")) {
    (Some((_, ay, _, _)), Some((_, by))) => assert_true(ay < by)
    _ => fail("the avatar or the words not drawn")
  }
  // the answer comes in as they land, over them: they are pushed down from where they were, not moved at once
  t.run_for(landing - 20.0 - t.time())
  assert_true(not_seen(t, "收到：「看一下列表」"))
  let was = t.drawn_of("再看一下按钮")
  t.run_for(landing - t.time())
  assert_true(send_flight.get() is None)
  assert_true(t.find("收到：「看一下列表」") is Some(_))
  match (was, t.drawn_of("再看一下按钮")) {
    (Some((_, y0)), Some((_, y1))) => assert_true((y1 - y0).abs() < 1.0)
    _ => fail("the words not drawn")
  }
  emit_restore()
}

///|
test "words sent are seen every frame from the field to their bubble: not gone the frame their row is laid out" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("先上屏")
  t.draw()
  tap_send(t)
  let sent = t.time()
  while t.time() < sent + flight_ms + 50.0 {
    t.frame()
    seen_once(t, "先上屏") |> ignore
  }
  assert_true(send_flight.get() is None)
}

///|
test "the core's row joined to the viewer's last as the words fly: the rows above go on up with them, never put up at once" {
  // as the core says it (views.ts drawn): words sent soon after the viewer's last are joined to it, its time going
  // under them; what was sent from here is drawn apart (LocalSent) until the core has it, a frame or two later
  let has = Ref::new(false)
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    match (name, tp.value) {
      ("chat", Some(Object(m))) => {
        let v = m.copy()
        let messages = match m.get("messages") {
          Some(Array(a)) => a.copy()
          _ => []
        }
        let mine : Map[String, Json] = { "mine": true, "author": "lin@example.com" }
        if has.val {
          mine["followed"] = true
          v["outbox"] = [
            {
              "id": "out-1",
              "text": "看看怎么回事",
              "attachments": [],
              "quotes": [],
              "createdAt": 0,
              "state": "sending",
              "joined": true,
            },
          ]
        }
        messages.push(msg(12, "person", by_person("林"), "先看一下列表", "刚刚", mine))
        v["messages"] = Json::array(messages)
        { ..tp, value: Some(Json::object(v)), version: if has.val { 2 } else { 1 } }
      }
      _ => tp
    }
  })
  t.tap_text("发消息")
  t.type_text("看看怎么回事")
  t.draw()
  let (_, was) = seen_once(t, "先看一下列表")
  tap_send(t)
  t.draw()
  // the core has it: its row, joined, shorter than what was sent from here (and the one before without its time)
  has.val = true
  t.frame()
  let lands = match send_flight.get() {
    Some(f) => {
      assert_true(f.key == "o:local:1")
      f.way.ends()
    }
    None => fail("nothing flies")
  }
  // (on its way up with the words from the frame they were sent: their row's room opening, Ctx::row_size)
  let (_, y) = seen_once(t, "先看一下列表")
  assert_true(y <= was + 0.5 && was - y < 10.0, msg="put up at once: \{was} → \{y}")
  // every frame on the words' way, up from where it was to where it is at the end, never past it nor back down
  let ys = [y]
  while t.time() < lands + 50.0 {
    t.frame()
    ys.push(seen_once(t, "先看一下列表").1)
  }
  let end = ys[ys.length() - 1]
  assert_true(end < was - 10.0)
  for i, y in ys {
    assert_true(y >= end - 0.5, msg="past its place at frame \{i}: \{y} < \{end}")
    if i > 0 {
      assert_true(y <= ys[i - 1] + 0.5, msg="back down at frame \{i}: \{ys[i - 1]} → \{y}")
    }
  }
}
