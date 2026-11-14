// Regression tests for the execution history UI fixes across narrow (`sfapp/history_node.mbt`, `sfapp/history.mbt`),
// wide (`sfdesk/history.mbt`), and shared step/markdown nodes (`sfpages/history_steps_node.mbt`, `sf/markdown_node.mbt`).

///|
/// A narrow chat source whose first agent is actively running (`status = "running"`) and warm (`process = "warm"`),
/// with optional `attention` alerts, paired with a caller-supplied `history` topic JSON.
fn history_fixes_src(
  history : Json,
  attention? : Array[Json] = [],
) -> (Source, ChatRef) {
  let base = fixture("chat")
  let base_chat = base.topic("chat", { "station": "ws1/st1", "session": "s-c1" }).get().value
  let chat_with_active : Json? = match base_chat {
    Some(Object(cm)) => {
      let co = cm.copy()
      co["agents"] = Json::array(
        items(base_chat, "agents").mapi(fn(idx, a) {
          if idx != 0 {
            return a
          }
          match a {
            Object(am) => {
              let w = am.copy()
              w["status"] = Json::string("running")
              if !attention.is_empty() {
                w["attention"] = Json::array(attention)
              }
              match field(Some(a), "session") {
                Some(Object(sm)) => {
                  let so = sm.copy()
                  so["process"] = Json::string("warm")
                  w["session"] = Json::object(so)
                }
                _ => ()
              }
              Json::object(w)
            }
            _ => a
          }
        }),
      )
      Some(Json::object(co))
    }
    _ => base_chat
  }
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "history" {
        { value: Some(history), error: None, version: 1 }
      } else if name == "chat" {
        { value: chat_with_active, error: None, version: 1 }
      } else {
        (base.topic_read)(name, params)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  (src, r)
}

///|
test "history tab switch preserves steps scroll and only-io filter toggles non-io steps" {
  new_run()
  let base_hist = fling_history(8)
  let marked_hist : Json = match base_hist {
    Object(hm) => {
      let ho = hm.copy()
      ho["items"] = Json::array(
        items(Some(base_hist), "items").map(fn(it) {
          if text(field(Some(it), "body"), "kind") == "group" {
            match it {
              Object(im) => {
                let io = im.copy()
                io["work"] = Json::boolean(true)
                Json::object(io)
              }
              _ => it
            }
          } else {
            it
          }
        }),
      )
      Json::object(ho)
    }
    _ => base_hist
  }
  let (src, r) = history_fixes_src(marked_hist)
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  // Scroll up away from the live tail so an older turn sits in the viewport.
  t.wheel(195.0, 440.0, -360.0)
  t.run_for(@ui.move_most_ms)
  let mut picked : (String, Double)? = None
  for k in 0..<8 {
    let label = "读了文件，跑了命令 第\{k}轮"
    match t.find(label) {
      Some((_, y)) if y > 220.0 && y < 700.0 => {
        picked = Some((label, y))
        break
      }
      _ => ()
    }
  }
  guard picked is Some((marker, y_before)) else { fail("expected a scrolled turn group visible") }
  // Switch to 详情 and back to 步骤: View::park retention must keep the steps scroll offset.
  let det = t.rect_of("详情").unwrap()
  t.tap(det.0 + det.2 / 2.0, det.1 + det.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  let steps_tab = t.rect_of("步骤").unwrap()
  t.tap(steps_tab.0 + steps_tab.2 / 2.0, steps_tab.1 + steps_tab.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  let y_after = t.find(marker).map(fn(p) { p.1 }).unwrap_or(-1.0)
  assert_true((y_after - y_before).abs() < 1.5, msg="scroll jumped: \{y_before} -> \{y_after}")
  // Flip 只看收发 on and off: non-io groups vanish while received/post remain.
  @sfpages.history_only_io_flip()
  t.draw()
  assert_true(t.find(marker) is None, msg="expected group hidden when only-io filter is active")
  @sfpages.history_only_io_flip()
  t.draw()
  assert_true(t.find(marker) is Some(_), msg="expected group restored when only-io filter turns off")
}

///|
test "history head with active stop and evict actions has sufficient touch room and attention wraps" {
  new_run()
  let notes : Array[Json] = [
    {
      "kind": "disk",
      "text": "这个工作区的磁盘空间只剩 1.2 GiB，建议先清理构建缓存目录再继续跑完整测试",
      "more": "",
    },
    {
      "kind": "quota",
      "text": "周额度提醒",
      "more": "本周已用 88%",
      "quota": { "left": 88, "level": "warn", "mark": "C" },
    },
  ]
  let post_with_code : Json = {
    "items": [
      {
        "key": "p-code",
        "entries": [1, 2],
        "body": {
          "kind": "post",
          "content": {
            "text": "运行命令：\n\n```sh\nmoon test --target wasm-gc --release\n```\n",
            "place": { "name": "整理发布清单", "surface": "ember", "session": "s-c1" },
            "block": false,
            "failed": false,
          },
        },
      },
    ],
    "live": [],
    "usage": [],
    "edge": "从 10/19 08:12 开始",
    "empty": false,
    "loaded": true,
    "more": false,
  }
  let (src, r) = history_fixes_src(post_with_code, attention=notes)
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(@ui.move_most_ms)
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  let head_rooms = t.room_faults().filter(fn(f) { f.contains("history_node.mbt") })
  assert_eq(head_rooms, [])
  let code_rooms = t.room_faults().filter(fn(f) { f.contains("markdown_node.mbt") })
  assert_eq(code_rooms, [])
  let note_squeeze = t
    .squeeze_faults()
    .filter(fn(f) { f.contains("sfapp/history.mbt") || f.contains("history_steps_node.mbt") })
  assert_eq(note_squeeze, [])
  assert_true(t.find("这个工作区的磁盘空间只剩") is Some(_))
}

///|
test "wide history details runtime and evict wrap without room or squeeze faults" {
  guard corner_windows.search_by(w => w.0 == "desk") is Some(i) else { fail("no desk window in corner_windows") }
  let win = corner_windows[i]
  for scale in [1.0, 1.3] {
    let t = screen_in("history", win, "zh", said=true, font_scale=scale)
    let room = t.room_faults().filter(fn(f) { f.contains("sfdesk/history.mbt") })
    assert_eq(room, [])
    let squeeze = t.squeeze_faults().filter(fn(f) { f.contains("sfdesk/history.mbt") })
    assert_eq(squeeze, [])
  }
}

///|
test "history steps at 1.3x: fold toggle room, task wrap, step meta and tool path extra stay uncrushed" {
  new_run()
  let long_lines = Array::makei(14, fn(i) { "第 \{i + 1} 行：验证放大字号下折叠行数预算与展开点击高度是否充足" }).join("\n")
  let rich_history : Json = {
    "items": [
      {
        "key": "r-task",
        "entries": [1, 1],
        "body": {
          "kind": "received",
          "content": {
            "tasks": [
              {
                "text": "构建任务失败：在编译与静态检查阶段遇到较长的错误说明文本，过去单行省略会丢失后半段原因，现在应当在窄屏下完整换行展示出来",
                "agent": true,
                "failed": true,
              },
            ],
            "messages": [],
          },
        },
      },
      {
        "key": "g-step",
        "entries": [2, 3],
        "body": {
          "kind": "group",
          "content": {
            "summary": "读取超长路径并执行验证脚本",
            "title": "读取",
            "failures": 1,
            "pending": 0,
            "rows": [
              {
                "kind": "step",
                "content": {
                  "name": "Read",
                  "hint": "apps/mbui/src/sfpages/very/long/nested/directory/history_steps_node_implementation.mbt",
                  "meta": "12.3s · 退出码 1",
                  "failed": true,
                  "call": "{\"file_path\":\"/Users/lin/project/apps/mbui/src/sfpages/very/long/nested/directory/history_steps_node_implementation.mbt\",\"offset\":80,\"limit\":40}",
                  "result": "pub fn history_steps_node() {}",
                  "entries": [2, 3],
                  "brief": false,
                },
              },
            ],
          },
        },
      },
      {
        "key": "p-fold",
        "entries": [4, 4],
        "body": {
          "kind": "post",
          "content": {
            "text": long_lines,
            "place": { "name": "整理发布清单", "surface": "ember", "session": "s-c1" },
            "block": false,
            "failed": false,
          },
        },
      },
    ],
    "live": [],
    "usage": [],
    "edge": "从 10/19 08:12 开始",
    "empty": false,
    "loaded": true,
    "more": false,
  }
  let (base_src, r) = history_fixes_src(rich_history)
  let src : Source = {
    ..base_src,
    call: fn(name, params, done) {
      if name == "history.tool" {
        done(
          Ok({
            "call": [
              {
                "kind": "path",
                "path": "/Users/lin/project/apps/mbui/src/sfpages/very/long/nested/directory/history_steps_node_implementation.mbt",
                "extra": "第 80-119 行",
              },
              {
                "kind": "facts",
                "items": [
                  { "key": "很长的参数键名称用于测试折行", "value": "非常长的参数值内容不会在宽度不足时把同排标签挤没" },
                ],
              },
            ],
            "result": [],
          }),
        )
      } else {
        (base_src.call)(name, params, done)
      }
    },
  }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.set_font_scale(1.3)
  t.run_for(@ui.move_most_ms)
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  // Unwrapped task error wraps across multiple lines instead of clipping to one line.
  let task_rect = t.rect_of("构建任务失败").unwrap()
  assert_true(task_rect.3 > 25.0, msg="expected wrapped task height > 25, got \{Repr(task_rect)}")
  // Fold toggle button has >= 44px touch height under 1.3x font scale.
  let fold_btn = t.rect_of("展开 · 还有").unwrap()
  assert_true(fold_btn.3 >= @sf.row_least() - 0.5 || t.room_faults().filter(fn(f) { f.contains("history_steps_node.mbt") }).is_empty(), msg="fold toggle: \{Repr(fold_btn)}")
  // Open group and open Read step: step meta and tool path extra stay uncrushed, facts wrap cleanly.
  let grp = t.rect_of("读取超长路径并执行验证脚本").unwrap()
  t.tap(grp.0 + grp.2 / 2.0, grp.1 + grp.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  let meta = t.rect_of("12.3s · 退出码 1").unwrap()
  assert_true(meta.2 > 40.0, msg="expected uncrushed step meta width > 40, got \{Repr(meta)}")
  t.tap(meta.0 - 20.0, meta.1 + meta.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  let extra = t.rect_of("第 80-119 行").unwrap()
  assert_true(extra.2 > 40.0, msg="expected uncrushed path extra width > 40, got \{Repr(extra)}")
  let step_rooms = t.room_faults().filter(fn(f) { f.contains("history_steps_node.mbt") })
  assert_eq(step_rooms, [])
  let step_squeeze = t.squeeze_faults().filter(fn(f) { f.contains("history_steps_node.mbt") })
  assert_eq(step_squeeze, [])
}

///|
/// How late the made-up core answers each subscription from a press of 详情 on (ms): at once, a frame late, and on to
/// well past the 300 ms nothing may look like loading in.
let details_press_lates : Array[Double] = [0.0, 16.0, 120.0, 250.0, 400.0, 700.0]

///|
/// An agent's history in fixture mode `mode` in screen `s`, answered through the app's client of its core, each
/// subscription as late as `pace` says when it is asked (opened at once, the test's own setup), as a device's host draws
/// it (check_looks off), at rest: what the client sent and was told, to `heard`.
fn details_press_tester(s : Screen, mode : String, pace : Ref[Double], heard : Array[String]) -> @ui.Tester {
  new_run()
  let src = round_trip_again(fixture_app(mode), 0.0, heard=fn(h) { heard.push(h) }, late=fn(_, _) { pace.val })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=s.w, h=s.h, platform=s.platform)
  t.check_looks(false)
  t.draw()
  t.run_for(@ui.move_most_ms + 1000.0)
  t.ways_set_out() |> ignore
  t
}

///|
/// The control that folds or unfolds the details in screen `s`, as a screen reader finds it: on 小屏 the head's tab
/// (`label`, 步骤 or 详情), on 大屏 the head's chip 详情; with whether it shows the details unfolded.
fn details_control(t : @ui.Tester, s : Screen, label : String) -> (@ui.SemNode, Bool)? {
  if s.platform == 2 {
    t.query(Radio, label~).map(fn(n) { (n, n.check is Some(On) && label == "详情") })
  } else {
    t.query(Button, label="详情").map(fn(n) { (n, n.pressed == Some(true)) })
  }
}

///|
/// Every word drawn now and where (Tester::words: an old view's too, each frame), the control's own left out (what the
/// pressed control answers with), none faded to nothing.
fn details_words(t : @ui.Tester) -> Array[String] {
  t
  .words()
  .filter(fn(w) { w.5 > 0.01 && w.0 != "详情" && w.0 != "步骤" })
  .map(fn(w) { "\{w.0}@\{(w.1 * 10.0).round() / 10.0},\{(w.2 * 10.0).round() / 10.0}" })
}

///|
/// What the client subscribed to in `heard` from its `from`th (each its topic and params as sent), whether it was let go
/// after, and at which of `heard` it was sent.
fn details_subscribed(heard : Array[String], from : Int) -> Array[(String, Bool, Int)] {
  let out : Array[(Int, String, Int)] = []
  let gone : Map[Int, Bool] = Map([])
  for i in from..<heard.length() {
    let h = heard[i]
    guard h.has_prefix("out ") else { continue }
    let j = @json.parse(h.exact_view(start=4).to_owned()) catch { _ => continue }
    guard j is Object(m) && m.get("id") is Some(Number(n, ..)) else { continue }
    match (m.get("subscribe"), m.get("unsubscribe")) {
      (Some(s), _) => out.push((n.to_int(), s.stringify(), i))
      (_, Some(_)) => gone[n.to_int()] = true
      _ => ()
    }
  }
  out.map(fn(o) { (o.1, gone.contains(o.0), o.2) })
}

///|
/// 详情 pressed in an agent's history's head to unfold it (sfpages' history_details_open: on 小屏 the head's tab, on 大屏
/// its chip), and pressed to fold it, in turn, 小屏 by touch and 大屏 with a mouse, the history opened over a core
/// answering at once and each press over one answering 0 to 700 ms late. Each unfolding: from the press till the details
/// come, every frame's words but the control's own where they were at the press, the control showing itself pressed;
/// from the frame they come, no way setting out but theirs, and once that is over (the most a move takes) every word
/// where it is at rest; nothing asked after they came (all they read asked by the press), what was asked once and held
/// at rest. Folding asks nothing.
test "an agent's history's 详情 unfolded: the head as it was till all the details read is answered, then the details whole" {
  let faults : Array[String] = []
  let say = fn(at : String, f : String) {
    if faults.length() < 24 {
      println("HDETAIL \{at} \{f}")
    }
    faults.push(at + " " + f)
  }
  for case in [(daily_small, "history"), (daily_small, "history-details"), (daily_large, "history")] {
    let (s, mode) = case
    for ms in details_press_lates {
      let heard : Array[String] = []
      let pace = Ref(0.0)
      let t = details_press_tester(s, mode, pace, heard)
      pace.val = ms
      guard details_control(t, s, "详情") is Some((_, open_at_first)) else {
        say("\{s.name} \{mode}", "no 详情")
        break
      }
      // (unfold, fold, unfold again: from folded at first; else folded first)
      let presses = if open_at_first { [false, true, false, true] } else { [true, false, true] }
      for p, unfold in presses {
        let at = "\{s.name} \{mode} \{ms}ms #\{p}"
        let label = if unfold || s.platform != 2 { "详情" } else { "步骤" }
        guard details_control(t, s, label) is Some((c, _)) else {
          say(at, "no \{label}")
          break
        }
        let before = details_words(t)
        let asked_from = heard.length()
        let from = t.time()
        t.tap(c.rect.0 + c.rect.2 / 2.0, c.rect.1 + c.rect.3 / 2.0)
        if !unfold {
          t.run_for(@ui.move_most_ms + ms + 1000.0)
          t.ways_set_out() |> ignore
          continue
        }
        // (each frame: its moment from the press, its words, what was heard by then)
        let frames : Array[(Double, Array[String], Int)] = []
        let ways : Array[(Double, String)] = []
        let n = ((ms * 2.0 + @ui.move_most_ms * 2.0) / @ui.frame_period_default).ceil().to_int()
        for i in 0..=n {
          if i > 0 {
            t.run_for(@ui.frame_period_default)
          }
          let now = t.time() - from
          for w in t.ways_set_out() {
            if w.at > from + 0.5 {
              ways.push((w.at - from, "\{w.kind} \{w.made} \{w.part}"))
            }
          }
          let words = details_words(t)
          if !(details_control(t, s, "详情") is Some((_, true))) {
            say(at, "+\{now.round()} 详情 not shown pressed")
          }
          frames.push((now, words, heard.length()))
        }
        t.run_for(@ui.move_most_ms + 1000.0)
        for w in t.ways_set_out() {
          ways.push((w.at - from, "\{w.kind} \{w.made} \{w.part}"))
        }
        let rest = details_words(t)
        // (the frame they came in, and the one before it: what was heard by then, the press's asks; in the press's frame,
        // what it heard)
        let mut came = -1.0
        let mut was = -1.0
        let mut heard_then = heard.length()
        for f in frames {
          if f.1 != before {
            came = f.0
            break
          }
          was = f.0
          heard_then = f.2
        }
        if came < 0.0 {
          say(at, "the details never came")
          continue
        }
        // (no way but theirs, set out as they came)
        let mut way_at = came
        for w in ways {
          if w.0 > was + 0.5 && w.0 <= came + 0.5 {
            way_at = @cmp.minimum(way_at, w.0)
          } else {
            say(at, "+\{w.0.round()} way set out: \{w.1}")
          }
        }
        let still = way_at + @ui.move_most_ms
        for f in frames {
          if f.0 >= still && f.1 != rest {
            let gone = rest.filter(fn(w) { !f.1.contains(w) })
            let now = f.1.filter(fn(w) { !rest.contains(w) })
            say(at, "+\{f.0.round()} not as at rest (came +\{came.round()}): gone [\{gone.iter().take(3).collect().join(" | ")}] new [\{now.iter().take(3).collect().join(" | ")}]")
            break
          }
        }
        // (all they read asked by the press, before they came; once each, held at rest)
        let asked = details_subscribed(heard, asked_from)
        let said : Map[String, Int] = Map([])
        for a in asked {
          said[a.0] = said.get(a.0).unwrap_or(0) + 1
          if a.2 >= heard_then {
            say(at, "asked after the details came: \{a.0}")
          }
          if a.1 {
            say(at, "let go by rest: \{a.0}")
          }
        }
        for k, c in said {
          if c > 1 {
            say(at, "asked \{c} times: \{k}")
          }
        }
      }
    }
  }
  assert_eq(faults.length(), 0, msg="详情 unfolded: \{faults.length()} faults (HDETAIL lines)")
}
