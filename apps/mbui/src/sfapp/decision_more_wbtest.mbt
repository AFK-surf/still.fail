// What is under a post that asks (sfpages' decision.mbt message_decision, decision_options): a post that asks with no
// card (忽略 alone under it), an option on its way (none pressed again meanwhile), who a login card waits on.

///|
test "a post that asks with no card or options has 忽略 alone under it; pressed, the core lets it go (decision.dismiss by its seq)" {
  let calls : Array[Made] = []
  let last = "做完了：列表、跳到最新的按钮、加载更早的消息都好了，截图也换了。"
  let t = changed_chat(calls, fn(w) {
    if text(Some(Json::object(w)), "text") == last {
      w["asked"] = Json::boolean(true)
    }
  })
  t.run_for(@ui.move_most_ms)
  let (_, ly) = t.find(last).unwrap()
  // (its 忽略: the one under it, not the options card's further up)
  let under = t.words().filter(fn(w) { w.0 == "忽略" && w.2 > ly && w.5 > 0.0 })
  assert_eq(under.length(), 1, msg="\{Repr(t.words().map(fn(w) { (w.0, w.2) }))}")
  let (_, x, y, w, h, _) = under[0]
  t.tap(x + w / 2.0, y + h / 2.0)
  t.draw()
  let made = named(calls, "decision.dismiss")
  assert_eq(made.length(), 1)
  assert_eq(number(Some(made[0].params), "seq"), 11.0)
}

///|
test "an option on its way (the core's doing: decision.answer): no option pressed again meanwhile" {
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    guard name == "doing" else { return tp }
    {
      ..tp,
      value: Some({
        "doing": [
          {
            "call": "decision.answer",
            "stage": "sent",
            "params": { "station": "ws1/st1", "thread": "7", "seq": "8", "option": "一起换" },
          },
        ],
      }),
    }
  })
  t.run_for(@ui.move_most_ms)
  t.tap_text("先不换")
  t.draw()
  t.tap_text("一起换")
  t.draw()
  assert_eq(named(calls, "decision.answer").length(), 0)
}

///|
test "a login card says whom it waits on over it while it is asked" {
  let calls : Array[Made] = []
  let t = changed_chat(calls, fn(w) {
    match w.get("card") {
      Some(Object(card)) if text(Some(Json::object(card)), "type") == "login" => {
        let o = card.copy()
        o["assigneeText"] = Json::string("等 林 登录")
        w["card"] = Json::object(o)
      }
      _ => ()
    }
  })
  t.run_for(@ui.move_most_ms)
  guard t.find("等 林 登录") is Some((_, ay)) else { fail("\{Repr(t.words().map(fn(w) { w.0 }))}") }
  let (_, cy) = t.find("在 Willow 上登录 gh").unwrap()
  assert_true(ay < cy, msg="\{ay} \{cy}")
}
