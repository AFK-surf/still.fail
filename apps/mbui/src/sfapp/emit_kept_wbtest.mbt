// An agent's answer coming out of its avatar with the pages kept as a device keeps them (mbui's kept_part.mbt: a page
// built again only as what it read changes), the frames drawn only as the app asks its host for them (wanted_after:
// the display's next, or its wake), the station's answers on the window's runtime's clock (fix_later without a test's
// clock): nothing of the test's own telling a change came. It comes out whole, its avatar back home, nothing asked for
// after, and the next comes too: on the phone's screen, a Medium one and a Large one, the field kept focused or let
// go. (The chat's page kept as it was drawn is shown all the same: what it marks used each frame it is drawn,
// chat_list.mbt's list_frame.) Under another page it is shown no more, and waits.

///|
/// The frames a host draws from now till `until`: each when the app asks (its next display frame, or its wake), none
/// when it asks for none. What stands when it asks for none before `until`, in words; "" when it asked all the way.
fn host_frames_till(t : @ui.Tester, until : Double) -> String {
  while t.time() < until {
    let w = t.wanted_after()
    if w == @double.infinity {
      return "asks for no frame at \{t.time()}"
    }
    let at = if w <= t.time() { t.next_frame_time() } else { t.display_frame(w) }
    if at > until {
      return ""
    }
    t.frame_at(at)
  }
  ""
}

///|
let emit_chat : String = "ws1/st1\u{1}s-c1"

///|
/// The chat's state as it stands, for what is told of a stall.
fn emit_said(t : @ui.Tester) -> String {
  let em = emits_of(emit_chat)
  let rd = reading_of(emit_chat)
  let tu = turns_of(emit_chat)
  "frame \{t.ctx().frame_number()} shown_frame \{rd.shown_frame} stepped \{tu.stepped} current \{em.current is Some(_)} queue \{em.queue.length()} copied \{em.copied} asks \{tu.asks.length()} wanted \{t.wanted_after()} (\{t.wanted_why()})"
}

///|
/// The field pressed and `words` typed in it.
fn emit_typed(t : @ui.Tester, words : String) -> String {
  ignore(host_frames_till(t, t.time() + 300.0))
  // (the field as it says itself: 发消息, or let go on a Large screen 按空格输入; a page not in use (a Medium screen's
  // beside its list) comes over at the first press, the field takes the second)
  for _ in 0..<2 {
    if t.ime().0 {
      break
    }
    let at = match t.find("发消息") {
      Some(p) => Some(p)
      None => t.find("按空格输入")
    }
    match at {
      Some((x, y)) => t.tap(x, y)
      None => return "no field: \{t.words().map(fn(w) { w.0 })}"
    }
    ignore(host_frames_till(t, t.time() + 500.0))
  }
  if !t.ime().0 {
    return "the field not focused by a press on it"
  }
  t.type_text(words)
  ""
}

///|
/// Words sent, the answer out of its avatar: what came of it ("ok": its words in the list, the avatar back home, and,
/// the field let go, no display frame asked for after; else what stood).
fn emit_sent(t : @ui.Tester, words : String, focused : Bool) -> String {
  let typed = emit_typed(t, words)
  if typed != "" {
    return typed
  }
  tap_send(t)
  // A person puts the keyboard away when they are done writing.
  if !focused {
    t.keyboard_gone()
    if t.ime().0 {
      return "the field still focused after the keyboard was put away"
    }
  }
  t.frames_owed()
  let end = t.time() +
    fix_deliver_ms +
    fix_answer_ms +
    fix_turn_end_ms +
    Pose::Fold.ms() +
    Pose::Float.ms() +
    Pose::Spit.ms() +
    Pose::Return.ms() +
    1000.0
  let stall = host_frames_till(t, end)
  let em = emits_of(emit_chat)
  let shown = t.find("收到：「" + words + "」") is Some(_)
  // (its avatar home: no flying copy, its activity's own shown again)
  let done = em.current is None && em.queue.length() == 0 && em.copied == ""
  // (let go, nothing goes on: no display frame asked for once it is over; at most the next step of a working mark
  // still drawn (resident cycle_look, a wake each cycle_step_ms: the list's spoke, src/sf/icons.mbt spoke_turn, and
  // its rows' marks, src/sfpages/chat_mark.mbt lead_look); focused, the caret's blink asks for its own)
  let idle = focused || t.wanted_after() != 0.0
  if shown && done && idle {
    "ok"
  } else {
    "shown \{shown} done \{done} idle \{idle} \{stall}; \{emit_said(t)}"
  }
}

///|
/// The chat open in a window `w` wide (the phone's below 600, with touch), its pages kept, frames as the host is asked.
fn emit_window(w : Double) -> @ui.Tester {
  let t = if w >= 600.0 {
    wide_tester([], mode="chat", w~)
  } else {
    new_run()
    let src = fixture("chat")
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
    t.run_for(@ui.move_most_ms)
    t
  }
  t.keep_parts(true)
  t.frames_owed()
  // (a Medium screen's sidebar in use: the chat brought over as a person brings it, a press on its edge showing)
  if w >= 600.0 && w < 840.0 {
    t.tap(w - 20.0, 400.0)
    ignore(host_frames_till(t, t.time() + @ui.move_most_ms + 100.0))
  }
  t
}

///|
fn emit_kept(w : Double, focused : Bool) -> (String, String) {
  let t = emit_window(w)
  let first = emit_sent(t, "看一下列表", focused)
  let second = emit_sent(t, "测试一下", focused)
  (first, second)
}

///|
test "kept, host frames: the phone's screen, the field focused" {
  assert_eq(emit_kept(390.0, true), ("ok", "ok"))
}

///|
test "kept, host frames: the phone's screen, the field let go" {
  assert_eq(emit_kept(390.0, false), ("ok", "ok"))
}

///|
test "kept, host frames: a Medium screen, the field focused" {
  assert_eq(emit_kept(720.0, true), ("ok", "ok"))
}

///|
test "kept, host frames: a Medium screen, the field let go" {
  assert_eq(emit_kept(720.0, false), ("ok", "ok"))
}

///|
test "kept, host frames: a Large screen, the field focused" {
  assert_eq(emit_kept(1280.0, true), ("ok", "ok"))
}

///|
test "kept, host frames: a Large screen, the field let go" {
  assert_eq(emit_kept(1280.0, false), ("ok", "ok"))
}

///|
test "the avatar going home draws its movement without laying out the chat again" {
  let clock = Ref(0.0)
  let t = emit_core(clock)
  t.keep_parts(true)
  // A focused editor keeps its page live for its caret. Put the keyboard away to test the avatar's work alone.
  t.keyboard_gone()
  t.frames_owed()
  clock.val = clock.val + fix_answer_ms
  t.draw()
  let em = emits_of(emit_chat)
  let until = t.time() + Pose::Fold.ms() + Pose::Float.ms() + Pose::Spit.ms() + Pose::Return.ms() / 4.0
  ignore(host_frames_till(t, until))
  guard em.current is Some(turn) && turn.pose == Return else {
    fail("the avatar is not on its way home: \{em.current.map(fn(c) { c.pose })}")
  }
  // Compare whole and retained frames above; inspect the next frame itself, without the comparison's rebuild.
  t.check_looks(false)
  for _ in 0..<3 {
    let before = em.trace.0
    t.frame_at(t.next_frame_time())
    let perf = t.frame_perf()
    assert_true(em.trace.0 > before, msg="the avatar did not move")
    assert_true(perf.painted, msg="its move laid out the chat again: \{t.built_why()}; \{perf}")
  }
  emit_restore()
}

///|
test "kept, host frames: the chat left before its answer is shown no more, and asks for no frame" {
  let t = emit_window(390.0)
  assert_eq(emit_typed(t, "看一下列表"), "")
  tap_send(t)
  t.frames_owed()
  // back to Home, its answer still to come
  t.back()
  t.frames_owed()
  let stall = host_frames_till(t, t.time() + fix_deliver_ms + fix_answer_ms + fix_turn_end_ms + 3000.0)
  let rd = reading_of(emit_chat)
  // (the chat's page not drawn: never shown, whatever it marked used while it was)
  assert_true(rd.shown_frame < t.ctx().frame_number() - 1, msg="shown under Home: \{emit_said(t)}")
  // (a wake each cycle_step_ms for the working marks the screen under it still draws, never a frame each frame)
  assert_true(t.wanted_after() != 0.0, msg="still asks: \{stall}; \{emit_said(t)}")
}
