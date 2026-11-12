// An agent's line while it waits on what it started (sfpages' chat_rows.mbt activity_row: the core's `wait`), and the
// stop of one agent among several from its line.

///|
/// The chat-working fixture's chat with its agent's `wait` as given (None: at work), `two`: a second agent at work beside
/// it; its calls kept in `calls` (answered).
fn waiting_chat(calls : Array[Made], wait? : Json? = None, two? : Bool = false) -> @ui.Tester {
  let base = fixture_app("chat-working")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      done(Ok(Json::object({})))
    },
    topic_read: fn(name, params) {
      let got = base.topic(name, params).get().snapshot()
      guard name == "chat" && got.value is Some(Object(chat)) else { return got }
      let agents = items(got.value, "agents").map(fn(a) {
        match (a, wait) {
          (Object(am), Some(w)) => {
            let o = am.copy()
            o["wait"] = w
            Json::object(o)
          }
          _ => a
        }
      })
      if two {
        agents.push({
          "session": {
            "key": "s-other",
            "runtime": "codex",
            "maker": { "id": "openai", "name": "OpenAI" },
            "agentText": "Codex",
            "statusText": "正在工作",
            "tone": "accent",
          },
          "status": "running",
          "since": -20000,
        })
      }
      let changed = chat.copy()
      changed["agents"] = Json::array(agents)
      { ..got, value: Some(Json::object(changed)) }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(squeeze_opening)
  t
}

///|
test "an agent waiting on what it started says what it waits for and how long of the most it waits: its clock stops there" {
  let calls : Array[Made] = []
  let t = waiting_chat(calls, wait=Some({ "since": -65000, "seconds": 600, "text": "等 CI 跑完" }))
  assert_true(t.find("等 CI 跑完") is Some(_))
  assert_true(t.find("1m 5s / 10m") is Some(_))
  // (what it did before it waited not said over it)
  assert_true(t.find(@sffixture.working_step) is None)
  // waited past its most: the clock stands at it
  let calls : Array[Made] = []
  let t = waiting_chat(calls, wait=Some({ "since": -700000, "seconds": 600, "text": "等 CI 跑完" }))
  assert_true(t.find("10m / 10m") is Some(_))
}

///|
test "an agent waiting with nothing said of it: 等待中, its clock from when it began, no most" {
  let calls : Array[Made] = []
  let t = waiting_chat(calls, wait=Some({ "since": -5000 }))
  assert_true(t.find("等待中") is Some(_))
  assert_true(t.find("5s") is Some(_))
}

///|
test "one of several agents at work: its line's stop under the pointer stops it alone (session.stop by its key); one agent alone has none" {
  let calls : Array[Made] = []
  let t = waiting_chat(calls, two=true)
  let (x, y, _, h) = t.rect_of(@sffixture.working_step).unwrap()
  t.move_to(x + 2.0, y + h / 2.0)
  t.frame()
  guard t.all(Button).iter().find_first(fn(s) { s.label == "停止 Claude" }) is Some(stop) else {
    fail("no stop on Claude's line")
  }
  // (the other agent's line has its own, shown only under the pointer: not now)
  assert_true(!t.all(Button).iter().any(fn(s) { s.label == "停止 Codex" }))
  let (sx, sy, sw, sh) = stop.rect
  t.tap(sx + sw / 2.0, sy + sh / 2.0)
  t.draw()
  let made = named(calls, "session.stop")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "key"), "s-c1")
  assert_eq(text(Some(made[0].params), "station"), "ws1/st1")
  // one agent: nothing to stop from its line
  let calls : Array[Made] = []
  let t = waiting_chat(calls)
  let (x, y, _, h) = t.rect_of(@sffixture.working_step).unwrap()
  t.move_to(x + 2.0, y + h / 2.0)
  t.frame()
  assert_true(!t.all(Button).iter().any(fn(s) { s.label.has_prefix("停止") }))
}
