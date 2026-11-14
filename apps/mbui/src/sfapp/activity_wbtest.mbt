// An agent at work in a chat: its ring of eight arcs steps round, a step every 100 ms (Spokes.kt;
// the steps themselves: src/sf/spokes_test.mbt).

///|
test "activity: its ring steps round" {
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  // delivered: its agent at work (the station's clock stays, so its turn's time does too)
  fix_clock_set(clock, clock.val + fix_deliver_ms)
  t.draw()
  t.run_for(flight_wait_ms + @ui.move_most_ms + 1000.0)
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  // the keyboard put away: the field's caret no longer blinks
  t.keyboard_gone()
  let at = t.drawlist()
  t.run_for(@sf.spoke_step_ms)
  assert_true(t.drawlist() != at)
  fix_clock.val = None
}

///|
/// How soon after the words sent land their agent starts in activity_followed: soon enough that its line comes in
/// while the list has just come to rest at its end.
let agent_soon_ms : Double = 100.0

///|
/// The frames of a 120 Hz display, each drawn (a host's, not only the moments something is due).
let display_frame_ms : Double = 1000.0 / 120.0

///|
/// The working agent's card, returned only for that agent as the core would return it.
fn activity_card_tester(w : Double, h : Double, platform : Int) -> @ui.Tester {
  new_run()
  let base = fixture("chat-working")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let got = base.topic(name, params).get().snapshot()
      if name == "agentCard" && text(Some(Json::object(params)), "key") != "s-c1" {
        { ..got, value: None }
      } else {
        got
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The centre of the picture in the working agent's activity line.
fn activity_picture(t : @ui.Tester) -> (Double, Double) raise {
  let lines = t.all(Button).filter(fn(s) { s.label.has_prefix("Claude：") })
  assert_eq(lines.length(), 1, msg="the working agent's line")
  let (x, y, _, h) = lines[0].rect
  (x + 12.0, y + h / 2.0)
}

///|
test "activity: the picture opens its agent's card under the pointer, and still opens its history when pressed" {
  for (w, h) in [(390.0, 844.0), (900.0, 800.0), (1280.0, 800.0)] {
    let t = activity_card_tester(w, h, 0)
    let (x, y) = activity_picture(t)
    assert_true(t.find("共工作 1 小时 12 分") is None)
    let (wx, wy, ww, wh) = t.rect_of(@sffixture.working_step).unwrap()
    t.move_to(wx + ww / 2.0, wy + wh / 2.0)
    t.run_for(@sfpages.hover_open_ms * 2.0)
    assert_true(t.find("共工作 1 小时 12 分") is None, msg="the activity's words do not open the card")
    t.move_to(x, y)
    t.run_for(@sfpages.hover_open_ms * 2.0)
    let card = t.rect_of("共工作 1 小时 12 分")
    assert_true(card is Some(_), msg="the working agent's card appears over its picture")
    let (cx, cy, cw, ch) = card.unwrap()
    // The pointer can cross into the card and use it without it disappearing.
    t.move_to(cx + cw / 2.0, cy + ch / 2.0)
    t.run_for(@sfpages.hover_close_ms * 2.0)
    assert_true(t.find("共工作 1 小时 12 分") is Some(_))
    t.move_to(1.0, 1.0)
    t.run_for(@sfpages.hover_close_ms * 2.0)
    assert_true(t.find("共工作 1 小时 12 分") is None)
    t.tap(x, y)
    t.frame()
    let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
    if w >= 600.0 {
      assert_eq(side_now(r).1, "s-c1", msg="pressing the picture opens this agent's history")
    } else {
      assert_true(app.nav.top() is History(_, "s-c1", _), msg="pressing the picture opens this agent's history")
    }
  }
}

///|
test "activity: a touch on the picture still opens its agent's history" {
  let t = activity_card_tester(390.0, 844.0, 2)
  let (x, y) = activity_picture(t)
  t.tap(x, y)
  t.frame()
  assert_true(app.nav.top() is History(_, "s-c1", _))
}

///|
test "activity: a mouse used with a touch-native system opens the same card" {
  let t = activity_card_tester(390.0, 844.0, 2)
  let (x, y) = activity_picture(t)
  t.host_says_finger(Some(false))
  t.move_to(x, y)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  assert_true(t.find("共工作 1 小时 12 分") is Some(_))
}

///|
test "activity: its line coming in at the list's end is followed, the list gliding to its end as the line opens" {
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  // (its line's first frame laid out twice, its room not opened yet at the first: a glide that set out then is under
  // way at the second, not over with the line still to open under the composer)
  t.set_frame_period(display_frame_ms)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  // delivered, its agent not at work yet; at work a moment later
  fix_later(fix_deliver_ms + 1.0, fn() { fix_chat("s-c1").working = -1.0 })
  fix_clock_set(clock, clock.val + fix_deliver_ms + 1.0)
  t.draw()
  t.run_for(agent_soon_ms)
  assert_true(t.at_end())
  fix_later(1.0, fn() { fix_chat("s-c1").working = clock.val })
  fix_clock_set(clock, clock.val + 1.0)
  t.draw()
  t.run_for(flight_wait_ms)
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  assert_true(t.at_end())
  fix_clock.val = None
}

///|
test "the viewer's own message taller than the list is followed to the end: its foot and its agent's line in view" {
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  // a message of the viewer's taller than the list (sent from here, or from another of their devices), its agent at
  // work on it: an agent's message so long is read from its top, the viewer's own followed to the end
  let lines = Array::makei(40, fn(i) { "第 \{i + 1} 行" })
  lines.push("最后一行")
  fix_later(1.0, fn() {
    let fc = fix_chat("s-c1")
    fc.sent.push(
      msg(150, "person", by_person("林"), lines.join("\n\n"), "刚刚", { "ts": Json::string("me150"), "mine": true, "said": true }),
    )
    fc.working = clock.val
  })
  fix_clock_set(clock, clock.val + 1.0)
  t.draw()
  t.run_for(flight_wait_ms)
  guard t.shown_of("最后一行") is Some((_, _, w, h)) && w > 0.0 && h > 0.0 else {
    fail("the foot of the viewer's message is out of view")
  }
  guard t.shown_of(tr("android-chat.chat.working")) is Some((_, _, w, h)) && w > 0.0 && h > 0.0 else {
    fail("its agent's line is out of view")
  }
  fix_clock.val = None
}

///|
test "its line gone with the answer that came out of its avatar, the agent still at work: not back this turn" {
  let clock = Ref(0.0)
  let t = emit_core(clock)
  let em = emits_of("ws1/st1\u{1}s-c1")
  fix_clock_set(clock, clock.val + fix_answer_ms)
  t.draw()
  t.run_for(emit_all_ms())
  assert_true(em.watched)
  assert_true(em.current is None)
  // (2026-11-09 the user: the answer takes its place, 「处理中」跟回复同一次换位)
  assert_true(readings.get("ws1/st1\u{1}s-c1").unwrap().running.length() > 0)
  assert_true(t.find(tr("android-chat.chat.working")) is None)
  // (the copy that flew is gone: the activity's own avatar shows again)
  assert_eq(em.copied, "")
  emit_restore()
}

///|
test "its line stays after a post saying how far it got, the agent still at work: only an answer that ends the turn takes its place" {
  // (2026-11-09 the user: 「agent 发完消息 activity 不出现」, its line gone for the rest of the turn after a progress post)
  let clock = Ref(0.0)
  let t = emit_core(clock, words="看下进度")
  let em = emits_of("ws1/st1\u{1}s-c1")
  fix_clock_set(clock, clock.val + fix_answer_ms)
  t.draw()
  t.run_for(emit_all_ms())
  assert_true(em.current is None)
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  assert_true(rd.running.length() > 0)
  assert_true(rd.answered.is_empty())
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  emit_restore()
}

///|
test "activity: an agent given words it has yet to take is at work: its line there as they wait for it" {
  // Queued (the station has the words, its agent not yet taken them; or a summary read before it took them says so):
  // its line went, and came back as it took them, each time words were sent (2026-11-09).
  new_run()
  @sffixture.fix_working_status.val = "queued"
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  fix_clock_set(clock, clock.val + fix_deliver_ms)
  t.draw()
  t.run_for(flight_wait_ms + @ui.move_most_ms + 1000.0)
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  fix_clock.val = None
}

///|
/// The working agent's chat on 小屏, its agent's `live` as the core client holds it (`live`: its version one more each
/// time it is another value), the rest the fixture's.
fn activity_live_chat(live : @signals.Signal[Json]) -> @ui.Tester {
  new_run()
  let base = fixture("chat-working")
  let version = Ref(0)
  let seen : Ref[Json?] = Ref(None)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "live" && text(Some(Json::object(params)), "key") == "s-c1" {
        let value = live.get()
        if !(seen.val is Some(v) && physical_equal(v, value)) {
          seen.val = Some(value)
          version.val += 1
        }
        return { value: Some(value), error: None, version: version.val }
      }
      base.topic(name, params).get().snapshot()
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// What the frame drawn after `come` built, made and laid out: why it was built ("" its looks alone), the tree's work.
fn activity_frame_after(t : @ui.Tester, come : () -> Unit) -> (String, @ui.TreeFrame, @ui.FramePerf) {
  t.tree_frames_from_now()
  come()
  t.frame()
  let f = t.tree_frames()
  let why = t.built_why()
  let perf = t.frame_perf()
  (why, f.get(0).unwrap_or({ made: 0, let_go: 0, laid: 0, measured: 0 }), perf)
}

///|
/// What its agent's stream changes beside the line (its rate where the line does not say it, a call's input growing, a
/// step ended before its entry comes, its work) the core sends a chat nothing of (`live` is its `activity` alone,
/// client/core-ts topic-bytes.test.ts: a working agent's stream): nothing is built in the frame after. Before, it was
/// sent the rest of the agent's state as it changed, and each such message built the chat's row of the line again as
/// one that changed the line did (a list's row read changed): shown here by such a value told, the line's words as
/// they were. What changes the line, the line.
test "activity: what its agent's stream changes beside the line builds nothing in the chat; what changes the line builds its row and says it" {
  fn now(key : String, words : String) -> Json {
    { "key": Json::string(key), "text": Json::string(words), "mono": true }
  }
  let live = @signals.signal(
    ({ "activity": { "now": now("call:1", @sffixture.working_step) } } : Json),
    same=fn(a, b) { physical_equal(a, b) },
  )
  let t = activity_live_chat(live)
  assert_true(t.find(@sffixture.working_step) is Some(_), msg="the line says its step")
  // a rate, a call's input growing, a step ended: nothing comes
  let none = activity_frame_after(t, fn() { () })
  assert_eq(none.0, "", msg="nothing built: \{Repr(none)}")
  assert_true(none.1 == { made: 0, let_go: 0, laid: 0, measured: 0 }, msg="nothing made: \{Repr(none)}")
  // as the core sent it before: the rest of the agent's state changed, the line's words as they were
  let before = activity_frame_after(t, fn() {
    live.set({
      "activity": { "now": now("call:1", @sffixture.working_step) },
      "rate": 52,
      "steps": [{ "id": "s-3", "step": "tool", "tool": "Bash", "input": "{\"command\":\"pnpm exec tsgo", "startedAt": 1 }],
    })
  })
  t.run_for(@ui.move_most_ms)
  let changed = activity_frame_after(t, fn() { live.set({ "activity": { "now": now("call:2", "整理下一步") } }) })
  t.run_for(@ui.move_most_ms * 4.0)
  println("nothing told: \{Repr(none)}\nthe rest of its state told, the line as it was (before): \{Repr(before)}\nthe line changed: \{Repr(changed)}")
  assert_true(before.0 != "", msg="before, the line's row was built again for what it does not show: \{Repr(before)}")
  assert_true(changed.0 != "", msg="the line's row built for its words: \{Repr(changed)}")
  assert_true(t.find("整理下一步") is Some(_), msg="the line says what it does now")
}
