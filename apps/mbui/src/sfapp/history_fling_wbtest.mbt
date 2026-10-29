// An agent's history beside its chat in the wide frame on a tablet's screen (an opened fold's inner one), flung toward
// its start with a finger: a sent message's card coming in at its top (its words cut once they are measured) does not
// send it back to its end.

///|
/// `older` turns of an agent's work (what it was asked, what it did, what it sent: words its card cuts), then its last: a
/// wait that ended, its own words, a turn sending a card, a wait still going, its own words.
fn fling_history(older : Int) -> Json {
  let items : Array[Json] = []
  let item = fn(key : String, kind : String, content : Json, turn : Bool) -> Json {
    let o : Map[String, Json] = {
      "key": Json::string(key),
      "entries": [1, 2],
      "body": { "kind": Json::string(kind), "content": content },
    }
    if turn {
      o["turn"] = { "time": "16:25", "text": "2 步 · 发了 1 条" }
    }
    Json::object(o)
  }
  let sent = fixture_markdown()
  let post = fn(key : String) -> Json {
    item(key, "post", {
      "text": Json::string(sent),
      "place": { "name": "整理发布清单", "surface": "ember", "session": "s-c1" },
      "block": false,
      "failed": false,
    }, false)
  }
  for k in 0..<older {
    items.push(
      item("o\{k}-in", "received", {
        "tasks": [],
        "messages": [{ "key": "m\{k}", "from": { "name": "林", "bound": false }, "text": "看看 CI 为什么慢" }],
      }, true),
    )
    items.push(item("o\{k}-g", "group", { "summary": "读了文件，跑了命令", "title": "读取", "failures": 0, "pending": 0, "rows": [] }, false))
    items.push(post("o\{k}-p"))
  }
  items.push(item("w1", "mark", { "wait": { "since": 0, "seconds": 3600, "until": 30000 }, "text": "后台助手做完了" }, false))
  items.push(item("t1", "text", { "text": "主线上又超时了", "line": "主线上又超时了", "subagent": false }, false))
  items.push(item("r2", "received", { "tasks": [{ "text": "后台助手做完了：跳过安装", "agent": true }], "messages": [] }, true))
  items.push(item("g2", "group", { "summary": "等 CI 跑完再合并", "title": "等待", "failures": 0, "pending": 0, "rows": [] }, false))
  items.push(post("p2"))
  items.push(item("w2", "mark", { "wait": { "since": 0, "seconds": 3600, "what": "最终提交上的检查" }, "text": "" }, false))
  items.push(item("t2", "text", { "text": "改动已经提交", "line": "改动已经提交", "subagent": false }, false))
  { "items": Json::array(items), "live": [], "usage": [], "edge": "从 10/19 08:12 开始", "empty": false, "loaded": true, "more": false }
}

///|
/// Longer than the fling a finger's 180 in six moves sets off (Android's spline: about a second).
let history_fling_ms : Double = 2000.0

///|
test "touch wide: an agent's history flung toward its start rests further that way, not back at its end" {
  reset()
  let base = fixture("chat")
  let history = fling_history(12)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "history" {
        { value: Some(history), error: None, version: 1 }
      } else {
        (base.topic)(name, params)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=752.0, h=830.0, platform=2)
  // (the tape's sidebar in use at first, a strip of the chat beside it)
  let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\nuntil 新建对话\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  side_change(r, "open", Some("s-c1"))
  t.run_for(@ui.move_most_ms)
  let marker = "等 CI 跑完再合并"
  let (x, y) = match t.find(marker) {
    Some(at) => at
    None => fail("no \{marker} in the history")
  }
  // the finger down on it, pulled down 180 in six moves and let go: flung toward the start, it comes to rest further
  // that way than the finger took it (out of view under the panel's foot), not back at its end, where a sent card coming
  // in at its top sent it
  t.drag(x, y, x, y + 180.0, steps=6)
  t.run_for(history_fling_ms)
  match t.find(marker) {
    Some((_, now)) => assert_true(now > y + 180.0, msg="flung to \{now}, from \{y}")
    None => ()
  }
}

///|
/// A step of the agent writing, as its words come.
let history_words_step_ms : Double = 16.0

///|
/// How far apart the agent's words come, told by the core.
let history_words_gap_ms : Int = 100

///|
/// A phone's display's frames, each drawn as a host draws them.
let history_frame_ms : Double = 1000.0 / 120.0


///|
test "touch wide: an agent's history as the agent writes builds again only the row its words are written in" {
  reset()
  let base = fixture("chat")
  let was = fling_history(12)
  let with_live = fn(words : String) -> Json {
    match was {
      Object(m) => {
        let o : Map[String, Json] = {}
        for k, v in m {
          o[k] = v
        }
        o["live"] = [{ "text": Json::string(words) }]
        Json::object(o)
      }
      _ => was
    }
  }
  let history = @signals.signal(with_live("在看"))
  // (dark as chosen, from when it is)
  let chose_dark = @signals.signal(false)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "history" {
        { value: Some(history.get()), error: None, version: 1 }
      } else if name == "prefs" && chose_dark.get() {
        let p = (base.topic)(name, params)
        match p.value {
          Some(Object(m)) => {
            let o : Map[String, Json] = {}
            for k, v in m {
              o[k] = v
            }
            o["appearance"] = "dark"
            { ..p, value: Some(Json::object(o)) }
          }
          _ => p
        }
      } else {
        (base.topic)(name, params)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=752.0, h=830.0, platform=2)
  let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\nuntil 新建对话\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  side_change(r, "open", Some("s-c1"))
  t.run_for(@ui.move_most_ms)
  // (the panel come and the tape at rest: nothing moving builds the frame)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("在看") is Some(_))
  // its words coming, a few at a time: the items before them, the same JSON, kept as they were built
  let words = ["在看 CI", "在看 CI 的日志", "在看 CI 的日志，慢在安装"]
  for w in words {
    history.set(with_live(w))
    t.run_for(history_words_step_ms)
    assert_true(t.find(w) is Some(_), msg="\{w} not shown")
  }
  // dark chosen as they come: the rows kept built again in its colours (each frame that kept rows built again keeping
  // none must come out the same)
  chose_dark.set(true)
  t.run_for(history_words_step_ms)
  assert_true(@sf.theme().dark)
  chose_dark.set(false)
  t.run_for(history_words_step_ms)
  // as a host draws them (no frame built again keeping none to hold it, as a Tester does) and as the core tells them,
  // between frames (not a step of the test's, whose first frame is built anew): of the history's rows, only the one the
  // words are in built for each, the rest kept however the frame is built
  t.check_looks(false)
  t.set_frame_period(history_frame_ms)
  let built_at : Array[Int] = []
  let more = ["读完了日志", "读完了日志，在改"]
  let whys : Array[String] = []
  for k, w in more {
    @ui.runtime().after((k + 1) * history_words_gap_ms, fn() {
      built_at.push(t.rows_read_built())
      history.set(with_live(w))
    })
    // (and why the frame after it was built, if it was: said where it fails)
    @ui.runtime().after((k + 1) * history_words_gap_ms + history_words_step_ms.to_int(), fn() {
      whys.push(t.built_why())
    })
  }
  @ui.runtime().after((more.length() + 1) * history_words_gap_ms, fn() { built_at.push(t.rows_read_built()) })
  t.run_for(((more.length() + 2) * history_words_gap_ms).to_double())
  assert_true(t.find(more[more.length() - 1]) is Some(_))
  for k in 0..<more.length() {
    let built = built_at[k + 1] - built_at[k]
    assert_true(built == 1, msg="\{more[k]}: \{built} built (\{whys})")
  }
}
