// A quote into a long message brings its passage back into view as before.

///|
test "a quote to a passage low in a long message brings the passage to the middle" {
  let calls : Array[Made] = []
  let passage = "有问题随时说。"
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
  let target = t.run_rects(passage)
  assert_false(target.is_empty(), msg="the quoted passage is visible after the jump")
  let (_, y, _, h) = target[0]
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  assert_true(y + h / 2.0 > 300.0 && y + h / 2.0 < 540.0,
    msg="the quoted passage should be near the middle of the 844-point list, at \{target}; pending \{rd.flash_centre}, flash \{rd.flash}")
}
