// An agent's history beside its chat in the wide frame on a tablet's screen (an opened fold's inner one), flung toward
// its start with a finger: a sent message's card coming in at its top (its words cut once they are measured) does not
// send it back to its end.

///|
/// `older` turns of an agent's work (what it was asked, what it did, what it sent: words its card cuts), then its last: a
/// wait that ended, its own words, a turn sending a card, a wait still going, its own words. `sent_first`: each older
/// turn's card before what it did, its short group under the tall card.
fn fling_history(older : Int, sent_first? : Bool = false) -> Json {
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
    let group = item("o\{k}-g", "group", { "summary": "读了文件，跑了命令 第\{k}轮", "title": "读取", "failures": 0, "pending": 0, "rows": [] }, false)
    if sent_first {
      items.push(post("o\{k}-p"))
      items.push(group)
    } else {
      items.push(group)
      items.push(post("o\{k}-p"))
    }
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
  new_run()
  let base = fixture("chat")
  let history = fling_history(12)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "history" {
        { value: Some(history), error: None, version: 1 }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=752.0, h=830.0, platform=2)
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
test "touch wide: an agent's history as the agent writes builds no old view's row: its steps are nodes" {
  new_run()
  let base = fixture("chat")
  let was = fling_history(12)
  let with_live = fn(words : String) -> Json {
    match was {
      Object(m) => {
        let o : Map[String, Json] = Map([])
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
    topic_read: fn(name, params) {
      if name == "history" {
        { value: Some(history.get()), error: None, version: 1 }
      } else if name == "prefs" && chose_dark.get() {
        let p = base.topic(name, params).get().snapshot()
        match p.value {
          Some(Object(m)) => {
            let o : Map[String, Json] = Map([])
            for k, v in m {
              o[k] = v
            }
            o["appearance"] = "dark"
            { ..p, value: Some(Json::object(o)) }
          }
          _ => p
        }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=752.0, h=830.0, platform=2)
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
  // between frames (not a step of the test's, whose first frame is built anew): none of an old view's list's rows built
  // for them, the history's steps nodes (sfpages' history_steps_node: a row made again only as what it shows changes)
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
    assert_true(built == 0, msg="\{more[k]}: \{built} built (\{Repr(whys)})")
  }
}

// An agent's history beside its chat in a desktop's window, the wheel turned a little at a time (a trackpad's: each
// event moves it at once, not eased in as a mouse's notch is): it goes as far as each turn, up from its foot too, and
// stays there as the agent works on (words come, a step ends), what was seen staying where the wheel put it. (desktop
// 0.1.8131: within the head's height of its foot, whatever laid the panel out again, a row come to show, the agent's
// next word, took it back to its foot: under an agent at work it could not be read up from its end at all.) What is
// pressed open at its foot stays under the hand (mbui's press_stays.mbt).

///|
/// The app in a desktop's window, an agent's history (as `history` says it) beside its chat.
fn wheel_history(history : () -> Json) -> @ui.Tester {
  new_run()
  let base = fixture("chat-history-side")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "history" {
        { value: Some(history()), error: None, version: 1 }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
  }
  decide_src.val = Some(src)
  open_fixture_over("chat-history-side", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "the desk's history beside a chat: a trackpad's wheel up from its foot, 12 at a time, takes it 12 each time, never back to its foot" {
  let history = fling_history(12)
  let t = wheel_history(fn() { history })
  // (its last turn's group, seen from the start)
  let marker = "等 CI 跑完再合并"
  let at = fn() { t.find(marker).map(fn(p) { p.1 }).unwrap_or(-1.0) }
  let from = at()
  assert_true(from > 0.0, msg="no \{marker} in the history")
  let mut y = from
  for i in 0..<16 {
    t.wheel(1100.0, 500.0, -12.0)
    let now = at()
    // (12 down the window, on its pixels)
    assert_true(now - y > 10.5 && now - y < 13.5, msg="turn \{i}: \{y} to \{now}")
    y = now
  }
  assert_true(y - from > 190.0 && y - from < 194.0, msg="\{from} to \{y}")
}

///|
test "the desk's history beside a chat: a wheel up 60 at a time over turns whose sent words are cut, every turn 60, none more where a tall card comes in at the top" {
  // (each turn's group, 50 tall, under its card, 218: a turn of 60 brings the group in and, once it is measured, the
  // card over it, in the same layout; held by the card, counted 48 till it was made, what showed went down 170)
  let history = fling_history(12, sent_first=true)
  let t = wheel_history(fn() { history })
  // (each turn's group by its own words, where it is drawn in the history beside the chat, made or not)
  let groups = fn() {
    let at : Map[Int, Double] = Map([])
    for k in 0..<12 {
      match t.find("跑了命令 第\{k}轮") {
        Some((x, y)) if x > 800.0 => at[k] = y
        _ => ()
      }
    }
    at
  }
  let moved = []
  let mut seen = 0
  for i in 0..<40 {
    let was = groups()
    t.wheel(1100.0, 500.0, -60.0)
    let now = groups()
    // (each group well within what shows before the turn, 60 further down after it: still in sight, 60 down the
    // window, on its pixels)
    for k, y in was {
      guard y > 320.0 && y < 680.0 else { continue }
      seen = seen + 1
      match now.get(k) {
        Some(y2) if (y2 - y - 60.0).abs() <= 1.5 => ()
        other => moved.push("turn \{i}, group \{k}: \{y} to \{Repr(other)}")
      }
    }
  }
  assert_true(seen > 20, msg="only \{seen} groups seen across a turn")
  assert_eq(moved, [])
}

///|
/// History `was` with the agent's words in flight (`words`).
fn wheel_live(was : Json, words : String) -> Json {
  match was {
    Object(m) => {
      let o : Map[String, Json] = Map([])
      for k, v in m {
        o[k] = v
      }
      o["live"] = [{ "text": Json::string(words) }]
      Json::object(o)
    }
    _ => was
  }
}

///|
test "the desk's history beside a chat: read 96 up from its foot, the agent's words coming on: where the wheel put it, not back at its foot" {
  let was = fling_history(12)
  let history = @signals.signal(was)
  let t = wheel_history(fn() { history.get() })
  let marker = "等 CI 跑完再合并"
  let at = fn() { t.find(marker).map(fn(p) { p.1 }).unwrap_or(-1.0) }
  let from = at()
  assert_true(from > 0.0, msg="no \{marker} in the history")
  for _ in 0..<8 {
    t.wheel(1100.0, 500.0, -12.0)
  }
  let put = at()
  assert_true(put - from > 94.0 && put - from < 98.0, msg="\{from} to \{put}")
  // the agent writes on, its words a row at the history's end, under what shows
  for words in ["在看", "在看 CI 的日志", "在看 CI 的日志，慢在安装"] {
    history.set(wheel_live(was, words))
    t.run_for(history_words_step_ms)
    assert_eq(at(), put)
  }
}

///|
test "the desk's history beside a chat: a sent message's words opened at its foot, the button pressed where it was" {
  let history = fling_history(12)
  let t = wheel_history(fn() { history })
  // (its last turn's message it sent, whose words are folded to six lines: what is over the button goes up as they
  // open, the button stays under the hand)
  let at = match t.find_last("展开 · 还有") {
    Some((x, y)) => {
      t.tap(x, y)
      y
    }
    None => fail("no words folded in the history")
  }
  t.run_for(@ui.move_most_ms)
  // (within half a point: what is over it measured as it grows, laid out on the window's pixels)
  match t.find_last("收起") {
    Some((_, y)) => assert_true((y - at).abs() < 0.5, msg="\{at} -> \{y}")
    None => fail("not opened")
  }
}

///|
test "the desk's history beside a chat: scrolling across turns reuses row views and keeps measurements" {
  let history = fling_history(20)
  let t = wheel_history(fn() { history })
  t.check_looks(false)
  let tree = @ui.view_tree().unwrap()
  let w0 = tree.work()
  for _ in 0..<18 {
    t.wheel(1100.0, 500.0, -30.0)
  }
  let w1 = tree.work()
  for _ in 0..<12 {
    t.wheel(1100.0, 500.0, -30.0)
  }
  let w2 = tree.work()
  let total_made = w2.made - w0.made
  let total_let_go = w2.let_go - w0.let_go
  let total_laid = w2.laid - w0.laid
  let total_measured = w2.measured - w0.measured
  let warm_made = w2.made - w1.made
  let warm_let_go = w2.let_go - w1.let_go
  assert_true(
    total_made <= 220 && total_let_go <= 40 && total_laid <= 400 && total_measured <= 40,
    msg="total=(\{total_made}, \{total_let_go}, \{total_laid}, \{total_measured})",
  )
  assert_true(warm_made == 0 && warm_let_go == 0, msg="warm=(\{warm_made}, \{warm_let_go})")
}
