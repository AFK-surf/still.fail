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
fn send_at_pace(deliver : Double, answer : Double, end : Double, sent? : Double = -1.0) -> SentMoves raise {
  new_run()
  fix_pace.val = (deliver, answer, end)
  fix_sent_for.val = sent
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("看一下列表")
  // (the field's top: what is drawn below it is the composer's, not the list's)
  let field = match t.find("看一下列表") {
    Some((_, y)) => y - 30.0
    None => 844.0
  }
  // (words drawn once only: another of the same, the agent's name on its line say, is not the one followed)
  let once = fn() {
    let n : Map[String, Int] = {}
    for w in t.words_said() {
      n[w.0] = n.get(w.0).unwrap_or(0) + 1
    }
    n
  }
  let before : Map[String, Double] = {}
  let counts = once()
  for w in t.words_said() {
    if w.2 + w.4 < field && w.2 > 0.0 && counts.get(w.0) == Some(1) {
      before[w.0] = w.2
    }
  }
  tap_send(t)
  let last : Map[String, Double] = {}
  let way : Map[String, Double] = {}
  let turns : Map[String, Int] = {}
  let down : Map[String, Double] = {}
  let end_at = t.time() + deliver + (if sent > 0.0 { sent } else { 0.0 }) + answer + (if end > 0.0 { end } else { 0.0 }) + 3000.0
  while t.time() < end_at {
    t.frame()
    let seen : Map[String, Double] = {}
    let counts = once()
    for w in t.words_said() {
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
