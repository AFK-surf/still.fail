// Messages from outside (messages.mbt): kept between frames, handed on as the next one begins, a frame asked for once
// a lot, kept on the tape and given again there.

///|
/// The time between two lots of messages in these tests: a run's frames apart, nothing more to it.
let lot_gap_ms : Double = 48.0

///|
test "messages posted between frames are handed on as the next frame begins, in their order, each to its channel" {
  let got : Array[String] = []
  on_message("test.a", fn(j, _) { got.push("a " + j) })
  on_message("test.b", fn(j, b) {
    got.push("b " + j + " " + b.map(b => b.length()).unwrap_or(-1).to_string())
  })
  // what the view saw as it built: the messages handed on before it
  let seen : Array[Int] = []
  let late : Ref[Bool] = Ref::new(false)
  let t = Tester::new(
    fn(c) {
      seen.push(got.length())
      // a post while a frame is built: the next frame's
      if late.val {
        late.val = false
        fake_post(fake.val.unwrap(), "test.a", "late", None)
      }
      c.text("x") |> ignore
    },
    w=100.0,
    h=100.0,
  )
  t.post("test.a", "1")
  t.post("test.b", "2", bytes=b"\x01\x02")
  t.post("test.a", "3")
  // between frames: nothing handed on yet
  assert_eq(got, [])
  seen.clear()
  late.val = true
  t.frame(ms=0.0)
  assert_eq(got, ["a 1", "b 2 2", "a 3"])
  assert_eq(t.messages_taken(), 3)
  // all of them before the view built, none while it did
  assert_eq(seen, [3])
  // the one posted during the frame: not that frame's, the next one's
  assert_true(t.fake.wants)
  t.frame(ms=0.0)
  assert_eq(got, ["a 1", "b 2 2", "a 3", "a late"])
  assert_eq(t.messages_taken(), 1)
  t.assert_idle()
}

///|
test "a lot of posts asks for one frame, and with no messages none is asked" {
  let got : Array[String] = []
  on_message("test.a", fn(j, _) { got.push(j) })
  let t = Tester::new(fn(c) { c.text("x") |> ignore }, w=100.0, h=100.0)
  t.assert_idle()
  // nothing posted: no frame asked for, none taken
  assert_false(t.fake.wants)
  assert_eq(t.post_wakes(), 0)
  t.run_for(lot_gap_ms)
  assert_eq(t.messages_taken(), 0)
  assert_false(t.fake.wants)
  t.post("test.a", "1")
  t.post("test.a", "2")
  t.post("test.a", "3")
  assert_eq(t.post_wakes(), 1)
  assert_true(t.fake.wants)
  let before = t.frames
  t.draw()
  // the one frame took all three, and asked for no other
  assert_eq(t.frames - before, 1)
  assert_eq(got, ["1", "2", "3"])
  assert_false(t.fake.wants)
  assert_false(g().wants_frame)
  // the next lot: one frame more
  t.post("test.a", "4")
  assert_eq(t.post_wakes(), 2)
  t.draw()
  assert_eq(got, ["1", "2", "3", "4"])
  t.assert_idle()
}

///|
/// What the messages' runs show: what came, and the bytes beside it.
fn shown_view(shown : Array[String]) -> (Ctx) -> Unit {
  fn(c) { c.text("got: " + shown.join(" | ")) |> ignore }
}

///|
test "MSG lines kept on the tape and given again by replay_frames draw the same frames" {
  let shown1 : Array[String] = []
  on_message("test.core", fn(j, b) {
    shown1.push(j + b.map(b => " +\{b.length()}").unwrap_or(""))
  })
  let t1 = Tester::new(shown_view(shown1), w=300.0, h=100.0)
  t1.start_tape()
  t1.run_for(lot_gap_ms)
  t1.post("test.core", "{\"id\":1,\"value\":[]}")
  t1.draw()
  t1.run_for(lot_gap_ms)
  t1.post("test.core", "{\"id\":2,\"ok\":\"雪\"}", bytes=b"\xff\x00\x10\x80")
  t1.post("test.core", "{\"id\":3}")
  t1.draw()
  t1.run_for(lot_gap_ms)
  t1.assert_idle()
  let tape = t1.tape()
  let lines = tape.split("\n").map(l => l.to_owned()).to_array()
  assert_eq(lines.filter(l => l.has_prefix("MSG ")).length(), 3)
  assert_true(lines.filter(l => l.has_prefix("DRAWHASH ")).length() > 3)
  // the run seen again: its messages given at their frames, by the tape alone
  let shown2 : Array[String] = []
  on_message("test.core", fn(j, b) {
    shown2.push(j + b.map(b => " +\{b.length()}").unwrap_or(""))
  })
  let t2 = Tester::new(shown_view(shown2), w=300.0, h=100.0)
  let frames = t2.replay_frames(tape)
  assert_eq(frames.length(), lines.filter(l => l.has_prefix("DRAWHASH ")).length())
  for f in frames {
    assert_eq(f.2, f.1)
  }
  assert_eq(shown2, shown1)
  assert_eq(shown2, ["{\"id\":1,\"value\":[]}", "{\"id\":2,\"ok\":\"雪\"} +4", "{\"id\":3}"])
  t2.assert_idle()
}

///|
test "bytes beside a message are kept on the tape as they were" {
  let b = b"\x00\x01\x02\xfd\xfe\xff\x10"
  for n in 0..=b.length() {
    let part = Bytes::from_array(b.to_array()[0:n].to_array())
    assert_eq(@codec.from_base64(@codec.base64(part)), part)
  }
}

///|
test "panic assert_idle with a message posted that no frame took" {
  let t = Tester::new(fn(c) { c.text("x") |> ignore }, w=100.0, h=100.0)
  t.post("test.a", "1")
  t.assert_idle()
}

///|
test "the outside a test stands for posts after a frame what came by then: the next frame takes it" {
  let got : Array[String] = []
  on_message("test.a", fn(j, _) { got.push(j) })
  // an ask made in a frame, answered as the frame ends (a core that answers at once)
  let asked : Array[String] = []
  let t = Tester::new(
    fn(c) {
      if c.messages_taken() == 0 && got.length() == 0 && asked.length() == 0 {
        asked.push("q")
      }
      c.text(got.join(",")) |> ignore
    },
    w=100.0,
    h=100.0,
  )
  t.between_frames(fn() {
    for q in asked {
      t.post("test.a", "answer to " + q)
    }
    asked.clear()
  })
  // the ask was made in the first frame, before the outside was there: posted as the next frame ends, not in it
  t.frame(ms=0.0)
  assert_eq(got, [])
  assert_eq(t.posted(), 1)
  assert_true(t.fake.wants)
  // taken as the frame after begins
  t.frame(ms=0.0)
  assert_eq(got, ["answer to q"])
  assert_eq(t.posted(), 0)
  t.assert_idle()
}

///|
test "what the outside says comes at its moment, however the clock is run on: a frame drawn then, taken at it" {
  let got : Array[(String, Double)] = []
  let t = Tester::new(fn(c) { c.text(got.map(fn(g) { g.0 }).join(",")) |> ignore }, w=100.0, h=100.0)
  on_message("test.a", fn(j, _) { got.push((j, g().clock)) })
  // a kept conversation's message due 437 ms on (off the display's frames)
  let at = t.time() + 437.0
  let due = Ref::new(at)
  t.between_frames(
    fn() {
      if t.time() >= due.val {
        t.post("test.a", "late")
        due.val = @double.infinity
      }
    },
    due=fn() { due.val },
  )
  assert_eq(t.taken_at(), t.time())
  // run on in one go past it: the frame at its moment posts it, the one that takes it is drawn there too
  let past_it = 1000.0
  t.run_for(past_it)
  assert_eq(got, [("late", at)])
  assert_true(t.find("late") is Some(_))
  t.assert_idle()
}

///|
/// A display's frames, each drawn as a host draws them.
let said_frame_ms : Double = 1000.0 / 120.0

///|
/// When a message is posted, and the frame after it looked at.
let said_post_ms : Int = 100

///|
test "a message that changes only a signal, taken as it comes: what read it built again, not the whole frame" {
  let shown : @signals.Signal[String] = @signals.signal("a", same=fn(a, b) { a == b })
  let handed : Array[String] = []
  on_message("test.said", fn(j, _) { handed.push(j) })
  on_message_said("test.said", fn(j, _) {
    if j.has_prefix("set ") {
      shown.set(j.unsafe_substring(start=4, end=j.length()))
      true
    } else {
      false
    }
  })
  // twenty rows, the fourth showing the signal
  let t = Tester::new(
    fn(c) {
      c.list("rows", 20, 20.0, fn(i) {
        c.text(if i == 3 { "row " + shown.get() } else { "row \{i}" }) |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=600.0,
  )
  t.run_for(said_frame_ms)
  t.check_looks(false)
  t.set_frame_period(said_frame_ms)
  // posted between frames, as a host's message comes (each frame's rows kept and built taken as it ends): the first
  // changing only the signal, then one left for its handler
  let ends : Array[(Int, Int)] = []
  let posted : Array[Int] = []
  t.between_frames(fn() {
    ends.push(t.rows_as_nodes())
    let at = (posted.length() + 1) * said_post_ms
    if posted.length() < 2 && t.time() >= at.to_double() {
      t.post("test.said", if posted.is_empty() { "set b" } else { "other" })
      posted.push(ends.length())
    }
  })
  t.run_for((3 * said_post_ms).to_double())
  assert_true(t.find("row b") is Some(_))
  assert_eq(handed, ["other"])
  // the frame that took the first: the one row that read it built, the others kept; the second's, every row built
  let (kept, built) = ends[posted[0]]
  assert_true(built == 1 && kept > 10, msg="\{ends[posted[0]]}")
  assert_true(ends[posted[1]].1 >= 20, msg="\{ends[posted[1]]}")
}
