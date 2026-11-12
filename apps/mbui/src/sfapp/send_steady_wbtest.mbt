// Words sent while the list is at its end: what was there goes one way, up, as the words, the agent's line and its
// answer come in, whatever the pace of the station (fix_pace): never down and back (2026-11-09 the user, 「现在发个消息
// 都抖了」「偶现」「想办法写出必现的测试」).

///|
/// Where each of the words on screen was drawn, top to bottom, frame by frame, from the moment send was pressed, of
/// those there before it (what moves only as the list does): how often each went back the way it came, and how far
/// it went down in all.
priv struct SentMoves {
  turns : Int
  down : Double
  worst : String
}

///|
/// `core`: how long the core has them before its view has their row (fix_core_for). `after`: words sent that long
/// before them, nothing between the two (the agent's answer further off than is watched): 0 or more.
fn send_at_pace(
  deliver : Double,
  answer : Double,
  end : Double,
  sent? : Double = -1.0,
  core? : Double = 0.0,
  after? : Double = -1.0,
) -> SentMoves {
  new_run()
  fix_pace.val = (deliver, answer, end)
  fix_sent_for.val = sent
  fix_core_for.val = core
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  if after >= 0.0 {
    t.type_text("再看一下")
    tap_send(t)
    let till = t.time() + after
    while t.time() < till {
      t.frame()
    }
  }
  t.type_text("看一下列表")
  // (the field's top: what is drawn below it is the composer's, not the list's)
  let field = match t.find("看一下列表") {
    Some((_, y)) => y - 30.0
    None => 844.0
  }
  // (words drawn once only: another of the same, the agent's name on its line say, is not the one followed)
  let once = fn(said : Array[(String, Double, Double, Double, Double, Double)]) {
    let n : Map[String, Int] = Map([])
    for w in said {
      n[w.0] = n.get(w.0).unwrap_or(0) + 1
    }
    n
  }
  let before : Map[String, Double] = Map([])
  let said = t.words_said()
  let counts = once(said)
  // (not what is said under the viewer's own last message, its time or that it is on its way: under the new one once
  // that follows it, the core's `followed`)
  let under = if after >= 0.0 { ["刚刚", @sf.t("web-main.chat.sending")] } else { [] }
  for w in said {
    if w.2 + w.4 < field && w.2 > 0.0 && counts.get(w.0) == Some(1) && !under.contains(w.0) {
      before[w.0] = w.2
    }
  }
  tap_send(t)
  let last : Map[String, Double] = Map([])
  let way : Map[String, Double] = Map([])
  let turns : Map[String, Int] = Map([])
  let down : Map[String, Double] = Map([])
  // (sent after others, their answer is not waited for: till the core, then the station, has them, and they are in)
  let end_at = t.time() +
    core +
    deliver +
    (if sent > 0.0 { sent } else { 0.0 }) +
    (if after >= 0.0 { 0.0 } else { answer + (if end > 0.0 { end } else { 0.0 }) }) +
    3000.0
  while t.time() < end_at {
    t.frame()
    let seen : Map[String, Double] = Map([])
    // (the frame's words read once, not twice: a tenth or so of this file's time, run at each of CI's rates)
    let said = t.words_said()
    let counts = once(said)
    for w in said {
      if before.contains(w.0) && counts.get(w.0) == Some(1) {
        seen[w.0] = w.2
      }
    }
    for k, y in seen {
      let from = last.get(k).unwrap_or(before[k])
      let d = y - from
      if d.abs() < 0.5 {
        continue
      }
      let was = way.get(k).unwrap_or(0.0)
      if was != 0.0 && d * was < 0.0 {
        turns[k] = turns.get(k).unwrap_or(0) + 1
      }
      if d > 0.0 {
        down[k] = down.get(k).unwrap_or(0.0) + d
      }
      way[k] = d
      last[k] = y
    }
  }
  let mut most = 0
  let mut deepest = 0.0
  let mut worst = ""
  for k, n in turns {
    if n > most {
      most = n
      worst = k
    }
  }
  for k, d in down {
    if d > deepest {
      deepest = d
      if worst == "" {
        worst = k
      }
    }
  }
  { turns: most, down: deepest, worst }
}

///|
test "words sent at any pace of the station: the list goes up only, never down and back" {
  // (judged frame to frame on frame()'s, the display's own: the default run's alone, @ui.test_at_a_rate)
  if @ui.test_at_a_rate() {
    return
  }
  // (paces each of which took it down and back before: the turn told over before its answer came (end < 0), the answer
  // come too soon to come out of an avatar (answer 100, 400; end after it), in rows_steady and on the screen)
  let bad : Array[String] = []
  for deliver in [0.0, 700.0] {
    for answer in [0.0, 100.0, 400.0, 1400.0] {
      for end in [-300.0, -100.0, 0.0, 100.0, 300.0, 900.0] {
        let at = "deliver \{deliver} answer \{answer} end \{end}"
        let s = send_at_pace(deliver, answer, end)
        if s.turns > 0 || s.down >= 1.0 {
          bad.push(at + ": \{s.turns} turns, down \{s.down} (\{s.worst})")
        }
      }
    }
  }
  for b in bad {
    println("SENDSTEADY " + b)
  }
  assert_eq(bad.length(), 0)
}

///|
test "words sent, the station slow to take them or the chat to reach them: the list goes up only, never down and back" {
  // (judged frame to frame on frame()'s, the display's own: the default run's alone, @ui.test_at_a_rate)
  if @ui.test_at_a_rate() {
    return
  }
  // (正在发送 shows once they have been on their way a while (sending_shows_ms); taken, the outbox row is `sent`, its
  // time under it, till the chat's entries reach its message: 2026-11-09 the user, 「发消息会跳动」「跟发送中的状态有关」)
  let bad : Array[String] = []
  for deliver in [0.0, 300.0, 790.0, 810.0, 1500.0] {
    for sent in [-1.0, 0.0, 100.0, 600.0, 1200.0] {
      for answer in [0.0, 1400.0] {
        let at = "deliver \{deliver} sent \{sent} answer \{answer}"
        let s = send_at_pace(deliver, answer, fix_turn_end_ms, sent~)
        if s.turns > 0 || s.down >= 1.0 {
          bad.push(at + ": \{s.turns} turns, down \{s.down} (\{s.worst})")
        }
      }
    }
  }
  for b in bad {
    println("SENDSLOW " + b)
  }
  assert_eq(bad.length(), 0)
}

///|
test "words sent soon after words sent, the core's row of them late or not: the list goes up only, never down and back" {
  // (judged frame to frame on frame()'s, the display's own: the default run's alone, @ui.test_at_a_rate)
  if @ui.test_at_a_rate() {
    return
  }
  // (the viewer's own one after another go close together, the time under the last alone: the core says so of its row,
  // which comes a round trip after they are sent, long after on a busy device; laid out as standing apart till then,
  // the list went up 80 and came back 35 (the row 400 ms late), or 67 in one frame and back 22 (the station taking
  // them at once): 2026-11-10 the user, 「现在偶现发消息动效都会抖」)
  let bad : Array[String] = []
  for after in [1000.0, 3000.0] {
    for deliver in [0.0, 100.0, 700.0] {
      for core in [0.0, 100.0, 400.0, 800.0] {
        // (the station's message there in the call that sends them, before a frame has what was sent from here: the
        // made-up core's alone, a device's comes between frames at the soonest)
        if deliver == 0.0 && core == 0.0 {
          continue
        }
        let at = "after \{after} deliver \{deliver} core \{core}"
        let s = send_at_pace(deliver, 30000.0, fix_turn_end_ms, core~, after~)
        if s.turns > 0 || s.down >= 1.0 {
          bad.push(at + ": \{s.turns} turns, down \{s.down} (\{s.worst})")
        }
      }
    }
  }
  for b in bad {
    println("SENDAFTER " + b)
  }
  assert_eq(bad.length(), 0)
}

///|
test "words sent, the core's row of them late: the list goes up only, never down and back" {
  // (judged frame to frame on frame()'s, the display's own: the default run's alone, @ui.test_at_a_rate)
  if @ui.test_at_a_rate() {
    return
  }
  let bad : Array[String] = []
  for core in [100.0, 400.0, 800.0] {
    for deliver in [0.0, 300.0, 700.0] {
      for answer in [0.0, 400.0, 1400.0] {
        let at = "core \{core} deliver \{deliver} answer \{answer}"
        let s = send_at_pace(deliver, answer, fix_turn_end_ms, core~)
        if s.turns > 0 || s.down >= 1.0 {
          bad.push(at + ": \{s.turns} turns, down \{s.down} (\{s.worst})")
        }
      }
    }
  }
  for b in bad {
    println("SENDLATE " + b)
  }
  assert_eq(bad.length(), 0)
}

///|
/// Words sent `soon` after the words sent before them were out of the field (flight_out; before it with `soon` under
/// 0: that long after they were sent), those still on their way to their row: the furthest the words sent first went
/// in one frame past twice what they went the frame before and the frame after (what goes on a way goes on at about
/// its pace; what is put somewhere at once goes far in one frame between two it hardly moved in), from the frame the
/// next were sent, and when.
fn sent_soon_step(soon : Double, deliver : Double) -> (Double, Double) raise {
  new_run()
  fix_pace.val = (deliver, 30000.0, fix_turn_end_ms)
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("再看一下")
  tap_send(t)
  let sent = t.time()
  if soon >= 0.0 {
    while send_flight.get().map(fn(f) { !@sfbase.flight_out(t.ctx(), f) }).unwrap_or(false) {
      t.frame()
    }
    assert_true(send_flight.get() is Some(_), msg="the words sent first landed before they were out of the field")
  }
  let till = if soon >= 0.0 { t.time() + soon } else { sent - soon }
  while t.time() < till {
    t.frame()
  }
  t.type_text("看一下列表")
  let at = fn() { t.drawn_of("再看一下").map(fn(p) { p.1 }).unwrap_or(-1.0) }
  let ys : Array[Double] = [at()]
  let ts : Array[Double] = [t.time()]
  t.frame()
  ys.push(at())
  ts.push(t.time())
  tap_send(t)
  ys.push(at())
  ts.push(t.time())
  let end_at = t.time() + @sfbase.flight_most_ms + @ui.move_most_ms
  while t.time() < end_at {
    t.frame()
    ys.push(at())
    ts.push(t.time())
  }
  let mut worst = 0.0
  let mut when = -1.0
  for i in 2..<(ys.length() - 1) {
    let d = (ys[i] - ys[i - 1]).abs()
    let by = dmax((ys[i - 1] - ys[i - 2]).abs(), (ys[i + 1] - ys[i]).abs())
    if d - 2.0 * by > worst {
      worst = d - 2.0 * by
      when = ts[i] - sent
    }
  }
  (worst, when)
}

///|
test "words sent while the words sent before them still fly: those go on to their row, put nowhere at once" {
  // (judged frame to frame on frame()'s, the display's own: the default run's alone, @ui.test_at_a_rate)
  if @ui.test_at_a_rate() {
    return
  }
  // (one flight at a time, the next words sent dropped the one before: its words stood in their row in that frame,
  // 26 points from where they were with the next sent 300 ms after them; and their row, no flight's any more, was
  // put in the middle of its room as it opened, what it holds 14 down in a frame with 500. Found looking into
  // 2026-11-10 the user, 「现在偶现发消息动效都会抖」)
  let bad : Array[String] = []
  for soon in [0.0, 50.0, 100.0, 200.0, 400.0] {
    for deliver in [100.0, 700.0] {
      let (step, when) = sent_soon_step(soon, deliver) catch {
        e => {
          let said = e.to_string()
          let cut = if said.length() > 900 { said.clamped_view(end=900).to_owned() } else { said }
          bad.push("soon \{soon} deliver \{deliver}: " + cut.replace_all(old="\n", new=" "))
          continue
        }
      }
      if step > 6.0 {
        bad.push("soon \{soon} deliver \{deliver}: the words sent first went \{step} past their pace in a frame, \{when} ms after they were sent")
      }
    }
  }
  for b in bad {
    println("SENDSOON " + b)
  }
  assert_eq(bad.length(), 0)
}

///|
test "words sent before the words sent before them are out of the field: never drawn over those" {
  if @ui.test_at_a_rate() {
    return
  }
  // (still where they were typed, they would lie under the words now sent, drawn there as typed till their row is
  // laid out (words_over.mbt): in their row at once, the frame those are sent)
  let bad : Array[String] = []
  for soon in [-17.0, -50.0, -100.0, -150.0] {
    let _ = sent_soon_step(soon, 100.0) catch {
      e => {
        let said = e.to_string()
        let cut = if said.length() > 900 { said.clamped_view(end=900).to_owned() } else { said }
        bad.push("\{-soon} ms after: " + cut.replace_all(old="\n", new=" "))
        continue
      }
    }
  }
  for b in bad {
    println("SENDUNDER " + b)
  }
  assert_eq(bad.length(), 0)
}

///|
test "words sent under a waiting card, the core yet to have them: the chat's rows given its list the same each frame" {
  // (2026-11-10: said answered from the frame they are sent (sent_here_view), the view and its entries were made anew
  // each time they were read: other rows to the list every frame of the words' flight, all of them built again, as
  // long as the core took to have them, many frames on a phone)
  new_run()
  fix_core_for.val = 400.0
  // (the made-up chat's card waits, 等 林 决定, its agent's posts after it: what is sent answers it)
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("看一下列表")
  let (_, core, _) = view_of_chat(src, r)
  tap_send(t)
  t.frame()
  let (was_view, was, _) = view_of_chat(src, r)
  // (answered from here, the core yet to say so: not the entries the core gave, which are as they were)
  assert_true(!physical_equal(core, was), msg="said answered from here")
  // (the frames of a tenth of a second on, the core still without them: fix_core_for)
  let till = t.time() + 100.0
  while t.time() < till {
    t.frame()
    let (now_view, now, _) = view_of_chat(src, r)
    assert_true(physical_equal(was_view.unwrap(), now_view.unwrap()), msg="the same view")
    assert_true(physical_equal(was, now), msg="the same entries")
  }
}

///|
test "words sent: the chat's rows they fly past are kept, not built again each frame of their flight" {
  // (2026-11-10: where they are on their way was read as their row was built (flight_p, the send button's ease_to),
  // every row of the chat's list built again each frame of the flight, 14-17M instructions a frame on a phone, the
  // instrbench's `send`; read where it is laid out or painted, their own row alone is. Tester::built_why names neither:
  // the list's own clock read as it is laid out is the frame's first cause either way. Judged on frame()'s, the
  // display's own: the default run's alone, @ui.test_at_a_rate)
  if @ui.test_at_a_rate() {
    return
  }
  new_run()
  let src = fixture("chat-done-live")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  // (words the core's answers are kept for, src/sfkept: as the tests above type)
  t.type_text("看一下列表")
  t.run_for(@ui.move_most_ms)
  tap_send(t)
  ignore(t.rows_built())
  // (each frame on their way: how many of the list's rows it built, not kept)
  let built : Array[Int] = []
  let end_at = t.time() + @sfbase.flight_most_ms
  while t.time() < end_at {
    t.frame()
    let rows = t.rows_built().filter(fn(r) { r.1 >= 0 }).length()
    match send_flight.get() {
      Some(f) if f.placed => built.push(rows)
      _ => ()
    }
  }
  assert_true(built.length() >= 20, msg="frames of their flight: \{built.length()}")
  // (their own row, where its pieces are drawn, and no other; all of them again only in the frames a share of their
  // way is reached: their row opening, the composer let go and down, shows_from)
  let own = built.filter(fn(n) { n <= 1 }).length()
  assert_true(own * 4 >= built.length() * 3, msg="rows built each frame of their flight: \{Repr(built)}")
}

///|
test "words sent in a chat whose turn is over: 已完成 closing as they come and 处理中 opening after them, every row drawn goes up only" {
  // (judged frame to frame on frame()'s, the display's own: the default run's alone, @ui.test_at_a_rate)
  if @ui.test_at_a_rate() {
    return
  }
  // (as a device has it: the core has them a frame after the press, the station takes them and sets its agent to work
  // 350 ms after; 已完成 shows only while nothing is on its way and the agent idles, chat-done-live. A freshly recorded
  // core trace of the same, bar_going_down's, had 已完成's row, closing under half open and nothing of it drawn, said by
  // rows_steady as come back as 处理中 opened, every row seen going up only (rows_steady_return holds what is drawn: the
  // coordinator of the migration, 2026-11-11). Here its card still waiting, the words answer it from the frame they are
  // sent (sent_here_view), 已完成 going in that frame, over their row: it only goes up, nothing comes back)
  new_run()
  fix_pace.val = (350.0, 30000.0, fix_turn_end_ms)
  fix_core_for.val = 17.0
  let src = fixture("chat-done-live")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  // (words the core's answers are kept for, src/sfkept)
  t.type_text("看一下列表")
  // (the field's top: what is drawn below it is the composer's, not the list's)
  let field = match t.find("看一下列表") {
    Some((_, y)) => y - 30.0
    None => 844.0
  }
  let working = @sf.t("android-chat.chat.working")
  tap_send(t)
  let sent = t.time()
  // (where each of the words drawn, once on the screen, was the frame before, and how far down any went in a frame;
  // till 处理中's row is open: it comes as the station takes them, its room on the list's way from then)
  let last : Map[String, Double] = Map([])
  let bad : Array[String] = []
  let mut came = false
  while t.time() < sent + 350.0 + 2.0 * @ui.move_most_ms {
    t.frame()
    let said = t.words_said()
    let n : Map[String, Int] = Map([])
    for w in said {
      n[w.0] = n.get(w.0).unwrap_or(0) + 1
    }
    let seen : Map[String, Double] = Map([])
    for w in said {
      if n.get(w.0) == Some(1) && w.5 > 0.0 && w.2 + w.4 < field && w.2 + w.4 > 0.0 {
        seen[w.0] = w.2
      }
      if w.0 == working && w.5 > 0.0 {
        came = true
      }
    }
    for k, y in seen {
      match last.get(k) {
        Some(was) if y - was >= 0.5 => bad.push("\{k} down \{y - was} at \{t.time() - sent}")
        _ => ()
      }
    }
    last.clear()
    for k, y in seen {
      last[k] = y
    }
  }
  assert_true(came, msg="处理中 not drawn")
  assert_eq(bad, [])
}
