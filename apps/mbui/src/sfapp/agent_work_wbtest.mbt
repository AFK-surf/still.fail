// What an agent has going in the background and its checklist (sfpages/agent_work.mbt), as its `agentCard` view says
// them: in its card (opened over its name beside its messages as over its picture), and in its history's details.

///|
/// Its line as the core says it (views/brief.ts workOf).
let work_line : String = "后台 4 · 清单 2/6：core 的 agentCard 加上后台和清单"

///|
test "an agent's card offers its jobs when a compact chat says it has them" {
  for has_jobs in [true, false] {
    new_run()
    let base = fixture("chat-agent")
    let src : Source = {
      ..base,
      topic_read: fn(name, params) {
        let got = base.topic(name, params).get().snapshot()
        guard name == "chat" && got.value is Some(Object(chat)) else { return got }
        let out = chat.copy()
        out["agents"] = Json::array(items(got.value, "agents").map(fn(a) {
          match a {
            Object(agent) => {
              let shown = agent.copy()
              shown["jobs"] = Json::array([])
              shown["hasJobs"] = Json::boolean(has_jobs)
              Json::object(shown)
            }
            _ => a
          }
        }))
        { ..got, value: Some(Json::object(out)) }
      },
    }
    open_fixture_over("chat-agent", src)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
    t.run_for(@ui.move_most_ms)
    sheet_rested(t, "sf-present")
    assert_eq(t.find("后台") is Some(_), has_jobs)
  }
}

///|
/// The made-up core of `mode` whose agents' cards say four tasks in the background and a checklist of six, two done
/// (views/brief.ts workOf), the tasks begun `ago` before the core's now.
fn work_source(mode : String, on? : @signals.Signal[Bool] = @signals.signal(true), running? : Bool = true) -> Source {
  let base = fixture(mode)
  {
    ..base,
    topic_read: fn(name, params) {
      let got = base.topic(name, params).get().snapshot()
      guard on.get() && name == "agentCard" && got.value is Some(Object(card)) else { got }
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
  new_run()
  let src = work_source("chat-agent-card")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
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
  t.move_to(name.1 + name.3 / 2.0, name.2 + name.4 / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // one line, under its latest lines, none of the lists it sums up
  let line = word(work_line)
  assert_eq(line.length(), 1)
  let latest = word("改了 src/ui/list.mbt")
  assert_true(latest.length() == 1 && line[0].2 > latest[0].2, msg="\{Repr((line, latest))}")
  // the card's words start where the name does, its edge out to the side of them (its lines 14 in, after the dot)
  assert_eq(latest[0].1, name.1 + 14.0)
  assert_eq(word("审阅 live.ts 的改动").length(), 0)
  assert_eq(word("截图").length(), 0)
  // as tall as one of its latest lines: it never wraps
  assert_true(line[0].4 <= latest[0].4 + 0.5, msg="\{Repr((line[0].4, latest[0].4))}")
  assert_eq(t.corner_faults(), [])
  // pressed: its execution history, beside the chat
  t.tap(line[0].1 + 10.0, line[0].2 + line[0].4 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(@sf.t("web-main.history.onlyIo")) is Some(_), msg="its history open")
}

///|
test "the history's details: its turns' line says its work after it, none without it, nothing else moved; pressed, every task in the background and its whole checklist under it; the tabs and the head as they were" {
  new_run()
  let on = @signals.signal(false)
  let src = work_source("chat-history-side", on~)
  decide_src.val = Some(src)
  open_fixture_over("chat-history-side", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  let forms = fn() { word("后台 4 · 2/6") + word("4 · 2/6") + word("4") }
  // nothing in the background, no checklist: no mark; the line, the tabs, the head and what is under the line
  assert_eq(forms().length(), 0)
  let turns = word("共工作 1 小时 12 分")
  assert_eq(turns.length(), 1)
  let before = t.words().filter(fn(w) { w.5 > 0.5 && w.0 != " · " }).map(fn(w) { (w.0, w.1, w.2) })
  // told: the mark at the turns' line's end, on its line; the line's words whole; nothing else anywhere moved (the
  // details as tall as they were)
  on.set(true)
  t.frame()
  t.frame()
  let mark = forms()
  assert_eq(mark.length(), 1)
  assert_true((mark[0].2 - turns[0].2).abs() < 2.0 && mark[0].1 > turns[0].1 + turns[0].3, msg="\{Repr((mark, turns))}")
  assert_eq(word("共工作 1 小时 12 分").length(), 1)
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
  let ys = ["读 claude.ts 里的 task 帧", "station 推送 tasks 和 plan", "core 的 agentCard 加上后台和清单", "跑检查并提交"].map(fn(s) raise {
    let w = word(s)
    assert_eq(w.length(), 1)
    w[0].2
  })
  assert_true(ys[0] < ys[1] && ys[1] < ys[2] && ys[2] < ys[3], msg="\{Repr(ys)}")
  assert_eq(word("✓").length(), 2)
  // the tasks' descriptions in one column, their times' ends in one; the checklist's marks on the chips' line
  let xs = ["审阅 live.ts 的改动", "pnpm test --watch", "gh run watch 18820431"].map(fn(s) { word(s)[0].1 })
  assert_true(xs[0] == xs[1] && xs[1] == xs[2], msg="\{Repr(xs)}")
  let ends = ["4m 12s", "1m 35s", "31s", "12m"].map(fn(s) { word(s)[0].1 + word(s)[0].3 })
  assert_true(ends.iter().all(fn(e) { (e - ends[0]).abs() < 0.5 }), msg="\{Repr(ends)}")
  assert_true((word("子代理")[0].1 - word("✓")[0].1).abs() < 8.0, msg="\{Repr((word("子代理"), word("✓")))}")
  // beside the mark, under it
  assert_true(word("后台进行中")[0].2 > mark[0].2, msg="under it")
  // Escape: gone
  t.key(@ui.key_escape)
  t.run_for(@kit.presence_out_ms)
  assert_eq(word("后台进行中").length(), 0)
}

///|
test "on a phone, its details' turns say its work after them, its head as it was; pressed, all of it from the foot" {
  new_run()
  let src = work_source("history-details")
  decide_src.val = Some(src)
  open_fixture_over("history-details", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  let turns = word("共工作 1 小时 12 分")
  assert_eq(turns.length(), 1)
  let mark = word("后台 4 · 2/6") + word("4 · 2/6") + word("4")
  assert_eq(mark.length(), 1)
  assert_true((mark[0].2 + mark[0].4 / 2.0 - turns[0].2 - turns[0].4 / 2.0).abs() < 2.0, msg="\{Repr((mark, turns))}")
  assert_eq(word("后台进行中").length(), 0)
  t.tap(mark[0].1 + 4.0, mark[0].2 + mark[0].4 / 2.0)
  t.run_for(@kit.presence_in_ms * 2.0)
  assert_eq(word("后台进行中").length(), 1)
  assert_eq(word("跑检查并提交").length(), 1)
  // from the foot: its lists low in the window
  assert_true(word("跑检查并提交")[0].2 > 422.0, msg="\{Repr(word("跑检查并提交"))}")
}

///|
test "the mark of an agent's work: at work's spokes before it while something runs in the background, none for a checklist alone" {
  let cycles = fn(running : Bool) -> Array[String] {
    new_run()
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
  assert_true(cycles(true).iter().any(fn(c) { c.has_prefix("800 ms") }), msg="\{Repr(cycles(true))}")
  assert_eq(cycles(false), [])
}

///|
test "the history's details on a phone: each tile's figure on a line as high as its box, over nothing of its name, at the default size of words and at 1.3" {
  guard corner_windows.search_by(w => w.0 == "phone") is Some(i) else { fail("no phone window in corner_windows") }
  for lang in ["zh", "en"] {
    for scale in [1.0, words_large_scale] {
      let t = screen_in("history-details", corner_windows[i], lang, font_scale=scale)
      let names = if lang == "zh" { ["费用估算", "缓存命中", "上下文"] } else { ["Est. cost", "Cache hits", "Context"] }
      for n in names {
        assert_true(t.find(n) is Some(_), msg="\{lang} at \{scale}: no tile named \{n}")
      }
      // (a figure drawn over its name: 「figure」 (…) and 「name」 (…) overlap)
      let over = t.squeeze_faults().filter(fn(f) { names.iter().any(fn(n) { f.contains(" and 「" + n) }) })
      assert_eq(over, [], msg="\{lang} at \{scale}: \{Repr(over)}")
    }
  }
}

///|
test "the history's tiles: a figure longer than six characters, on its smaller line, in a tile as high as a short one's beside it, the names level, at the default size of words and at 1.3" {
  // (a cost of nine characters, drawn smaller, beside a cache's of three)
  let card : Json = { "cost": "$1,234.56", "cache": { "text": "91%" } }
  for scale in [1.0, words_large_scale] {
    new_run()
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=300.0, platform=2)
    if scale != 1.0 {
      t.set_font_scale(scale)
    }
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      agent_tiles_node(root, fn() { Some(card) }, 14.0)
    })
    t.run_for(@ui.move_most_ms)
    let word = fn(s : String) {
      match t.words().search_by(fn(w) { w.0 == s }) {
        Some(i) => t.words()[i]
        None => ("", 0.0, 0.0, 0.0, 0.0, 0.0)
      }
    }
    let long = word("$1,234.56")
    let short = word("91%")
    let long_name = word(tr("android-chat.agent.cost"))
    let short_name = word(tr("android-chat.agent.cache"))
    for w in [long, short, long_name, short_name] {
      assert_true(w.4 > 0.0, msg="at \{scale}: \{Repr(t.words())}")
    }
    assert_true(long.4 < short.4, msg="at \{scale}: the long figure on the smaller line: \{Repr(long)} \{Repr(short)}")
    assert_eq(long_name.2, short_name.2, msg="at \{scale}: the names level: \{Repr(long_name)} \{Repr(short_name)}")
    assert_true(short.2 + short.4 <= short_name.2 + 1.0, msg="at \{scale}: \{Repr(short)} over \{Repr(short_name)}")
    assert_true(long.2 + long.4 <= long_name.2 + 1.0, msg="at \{scale}: \{Repr(long)} over \{Repr(long_name)}")
    assert_eq(t.squeeze_faults(), [], msg="at \{scale}: \{Repr(t.squeeze_faults())}")
  }
}

///|
/// The screens its panel opens on: (platform, wide). A phone's window (390 by 844, its history's details) with touch
/// and with keyboard and mouse, a sheet from the foot; a wide window (1200 by 800, the history beside the chat), a panel
/// beside the mark.
let aw_screens : Array[(Int, Bool)] = [(2, false), (0, false), (0, true)]

///|
/// A task of the made-up core's, begun `ago` before `now`.
fn aw_task(id : String, kind_words : String, words : String, ago : Double) -> (String, String, String, Double) {
  (id, kind_words, words, ago)
}

///|
/// What agent s-c1's card says as the test sets it: its tasks (id, kind's words, what it is, how long before the
/// core's now it began) and its checklist (what, status); its line and marks said of them as the core says them.
struct AwCard {
  tasks : @signals.Signal[Array[(String, String, String, Double)]]
  plan : @signals.Signal[Array[(String, String)]]
  /// whether the core has said the card (false: no card, as before it answers)
  answered : @signals.Signal[Bool]
}

///|
/// The four tasks and the checklist of six, two done, work_source's.
fn aw_card() -> AwCard {
  {
    tasks: @signals.signal([
      aw_task("a1", "子代理", "审阅 live.ts 的改动", 252_000.0),
      aw_task("b1", "命令", "pnpm test --watch", 95_000.0),
      aw_task("b2", "命令", "gh run watch 18820431", 31_000.0),
      aw_task("b3", "命令", "vite --config web/vite.demo.config.ts", 720_000.0),
    ]),
    plan: @signals.signal([
      ("读 claude.ts 里的 task 帧", "completed"),
      ("station 推送 tasks 和 plan", "completed"),
      ("core 的 agentCard 加上后台和清单", "in_progress"),
      ("web 和 mbui 画出来", "pending"),
      ("截图", "pending"),
      ("跑检查并提交", "pending"),
    ]),
    answered: @signals.signal(true),
  }
}

///|
/// The made-up core of `mode` whose agents' cards say what `card` holds now (views/brief.ts workOf's words).
fn aw_source(mode : String, card : AwCard) -> Source {
  let base = fixture(mode)
  {
    ..base,
    topic_read: fn(name, params) {
      let got = base.topic(name, params).get().snapshot()
      guard name == "agentCard" && got.value is Some(Object(was)) else { got }
      guard card.answered.get() else { { ..got, value: None } }
      let now = (base.now)()
      let tasks = card.tasks.get()
      let plan = card.plan.get()
      let done = plan.filter(fn(s) { s.1 == "completed" }).length()
      let under_way = match plan.iter().find_first(fn(s) { s.1 == "in_progress" }) {
        Some(s) => s.0
        None => ""
      }
      let n = tasks.length()
      let counts = [if n > 0 { "\{n}" } else { "" }, if plan.length() > 0 { "\{done}/\{plan.length()}" } else { "" }].filter(fn(s) { s != "" })
      let out = was.copy()
      out["tasks"] = Json::array(tasks.map(fn(t) {
        let kind = if t.1 == "子代理" { "agent" } else { "command" }
        { "id": Json::string(t.0), "kind": Json::string(kind), "text": Json::string(t.2), "kindText": Json::string(t.1), "since": Json::number(now - t.3) }
      }))
      out["plan"] = Json::array(plan.map(fn(s) { { "text": Json::string(s.0), "status": Json::string(s.1) } }))
      out["planText"] = Json::string(if plan.length() > 0 { "已完成 \{done}/\{plan.length()}" } else { "" })
      let line = [if n > 0 { "后台 \{n}" } else { "" }, if plan.length() > 0 { "清单 \{done}/\{plan.length()}" + (if under_way != "" { "：" + under_way } else { "" }) } else { "" }].filter(fn(s) { s != "" })
      out["workLine"] = Json::string(line.join(" · "))
      out["workMark"] = Json::string(if counts.is_empty() { "" } else if n > 0 { "后台 " + counts.join(" · ") } else { counts.join(" · ") })
      out["workMarkShort"] = Json::string(counts.join(" · "))
      out["workMarkCount"] = Json::string(if n > 0 { "\{n}" } else if plan.length() > 0 { "\{done}/\{plan.length()}" } else { "" })
      { ..got, value: Some(Json::object(out)) }
    },
  }
}

///|
/// The history (beside the chat on a wide window, its details on a phone's) of agent s-c1 on `platform`, its card as
/// `card` says, words at `scale`; its mark at rest.
fn aw_tester(card : AwCard, platform~ : Int, wide~ : Bool, scale? : Double = 1.0) -> @ui.Tester {
  new_run()
  @sf.presenters_reset()
  let mode = if wide { "chat-history-side" } else { "history-details" }
  let src = aw_source(mode, card)
  decide_src.val = Some(src)
  open_fixture_over(mode, src)
  let (w, h) = if wide { (1200.0, 800.0) } else { (390.0, 844.0) }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  if scale != 1.0 {
    t.set_font_scale(scale)
  }
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Words `s` drawn and seen.
fn aw_word(t : @ui.Tester, s : String) -> Array[(String, Double, Double, Double, Double, Double)] {
  t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 })
}

///|
/// Its mark, whichever form shows: (x, y, w, h).
fn aw_mark(t : @ui.Tester, at : String) -> (Double, Double, Double, Double) raise {
  for s in ["后台 4 · 2/6", "4 · 2/6", "4"] {
    match aw_word(t, s) {
      [w, ..] => return (w.1, w.2, w.3, w.4)
      _ => ()
    }
  }
  fail("\{at}: no mark")
}

///|
/// Its mark pressed; at the frame its panel opened in (`rest`: at rest).
fn aw_opened(t : @ui.Tester, at : String, rest? : Bool = true) -> Unit raise {
  let m = aw_mark(t, at)
  t.tap(m.0 + 4.0, m.1 + m.3 / 2.0)
  if rest {
    t.run_for(@ui.move_most_ms)
  }
}

///|
/// A fault said as `t.audit()` says it, without which node of the old view's it names (that numbering moves as a
/// panel opens over it).
fn aw_plain(f : String) -> String {
  let out = StringBuilder()
  let cs = f.to_array()
  let mut i = 0
  while i < cs.length() {
    // (「, node 12」 left out)
    if i + 7 < cs.length() && cs[i] == ',' && cs[i + 1] == ' ' && cs[i + 2] == 'n' && cs[i + 3] == 'o' && cs[i + 4] == 'd' && cs[i + 5] == 'e' && cs[i + 6] == ' ' && cs[i + 7] >= '0' && cs[i + 7] <= '9' {
      i += 7
      while i < cs.length() && cs[i] >= '0' && cs[i] <= '9' {
        i += 1
      }
      continue
    }
    out.write_char(cs[i])
    i += 1
  }
  out.to_string()
}

///|
/// What the audit finds now that it did not before (`before`, the window's as it was before the panel opened), at
/// `at`: none but the old panel's own, which this left as they were, all three while its checklist shows (`open`), none
/// once it is gone. Those, as the old panel (base, m2-11) said them:
///   words "✓" 13/400 at 26,696 16×18 (in an old view made at mbui/src/view/view.mbt:10268) by "✓": #2f8f5b on #f7f7f7 3.78:1, under 4.5
///   words "✓" 12/400 at 854,372 16×18 (…) by "✓": #2f8f5b on #ffffff 4.04:1, under 4.5 (a wide window's)
///   words "›" 13/400 at 26,736 16×18 (…) by "›": #cc5a34 on #f7f7f7 3.87:1, under 4.5
/// (its checklist's marks of what is done and what is under way, the green and the accent on its ground: their colours
/// are the theme's, not this panel's to change). The old one's other, at the words set to 1.3, a task's kind cut short
/// (「子代理」: its words cut to 1 characters), is not left: its chip is whole.
fn aw_audited(t : @ui.Tester, before : Array[String], at : String, open? : Bool = true) -> Unit raise {
  let was = before.map(aw_plain)
  let added = t.audit().filter(fn(f) { !was.contains(aw_plain(f)) })
  let old_own = fn(f : String) {
    f.contains("under 4.5") &&
    ((f.has_prefix("words \"✓\"") && f.contains("#2f8f5b on")) || (f.has_prefix("words \"›\"") && f.contains("#cc5a34 on")))
  }
  assert_eq(added.filter(fn(f) { !old_own(f) }), [], msg=at)
  assert_eq(added.filter(old_own).length(), if open { 3 } else { 0 }, msg="\{at}: \{Repr(added)}")
}

///|
/// What `faults` (`t.audit()`'s) say of a press's room the history's details' links (sfdesk/history.mbt's
/// `wh_link_node`) and its line of the agent's work (sfpages/agent_work.mbt's mark) are short of: lines of words 18
/// high (22 at 1.3) two apart, each pressed in 32 (34) where a keyboard and mouse's is 36. Crowded as drawn, by either
/// way of measuring it (the coordinator of the migration, 2026-11-12: known, its count held, only to fall); said
/// exactly `history` and `work` times, so that once the rows are set further apart this is brought down.
fn aw_crowded(faults : Array[String], at : String, history : Int, work : Int) -> Unit raise {
  let room = faults.filter(fn(f) { f.has_prefix("room: ") })
  let of = fn(place : String) { room.filter(fn(f) { f.contains(place) }) }
  let h = of("sfdesk/history.mbt:215")
  let w = of("sfpages/agent_work.mbt:361")
  assert_eq(h.length(), history, msg="\{at}: \{Repr(h)}")
  assert_eq(w.length(), work, msg="\{at}: \{Repr(w)}")
}

///|
test "its panel on each screen, at the default size of words and at 1.3: what runs in the background under its head and how many, a task a row (its kind's chip whole, what it is, how long it has run), then the checklist in its order; nothing more for the audit than the old panel's own" {
  for screen in aw_screens {
    for scale in [1.0, words_large_scale] {
      let (platform, wide) = screen
      let at = "platform \{platform} wide \{wide} at \{scale}"
      let t = aw_tester(aw_card(), platform~, wide~, scale~)
      let before = t.audit()
      // (on a wide window at 1.3, 「Profile 详情」 108×34 and 「后台 4 · 2/6」 110×34 stay under 36; at 1, they clear; known, see aw_crowded)
      if wide && at.has_suffix("at 1.3") {
        aw_crowded(before, at, 1, 1)
      } else {
        aw_crowded(before, at, 0, 0)
      }
      let mark = aw_mark(t, at)
      aw_opened(t, at)
      let one = fn(s : String) raise {
        let w = aw_word(t, s)
        assert_eq(w.length(), 1, msg="\{at}: \{s} \{Repr(w)}")
        w[0]
      }
      let head = one("后台进行中")
      // (its head's count on its line, after it)
      assert_true(aw_word(t, "4").iter().any(fn(w) { (w.2 - head.2).abs() < 0.5 && w.1 > head.1 + head.3 }), msg=at)
      // a task a row under the head, its kind's chip, what it is, its clock on its line; the chips whole
      let rows = [
        ("审阅 live.ts 的改动", "4m 12s"),
        ("pnpm test --watch", "1m 35s"),
        ("gh run watch 18820431", "31s"),
        ("vite --config web/vite.demo.config.ts", "12m"),
      ]
      let mut y = head.2
      for r in rows {
        let w = one(r.0)
        let c = one(r.1)
        assert_true(w.2 > y, msg="\{at}: \{r.0} under what is before it")
        assert_true((c.2 - w.2).abs() < 0.5 && c.1 >= w.1 + w.3, msg="\{at}: \{r.1} at \{r.0}'s end")
        y = w.2
      }
      assert_eq(aw_word(t, "命令").length(), 3, msg=at)
      let kind = one("子代理")
      assert_true(one("审阅 live.ts 的改动").1 >= kind.1 + kind.3, msg="\{at}: the kind's chip before what it is")
      assert_eq(t.squeeze_faults().filter(fn(f) { f.contains("子代理") || f.contains("命令") }), [], msg=at)
      // its checklist under them, in its order
      let plan = one("清单")
      assert_true(plan.2 > y, msg="\{at}: the checklist under the tasks")
      assert_true(aw_word(t, "已完成 2/6").length() == 1, msg=at)
      for s in ["读 claude.ts 里的 task 帧", "station 推送 tasks 和 plan", "core 的 agentCard 加上后台和清单", "web 和 mbui 画出来", "截图", "跑检查并提交"] {
        let w = one(s)
        assert_true(w.2 > y, msg="\{at}: \{s} in its order")
        y = w.2
      }
      assert_eq(aw_word(t, "✓").length(), 2, msg=at)
      assert_eq(aw_word(t, "›").length(), 1, msg=at)
      // beside its mark on a wide window (under it), from the foot on a phone's
      if wide {
        assert_true(head.2 > mark.1 + mark.3, msg="\{at}: under its mark")
      } else {
        assert_true(one("跑检查并提交").2 > 422.0, msg="\{at}: from the foot")
      }
      aw_audited(t, before, at)
      t.key(@ui.key_escape)
      t.run_for(@ui.move_most_ms)
      assert_false(@sf.presenter_visible(), msg="\{at}: Escape closed it")
      aw_audited(t, before, at, open=false)
    }
  }
}

///|
test "its panel as the card changes while it is open: a task done goes, an item added comes under the last, its count with it; the tasks all done, the checklist alone, the panel open" {
  for screen in aw_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let card = aw_card()
    let t = aw_tester(card, platform~, wide~)
    let before = t.audit()
    aw_opened(t, at)
    card.tasks.set(card.tasks.get().filter(fn(x) { x.0 != "b1" }))
    card.plan.set(card.plan.get() + [("再截一次图", "pending")])
    t.run_for(@ui.move_most_ms)
    assert_eq(aw_word(t, "pnpm test --watch").length(), 0, msg=at)
    assert_eq(aw_word(t, "1m 35s").length(), 0, msg=at)
    for s in ["审阅 live.ts 的改动", "gh run watch 18820431", "vite --config web/vite.demo.config.ts", "跑检查并提交", "再截一次图"] {
      assert_eq(aw_word(t, s).length(), 1, msg="\{at}: \{s}")
    }
    let head = aw_word(t, "后台进行中")[0]
    assert_true(aw_word(t, "3").iter().any(fn(w) { (w.2 - head.2).abs() < 0.5 }), msg="\{at}: 3 on its head's line")
    assert_eq(aw_word(t, "已完成 2/7").length(), 1, msg=at)
    assert_true(aw_word(t, "再截一次图")[0].2 > aw_word(t, "跑检查并提交")[0].2, msg="\{at}: the new item last")
    // the tasks all done: their group goes, the checklist stays, the panel too
    card.tasks.set([])
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenter_visible(), msg="\{at}: still open")
    assert_eq(aw_word(t, "后台进行中").length(), 0, msg=at)
    assert_eq(aw_word(t, "审阅 live.ts 的改动").length(), 0, msg=at)
    assert_eq(aw_word(t, "清单").length(), 1, msg=at)
    assert_eq(aw_word(t, "再截一次图").length(), 1, msg=at)
    aw_audited(t, before, at)
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenter_visible(), msg=at)
  }
}

///|
test "its panel closes as the card comes to say neither (none left in the background, no checklist), showing what it showed till it is gone; on a phone's window its sheet and scrim go with it" {
  for screen in aw_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let card = aw_card()
    let t = aw_tester(card, platform~, wide~)
    let before = t.audit()
    aw_opened(t, at)
    let seen = ["后台进行中", "审阅 live.ts 的改动", "清单", "跑检查并提交"]
    let places = fn() { seen.map(fn(s) { t.words().iter().find_first(fn(w) { w.0 == s && w.5 > 0.0 }).map(fn(w) { w.2 }) }) }
    let was = places()
    // (both at once, as the core says the card)
    @signals.start_batch()
    card.tasks.set([])
    card.plan.set([])
    @signals.end_batch()
    let mut n = 0
    while @sf.presenter_visible() && n < 120 {
      t.frame()
      // (on each frame of its way out all of it, each where it was from the first, or none)
      let now = places()
      let drawn = now.filter(fn(p) { p is Some(_) }).length()
      assert_true(drawn == 0 || drawn == seen.length(), msg="\{at}: frame \{n}: \{drawn} of \{Repr(seen)}")
      if drawn > 0 && !wide {
        // (a sheet goes down whole)
        for i in 1..<now.length() {
          let d = now[i].unwrap() - now[0].unwrap()
          let d0 = was[i].unwrap() - was[0].unwrap()
          assert_true((d - d0).abs() <= 0.01, msg="\{at}: frame \{n}: \{seen[i]} \{d} under \{seen[0]}, \{d0} before")
        }
      }
      n += 1
    }
    assert_false(@sf.presenter_visible(), msg="\{at}: gone")
    t.run_for(@ui.move_most_ms)
    for s in seen {
      assert_eq(t.words().filter(fn(w) { w.0 == s && w.5 > 0.0 }).length(), 0, msg="\{at}: \{s}")
    }
    if !wide {
      assert_eq(t.drawn_glass().filter(fn(g) { g.3 > 100.0 }), [], msg="\{at}: its sheet")
      assert_eq(scrim_drawn(t), [], msg="\{at}: its scrim")
    }
    aw_audited(t, before, at, open=false)
  }
}

///|
test "its panel while the core says no card, on a phone's window: open, nothing in it, as before; said again, all of it" {
  // (on a phone's window alone: on a wide window, as the card comes to be none, the history beside the chat steps 3.77 in
  // a frame at y 97 to 101 (3.768 at 60 a second, 3.896 at 120), however long after the panel opened (m2-30, m2-31), on
  // the old panel's base the same (m2-26): the history's, not this panel's, and told to motion's line; the wide window
  // comes back here with its mend. As the panel opens the card is always there: the mark is only while the card says
  // work, and the panel reads what the mark does)
  for screen in aw_screens.filter(fn(s) { !s.1 }) {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let card = aw_card()
    let t = aw_tester(card, platform~, wide~)
    let before = t.audit()
    aw_opened(t, at)
    card.answered.set(false)
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenter_visible(), msg="\{at}: open")
    assert_eq(aw_word(t, "后台进行中").length(), 0, msg=at)
    assert_eq(aw_word(t, "清单").length(), 0, msg=at)
    card.answered.set(true)
    t.run_for(@ui.move_most_ms)
    assert_eq(aw_word(t, "后台进行中").length(), 1, msg=at)
    assert_eq(aw_word(t, "跑检查并提交").length(), 1, msg=at)
    aw_audited(t, before, at)
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenter_visible(), msg=at)
  }
}

///|
/// What a screen reader says of the mark with the focus: a button named by its line.
let aw_mark_said : String = "Button \"" + work_line + "\""

///|
test "its panel opened by a pointer and closed by Escape: the focus on its mark, what opened it (the presenters', #5181), on each screen" {
  for screen in aw_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = aw_tester(aw_card(), platform~, wide~)
    let before = t.audit()
    aw_opened(t, at)
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenter_visible(), msg=at)
    assert_true(t.focus_said().has_prefix(aw_mark_said), msg="\{at}: \{t.focus_said()}")
    aw_audited(t, before, at, open=false)
  }
}

///|
test "its panel on a wide window by the keyboard: the mark with the focus, Enter opens it, Escape closes it, the focus still on the mark, Enter opens it again" {
  let t = aw_tester(aw_card(), platform=0, wide=true)
  let before = t.audit()
  let mut n = 0
  while !t.focus_said().has_prefix(aw_mark_said) && n < 80 {
    t.key(@ui.key_tab)
    n += 1
  }
  assert_true(t.focus_said().has_prefix(aw_mark_said), msg=t.focus_said())
  for round in 0..<2 {
    t.key(@ui.key_code_enter)
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenter_visible(), msg="round \{round}: Enter opened it")
    assert_eq(aw_word(t, "后台进行中").length(), 1, msg="round \{round}")
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenter_visible(), msg="round \{round}: Escape closed it")
    assert_true(t.focus_said().has_prefix(aw_mark_said), msg="round \{round}: \{t.focus_said()}")
  }
  aw_audited(t, before, "keyboard", open=false)
}

///|
test "the history's tiles: 6-char numbers ($1,911, 430.5K) on a 360dp row shrink to fit cleanly with names level at 1.0x and 1.3x" {
  let card : Json = {
    "cost": "$1,911",
    "cache": { "text": "99%" },
    "context": { "percent": 0, "text": "430.5K", "unknown": true },
  }
  for scale in [1.0, words_large_scale] {
    new_run()
    let t = @ui.Tester::new(
      fn(_) {  },
      tree=fn(root) {
        root.padding(Is((24.0, 24.0, 24.0, 24.0))) |> ignore
        agent_tiles_node(root, fn() { Some(card) }, 14.0)
      },
      w=360.0,
      h=400.0,
      platform=2,
      scale~,
    )
    assert_eq(t.squeeze_faults(), [], msg="scale=\{scale}")
    let words = t.words()
    for want in ["$1,911", "99%", "430.5K"] {
      assert_true(words.any(fn(w) { w.0 == want && w.5 > 0.5 }), msg="scale=\{scale}: missing \{want}")
    }
    let name_y = fn(s : String) {
      match words.iter().find_first(fn(w) { w.0 == s && w.5 > 0.5 }) {
        Some(w) => w.2
        None => -1.0
      }
    }
    assert_eq(name_y("费用估算"), name_y("缓存命中"), msg="scale=\{scale}: names not level: words=\{Repr(words)}")
    assert_eq(name_y("缓存命中"), name_y("上下文"), msg="scale=\{scale}: names not level: words=\{Repr(words)}")
  }
}
