// What an agent has going in the background and its checklist (sfpages/agent_work.mbt), as its `agentCard` view says
// them: in its card (opened over its name beside its messages as over its picture), and in its history's details.

///|
/// Its line as the core says it (views/brief.ts workOf).
let work_line : String = "后台 4 · 清单 2/6：core 的 agentCard 加上后台和清单"

///|
/// The made-up core of `mode` whose agents' cards say four tasks in the background and a checklist of six, two done
/// (views/brief.ts workOf), the tasks begun `ago` before the core's now.
fn work_source(mode : String, on? : Ref[Bool] = Ref(true), running? : Bool = true) -> Source {
  let base = fixture(mode)
  {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      guard on.val && name == "agentCard" && got.value is Some(Object(card)) else { got }
      let now = (base.now)()
      let task = fn(id : String, kind : String, words : String, kind_words : String, ago : Double) -> Json {
        { "id": Json::string(id), "kind": Json::string(kind), "text": Json::string(words), "kindText": Json::string(kind_words), "since": Json::number(now - ago) }
      }
      let step = fn(words : String, status : String) -> Json { { "text": Json::string(words), "status": Json::string(status) } }
      let plan = [
        step("读 claude.ts 里的 task 帧", "completed"),
        step("station 推送 tasks 和 plan", "completed"),
        step("core 的 agentCard 加上后台和清单", "in_progress"),
        step("web 和 mbui 画出来", "pending"),
        step("截图", "pending"),
        step("跑检查并提交", "pending"),
      ]
      let out = card.copy()
      out["tasks"] = if !running { Json::array([]) } else { Json::array([
        task("a1", "agent", "审阅 live.ts 的改动", "子代理", 252_000.0),
        task("b1", "command", "pnpm test --watch", "命令", 95_000.0),
        task("b2", "command", "gh run watch 18820431", "命令", 31_000.0),
        task("b3", "command", "vite --config web/vite.demo.config.ts", "命令", 720_000.0),
      ]) }
      out["plan"] = Json::array(plan)
      out["planText"] = Json::string("已完成 2/6")
      out["workLine"] = Json::string(work_line)
      out["workMark"] = Json::string("后台 4 · 2/6")
      out["workMarkShort"] = Json::string("4 · 2/6")
      out["workMarkCount"] = Json::string("4")
      { ..got, value: Some(Json::object(out)) }
    },
  }
}

///|
test "an agent's card over its name, as over its picture: its background work and its checklist in one line, which leads to its execution history" {
  reset()
  let src = work_source("chat-agent-card")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  assert_eq(word(work_line).length(), 0)
  // the pointer on the agent's name over its last message (not its picture)
  let last = word("Claude").iter().fold(init=None, fn(acc : (String, Double, Double, Double, Double, Double)?, w) {
    match acc {
      Some(a) if a.2 >= w.2 => acc
      _ => Some(w)
    }
  })
  guard last is Some(name) else { fail("no agent's message") }
  t.move(name.1 + name.3 / 2.0, name.2 + name.4 / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // one line, under its latest lines, none of the lists it sums up
  let line = word(work_line)
  assert_eq(line.length(), 1)
  let latest = word("改了 src/ui/list.mbt")
  assert_true(latest.length() == 1 && line[0].2 > latest[0].2, msg="\{(line, latest)}")
  assert_eq(word("审阅 live.ts 的改动").length(), 0)
  assert_eq(word("截图").length(), 0)
  // as tall as one of its latest lines: it never wraps
  assert_true(line[0].4 <= latest[0].4 + 0.5, msg="\{(line[0].4, latest[0].4)}")
  assert_eq(t.corner_faults(), [])
  // pressed: its execution history, beside the chat
  t.tap(line[0].1 + 10.0, line[0].2 + line[0].4 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(@sf.t("web-main.history.onlyIo")) is Some(_), msg="its history open")
}

///|
test "the history's details: its turns' line says its work after it, none without it, nothing else moved; pressed, every task in the background and its whole checklist under it; the tabs and the head as they were" {
  reset()
  let on = Ref(false)
  let src = work_source("chat-history-side", on~)
  decide_src.val = Some(src)
  open_fixture_over("chat-history-side", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  let forms = fn() { word("后台 4 · 2/6") + word("4 · 2/6") + word("4") }
  // nothing in the background, no checklist: no mark; the line, the tabs, the head and what is under the line
  assert_eq(forms().length(), 0)
  let turns = word("8 轮 · 共干了 1 小时 12 分")
  assert_eq(turns.length(), 1)
  let before = t.words().filter(fn(w) { w.5 > 0.5 && w.0 != " · " }).map(fn(w) { (w.0, w.1, w.2) })
  // told: the mark at the turns' line's end, on its line; the line's words whole; nothing else anywhere moved (the
  // details as tall as they were)
  on.val = true
  t.frame()
  t.frame()
  let mark = forms()
  assert_eq(mark.length(), 1)
  assert_true((mark[0].2 - turns[0].2).abs() < 2.0 && mark[0].1 > turns[0].1 + turns[0].3, msg="\{(mark, turns)}")
  assert_eq(word("8 轮 · 共干了 1 小时 12 分").length(), 1)
  let after = t.words().filter(fn(w) { w.5 > 0.5 && w.0 != " · " && w.0 != mark[0].0 }).map(fn(w) { (w.0, w.1, w.2) })
  assert_eq(after, before)
  assert_eq(word(work_line).length(), 0)
  assert_eq(word("后台进行中").length(), 0)
  // pressed: all of it beside it
  t.tap(mark[0].1 + 4.0, mark[0].2 + mark[0].4 / 2.0)
  t.run_for(@kit.presence_in_ms)
  assert_true(word("后台进行中").length() == 1 && word("4").length() >= 1)
  assert_eq(word("vite --config web/vite.demo.config.ts").length(), 1)
  assert_eq(word("4m 12s").length(), 1)
  assert_eq(word("12m").length(), 1)
  assert_true(word("清单").length() == 1 && word("已完成 2/6").length() == 1)
  let ys = ["读 claude.ts 里的 task 帧", "station 推送 tasks 和 plan", "core 的 agentCard 加上后台和清单", "跑检查并提交"].map(fn(s) {
    let w = word(s)
    assert_eq(w.length(), 1)
    w[0].2
  })
  assert_true(ys[0] < ys[1] && ys[1] < ys[2] && ys[2] < ys[3], msg="\{ys}")
  assert_eq(word("✓").length(), 2)
  // the tasks' descriptions in one column, their times' ends in one; the checklist's marks on the chips' line
  let xs = ["审阅 live.ts 的改动", "pnpm test --watch", "gh run watch 18820431"].map(fn(s) { word(s)[0].1 })
  assert_true(xs[0] == xs[1] && xs[1] == xs[2], msg="\{xs}")
  let ends = ["4m 12s", "1m 35s", "31s", "12m"].map(fn(s) { word(s)[0].1 + word(s)[0].3 })
  assert_true(ends.iter().all(fn(e) { (e - ends[0]).abs() < 0.5 }), msg="\{ends}")
  assert_true((word("子代理")[0].1 - word("✓")[0].1).abs() < 8.0, msg="\{(word("子代理"), word("✓"))}")
  // beside the mark, under it
  assert_true(word("后台进行中")[0].2 > mark[0].2, msg="under it")
  // Escape: gone
  t.key(@ui.key_escape)
  t.run_for(@kit.presence_out_ms)
  assert_eq(word("后台进行中").length(), 0)
}

///|
test "on a phone, its details' turns say its work after them, its head as it was; pressed, all of it from the foot" {
  reset()
  let src = work_source("history-details")
  decide_src.val = Some(src)
  open_fixture_over("history-details", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  let turns = word("8 轮 · 共干了 1 小时 12 分")
  assert_eq(turns.length(), 1)
  let mark = word("后台 4 · 2/6") + word("4 · 2/6") + word("4")
  assert_eq(mark.length(), 1)
  assert_true((mark[0].2 + mark[0].4 / 2.0 - turns[0].2 - turns[0].4 / 2.0).abs() < 2.0, msg="\{(mark, turns)}")
  assert_eq(word("后台进行中").length(), 0)
  t.tap(mark[0].1 + 4.0, mark[0].2 + mark[0].4 / 2.0)
  t.run_for(@kit.presence_in_ms * 2.0)
  assert_eq(word("后台进行中").length(), 1)
  assert_eq(word("跑检查并提交").length(), 1)
  // from the foot: its lists low in the window
  assert_true(word("跑检查并提交")[0].2 > 422.0, msg="\{word("跑检查并提交")}")
}

///|
test "the mark of an agent's work: at work's spokes before it while something runs in the background, none for a checklist alone" {
  let cycles = fn(running : Bool) -> Array[String] {
    reset()
    let src = work_source("chat-history-side", running~)
    let t = @ui.Tester::new(
      fn(c) { @sfpages.work_mark(c, src, "ws1/st1", "s-c1", @sfdesk.side_tab_words, @sfdesk.side_tab_words, lead=" · ") },
      w=400.0,
      h=40.0,
    )
    t.run_for(@sf.spoke_step_ms)
    t.cycles()
  }
  // the spokes' step, on the resident clock (10 a second)
  assert_true(cycles(true).iter().any(fn(c) { c.has_prefix("800 ms") }), msg="\{cycles(true)}")
  assert_eq(cycles(false), [])
}
