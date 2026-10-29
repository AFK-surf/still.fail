// An agent's answer coming out of its activity's avatar (emit.mbt, ChatMotion.kt), over the fixture's station: what
// is sent sets its agent to work (its activity shows), its answer is said while the chat shows.

///|
/// The fixture's chat open, its clock the test's; words sent and taken by the station (its agent then at work).
fn emit_core(clock : Ref[Double]) -> @ui.Tester {
  reset()
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  // the chat pushed in over Home
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("看一下列表")
  tap_send(t)
  // the station has it: in the chat, its agent at work
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  // (the station answers fix_answer_ms after it took them: that time passes on the page too, the words sent landed
  // and the agent's line come in their turns meanwhile)
  t.run_for(fix_answer_ms)
  t
}

///|
/// A message's whole way out of its avatar: fold, float, spit, return.
fn emit_all_ms() -> Double {
  Pose::Fold.ms() + Pose::Float.ms() + Pose::Spit.ms() + Pose::Return.ms()
}

///|
fn emit_restore() -> Unit {
  fix_clock.val = None
}

///|
test "an answer said while its agent's activity shows waits, then comes out of its avatar: fold, float, spit, return" {
  let clock = Ref::new(0.0)
  let t = emit_core(clock)
  // at work: its activity
  assert_true(t.find("看一下列表") is Some(_))
  let em = emits_of("ws1/st1\u{1}s-c1")
  clock.val = clock.val + fix_answer_ms
  t.draw()
  // the answer is taken: it waits (folding, then the avatar on its way), not in the list yet
  assert_eq(em.queue.length() + (if em.current is Some(_) { 1 } else { 0 }), 1)
  assert_true(t.find("收到：「看一下列表」") is None)
  // fold and float: it comes into the list as the avatar lands
  t.run_for(Pose::Fold.ms() + Pose::Float.ms())
  assert_true(t.find("收到：「看一下列表」") is Some(_))
  t.run_for(Pose::Spit.ms() + Pose::Return.ms())
  assert_true(em.current is None)
  assert_true(t.find("收到：「看一下列表」") is Some(_))
  emit_restore()
}

///|
test "an answer taller than the window out of the avatar, the list at its end: read from its top, under the bar" {
  let clock = Ref::new(0.0)
  let t = emit_core(clock)
  // its agent at work, the list at its end: it says something long (in over its line), before the fixture's answer
  let first = "列表改成虚拟列表"
  let more = Array::makei(30, fn(i) { "第 \{i + 1} 段，接着往下讲。" }).join("\n\n")
  fix_later(1.0, fn() {
    fix_chat("s-c1").sent.push(
      msg(170, "agent", @sffixture.by_agent("anthropic", "claude", "s-c1"), long_reply + "\n\n" + more, "刚刚", {
        "ts": Json::string("long170"),
        "said": true,
      }),
    )
  })
  clock.val = clock.val + 1.0
  t.draw()
  t.run_for(emit_all_ms() + 1000.0)
  // its top in view under the bar (Follow.kt), not the list at the end of it
  guard t.drawn_of(first) is Some((_, y)) else { fail("the answer's top is not in view") }
  assert_true(y > bar_foot() && y < 844.0 / 2.0, msg="the answer's top at \{y}, the bar's foot at \{bar_foot()}")
  emit_restore()
}

///|
/// As the flying avatar lands on the answer (Spit): where the agent's picture is in its line and where the answer's is
/// (their left edges, in the window).
fn landing_faces(t : @ui.Tester) -> (Double, Double) raise {
  let rk = "ws1/st1\u{1}s-c1"
  let em = emits_of(rk)
  guard em.current is Some(turn) && turn.pose == Spit else {
    fail("not landing: \{em.current.map(fn(c) { c.pose })}")
  }
  let face = @motion.measured_rect(t.ctx(), "emit-avatar/" + rk + "/" + turn.agent).unwrap()
  let lands = @motion.measured_rect(t.ctx(), "emit-landing/" + rk + "/" + seq_s(turn.seq)).unwrap()
  (face.0, lands.0)
}

///|
test "an agent's picture in its line is where its answer's is, at the row's start: the flying one lands with no step aside" {
  let clock = Ref::new(0.0)
  let t = emit_core(clock)
  clock.val = clock.val + fix_answer_ms
  t.draw()
  t.run_for(Pose::Fold.ms() + Pose::Float.ms() + Pose::Spit.ms() / 2.0)
  let (face, lands) = landing_faces(t)
  assert_true((face - lands).abs() < 0.5, msg="\{face} \{lands}")
  emit_restore()
}

///|
test "the flying avatar goes where its answer comes in: where it was aimed on its way is where it lands, no jump as the answer comes out" {
  let clock = Ref::new(0.0)
  let t = emit_core(clock)
  let em = emits_of("ws1/st1\u{1}s-c1")
  clock.val = clock.val + fix_answer_ms
  t.draw()
  // every frame of its way: where it was aimed last on it, then where it lets the answer out
  let mut aimed : (Double, Double)? = None
  let mut landed : (Double, Double)? = None
  let end = t.time() + emit_all_ms()
  while t.time() < end && landed is None {
    t.frame()
    match em.current {
      Some(turn) if turn.pose == Float => aimed = em.aimed
      Some(turn) if turn.pose == Spit => landed = em.landed
      _ => ()
    }
  }
  guard (aimed, landed) is (Some(a), Some(l)) else { fail("aimed \{aimed}, landed \{landed}") }
  assert_true((a.0 - l.0).abs() < 0.5 && (a.1 - l.1).abs() < 0.5, msg="aimed at \{a}, landed at \{l}")
  emit_restore()
}

///|
test "with the reader scrolled up (not watched), an answer just appears" {
  let clock = Ref::new(0.0)
  let t = emit_core(clock)
  t.wheel(195.0, 400.0, -600.0)
  let em = emits_of("ws1/st1\u{1}s-c1")
  clock.val = clock.val + fix_answer_ms
  t.draw()
  assert_true(em.current is None)
  assert_eq(em.queue.length(), 0)
  assert_false(emit_held(em, 102.0))
  emit_restore()
}

///|
test "the answer coming in does not end its own motion: float, spit and return each played whole, the avatar drawn" {
  let clock = Ref::new(0.0)
  let t = emit_core(clock)
  let em = emits_of("ws1/st1\u{1}s-c1")
  clock.val = clock.val + fix_answer_ms
  t.draw()
  let frames : Map[String, Int] = {}
  // frame by frame over its whole way out
  let end = t.time() + emit_all_ms()
  while t.time() < end {
    t.frame()
    match em.current {
      Some(turn) => {
        let k = turn.pose.to_string()
        frames[k] = frames.get(k).unwrap_or(0) + 1
        // the flying copy is drawn in every pose after the fold (emit_flyer)
        if turn.pose != Fold {
          assert_true(emit_flight(t.ctx(), "ws1/st1\u{1}s-c1", em, [turn.agent]) is Some(_))
        }
      }
      None => ()
    }
  }
  // 16 ms frames: Float 440 ms, Spit 380, Return 320 (ChatMotion.kt), each to its end
  assert_true(frames.get("Float").unwrap_or(0) >= 26)
  assert_true(frames.get("Spit").unwrap_or(0) >= 22)
  assert_true(frames.get("Return").unwrap_or(0) >= 18)
  assert_true(em.current is None)
  emit_restore()
}
