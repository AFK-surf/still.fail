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
) -> SentMoves raise {
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
    let n : Map[String, Int] = {}
    for w in said {
      n[w.0] = n.get(w.0).unwrap_or(0) + 1
    }
    n
  }
  let before : Map[String, Double] = {}
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
  let last : Map[String, Double] = {}
  let way : Map[String, Double] = {}
  let turns : Map[String, Int] = {}
  let down : Map[String, Double] = {}
  // (sent after others, their answer is not waited for: till the core, then the station, has them, and they are in)
  let end_at = t.time() +
    core +
    deliver +
    (if sent > 0.0 { sent } else { 0.0 }) +
    (if after >= 0.0 { 0.0 } else { answer + (if end > 0.0 { end } else { 0.0 }) }) +
    3000.0
  while t.time() < end_at {
    t.frame()
    let seen : Map[String, Double] = {}
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
        let s = send_at_pace(deliver, answer, end) catch {
          e => {
            let said = e.to_string()
            let cut = if said.length() > 900 { said.view(end_offset=900).to_string() } else { said }
            bad.push(at + ": " + cut.replace_all(old="\n", new=" "))
            continue
          }
        }
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
        let s = send_at_pace(deliver, answer, fix_turn_end_ms, sent~) catch {
          e => {
            let said = e.to_string()
            let cut = if said.length() > 900 { said.view(end_offset=900).to_string() } else { said }
            bad.push(at + ": " + cut.replace_all(old="\n", new=" "))
            continue
          }
        }
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
        let s = send_at_pace(deliver, 30000.0, fix_turn_end_ms, core~, after~) catch {
          e => {
            let said = e.to_string()
            let cut = if said.length() > 900 { said.view(end_offset=900).to_string() } else { said }
            bad.push(at + ": " + cut.replace_all(old="\n", new=" "))
            continue
          }
        }
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
        let s = send_at_pace(deliver, answer, fix_turn_end_ms, core~) catch {
          e => {
            let said = e.to_string()
            let cut = if said.length() > 900 { said.view(end_offset=900).to_string() } else { said }
            bad.push(at + ": " + cut.replace_all(old="\n", new=" "))
            continue
          }
        }
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
          let cut = if said.length() > 900 { said.view(end_offset=900).to_string() } else { said }
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
        let cut = if said.length() > 900 { said.view(end_offset=900).to_string() } else { said }
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
/// Words sent with the list at its end (the station's paces as fix_pace, the core's row of them `core` late): frame by
/// frame from the press till they have long landed, how far their words are under the words of the row over them
/// (the last words over the field before the press that are still there at the end, as the list has them): how far
/// that room ever opened again on the way, all told.
fn sent_gap_opened(deliver : Double, answer : Double, core : Double) -> Double raise {
  new_run()
  fix_pace.val = (deliver, answer, fix_turn_end_ms)
  fix_core_for.val = core
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  let words = "看一下列表"
  t.type_text(words)
  let field = match t.find(words) {
    Some((_, y)) => y - 30.0
    None => 844.0
  }
  let before = t.words_said().filter(fn(w) { w.2 > 0.0 && w.2 + w.4 < field && w.0 != words })
  tap_send(t)
  let frames : Array[Array[(String, Double, Double, Double, Double, Double)]] = []
  let end_at = t.time() + core + deliver + @sfbase.flight_most_ms + @ui.move_most_ms
  while t.time() < end_at {
    t.frame()
    frames.push(t.words_said())
  }
  let at_end = frames.last().unwrap_or([])
  // (the row over them: of what was there before that is there still, drawn once, the lowest over where they end)
  let landed = match at_end.filter(fn(x) { x.0 == words }) {
    [w] => w.2
    _ => 0.0
  }
  let mut over = ""
  let mut low = -1.0
  for w in at_end {
    let n = at_end.filter(fn(x) { x.0 == w.0 }).length()
    if n == 1 &&
      before.filter(fn(x) { x.0 == w.0 }).length() == 1 &&
      w.2 + w.4 <= landed &&
      w.2 + w.4 > low {
      low = w.2 + w.4
      over = w.0
    }
  }
  assert_true(over != "", msg="no row over the words sent")
  let mut last = @double.infinity
  let mut opened = 0.0
  for said in frames {
    // (as drawn: not what is there unseen, the message's own words while their pieces fly)
    let mine = said.filter(fn(x) { x.0 == words && x.5 > 0.01 })
    let above = said.filter(fn(x) { x.0 == over && x.5 > 0.01 })
    if mine.length() != 1 || above.length() != 1 {
      continue
    }
    let gap = mine[0].2 - (above[0].2 + above[0].4)
    if gap > last {
      opened = opened + (gap - last)
    }
    last = gap
  }
  opened
}

///|
test "words sent: the room between them and the row over them only closes on their way" {
  // (judged frame to frame on frame()'s, the display's own: the default run's alone, @ui.test_at_a_rate)
  if @ui.test_at_a_rate() {
    return
  }
  // (the rows over them went up at once on their own way as the words rose late on theirs: the room between opened
  // 22 and closed again, every time anything was sent; 2026-11-10 the user, 「新消息距离上一条 agent 消息的距离能突变
  // 三次」「我一天碰到几百次」)
  let bad : Array[String] = []
  for deliver in [0.0, 300.0, 700.0] {
    for answer in [0.0, 1400.0] {
      for core in [0.0, 400.0] {
        let opened = sent_gap_opened(deliver, answer, core)
        if opened >= 1.0 {
          bad.push("deliver \{deliver} answer \{answer} core \{core}: opened \{opened}")
        }
      }
    }
  }
  for b in bad {
    println("SENTGAP " + b)
  }
  assert_eq(bad.length(), 0)
}
