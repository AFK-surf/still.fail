// A quote into a long message brings its passage back into view as before.

///|
fn quote_centre_tester(passage : String) -> @ui.Tester raise {
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" {
      return tp
    }
    match tp.value {
      Some(Object(m)) =>
        match m.get("messages") {
          Some(Array(messages)) => {
            let o = m.copy()
            o["messages"] = Json::array(messages.map(fn(message) {
              match message {
                Object(fields) if number(Some(message), "seq") == 6.0 => {
                  let changed = fields.copy()
                  changed["quotes"] = [
                    { "author": "Claude", "text": Json::string(passage), "comment": "", "ts": "ts3" },
                  ]
                  Json::object(changed)
                }
                _ => message
              }
            }))
            { ..tp, value: Some(Json::object(o)) }
          }
          _ => tp
        }
      _ => tp
    }
  })
  t.move(195.0, 400.0)
  t.wheel(195.0, 400.0, -500.0)
  let quote = t.words().filter(fn(w) { w.0.has_prefix("Claude") && w.0.contains(passage) })
  assert_false(quote.is_empty(), msg="the quote's card is visible")
  let (_, qx, qy, qw, qh, _) = quote[0]
  t.tap(qx + qw / 2.0, qy + qh / 2.0)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a quote to a passage low in a long message brings the passage to the middle" {
  let passage = "有问题随时说。"
  let t = quote_centre_tester(passage)
  let target = t.run_rects(passage)
  assert_false(target.is_empty(), msg="the quoted passage is visible after the jump")
  let (_, y, _, h) = target[0]
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  assert_true(y + h / 2.0 > 300.0 && y + h / 2.0 < 540.0,
    msg="the quoted passage should be near the middle of the 844-point list, at \{target}; pending \{rd.flash_centre}, flash \{rd.flash}")
}

///|
test "a quote to a passage already high leaves the message at the top" {
  let t = quote_centre_tester("先说结论")
  let target = t.run_rects("先说结论")
  assert_false(target.is_empty())
  assert_true(target[0].1 < 200.0, msg="the passage was already high: \{target}")
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  assert_false(rd.flash_centre, msg="the passage has been considered once")
}

///|
test "a quote missing from a laid out message leaves it at the top" {
  let t = quote_centre_tester("从未说过的内容")
  let target = t.run_rects("先说结论")
  assert_false(target.is_empty())
  assert_true(target[0].1 < 200.0, msg="the message stays at the top: \{target}")
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  assert_false(rd.flash_centre, msg="the absent passage has been considered once")
}

///|
test "a quote that runs from one paragraph into the next is brought to the middle" {
  let t = quote_centre_tester("了。 有问题随时说。")
  let target = t.run_rects("有问题随时说。")
  assert_false(target.is_empty())
  assert_true(target[0].1 > 300.0 && target[0].1 < 540.0, msg="the last line of the passage: \{target}")
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  assert_false(rd.flash_centre)
}
