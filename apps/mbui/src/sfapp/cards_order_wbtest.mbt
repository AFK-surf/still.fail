// What is sent after a card was answered stays after the answer, as a chat's time order has it: the made-up station
// put the answer's rows after every message, also those sent later, so words sent once its turn was over came to stand
// over the answer as the station took them, their row up 141 pt and the answer's down 80 pt in one frame.

///|
test "words sent after a card's answer stay under it: from the press to rest no word drawn steps in a frame" {
  // (judged frame to frame on frame()'s, the display's own: the default run's alone, @ui.test_at_a_rate)
  if @ui.test_at_a_rate() {
    return
  }
  new_run()
  let src = fixture("chat-done-live")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  // (what this test holds is said below, a bound on every word drawn; the motion judges are other files')
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, words_over_held=false)
  t.run_for(@ui.move_most_ms)
  // the card answered, its agent's answer come and its turn over
  t.tap_text("把首页和聊天页的截图都更新")
  t.run_for(@sffixture.fix_answer_ms + @sffixture.fix_turn_end_ms + @ui.move_most_ms)
  let answer = "好，按「一起换」来。"
  guard t.find(answer) is Some(_) else { @halt.saying("no answer to the card: \{Repr(t.words().map(fn(w) { w.0 }))}") }
  t.tap_text("发消息")
  // (words the core's answers are kept for, src/sfkept)
  t.type_text("看一下列表")
  // (the field's top: what is drawn below it is the composer's, not the list's)
  let field = match t.find("看一下列表") {
    Some((_, y)) => y - 30.0
    None => 844.0
  }
  tap_send(t)
  let sent = t.time()
  let (deliver, answer_in, end_in) = @sffixture.fix_pace.val
  // (till their answer has come and the turn is over, and what that sets off is at rest)
  let rest = sent + deliver + answer_in + end_in + 2.0 * @ui.move_most_ms
  let last : Map[String, Double] = Map([])
  let mut worst = 0.0
  let mut worst_at = ""
  while t.time() < rest {
    t.frame()
    let said = t.words_said()
    let n : Map[String, Int] = Map([])
    for w in said {
      n[w.0] = n.get(w.0).unwrap_or(0) + 1
    }
    let seen : Map[String, Double] = Map([])
    for w in said {
      if n.get(w.0) == Some(1) && w.5 > 0.0 && w.2 < field && w.2 + w.4 > 0.0 {
        seen[w.0] = w.2
      }
    }
    for k, y in seen {
      match last.get(k) {
        Some(was) if (y - was).abs() > worst => {
          worst = (y - was).abs()
          worst_at = "\{k} \{was} to \{y} at \{t.time() - sent}"
        }
        _ => ()
      }
    }
    last.clear()
    for k, y in seen {
      last[k] = y
    }
  }
  // (a frame's step of the list's own way is a few points: one row's whole height is 40 and more)
  assert_true(worst < 40.0, msg="a word drawn went \{worst} in one frame: \{worst_at}")
  // the words sent stand under the card's answer
  let at = fn(words : String) {
    let mut y = -1.0
    for w in t.words_said() {
      if w.0 == words && w.5 > 0.0 && w.2 < field {
        y = w.2
      }
    }
    y
  }
  assert_true(at(answer) >= 0.0 && at("看一下列表") > at(answer), msg="answer at \{at(answer)}, the words sent at \{at("看一下列表")}")
}
