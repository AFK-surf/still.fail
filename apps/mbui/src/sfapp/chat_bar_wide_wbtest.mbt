// The open chat's bar on 大屏 and 中屏 (sfdesk's chat_bar_wide_node over the chat's page): what it shows in each state the
// chat can be in, laid out as the old bar laid it (the two compared word by word and rectangle by rectangle as the bar
// was made of nodes), and what each of its presses does.

///|
/// The fixture's chat (`mode`) on 大屏 (中屏 where `w` is one's), a window `w` × `h` of `platform`, the system's bars handed it where `able`;
/// its calls kept in `calls` and answered with nothing; each topic as `over` makes it; `inset`: a Windows 11 window's
/// (its corners 8, its own buttons the app's, in its top row); `nodes`: the chat's page made with its inside nodes.
fn wide_bar_at(
  calls : Array[Made],
  mode? : String = "chat",
  over? : (String, Topic) -> Topic = fn(_, t) { t },
  w? : Double = 1280.0,
  h? : Double = 800.0,
  platform? : Int = 0,
  able? : Bool = false,
  room? : String = "",
  inset? : Bool = false,
  nodes? : Bool = false,
) -> @ui.Tester {
  new_run()
  // (the chat's page made with its inside nodes: sfbase's chat_page_nodes)
  if nodes {
    @sfbase.chat_page_nodes.set(true)
  }
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      done(Ok(Json::object({})))
    },
    topic_read: fn(name, params) { over(name, base.topic(name, params).get().snapshot()) },
  }
  open_fixture_over(mode, src)
  let t = if inset {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, nav_able=able, window_corner=8.0, window_inset=true)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, nav_able=able)
  }
  if able {
    t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":84}}")
  }
  if room != "" {
    say_room(t, room, room)
  }
  t.run_for(@ui.move_most_ms)
  // (中屏: the chat's panel of the tape brought into use, as a press on what shows of it does)
  if @sfdesk.wide.tape.get() {
    page_over(t, w)
  }
  t
}

///|
/// Topic `name`'s value as `edit` makes it of what it was (the rest as they are).
fn wide_bar_edit(name : String, edit : (Json?) -> Json?) -> (String, Topic) -> Topic {
  fn(n, tp) {
    guard n == name else { return tp }
    { ..tp, value: edit(tp.value) }
  }
}

///|
/// Two edits of the topics, one after the other.
fn wide_bar_both(a : (String, Topic) -> Topic, b : (String, Topic) -> Topic) -> (String, Topic) -> Topic {
  fn(n, tp) { b(n, a(n, tp)) }
}

///|
/// The chat's field `key` set to `value`.
fn wide_bar_chat_field(key : String, value : (Json?) -> Json) -> (String, Topic) -> Topic {
  wide_bar_edit("chat", fn(v) {
    match v {
      Some(Object(m)) => {
        let o = m.copy()
        o[key] = value(m.get(key))
        Some(Json::object(o))
      }
      other => other
    }
  })
}

///|
/// The chat with `n` agents, each its first's made again by another key and name.
fn wide_bar_agents(n : Int) -> (String, Topic) -> Topic {
  wide_bar_chat_field("agents", fn(was) {
    let first = match was {
      Some(Array(a)) if a.length() > 0 => a[0]
      _ => Json::object({})
    }
    let all : Array[Json] = []
    for i in 0..<n {
      match first {
        Object(m) => {
          let o = m.copy()
          match m.get("session") {
            Some(Object(s)) => {
              let ss = s.copy()
              if i > 0 {
                ss["key"] = Json::string("s-x\{i}")
                ss["agentText"] = Json::string("Agent \{i}")
              }
              o["session"] = Json::object(ss)
            }
            _ => ()
          }
          all.push(Json::object(o))
        }
        other => all.push(other)
      }
    }
    Json::array(all)
  })
}

///|
/// The chat with `n` people, the first `pictured` of them with a picture.
fn wide_bar_people(n : Int) -> (String, Topic) -> Topic {
  wide_bar_chat_field("people", fn(_) {
    Json::array(
      Array::makei(n, fn(i) {
        Json::object({
          "id": Json::string("u\{i}"),
          "shown": Json::object({ "name": Json::string("人\{i}"), "display": Json::string("Person \{i}") }),
        })
      }),
    )
  })
}

///|
/// The core's `doing` with one `chat.rename` of the fixture's chat to `title`, at `stage`.
fn wide_bar_renaming(title : String, stage? : String = "sent", error? : String = "") -> (String, Topic) -> Topic {
  wide_bar_edit("doing", fn(_) {
    Some({
      "doing": [
        {
          "call": "chat.rename",
          "stage": Json::string(stage),
          "error": Json::string(error),
          "params": { "station": "ws1/st1", "session": "s-c1", "title": Json::string(title) },
        },
      ],
    })
  })
}

///|
/// The chat's services and jobs: some, one died lately (`alarm`).
fn wide_bar_jobs(alarm : String) -> (String, Topic) -> Topic {
  wide_bar_edit("chatJobs", fn(_) { Some({ "hasJobs": true, "jobs": [], "alarm": Json::string(alarm) }) })
}

///|
/// The pointer moved onto the middle of what is said `label` in the bar (the topmost), or onto `words` drawn in it.
fn wide_bar_point(t : @ui.Tester, label? : String = "", suffix? : String = "", words? : String = "", right? : Double = 0.0) -> Unit {
  let at = if words != "" {
    match t.locate(words).filter(fn(p) { p.1 < 90.0 }) {
      [p, ..] => Some(p)
      _ => None
    }
  } else {
    match t.all(Button).filter(fn(b) { (label != "" && b.label == label) || (suffix != "" && b.label.has_suffix(suffix)) }) {
      [b, ..] => {
        let (x, y, w, h) = b.rect
        Some((if right > 0.0 { x + w + right } else { x + w / 2.0 }, y + h / 2.0))
      }
      _ => None
    }
  }
  match at {
    Some((x, y)) => {
      t.move_to(x, y)
      t.frame()
      t.frame()
    }
    None => @halt.saying("nothing in the bar said \{label}\{suffix}\{words}")
  }
}

///|
/// The pointer rested on the bar's button said `label` till its tip shows.
fn wide_bar_tip(t : @ui.Tester, label : String) -> Unit {
  wide_bar_point(t, label~)
  t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
}

///|
/// The states of a chat the bar on 大屏 is held to (the old bar's each pinned against the new: the PR's own), each made
/// on calls kept in `calls`, by its name.
fn wide_bar_large(calls : Array[Made]) -> Array[(String, () -> @ui.Tester)] {
  [
    ("AGENT", fn() { wide_bar_at(calls) }),
    ("NOAGENT", fn() { wide_bar_at(calls, over=wide_bar_agents(0)) }),
    ("AGENTS", fn() { wide_bar_at(calls, over=wide_bar_agents(3)) }),
    ("PEOPLE", fn() { wide_bar_at(calls, over=wide_bar_people(7)) }),
    ("NARROW", fn() { wide_bar_at(calls, over=wide_bar_both(wide_bar_people(7), wide_bar_agents(3)), w=860.0) }),
    ("RENAME", fn() { wide_bar_at(calls, over=wide_bar_renaming("发布清单 v2")) }),
    (
      "RENAMEFAIL",
      fn() { wide_bar_at(calls, over=wide_bar_renaming("发布清单 v2", stage="failed", error="无法重命名：Willow 不在线")) },
    ),
    ("JOBS", fn() { wide_bar_at(calls, over=wide_bar_jobs("fail")) }),
    ("RESTART", fn() { wide_bar_at(calls, over=wide_bar_jobs("restart")) }),
    ("SCREEN", fn() { wide_bar_at(calls, mode="chat-station-screen") }),
    ("SCREENS", fn() { wide_bar_at(calls, mode="chat-station-screens") }),
    ("BESIDE", fn() { wide_bar_at(calls, mode="chat-history-side") }),
    ("FIND", fn() { wide_bar_at(calls, mode="chat-find") }),
    ("NARROW-FIND", fn() { wide_bar_at(calls, mode="chat-find", over=wide_bar_people(7), w=860.0) }),
    ("ARCHIVABLE", fn() { wide_bar_at(calls, over=wide_bar_chat_field("archivable", fn(_) { Json::boolean(true) })) }),
    (
      "ARCHIVE-JOBS",
      fn() {
        wide_bar_at(calls, over=wide_bar_both(wide_bar_chat_field("archivable", fn(_) { Json::boolean(true) }), wide_bar_jobs("fail")))
      },
    ),
    ("SCREENS-DRIVEN", fn() { wide_bar_at(calls, mode="chat-station-screens", over=wide_bar_jobs("restart")) }),
    ("TOUCH", fn() { wide_bar_at(calls, platform=2) }),
    ("TOUCH-NOAGENT", fn() { wide_bar_at(calls, platform=2, over=wide_bar_agents(0)) }),
    ("WIN", fn() { wide_bar_at(calls, platform=3) }),
    ("NATIVE", fn() { wide_bar_at(calls, w=951.0, h=669.0, platform=1, able=true) }),
    ("WAITING", fn() { wide_bar_at(calls, mode="chat-loading") }),
    (
      "HOVER-STATION",
      fn() {
        let t = wide_bar_at(calls, over=wide_bar_agents(0))
        wide_bar_point(t, words="Willow")
        t
      },
    ),
    (
      "HOVER-AGENT",
      fn() {
        let t = wide_bar_at(calls)
        wide_bar_point(t, suffix="的执行历史")
        t
      },
    ),
    (
      "HOVER-PART",
      fn() {
        let t = wide_bar_at(calls)
        wide_bar_point(t, suffix="的执行历史", right=8.0)
        t
      },
    ),
    (
      "HOVER-INFO",
      fn() {
        let t = wide_bar_at(calls)
        wide_bar_point(t, label=@sf.t("web-pages.chat.info"))
        t
      },
    ),
    // (each button's tip shown: its words, then its keys where it has any)
    (
      "TIP-ARCHIVE",
      fn() {
        let t = wide_bar_at(calls, over=wide_bar_chat_field("archivable", fn(_) { Json::boolean(true) }))
        wide_bar_tip(t, @sf.t("web-pages.chat.archive"))
        t
      },
    ),
    (
      "TIP-JOBS",
      fn() {
        let t = wide_bar_at(calls, over=wide_bar_jobs("fail"))
        wide_bar_tip(t, @sf.t("web-pages.chat.services"))
        t
      },
    ),
    (
      "TIP-SCREEN",
      fn() {
        let t = wide_bar_at(calls, mode="chat-station-screen")
        wide_bar_tip(t, @sf.t("web-pages.chat.screen"))
        t
      },
    ),
    (
      "TIP-INFO",
      fn() {
        let t = wide_bar_at(calls)
        wide_bar_tip(t, @sf.t("web-pages.chat.info"))
        t
      },
    ),
    (
      "TIP-PANEL",
      fn() {
        let t = wide_bar_at(calls)
        wide_bar_tip(t, @sf.t("web-pages.chat.openPanel"))
        t
      },
    ),
    (
      "TIP-PANEL-TOUCH",
      fn() {
        let t = wide_bar_at(calls, platform=2)
        wide_bar_tip(t, @sf.t("web-pages.chat.openPanel"))
        t
      },
    ),
  ]
}

///|
/// The same on 中屏: the chat in the page's panel of the tape, brought into use.
fn wide_bar_medium(calls : Array[Made]) -> Array[(String, () -> @ui.Tester)] {
  [
    ("M-AGENT", fn() { wide_bar_at(calls, w=720.0) }),
    ("M-NOAGENT", fn() { wide_bar_at(calls, w=720.0, over=wide_bar_agents(0)) }),
    ("M-AGENTS", fn() { wide_bar_at(calls, w=720.0, over=wide_bar_agents(3)) }),
    ("M-PEOPLE", fn() { wide_bar_at(calls, w=720.0, over=wide_bar_people(7)) }),
    ("M-NARROW", fn() { wide_bar_at(calls, over=wide_bar_both(wide_bar_people(7), wide_bar_agents(3)), w=600.0) }),
    ("M-RENAME", fn() { wide_bar_at(calls, w=720.0, over=wide_bar_renaming("发布清单 v2")) }),
    (
      "M-RENAMEFAIL",
      fn() {
        wide_bar_at(calls, w=720.0, over=wide_bar_renaming("发布清单 v2", stage="failed", error="无法重命名：Willow 不在线"))
      },
    ),
    ("M-JOBS", fn() { wide_bar_at(calls, w=720.0, over=wide_bar_jobs("fail")) }),
    ("M-SCREENS", fn() { wide_bar_at(calls, w=720.0, mode="chat-station-screens") }),
    ("M-BESIDE", fn() { wide_bar_at(calls, w=720.0, mode="chat-history-side") }),
    ("M-FIND", fn() { wide_bar_at(calls, w=720.0, mode="chat-find") }),
    (
      "M-ARCHIVABLE",
      fn() { wide_bar_at(calls, w=720.0, over=wide_bar_chat_field("archivable", fn(_) { Json::boolean(true) })) },
    ),
    ("M-TOUCH", fn() { wide_bar_at(calls, w=690.0, h=840.0, platform=2, room="medium") }),
    ("M-WIN", fn() { wide_bar_at(calls, w=720.0, platform=3) }),
    ("M-NATIVE", fn() { wide_bar_at(calls, w=820.0, h=1180.0, platform=1, able=true) }),
    ("M-WAITING", fn() { wide_bar_at(calls, w=720.0, mode="chat-loading") }),
    (
      "M-HOVER-STATION",
      fn() {
        let t = wide_bar_at(calls, w=720.0, over=wide_bar_agents(0))
        wide_bar_point(t, words="Willow")
        t
      },
    ),
    (
      "M-HOVER-AGENT",
      fn() {
        let t = wide_bar_at(calls, w=720.0)
        wide_bar_point(t, suffix="的执行历史")
        t
      },
    ),
    (
      "M-TIP-ARCHIVE",
      fn() {
        let t = wide_bar_at(calls, w=720.0, over=wide_bar_chat_field("archivable", fn(_) { Json::boolean(true) }))
        wide_bar_tip(t, @sf.t("web-pages.chat.archive"))
        t
      },
    ),
    (
      "M-TIP-PANEL",
      fn() {
        let t = wide_bar_at(calls, w=720.0)
        wide_bar_tip(t, @sf.t("web-pages.chat.openPanel"))
        t
      },
    ),
  ]
}

///|
/// What the nodes' audit says of the bar (its faults made in chat_bar_wide_node or find_bar_node) in state `name`, the
/// old bar's own as it was laid out (the old view held them to no rule; reported, pinned, 2026-11-11): its agents but
/// the first, 20 marks 10 apart, pressed in 33 × 36 (AGENTS, NARROW: two each). (A station's screens' count, 2.27:1 on
/// the amber of one driven, went with the count itself, 2026-11-13.)
fn wide_bar_known(name : String) -> Array[String] {
  match name {
    "AGENTS" | "NARROW" | "M-AGENTS" | "M-NARROW" => ["has 33×36 to be pressed in, under 36", "has 33×36 to be pressed in, under 36"]
    _ => []
  }
}

///|
/// Each state of `states` held to the old bar's arrangement as the comparison found it the same (words and rectangles,
/// one by one: rc3-11 against rc3-24), as relations here: what the bar shows on its middle line, its buttons from its
/// end in, nothing of it past the window; what the audit says of it only what wide_bar_known pins.
fn wide_bar_held(states : Array[(String, () -> @ui.Tester)]) -> Array[String] {
  let faults : Array[String] = []
  for s in states {
    let (name, make) = s
    let t = make()
    let (ww, _) = t.ctx().window_size()
    // (the bar's own: its agents' marks and its buttons, by what they are called, none as tall as a panel (中屏's side
    // panel off the tape, said 打开侧栏))
    let own = [
      @sf.t("web-pages.chat.archive"),
      @sf.t("web-pages.chat.services"),
      @sf.t("web-pages.chat.screen"),
      @sf.t("web-pages.chat.info"),
      @sf.t("common.more"),
      @sf.t("web-pages.chat.openPanel"),
    ]
    let bar = t
      .all(Button)
      .filter(fn(b) { b.rect.1 < 90.0 && b.rect.3 < 90.0 && (own.contains(b.label) || b.label.has_suffix("的执行历史")) })
    // (in the bar's middle, each: its buttons and its agents' marks alike)
    let mids = bar.map(fn(b) { b.rect.1 + b.rect.3 / 2.0 })
    if mids.length() > 1 && mids.iter().any(fn(m) { (m - mids[0]).abs() > 0.5 }) {
      faults.push("\{name}: not on one line: \{Repr(bar.map(fn(b) { (b.label, b.rect) }))}")
    }
    if bar.iter().any(fn(b) { b.rect.0 + b.rect.2 > ww }) {
      faults.push("\{name}: past the window: \{Repr(bar.map(fn(b) { (b.label, b.rect) }))}")
    }
    let audit = t.audit().filter(fn(f) { f.contains("chat_bar_wide_node") || f.contains("find_bar_node") })
    let known = wide_bar_known(name)
    let unknown = audit.filter(fn(f) { !known.iter().any(fn(k) { f.contains(k) }) })
    if unknown.length() > 0 || audit.length() != known.length() {
      faults.push("\{name}: audit \{Repr(audit)}")
    }
  }
  faults
}

///|
test "大屏: the bar in each state of its chat, as the old one laid it out; what the audit says of it the old one's own, pinned" {
  // (its own run first: each state's maker starts another before it reads a word)
  new_run()
  let calls : Array[Made] = []
  let faults = wide_bar_held(wide_bar_large(calls))
  assert_eq(faults, [], msg=faults.join("\n"))
}

///|
test "中屏: the bar in each state of its chat, as the old one laid it out; what the audit says of it the old one's own, pinned" {
  new_run()
  let calls : Array[Made] = []
  let faults = wide_bar_held(wide_bar_medium(calls))
  assert_eq(faults, [], msg=faults.join("\n"))
}
///|
/// The bar's button said `label` (its topmost; none as tall as a panel), where it is.
fn wide_bar_button(t : @ui.Tester, label : String) -> (Double, Double, Double, Double)? {
  match t.all(Button).filter(fn(b) { b.label == label && b.rect.1 < 90.0 && b.rect.3 < 90.0 }) {
    [b, ..] => Some(b.rect)
    _ => None
  }
}

///|
/// A press in the middle of `r`, its moment declared.
fn wide_bar_tap(t : @ui.Tester, r : (Double, Double, Double, Double)) -> Unit {
  let (x, y, w, h) = r
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
}

///|
/// The windows a bar's press is held to: a Mac's 1280 × 800 (Large), 720 wide (Medium: the chat in the page's panel of
/// the tape).
// kept across runs: a value
let wide_bar_windows : Array[(String, Double)] = [("大屏", 1280.0), ("中屏", 720.0)]

///|
test "大屏, 中屏: the bar's 对话信息 opens the chat's info under it and closes it again, its services' button their popover" {
  for win in wide_bar_windows {
    let calls : Array[Made] = []
    let t = wide_bar_at(calls, w=win.1, over=wide_bar_jobs("fail"))
    let info = @sf.t("web-pages.chat.info")
    guard wide_bar_button(t, info) is Some(b) else { fail("\{win.0}: no \{info}") }
    wide_bar_tap(t, b)
    assert_eq(@sfdesk.chat_pops_open(), (true, false), msg=win.0)
    // (under its button, its right edge by the button's: bar_popovers' Bottom, End)
    let dialogs = t.all(Dialog)
    assert_true(dialogs.length() > 0, msg="\{win.0}: the info's popover")
    let (dx, dy, dw, _) = dialogs[dialogs.length() - 1].rect
    assert_true(dy >= b.1 + b.3, msg="\{win.0}: under its button: \{Repr((dx, dy, dw))} \{Repr(b)}")
    assert_true((dx + dw - (b.0 + b.2)).abs() < 1.0, msg="\{win.0}: its end at its button's: \{Repr((dx, dy, dw))} \{Repr(b)}")
    wide_bar_tap(t, b)
    assert_eq(@sfdesk.chat_pops_open(), (false, false), msg="\{win.0}: pressed again, closed")
    let jobs = @sf.t("web-pages.chat.services")
    guard wide_bar_button(t, jobs) is Some(j) else { fail("\{win.0}: no \{jobs}") }
    wide_bar_tap(t, j)
    assert_eq(@sfdesk.chat_pops_open(), (false, true), msg=win.0)
    @sfdesk.toggle_jobs_pop()
    t.run_for(@ui.move_most_ms)
  }
}

///|
test "大屏, 中屏: the bar's \"…\" opens the chat's menu beside it; its side panel's switch opens its first agent's history; its agent's mark the same" {
  for win in wide_bar_windows {
    let calls : Array[Made] = []
    let t = wide_bar_at(calls, w=win.1)
    @sf.presenters_reset()
    guard wide_bar_button(t, @sf.t("common.more")) is Some(m) else { fail("\{win.0}: no …") }
    wide_bar_tap(t, m)
    assert_true(@sf.presenting(), msg="\{win.0}: its menu")
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    assert_true(!@sf.presenting(), msg="\{win.0}: closed")
    let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
    guard wide_bar_button(t, @sf.t("web-pages.chat.openPanel")) is Some(p) else { fail("\{win.0}: no panel switch") }
    wide_bar_tap(t, p)
    // (the core asked to open its first agent's history beside the chat: its calls answered with nothing here)
    let opened = fn() { calls.filter(fn(c) { c.name == "chat.tabs.open" && text(Some(c.params), "tab") == "s-c1" }).length() }
    assert_eq(opened(), 1, msg="\{win.0}: its history beside the chat: \{Repr(calls.map(fn(c) { c.name }))}")
    let t = wide_bar_at(calls, w=win.1)
    let tile = t.all(Button).filter(fn(b) { b.label.has_suffix("的执行历史") && b.rect.1 < 90.0 })
    assert_eq(tile.length(), 1, msg=win.0)
    wide_bar_tap(t, tile[0].rect)
    assert_eq(opened(), 2, msg="\{win.0}: the agent's history from its mark: \{Repr(calls.map(fn(c) { c.name }))}")
    ignore(r)
  }
}

///|
test "大屏, 中屏: 归档 on a chat with nothing left in it puts it in the archive (chat.archive)" {
  for win in wide_bar_windows {
    let calls : Array[Made] = []
    let t = wide_bar_at(calls, w=win.1, over=wide_bar_chat_field("archivable", fn(_) { Json::boolean(true) }))
    guard wide_bar_button(t, @sf.t("web-pages.chat.archive")) is Some(a) else { fail("\{win.0}: no 归档") }
    wide_bar_tap(t, a)
    assert_true(calls.iter().any(fn(c) { c.name == "chat.archive" }), msg="\{win.0}: \{Repr(calls.map(fn(c) { c.name }))}")
  }
}

///|
test "大屏: a press on the bar where nothing of it takes one drags the window, in one with its buttons in its top row" {
  let calls : Array[Made] = []
  let t = wide_bar_at(calls)
  let before = t.window_drags()
  guard wide_bar_button(t, @sf.t("web-pages.chat.info")) is Some(b) else { fail("no info") }
  // (between the title's row and the buttons: the bar's own)
  t.press_at(b.0 - 120.0, b.1 + b.3 / 2.0)
  t.release(b.0 - 120.0, b.1 + b.3 / 2.0)
  t.frame()
  assert_eq(t.window_drags() - before, if @ui.window_inset() { 1 } else { 0 })
}

///|
test "大屏, 中屏: a button of the bar says its keys in its tip after its words, as the app says them" {
  for win in wide_bar_windows {
    let calls : Array[Made] = []
    let tips = [
      ("web-pages.chat.archive", "chat.archive"),
      ("web-pages.chat.services", "chat.jobs"),
      ("web-pages.chat.screen", "chat.screen"),
      ("web-pages.chat.openPanel", "chat.history"),
    ]
    for tip in tips {
      let t = wide_bar_at(
        calls,
        w=win.1,
        mode=if tip.1 == "chat.screen" { "chat-station-screen" } else { "chat" },
        over=wide_bar_both(wide_bar_chat_field("archivable", fn(_) { Json::boolean(true) }), wide_bar_jobs("fail")),
      )
      let label = @sf.t(tip.0)
      let keys = @sf.shortcut_keys(tip.1)
      assert_true(keys != "", msg="\{win.0}: \{tip.1} has keys")
      guard wide_bar_button(t, label) is Some(b) else { fail("\{win.0}: no \{label}") }
      wide_bar_tip(t, label)
      // (its words, its keys after them on their line, under the button)
      let under = fn(w : String) { t.locate(w).filter(fn(p) { p.1 > b.1 + b.3 }) }
      match (under(label), under(keys)) {
        ([w, ..], [k, ..]) => {
          assert_true(k.0 > w.0, msg="\{win.0}: \{label}'s keys after it: \{Repr(w)} \{Repr(k)}")
          assert_true((k.1 - w.1).abs() < 1.0, msg="\{win.0}: \{label}'s keys on its line: \{Repr(w)} \{Repr(k)}")
        }
        (ws, ks) => fail("\{win.0}: \{label}'s tip: \{Repr(ws)} \{Repr(ks)}")
      }
    }
  }
}

///|
/// The last dialog drawn (an old view's popover, the topmost), where it is.
fn wide_bar_dialog(t : @ui.Tester) -> (Double, Double, Double, Double)? {
  match t.all(Dialog) {
    [] => None
    ds => Some(ds[ds.length() - 1].rect)
  }
}

///|
/// Whether popover `d` stands under button `b`, its end at the button's (bar_popovers' Bottom, End).
fn wide_bar_under(d : (Double, Double, Double, Double), b : (Double, Double, Double, Double)) -> Bool {
  d.1 >= b.1 + b.3 && (d.0 + d.2 - (b.0 + b.2)).abs() < 1.0
}

///|
test "大屏, 中屏: the bar's popovers keep by their buttons as the window changes, opened by a press or by a key; closed, the focus where it was" {
  for win in wide_bar_windows {
    let calls : Array[Made] = []
    for which in ["info", "jobs"] {
      let t = wide_bar_at(calls, w=win.1, over=wide_bar_jobs("fail"))
      let label = @sf.t(if which == "info" { "web-pages.chat.info" } else { "web-pages.chat.services" })
      let opened = fn() {
        let (i, j) = @sfdesk.chat_pops_open()
        if which == "info" {
          i
        } else {
          j
        }
      }
      guard wide_bar_button(t, label) is Some(b) else { fail("\{win.0}: no \{label}") }
      let focused = fn() { t.focused().map(fn(s) { s.label }) }
      let had = focused()
      wide_bar_tap(t, b)
      assert_true(opened(), msg="\{win.0}: \{label} opened")
      guard wide_bar_dialog(t) is Some(d) else { fail("\{win.0}: \{label}'s popover") }
      assert_true(wide_bar_under(d, b), msg="\{win.0}: \{label}'s popover by it: \{Repr(d)} \{Repr(b)}")
      // (the window wider: the button moved with the bar's end, its popover with it)
      t.resize(win.1 + 160.0, 800.0)
      t.run_for(@ui.move_most_ms)
      guard (wide_bar_button(t, label), wide_bar_dialog(t)) is (Some(b2), Some(d2)) else {
        fail("\{win.0}: \{label} wider")
      }
      assert_true(b2.0 != b.0, msg="\{win.0}: \{label} moved: \{Repr(b)} \{Repr(b2)}")
      assert_true(wide_bar_under(d2, b2), msg="\{win.0}: \{label}'s popover by it, wider: \{Repr(d2)} \{Repr(b2)}")
      // (closed by Escape: the focus back where it was as it opened, as the old view's popover gives it (kit's popover:
      // what had it; the button only where that had it))
      t.key(@ui.key_escape)
      t.run_for(@ui.move_most_ms)
      assert_true(!opened(), msg="\{win.0}: \{label} closed")
      assert_eq(focused(), had, msg="\{win.0}: the focus back where it was")
      // (opened by a key (a fixture's, the system's bars' item): by the button where it is, the window narrower again)
      if which == "info" {
        @sfdesk.open_info_pop()
      } else {
        @sfdesk.open_jobs_pop()
      }
      t.run_for(@ui.move_most_ms)
      t.resize(win.1, 800.0)
      t.run_for(@ui.move_most_ms)
      guard (wide_bar_button(t, label), wide_bar_dialog(t)) is (Some(b3), Some(d3)) else {
        fail("\{win.0}: \{label} by a key")
      }
      assert_true(wide_bar_under(d3, b3), msg="\{win.0}: \{label}'s popover by it, by a key: \{Repr(d3)} \{Repr(b3)}")
      t.key(@ui.key_escape)
      t.run_for(@ui.move_most_ms)
      assert_true(!opened(), msg="\{win.0}: \{label} closed again")
      assert_eq(t.audit().filter(fn(f) { f.contains("chat_bar_wide_node") }), [], msg=win.0)
    }
  }
}

///|
/// The words `w` drawn in the bar (over 90), seen: where they are and how wide, the first of them.
fn wide_bar_seen(t : @ui.Tester, w : String) -> (Double, Double)? {
  match t.words().filter(fn(x) { x.0 == w && x.2 < 90.0 && x.5 > 0.0 && x.3 > 0.0 }) {
    [x, ..] => Some((x.1, x.3))
    _ => None
  }
}

///|
test "大屏, 中屏: ⌘F's bar open in a bar short of room: the chat's people leave first, its title cut to 4 of its letters, its field the rest, none of it past the bar" {
  // (not the old bar's, on purpose (the coordinator, 2026-11-12): the old title row's least was 12 + 64 + 10 + 20 =
  // 106, its agent's piece's least taken as 20 where it drew 41.6, so the 21.6 more it took came off the title's 4
  // letters (大屏 860 with 7 people: the title 42.4, the field 262.4; 中屏 720: 42.4 and 305.9; 760: 60.4), never meant
  // so (K2, measured in the old code). Here the title keeps its 4 letters, the field gives the rest (860: 248.6, 720:
  // 292.1))
  let calls : Array[Made] = []
  // (a letter of the title as the bar draws it with room: its whole width, its letters)
  let letter = match wide_bar_seen(wide_bar_at(calls), "整理发布清单") {
    Some((_, w)) => w / "整理发布清单".length().to_double()
    None => fail("no title with room")
  }
  let states = [
    ("NARROW-FIND", fn() { wide_bar_at(calls, mode="chat-find", over=wide_bar_people(7), w=860.0) }, ["P", "+2"]),
    ("M-FIND", fn() { wide_bar_at(calls, mode="chat-find", w=720.0) }, ["你", "A"]),
  ]
  for s in states {
    let (name, make, people) = s
    let t = make()
    let (ww, _) = t.ctx().window_size()
    for p in people {
      assert_true(wide_bar_seen(t, p) is None, msg="\{name}: its people left out (\{p}): \{Repr(t.words().filter(fn(w) { w.2 < 90.0 }))}")
    }
    let (tx, tw) = match wide_bar_seen(t, "整理发布清单") {
      Some(x) => x
      None => fail("\{name}: no title")
    }
    assert_true((tw - 4.0 * letter).abs() < 0.5, msg="\{name}: its title 4 letters wide: \{tw}, a letter \{letter}")
    match (wide_bar_seen(t, "在对话中查找"), wide_bar_seen(t, "无结果")) {
      (Some((fx, _)), Some((x, w))) => {
        assert_true(fx > tx + tw, msg="\{name}: the field after the title: \{fx} \{Repr((tx, tw))}")
        assert_true(x + w <= ww, msg="\{name}: its count within the window: \{Repr((x, w))} \{ww}")
      }
      _ => fail("\{name}: no field or count in ⌘F's bar")
    }
    let audit = t.audit().filter(fn(f) { f.contains("chat_bar_wide_node") || f.contains("find_bar_node") })
    assert_eq(audit, [], msg=name)
  }
}

///|
/// Whether something is drawn on `r` (a half of the agent's tile lit: its ground the hover's, none while it is not).
fn wide_bar_lit(t : @ui.Tester, r : (Double, Double, Double, Double)) -> Bool {
  let (x, y, w, h) = r
  t
  .drawn_rects()
  .iter()
  .any(fn(d) {
    (d.0 - x).abs() < 0.5 && (d.1 - y).abs() < 0.5 && (d.2 - w).abs() < 0.5 && (d.3 - h).abs() < 0.5 && (d.4 & 0xFFL) > 0L
  })
}

///|
/// Whether a hover card stands under `r` at its start (a card of what `r` is: hover_card_node's Bottom, Start, 6 off).
fn wide_bar_card_under(t : @ui.Tester, r : (Double, Double, Double, Double)) -> Bool {
  t
  .all(Group)
  .iter()
  .any(fn(g) {
    let (gx, gy, gw, _) = g.rect
    (gx - r.0).abs() < 1.0 && gy >= r.1 + r.3 && gy < r.1 + r.3 + 12.0 && gw >= 200.0
  })
}

///|
test "大屏, 中屏: where the agent's room reaches over its station's half, the pointer resting there lights the agent alone and opens its card alone; on the rest of that half, the station's alone" {
  for win in wide_bar_windows {
    let calls : Array[Made] = []
    let t = wide_bar_at(calls, w=win.1)
    let agent = match t.all(Button).filter(fn(b) { b.label.has_suffix("的执行历史") && b.rect.1 < 90.0 && b.rect.2 < 30.0 }) {
      [b, ..] => b.rect
      _ => fail("\{win.0}: no agent's half")
    }
    let station = match t.all(Group).filter(fn(g) { g.label == "Willow" && g.rect.1 < 90.0 }) {
      [g, ..] => g.rect
      _ => fail("\{win.0}: no station's half")
    }
    let y = agent.1 + agent.3 / 2.0
    // (3 past the agent's half: in its room (36 round a 20), drawn the station's; and 3 before the station's end, past it)
    let reached = agent.0 + agent.2 + 3.0
    let past = station.0 + station.2 - 3.0
    assert_true(reached >= station.0 && reached < past, msg="\{win.0}: \{Repr(agent)} \{Repr(station)}")
    t.move_to(reached, y)
    t.run_for(@sf.hover_card_open_ms + @ui.move_most_ms)
    assert_true(wide_bar_lit(t, agent), msg="\{win.0}: in the agent's room, the agent lit")
    assert_false(wide_bar_lit(t, station), msg="\{win.0}: in the agent's room, the station not lit")
    assert_true(wide_bar_card_under(t, agent), msg="\{win.0}: in the agent's room, its card")
    assert_false(wide_bar_card_under(t, station), msg="\{win.0}: in the agent's room, no station's card")
    t.move_to(past, y)
    t.run_for(@sf.hover_card_open_ms + @ui.move_most_ms)
    assert_false(wide_bar_lit(t, agent), msg="\{win.0}: on the station's half, the agent not lit")
    assert_true(wide_bar_lit(t, station), msg="\{win.0}: on the station's half, it lit")
    assert_false(wide_bar_card_under(t, agent), msg="\{win.0}: on the station's half, no agent's card")
    assert_true(wide_bar_card_under(t, station), msg="\{win.0}: on the station's half, its card")
    // (pressed in the agent's room: its history's, as ever)
    t.move_to(reached, y)
    t.run_for(@ui.move_most_ms)
    let n = calls.filter(fn(c) { c.name == "chat.tabs.open" }).length()
    t.press_at(reached, y)
    t.release(reached, y)
    t.run_for(@ui.move_most_ms)
    assert_eq(calls.filter(fn(c) { c.name == "chat.tabs.open" }).length(), n + 1, msg="\{win.0}: pressed in the agent's room, its history")
  }
}

///|
test "大屏, 中屏: the window's own buttons in its top row (Windows) pressed from 2 off them as on them, the bar's own part beside them none of theirs" {
  for win in wide_bar_windows {
    let calls : Array[Made] = []
    let t = wide_bar_at(calls, w=win.1, platform=3, inset=true)
    let key = fn(label : String) {
      match t.all(Button).filter(fn(b) { b.label == label && b.rect.1 < 90.0 }) {
        [b, ..] => Some(b.rect)
        _ => None
      }
    }
    guard key(@sf.t("desktop.menu.minimize")) is Some(least) else { fail("\{win.0}: no minimize") }
    guard key(@sf.t("desktop.menu.close")) is Some(close) else { fail("\{win.0}: no close") }
    let y = least.1 + least.3 / 2.0
    // (2 before the first, 2 after the last: within the room a press takes round each, 36 round their 32)
    for p in [(least.0 - 2.0, 1, "minimize"), (close.0 + close.2 + 1.5, 3, "close")] {
      let (x, act, name) = p
      let acts = t.window_acts().length()
      let drags = t.window_drags()
      t.press_at(x, y)
      t.release(x, y)
      t.run_for(@ui.move_most_ms)
      assert_eq(t.window_acts()[acts:].to_owned(), [act], msg="\{win.0}: \{name} pressed at \{x}")
      assert_eq(t.window_drags(), drags, msg="\{win.0}: \{name}: the window not dragged at \{x}")
    }
    // (past their room, the bar's: it drags the window)
    let x = least.0 - 8.0
    let drags = t.window_drags()
    let acts = t.window_acts().length()
    t.press_at(x, y)
    t.release(x, y)
    t.run_for(@ui.move_most_ms)
    assert_eq(t.window_drags(), drags + 1, msg="\{win.0}: 8 before them the bar's")
    assert_eq(t.window_acts().length(), acts, msg="\{win.0}: 8 before them none of theirs")
  }
}

///|
test "大屏, 中屏: 归档 on a chat keeping watch, asked, and 归档 in the question: the cursor in the next chat's composer, in the window, what is typed its; every frame built whole past the moment a composer let go would let go" {
  for win in wide_bar_windows {
    let calls : Array[Made] = []
    let t = wide_bar_at(
      calls,
      w=win.1,
      over=wide_bar_both(
        wide_bar_chat_field("archivable", fn(_) { Json::boolean(true) }),
        wide_bar_chat_field("watch", fn(_) { { "ask": "它还在盯着 CI，归档后就不盯了。" } }),
      ),
    )
    @sf.presenters_reset()
    guard wide_bar_button(t, @sf.t("web-pages.chat.archive")) is Some(a) else { fail("\{win.0}: no 归档") }
    // (pressed by a pointer: the composer keeps the cursor till the question takes it)
    wide_bar_tap(t, a)
    assert_true(@sf.presenting(), msg="\{win.0}: asked")
    guard t.all(Button).filter(fn(b) { b.label == @sf.t("web-pages.chat.archive") && b.rect.1 > 90.0 }) is [yes, ..] else {
      fail("\{win.0}: no 归档 in the question")
    }
    let (x, y, w, h) = yes.rect
    t.tap(x + w / 2.0, y + h / 2.0)
    // (each frame on the way, past the moment the composer of a chat without the cursor lets it go: the one archived,
    // sliding off on 中屏, and the next must not take turns with it; a size that steps there is said by the frame)
    let until = t.time() + @sfpages.let_go_ms + @ui.move_most_ms
    if @ui.test_at_a_rate() {
      t.run_for(until - t.time())
    } else {
      while t.time() < until {
        t.frame()
      }
    }
    assert_eq(named(calls, "chat.archive").length(), 1, msg=win.0)
    assert_true(!@sf.presenting(), msg="\{win.0}: the question gone")
    assert_true(
      match app.nav.top() {
        Chat(r) => r.session == "s-c2"
        _ => false
      },
      msg="\{win.0}: on to the next chat",
    )
    guard t.focused() is Some(f) else { fail("\{win.0}: the cursor nowhere") }
    let (fx, _, fw, _) = f.rect
    assert_true(f.role is TextField && f.label == "发消息" && fx >= 0.0 && fx + fw <= win.1, msg="\{win.0}: \{Repr(f.role)} \{f.label} \{@ui.rect_text(f.rect)}")
    let before = named(calls, "composer.text").length()
    t.type_text("接着写")
    t.run_for(@ui.move_most_ms)
    let typed = named(calls, "composer.text")
    assert_true(typed.length() > before, msg="\{win.0}: typed into none")
    let keys : Array[String] = []
    for i in before..<typed.length() {
      keys.push(text(Some(typed[i].params), "key"))
    }
    assert_true(keys.iter().all(fn(k) { k.contains("s-c2") }), msg="\{win.0}: \{Repr(keys)}")
  }
}
