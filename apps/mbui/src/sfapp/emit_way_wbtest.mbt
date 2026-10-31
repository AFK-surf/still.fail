// The flying avatar's way (emit.mbt) is one smooth motion (the user, 2026-10-31: 「整个头像运动需要流畅且符合逻辑，并且不
// 要有突变」): looked at each frame of a 60 Hz display from its answer's taking till it is home, its speed never steps (no
// start at speed, no dead stop, no speed changed at once: as the list's rows are held, ui's rows_steady.mbt) and its
// shape never jumps (no stretched to flattened at once).

///|
/// How far a 60th of a second's way may be from the mean of the ones before and after it (points; and more than half
/// the faster of them), as rows_steady.mbt holds the list's rows; how much its shape may change in one (a share).
let way_step_most : Double = 3.0

///|
let shape_step_most : Double = 0.1

///|
/// Looks at the flying avatar each frame of the display (60 a second) until none flies (at most `most` ms): where
/// each two looks after one another, its speed or shape stepped more than it may, said.
fn way_steps(t : @ui.Tester, most : Double) -> Array[String] {
  let rk = "ws1/st1\u{1}s-c1"
  let em = emits_of(rk)
  let steps = []
  // the last two looks: where it was, its shape
  let mut before : (Double, Double, Double, Double)? = None
  let mut last : (Double, Double, Double, Double)? = None
  let end = t.time() + most
  let mut flew = false
  while t.time() < end {
    t.frame()
    let now = match em.current {
      Some(turn) => emit_flight(t.ctx(), rk, em, [turn.agent])
      None => None
    }
    match (before, last, now) {
      (Some(a), Some(b), Some(n)) => {
        // (the way into the look before against the ones round it, across and up and down)
        let stepped = fn(a : Double, b : Double, n : Double) {
          let (v0, v1) = (b - a, n - b)
          let off = (v1 - (v0 + v1) / 2.0).abs()
          off > way_step_most && off > dmax(v0.abs(), v1.abs()) / 2.0
        }
        if stepped(a.0, b.0, n.0) || stepped(a.1, b.1, n.1) {
          steps.push("at \{t.time()} (\{em.current.map(fn(c) { c.pose })}): its speed went \{b.1 - a.1} then \{n.1 - b.1}")
        }
      }
      _ => ()
    }
    match (last, now) {
      (Some(b), Some(n)) =>
        if (n.2 - b.2).abs() > shape_step_most || (n.3 - b.3).abs() > shape_step_most {
          steps.push("at \{t.time()} (\{em.current.map(fn(c) { c.pose })}): its shape went from \{b.2} × \{b.3} to \{n.2} × \{n.3}")
        }
      _ => ()
    }
    if now is Some(_) {
      flew = true
    }
    before = last
    last = now
    if flew && em.current is None && em.queue.is_empty() {
      break
    }
  }
  if !flew {
    steps.push("no avatar flew")
  }
  steps
}

///|
test "the flying avatar goes out of its activity, lands on its answer and goes home in one smooth motion" {
  let clock = Ref(0.0)
  let t = emit_core(clock)
  clock.val = clock.val + fix_answer_ms
  t.draw()
  assert_eq(way_steps(t, emit_all_ms() + 500.0), [])
  emit_restore()
}

///|
/// What the agent says more (words of the fixture's: worked out already, sfkept).
let more_said : String = "推送截图前要先登录 gh。"

///|
test "two answers of the same agent: the avatar drops on from the first to the second with no step in its motion" {
  let clock = Ref(0.0)
  let t = emit_core(clock)
  clock.val = clock.val + fix_answer_ms
  t.draw()
  fix_later(1.0, fn() {
    fix_chat("s-c1").sent.push(
      msg(171, "agent", @sffixture.by_agent("anthropic", "claude", "s-c1"), more_said, "刚刚", {
        "ts": Json::string("more171"),
        "said": true,
      }),
    )
  })
  clock.val = clock.val + 1.0
  t.draw()
  let em = emits_of("ws1/st1\u{1}s-c1")
  assert_eq(em.queue.length() + (if em.current is Some(_) { 1 } else { 0 }), 2)
  assert_eq(way_steps(t, 2.0 * emit_all_ms() + 500.0), [])
  assert_eq(emits_of("ws1/st1\u{1}s-c1").done.get("171"), Some(true))
  emit_restore()
}

///|
test "words sent as the avatar is on its way: it slows to come down as they land, its speed never stepping" {
  let clock = Ref(0.0)
  let t = emit_core(clock)
  t.tap_text("发消息")
  t.type_text("再看一下按钮")
  clock.val = clock.val + fix_answer_ms
  t.draw()
  t.run_for(Pose::Fold.ms() + 200.0)
  tap_send(t)
  t.draw()
  assert_true(send_flight.get() is Some(_))
  assert_eq(way_steps(t, emit_all_ms() + 1000.0), [])
  emit_restore()
}

///|
test "an answer said once its agent's turn is over: no avatar to come out of, its words come in a glyph at a time" {
  let clock = Ref(0.0)
  let t = emit_core(clock)
  // its agent done (its line gone), then the answer said
  fix_later(1.0, fn() { fix_chat("s-c1").working = -1.0 })
  clock.val = clock.val + 1.0
  t.draw()
  t.run_for(linger_ms + @ui.move_most_ms)
  assert_true(t.find(tr("android-chat.chat.working")) is None)
  fix_later(1.0, fn() {
    fix_chat("s-c1").sent.push(
      msg(171, "agent", @sffixture.by_agent("anthropic", "claude", "s-c1"), more_said, "刚刚", {
        "ts": Json::string("more171"),
        "said": true,
      }),
    )
  })
  clock.val = clock.val + 1.0
  t.draw()
  let em = emits_of("ws1/st1\u{1}s-c1")
  assert_true(emit_words_only(em, 171.0))
  assert_true(em.current is None)
  // a moment in: some of its glyphs shown, not all; then all
  t.run_for(@ui.row_size_ms / 2.0)
  let some = t.glyphs_shown().length()
  t.run_for(@ui.move_most_ms + 1000.0)
  let all = t.glyphs_shown().length()
  assert_true(some < all, msg="\{some} of \{all}")
  assert_true(t.find(more_said) is Some(_))
  emit_restore()
}
