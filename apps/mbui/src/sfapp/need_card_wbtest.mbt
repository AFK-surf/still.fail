// What a chat needs of the viewer, as a card under its last message (sfpages' chat_rows.mbt chat_state, need_card):
// the bell and its words, 忽略 at its end. Let go, the core says so (已忽略：…): the card goes as its room closes, what is
// over it coming down with it a step each frame, then the line saying how it went fades in where it was; the two never
// seen at once, and 忽略 gone with the card.

///|
/// The chat with its agent's need (with_need), asked of the viewer while `asking`, else let go as the core says it.
fn need_chat(calls : Array[Made], asking : @signals.Signal[Bool]) -> @ui.Tester {
  fake_core(calls, over=fn(name, tp) {
    guard name == "chat" && tp.value is Some(v) else { return tp }
    let need = @sffixture.with_need(v)
    if asking.get() {
      return { ..tp, value: Some(need) }
    }
    let gone = match need {
      Object(m) => {
        let o = m.copy()
        o.remove("stateAsk") |> ignore
        Json::object(o)
      }
      _ => need
    }
    let said = "已忽略：" + @sffixture.need_state.2
    { ..tp, value: Some(@sffixture.with_state(gone, (said, "dismissed", @sffixture.need_state.2))), version: tp.version + 1 }
  })
}

///|
test "a need let go: its card goes as its room closes, what is over it coming down a step each frame, then 已忽略：… fades in where it was" {
  let asking = @signals.signal(true)
  let calls : Array[Made] = []
  let t = need_chat(calls, asking)
  t.run_for(@ui.move_most_ms)
  let need = @sffixture.need_state.2
  let said = "已忽略：" + need
  let above = "你在手机上试一下新的列表，有问题截个图给我。"
  guard t.rect_of(need) is Some((_, need_y, _, _)) else { fail("no need: \{Repr(t.words().map(fn(w) { w.0 }))}") }
  // (its 忽略 the last on the page: the card at the list's end)
  let (dx, dy) = t.find_last("忽略").unwrap()
  assert_true((dy - need_y).abs() < 20.0, msg="\{dy} \{need_y}")
  t.tap(dx, dy)
  t.draw()
  assert_eq(named(calls, "decision.dismiss").length(), 1)
  t.run_for(@ui.move_most_ms)
  let (_, was) = t.find(above).unwrap()
  // the core says it let go
  asking.set(false)
  t.draw()
  let seen = fn() { t.words().filter(fn(w) { w.5 > 0.0 }).map(fn(w) { w.0 }) }
  let mut last = was
  for _ in 0..<40 {
    t.run_for(@ui.frame_period_default)
    let (_, y) = t.find(above).unwrap()
    assert_true(y >= last - 0.01 && y - last < 4.0, msg="at \{t.time()}: \{last} to \{y}")
    last = y
    let now = seen()
    assert_true(!(now.contains(need) && now.contains(said)), msg="both at \{t.time()}")
  }
  assert_true(last > was + 1.0, msg="\{was} \{last}")
  // how it went, whole, where the card was; its 忽略 gone with it (the options card's further up stays)
  assert_true(seen().contains(said), msg="\{Repr(seen())}")
  assert_true(!seen().contains(need))
  assert_true(t.words().iter().all(fn(w) { w.0 != "忽略" || w.5 == 0.0 || w.2 < last }), msg="\{Repr(t.words())}")
}
