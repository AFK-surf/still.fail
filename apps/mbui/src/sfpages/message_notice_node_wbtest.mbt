// What still.fail said as nodes (message_notice_node.mbt's notice_said_node) set beside the old view's (message.mbt
// message_row: system_notice) on the same fixture: closed on one line and open, a failure in red with what failed said
// of it, · 安装 and · 上报 (and each under way), 取消 while its agent waits to retry and 重试 on a failed turn (and under
// way, and read only), a chat's run changed (whole, what changed, open), a profile's link, a chat opened; wide and
// narrow, at 1.3; and what each press asks of the core.

///|
/// One of the fixture's notices (seq 9, ts9): `words` (its Markdown's tree, `md`), a failure (`failed`), what failed
/// said (`detail`); about a profile (`link` where its link starts); a runtime the station lacks (`install`); reportable;
/// its agent waiting to retry (`retry`), or its failed turn to try again (`again`); a chat's run changed (`short`, `lines`,
/// `sides`).
fn nt_msg(
  words? : String = "Willow 的 codex 这一轮超时了，已经停下",
  md? : Json? = None,
  failed? : Bool = false,
  detail? : String = "",
  link? : Int = -1,
  install? : Bool = false,
  reportable? : Bool = false,
  retry? : Bool = false,
  again? : Bool = false,
  short? : String = "",
  lines? : Array[String] = [],
  sides? : Json? = None,
) -> Message {
  let n : Map[String, Json] = { "failed": Json::boolean(failed), "words": Json::string(words) }
  // (as the core reads its words: one paragraph, where it says no other)
  n["md"] = md.unwrap_or([["p", [[0, words.length()]]]])
  if detail != "" {
    n["detail"] = Json::string(detail)
  }
  if link >= 0 {
    n["linkAt"] = Json::number(link.to_double())
  }
  if retry {
    n["retrySession"] = "s-c1"
  }
  if again {
    n["againSession"] = "s-c1"
  }
  if short != "" {
    n["short"] = Json::string(short)
  }
  if lines.length() > 0 {
    n["lines"] = Json::array(lines.map(fn(l) { Json::string(l) }))
  }
  if sides is Some(d) {
    n["sides"] = d
  }
  @sfbase.message_of({
    "seq": 9,
    "thread": 7,
    "ts": "ts9",
    "authorKind": "ember",
    "system": true,
    "author": "still.fail",
    "text": Json::string(words),
    "by": { "name": "still.fail" },
    "profile": if link >= 0 { "p1" } else { "" },
    "install": if install {
      { "runtime": "codex", "state": "missing", "title": "Willow 上没有 codex", "action": "安装" }
    } else {
      Json::null()
    },
    "reportable": reportable,
    "notice": Json::object(n),
    "chats": [{ "href": "https://app.still.fail/o/ws1/st1/s-c2", "title": "共享调试：配对后连不上" }],
    "createdAt": 9,
    "time": @sffixture.ago("1 分钟前", "2026-11-11 21:07"),
  })
}

///|
/// The core's tree of a notice that a chat was opened (sessions/opened.ts sayOpened): its link to the chat.
fn nt_opened() -> Message {
  let link = "https://app.still.fail/o/ws1/st1/s-c2"
  let words = "已创建对话：[共享调试：配对后连不上](\{link})"
  nt_msg(words~, md=Some([["p", [[0, 6], ["a", [[7, 18]], { "href": Json::string(link), "to": { "chat": true } }]]]]))
}

///|
/// The core's doing with `call` (session.cancelRetry, chat.report, software.update) on the fixture's notice.
fn nt_doing(call : String) -> Json {
  let params : Json = match call {
    "session.cancelRetry" | "session.retry" => { "station": "ws1/st1", "key": "s-c1" }
    "software.update" => { "station": "ws1/st1", "id": "codex" }
    _ => { "station": "ws1/st1", "thread": "7", "seq": "9" }
  }
  { "doing": [{ "call": Json::string(call), "stage": "running", "params": params }] }
}

///|
/// The fixture's source, its `doing` as `doing` says, its calls kept in `calls` (answered `answer`), read only where
/// `read_only`.
fn nt_src(doing : Json?, calls : Array[(String, Json)], answer? : Json = Json::object({}), read_only? : Bool = false) -> Source {
  let base = @sffixture.fixture("history")
  {
    ..base,
    read_only,
    topic_read: fn(name, params) {
      if name == "doing" {
        { value: Some(doing.unwrap_or({ "doing": [] })), error: None, version: 1 }
      } else {
        (base.topic_read)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push((name, params))
      done(Ok(answer))
    },
  }
}

///|
/// The fixture's chat's view (offline where `offline`).
fn nt_view(offline? : Bool = false) -> ChatView {
  @sfbase.chat_view_made({
    "title": "发布",
    "messages": [],
    "offline": offline,
    "agents": [{ "session": { "key": "s-c1" } }],
  })
}

///|
/// Notice `m` as the old view draws it in its row (message_row in row_box), in a chat's list (its 取消 shown there
/// alone: a list of the test's own, nothing gone to), `w` wide.
fn nt_old(w : Double, src : Source, m : Message, view? : ChatView = nt_view(), platform? : Int = 0) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  absolute_times.set(false)
  notices_open.clear()
  let rk = "nt-list"
  let here : MessageHere = {
    station: "ws1/st1",
    session: "s1",
    view,
    go: None,
    inline: w <= chat_narrow_w,
    gutter: 0.0,
    list: Some({ rk, turns: @sfbase.turns_of(rk), emits: @sfbase.emits_of(rk), flight: None }),
    core: None,
  }
  @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        c.box(style=head_frame, fn() { row_box(c, row_side(w), 0.0, fn() { message_row(c, src, here, m) }) |> ignore })
        |> ignore
      })
    },
    w~,
    h=420.0,
    platform~,
  )
}

///|
/// The same notice as the nodes draw it in its row (notice_said_node), `m` as it changes, kept open in `opened`; what
/// is presented over it drawn; `pill`, the pill's node and key as they are told.
fn nt_new(
  w : Double,
  src : Source,
  m : () -> Message,
  opened? : @sf.LiveMap[String, Bool] = @sf.LiveMap::new(),
  copied? : @sf.LiveMap[String, Double] = @sf.LiveMap::new(),
  view? : ChatView = nt_view(),
  platform? : Int = 0,
  pill? : Ref[(@view.View, String)?] = Ref(None),
) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  absolute_times.set(false)
  @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let tips = @sf.TipLayer::new(fn() { Some(root) })
      let here : MessageNodeHere = {
        station: "ws1/st1",
        session: "s1",
        view: fn() { view },
        width: fn() { w },
        tips,
        stint: fn() { 0 },
        jump: None,
      }
      root.box(fn(f) {
        @sf.style_node(f, fn() { head_frame })
        notice_said_node(f, src, here, "m:ts9", fn() { row_side(w) }, fn() { 0.0 }, m, opened, copied, pill_over=fn(
          p,
          k,
        ) {
          pill.val = Some((p, k))
        })
        |> ignore
      })
      |> ignore
      @sf.presented_nodes(root)
    },
    w~,
    h=420.0,
    platform~,
  )
}

///|
/// The fixture's states by name: the notice, what the core's doing says, whether it is opened, the chat read only.
fn nt_cases() -> Array[(String, Message, Json?, Bool)] {
  let detail = "Error: request timed out after 600s\n  at Session.run (session.ts:412)"
  let run = nt_msg(
    words="Claude Code · Sonnet 5.5 · 中 · 标准 → Codex · GPT-6 Astra · 高 · Fast",
    short="换成 Codex · GPT-6 Astra · 高 · Fast",
    lines=["之前：Claude Code · Sonnet 5.5 · 中 · 标准 · 自动 · lin@example.com", "现在：Codex · GPT-6 Astra · 高 · Fast · 自动 · lin@example.com"],
  )
  let sided = nt_msg(
    words="Claude Code · Opus 5.5 → Codex · GPT-6",
    short="换成 Codex · GPT-6",
    lines=["之前：Claude Code · Opus 5.5 · 高 · 自动 · lin@example.com", "现在：Codex · GPT-6 · 高 · 自动 · lin@example.com"],
    sides=Some({
      "was": "Claude Code · Opus 5.5",
      "now": "Codex · GPT-6",
      "to": "换成",
      "wasMaker": "anthropic",
      "wasRuntime": "claude",
      "nowMaker": "openai",
      "nowRuntime": "codex",
    }),
  )
  let report_long = "本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发出的消息），请留意"
  [
    ("closed", nt_msg(), None, false),
    ("open", nt_msg(), None, true),
    ("failed", nt_msg(failed=true, detail~), None, false),
    ("failed open", nt_msg(failed=true, detail~), None, true),
    ("install", nt_msg(install=true), None, false),
    ("installing", nt_msg(install=true), Some(nt_doing("software.update")), false),
    ("report", nt_msg(failed=true, reportable=true), None, false),
    ("report long", nt_msg(words=report_long, failed=true, reportable=true), None, false),
    ("reporting", nt_msg(failed=true, reportable=true), Some(nt_doing("chat.report")), false),
    ("retry", nt_msg(words="模型满载，自动重试，与额度无关", failed=true, retry=true), None, false),
    ("cancelling", nt_msg(words="模型满载，自动重试，与额度无关", failed=true, retry=true), Some(nt_doing("session.cancelRetry")), false),
    // (the model's failure's words: the connection's, longer, are cut otherwise by the nodes than by the old view at
    // 390 and 1.3, as 取消's are with words as long, with or without either)
    ("again", nt_msg(words="模型服务出错，回复即可重试", failed=true, again=true), None, false),
    ("trying again", nt_msg(words="模型服务出错，回复即可重试", failed=true, again=true), Some(nt_doing("session.retry")), false),
    ("run changed", run, None, false),
    ("run changed open", run, None, true),
    ("run changed sides", sided, None, false),
    ("run changed sides open", sided, None, true),
    ("profile", nt_msg(words="Willow 上 codex 的登录已失效：请在设置里重新登录", failed=true, link=22), None, false),
    ("profile open", nt_msg(words="Willow 上 codex 的登录已失效：请在设置里重新登录", failed=true, link=22), None, true),
    ("chat opened", nt_opened(), None, false),
  ]
}

///|
/// The fixture's notice's pill pressed open (both views): at the start of its words, the first drawn.
fn nt_open(t : @ui.Tester) -> Unit {
  let (_, x, y, _, h, _) = match t.words().get(0) {
    Some(w) => w
    None => @halt.saying("no notice's words drawn")
  }
  t.tap(x + 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
}

///|
/// What `t.audit()` says of a notice's row, but what the old notice's row was laid out with, said exactly so many times
/// each (xfer/ra5-notice-rooms.md: the old view checks no press's room; all of it to go before the row is in the app,
/// its way the owner's to say, the coordinator 2026-11-11), one more or one fewer a fault:
/// - `time`: its time under the open pill, 18 high, the pill a neighbour 4 over it that takes presses: their rooms
///   parted between them, 29 (a keyboard and mouse's 36);
/// - `copy`: 复制 at the open pill's foot, 22 high, in the pill that takes presses (opening and closing it), its room
///   cut at the pill's edge: 35;
/// - `act`: · 安装 or · 上报 in the pill, 22 high, cut to the pill's 34;
/// - `dot`: the · before them, the ink at 60% the old one's (3.95:1 on the pill, 3.05:1 failed), the product's colour.
fn nt_audit(t : @ui.Tester, time : Int, copy : Int, act : Int, dot : Int) -> Array[String] {
  let room = fn(f : String, words : Array[String], file : String) {
    words.iter().any(fn(w) { f.has_prefix("room: 「" + w + "」") }) &&
    f.contains("stillfail/src/sfpages/" + file) &&
    f.contains("to be pressed in, under 36")
  }
  let kinds : Array[(String, (String) -> Bool, Int)] = [
    ("time", fn(f) { room(f, ["1 分钟前"], "message_head_node.mbt") }, time),
    ("copy", fn(f) { room(f, ["复制"], "message_notice_node.mbt") }, copy),
    ("act", fn(f) { room(f, ["安装", "上报"], "message_notice_node.mbt") }, act),
    (
      "dot",
      fn(f) { f.has_prefix("words \"·\"") && f.contains("stillfail/src/sfpages/message_notice_node.mbt") && f.contains(":1, under 4.5") },
      dot,
    ),
  ]
  let all = t.audit()
  let faults = all.filter(fn(f) { !kinds.iter().any(fn(k) { (k.1)(f) }) })
  for k in kinds {
    let n = all.filter(k.1).length()
    if n != k.2 {
      faults.push("\{k.0} said \{n} times, \{k.2} known: " + all.filter(k.1).join(" | "))
    }
  }
  faults
}

///|
/// How many times each of nt_audit's is said of case `c` drawn (open or not) at the system's size of words `scale`:
/// time, copy, act, dot. At 1.3 复制 is 25 high and the pill 40.6: those in it have their room.
fn nt_known(c : (String, Message, Json?, Bool), scale : Double) -> (Int, Int, Int, Int) {
  let (_, m, doing, open) = c
  let small = scale == 1.0
  let ends = (m.install is Some(_) || m.reportable) && m.notice_short == "" && m.notice_lines.is_empty()
  (
    if open { 1 } else { 0 },
    if small && open && m.notice_detail != "" { 1 } else { 0 },
    if small && ends && doing is None { 1 } else { 0 },
    if ends { 1 } else { 0 },
  )
}

///|
/// What a Tester draws (head_drawn's), each place and size to a hundredth (the old view's sums leave tails the nodes'
/// do not: 31.200000000000003 against 31.2); where `under` (x, y), the underline drawn from x at y set `by` lower first.
fn nt_drawn(t : @ui.Tester, under? : (Double, Double, Double)? = None) -> String {
  let r = fn(v : Double) { (v * 100.0).round() / 100.0 }
  // (but what the old view's row left out, 换成 while what a run ran on is there: words of no size, never drawn)
  t.words().filter(fn(w) { w.3 > 0.0 || w.4 > 0.0 }).map(fn(w) { "\{w.0}@\{r(w.1)},\{r(w.2)} \{r(w.3)}x\{r(w.4)} a\{w.5}" }).join("\n") +
  "\n" +
  t
  .drawn_rects()
  .map(fn(d) {
    let y = match under {
      Some((x, at, by)) if r(d.0) == r(x) && r(d.1) == r(at) && d.3 <= 1.0 => d.1 + by
      _ => d.1
    }
    "\{r(d.0)},\{r(y)} \{r(d.2)}x\{r(d.3)} \{d.4}"
  })
  .join("\n")
}

///|
/// Where the old view underlines notice `m`'s · 安装 or · 上报 at the system's size of words `scale` (its x, its y), if
/// it ends in one and that is not the default size of words: the nodes' 0.1 lower (the old view's rich line puts it
/// 18.9 under its words' top where they stand at 25.6, the nodes' runs 19, as they do for the profile's link at 22).
fn nt_under(t : @ui.Tester, m : Message, scale : Double) -> (Double, Double, Double)? {
  guard scale != 1.0 else { return None }
  let act = match m.install {
    Some(_) => "安装"
    None => if m.reportable { "上报" } else { "" }
  }
  guard act != "" && m.notice_short == "" else { return None }
  let words = t.words().iter().find_first(fn(w) { w.0 == act })
  let line = t.drawn_rects().iter().find_first(fn(d) { d.3 <= 1.0 && words.map(fn(w) { (d.0 - w.1).abs() < 0.01 }).unwrap_or(false) })
  match line {
    Some(d) => Some((d.0, d.1, 0.1))
    None => None
  }
}

///|
test "what still.fail said, made once as nodes, is drawn as the old view drew it: closed and open, failed, · 安装, · 上报, 取消, a run changed, a profile's link, a chat opened; wide and narrow, at 1.3" {
  for c in nt_cases() {
    for (w, scale) in [(760.0, 1.0), (390.0, 1.0), (390.0, 1.3)] {
      let at = "\{c.0} at \{w}, \{scale}"
      let old = nt_old(w, nt_src(c.2, []), c.1)
      old.set_font_scale(scale)
      old.run_for(@ui.move_most_ms)
      if c.3 {
        nt_open(old)
      }
      let was = nt_drawn(old, under=nt_under(old, c.1, scale))
      let t = nt_new(w, nt_src(c.2, []), fn() { c.1 })
      t.set_font_scale(scale)
      t.run_for(@ui.move_most_ms)
      if c.3 {
        nt_open(t)
      }
      assert_eq(nt_drawn(t), was, msg=at)
      let (time, copy, act, dot) = nt_known(c, scale)
      let faults = nt_audit(t, time, copy, act, dot)
      assert_true(faults.is_empty(), msg=at + ": " + faults.join(" | "))
    }
  }
}

///|
test "pressed, a notice opens, kept open by its message: all its words, its time under it; pressed again, closed" {
  let opened : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()
  let m = nt_msg()
  let t = nt_new(760.0, nt_src(None, []), fn() { m }, opened~)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("1 分钟前") is None, msg="closed: no time")
  nt_open(t)
  assert_eq(opened.get("ts9"), Some(true))
  assert_true(t.find("1 分钟前") is Some(_), msg="open: its time under it")
  nt_open(t)
  assert_eq(opened.get("ts9"), Some(false))
  assert_true(t.find("1 分钟前") is None, msg="closed again")
  let faults = nt_audit(t, 0, 0, 0, 0)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "what failed said, copied: 已复制 till copied_ms from the press, then 复制; the notice stays open" {
  let opened : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()
  let copied : @sf.LiveMap[String, Double] = @sf.LiveMap::new()
  opened["ts9"] = true
  let detail = "Error: request timed out after 600s"
  let t = nt_new(760.0, nt_src(None, []), fn() { nt_msg(failed=true, detail~) }, opened~, copied~)
  t.run_for(@ui.move_most_ms)
  t.tap_run("复制")
  t.frame()
  assert_eq(t.clipboard(), detail)
  assert_true(t.find("已复制") is Some(_), msg="said copied")
  assert_eq(opened.get("ts9"), Some(true), msg="the press its own, the pill not closed")
  assert_true(copied.get("ts9") is Some(_), msg="kept by its message")
  t.run_for(@sf.copied_ms)
  assert_true(t.find("已复制") is None, msg="no more after copied_ms")
  assert_true(t.find("复制") is Some(_))
  let faults = nt_audit(t, 1, 1, 0, 0)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "· 安装 installs the runtime (software.update), not offered while it installs; the pill not opened" {
  let calls : Array[(String, Json)] = []
  let opened : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()
  let t = nt_new(760.0, nt_src(None, calls), fn() { nt_msg(install=true) }, opened~)
  t.run_for(@ui.move_most_ms)
  t.tap_run("安装")
  t.frame()
  assert_eq(calls.filter(fn(c) { c.0 == "software.update" }).length(), 1)
  assert_eq(opened.get("ts9"), None, msg="the pill not opened")
  let busy : Array[(String, Json)] = []
  let t = nt_new(760.0, nt_src(Some(nt_doing("software.update")), busy), fn() { nt_msg(install=true) })
  t.run_for(@ui.move_most_ms)
  t.tap_run("安装")
  t.run_for(@ui.move_most_ms)
  assert_eq(busy.filter(fn(c) { c.0 == "software.update" }).length(), 0, msg="not while it installs")
  // (not offered: a press there is the pill's, which opens; closed again)
  assert_true(t.find("1 分钟前") is Some(_), msg="the pill's press")
  nt_open(t)
  let faults = nt_audit(t, 0, 0, 0, 1)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "· 上报 asks first, then reports the failure (chat.report) and says what it was filed as" {
  @sf.presenters_reset()
  let calls : Array[(String, Json)] = []
  let t = nt_new(760.0, nt_src(None, calls, answer={ "number": 42, "duplicate": false }), fn() {
    nt_msg(failed=true, reportable=true)
  })
  t.run_for(@ui.move_most_ms)
  t.tap_run("上报")
  t.frame()
  assert_true(@sf.presenting(), msg="asked first")
  assert_eq(calls.length(), 0)
  t.run_for(@ui.move_most_ms)
  let ok = t.get(Button, label="上报", within=t.get(Dialog))
  t.tap(ok.rect.0 + ok.rect.2 / 2.0, ok.rect.1 + ok.rect.3 / 2.0)
  t.frame()
  let sent = calls.filter(fn(c) { c.0 == "chat.report" })
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].1), "station"), "ws1/st1")
  assert_eq(number(Some(sent[0].1), "seq"), 9.0)
  assert_eq(number(Some(sent[0].1), "thread"), 7.0)
  t.frame()
  assert_eq(@sfbase.toast_words(), "已上报为 FB-42")
  t.run_for(@ui.move_most_ms)
  assert_true(!@sf.presenting(), msg="closed once it went")
  let faults = nt_audit(t, 0, 0, 1, 1)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "取消 while its agent waits to retry cancels it (session.cancelRetry); not offered read only or offline; gone once the retry is over" {
  let calls : Array[(String, Json)] = []
  let retry = @signals.signal(true)
  let m = fn() { nt_msg(words="模型满载，自动重试，与额度无关", failed=true, retry=retry.get()) }
  let t = nt_new(760.0, nt_src(None, calls), m)
  t.run_for(@ui.move_most_ms)
  t.tap_text("取消")
  t.frame()
  let sent = calls.filter(fn(c) { c.0 == "session.cancelRetry" })
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].1), "key"), "s-c1")
  assert_eq(number(Some(sent[0].1), "seq"), 9.0)
  retry.set(false)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("取消") is None, msg="gone once the retry is over")
  for (ro, off) in [(true, false), (false, true)] {
    let calls : Array[(String, Json)] = []
    let t = nt_new(760.0, nt_src(None, calls, read_only=ro), fn() {
      nt_msg(words="模型满载，自动重试，与额度无关", failed=true, retry=true)
    }, view=nt_view(offline=off))
    t.run_for(@ui.move_most_ms)
    assert_true(t.get(Button, label="取消").disabled, msg="read only \{ro}, offline \{off}")
    t.tap_text("取消")
    t.frame()
    assert_eq(calls.length(), 0)
    let faults = nt_audit(t, 0, 0, 0, 0)
    assert_true(faults.is_empty(), msg=faults.join(" | "))
  }
}

///|
test "重试 on a failed turn's notice tries it again (session.retry); gone once its agent goes on" {
  let calls : Array[(String, Json)] = []
  let again = @signals.signal(true)
  let m = fn() { nt_msg(words="与模型服务的连接中断，回复即可重试", failed=true, again=again.get()) }
  let t = nt_new(760.0, nt_src(None, calls), m)
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="取消") is None)
  t.click(Button, label="重试")
  t.frame()
  let sent = calls.filter(fn(c) { c.0 == "session.retry" })
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].1), "key"), "s-c1")
  assert_eq(number(Some(sent[0].1), "thread"), 7.0)
  assert_eq(number(Some(sent[0].1), "seq"), 9.0)
  again.set(false)
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="重试") is None, msg="gone once its agent goes on")
  assert_true(t.query(Button, label="取消") is None, msg="never 取消 on its way out")
  let faults = nt_audit(t, 0, 0, 0, 0)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "a notice about a profile: what went wrong leads to the profile's page" {
  let opened : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()
  let t = nt_new(760.0, nt_src(None, []), fn() {
    nt_msg(words="Willow 上 codex 的登录已失效：请在设置里重新登录", failed=true, link=22)
  }, opened~)
  t.run_for(@ui.move_most_ms)
  t.tap_run("请在设置里重新登录")
  t.frame()
  assert_true(app.nav.top() == Setting(@settings.Route::Profile("ws1/st1", "p1")))
  assert_eq(opened.get("ts9"), None, msg="the pill not opened")
  let faults = nt_audit(t, 0, 0, 0, 0)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "the pill told with the row's key as it is made, for what lights it as the notice is gone to" {
  let pill : Ref[(@view.View, String)?] = Ref(None)
  let t = nt_new(760.0, nt_src(None, []), fn() { nt_msg() }, pill~)
  t.run_for(@ui.move_most_ms)
  match pill.val {
    Some((p, k)) => {
      assert_eq(k, "m:ts9")
      let (_, _, w, h) = p.rect()
      let (_, ty, _, th) = t.rect_of("Willow 的 codex 这一轮超时了，已经停下").unwrap_or((0.0, 0.0, 0.0, 0.0))
      assert_true(w > 0.0 && h >= th && ty > 0.0, msg="the pill round its words")
    }
    None => fail("no pill told")
  }
  let faults = nt_audit(t, 0, 0, 0, 0)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "取消 makes its way along the row as a retry begins and as it ends: the pill moved aside on the way, centred again once it is gone" {
  let calls : Array[(String, Json)] = []
  let retry = @signals.signal(false)
  let words = "模型满载，自动重试，与额度无关"
  let m = fn() { nt_msg(words~, failed=true, retry=retry.get()) }
  let t = nt_new(760.0, nt_src(None, calls), m)
  t.run_for(@ui.move_most_ms)
  let alone = t.rect_of(words).unwrap().0
  assert_true(t.find("取消") is None)
  // (a retry begins: 取消 comes along the row, the pill moved aside as it does)
  retry.set(true)
  t.frame()
  t.frame()
  let coming = t.rect_of(words).unwrap().0
  t.run_for(@ui.move_most_ms)
  let beside = t.rect_of(words).unwrap().0
  assert_true(beside < coming && coming < alone, msg="the pill on its way aside: \{Repr((alone, coming, beside))}")
  let (px, _, pw, _) = t.rect_of(words).unwrap()
  assert_true(t.rect_of("取消").unwrap().0 > px + pw, msg="取消 after the pill")
  // (the retry over: 取消 goes along the row, the pill back to the middle as it does)
  retry.set(false)
  t.frame()
  t.frame()
  let going = t.rect_of(words).unwrap().0
  assert_true(beside < going && going < alone, msg="the pill on its way back: \{Repr((beside, going, alone))}")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("取消") is None, msg="gone once its way is over")
  assert_true((t.rect_of(words).unwrap().0 - alone).abs() < 0.01, msg="the pill centred again")
  let faults = nt_audit(t, 0, 0, 0, 0)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}
