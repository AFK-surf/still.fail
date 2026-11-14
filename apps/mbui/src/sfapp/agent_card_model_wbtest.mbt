// An agent's card on a phone (sheets.mbt agent_body): what it runs on under its own name, apart from who runs it.

///|
/// A phone with fixture `chat-agent`'s card of its agent open over the chat.
fn phone_agent_card() -> @ui.Tester {
  new_run()
  let src = fixture("chat-agent")
  open_fixture_over("chat-agent", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  sheet_rested(t, "sf-present")
  t
}

///|
test "a phone's agent card: 模型 says its model and how hard it thinks, over 账号; pressed, the model's panel, no accounts over it" {
  // (2026-11-10: the only way to the model's panel was the row named 账号, and how hard it thinks was said nowhere
  // short of the panel)
  let t = phone_agent_card()
  let model = t.get(Button, label="模型 Opus 5.5 · 高").rect
  let account = t.get(Button, label="账号 林的 Max · 自动 5H 62% W 18%").rect
  assert_true(model.1 + model.3 <= account.1, msg="\{Repr(model)} \{Repr(account)}")
  t.click(Button, label="模型 Opus 5.5 · 高")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Slider, label="思考深度") is Some(_) && t.query(Button, label="Opus 5.5") is Some(_), msg=t.semantics_dump())
  assert_eq(t.all(Dialog).length(), 1, msg=t.semantics_dump())
}

///|
test "a phone's agent card: 账号 pressed, who runs it: its accounts, not its models" {
  let t = phone_agent_card()
  t.click(Button, label="账号 林的 Max · 自动 5H 62% W 18%")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="Claude 订阅") is Some(_) && t.query(Button, label="团队 API key") is Some(_), msg=t.semantics_dump())
  assert_true(t.query(Slider, label="思考深度") is None && t.query(Button, label="Opus 5.5") is None, msg=t.semantics_dump())
  assert_eq(t.all(Dialog).length(), 1, msg=t.semantics_dump())
}


///|
test "a phone's agent card: 6-char tiles ($1,911, 430.5K) and long history line fit cleanly on 360dp and 1.3x scale without ellipsis, label aligned to line 1" {
  for scale in [1.0, words_large_scale] {
    new_run()
    let base = fixture("chat-agent")
    let src : Source = {
      ..base,
      topic_read: fn(topic, params) {
        let got = base.topic(topic, params).get().snapshot()
        if topic == "agentCard" {
          let o : Map[String, Json] = match got.value {
            Some(Object(m)) => m.copy()
            _ => {}
          }
          o["cost"] = Json::string("$1,911")
          o["cache"] = { "text": "99%" }
          o["context"] = { "percent": 0, "text": "430.5K", "unknown": true }
          o["work"] = Json::string("1217 轮 · 共工作 22 小时 35 分")
          { ..got, value: Some(Json::object(o)) }
        } else {
          got
        }
      },
    }
    open_fixture_over("chat-agent", src)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=800.0, platform=2, scale~)
    t.run_for(@ui.move_most_ms)
    let faults = t.squeeze_faults()
    assert_eq(faults, [], msg="scale=\{scale}: \{Repr(faults)}")
    let words = t.words()
    for want in ["$1,911", "99%", "430.5K"] {
      assert_true(words.any(fn(w) { w.0 == want && w.5 > 0.5 }), msg="scale=\{scale}: missing \{want}")
    }
    let hist_words = words.filter(fn(w) { w.5 > 0.5 && w.0.contains("1217") })
    let combined = hist_words.map(fn(w) { w.0 }).join("")
    assert_true(combined.contains("1217") && combined.contains("35") && !combined.contains("…"), msg="scale=\{scale}: truncated history \{combined}")
    if scale == 1.0 {
      let hist_top = hist_words.iter().fold(init=1.0e9, fn(m, w) { dmin(m, w.2) })
      let hist_bot = hist_words.iter().fold(init=0.0, fn(m, w) { dmax(m, w.2 + w.4) })
      let lbl = words.iter().find_first(fn(w) { w.0 == "历史" && w.5 > 0.5 })
      guard lbl is Some(lw) else { fail("missing 历史 label") }
      assert_true(hist_bot - hist_top > 30.0, msg="expected wrapped history text, got height \{hist_bot - hist_top}")
      assert_true(lw.2 + lw.4 / 2.0 < (hist_top + hist_bot) / 2.0, msg="label centered across wrapped block instead of first line: lw=\{Repr(lw)} hist=\{Repr(hist_words)}")
    }
  }
}
