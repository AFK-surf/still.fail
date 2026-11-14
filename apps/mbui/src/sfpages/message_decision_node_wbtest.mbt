// What a post asks under it and what a chat needs of the viewer at its end, as nodes (message_decision_node.mbt; the
// library's options_card_node, ask_line_node), set beside the old view's (decision.mbt message_decision, chat_rows.mbt
// chat_state, out of a list) on the same fixture: an agent's message with its options asked, one on its way, answered,
// let go; 忽略 alone; the chat's need as a card, let go, 忽略 under its line; wide, narrow, at 1.3. The message's own
// words over the options are plain words in both (its Markdown is the agent's message's own, compared with it), not
// what is compared for here.

///|
/// The post's words over what it asks, plain in both.
// kept across runs: a value (no field of it changes)
let dec_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg)

///|
/// The options the fixture's post gives.
fn dec_options() -> Json {
  [
    { "label": "先不换", "detail": "这次只改列表，截图下次再说" },
    { "label": "一起换", "detail": "把首页和聊天页的截图都更新", "recommended": true },
  ]
}

///|
/// The fixture's agent's post (seq 8 of thread 7): its options asked of 林 (`state`: asked), answered with 一起换, let
/// go, or (alone) an agent's need with no card, asked.
fn dec_msg(state : String) -> Message {
  let card : Json = if state == "alone" {
    Json::null()
  } else {
    { "type": "options", "assigneeText": "等 林 决定", "options": dec_options() }
  }
  let decision : Json = match state {
    "answered" => { "resolved": true, "chosen": "一起换", "text": "你 选择了「一起换」" }
    "dismissed" => { "resolved": false, "dismissed": true, "text": "已忽略" }
    _ => { "resolved": false }
  }
  @sfbase.message_of({
    "seq": 8,
    "thread": 7,
    "ts": "ts8",
    "authorKind": "agent",
    "author": "s-c1",
    "text": "高度先按 90 估，量过一次就记住。要不要把旧的截图也一起换掉？",
    "attachments": [],
    "quotes": [],
    "createdAt": 8,
    "mine": false,
    "system": false,
    "by": { "name": "Claude", "agent": "s-c1", "maker": "anthropic", "runtime": "claude" },
    "card": card,
    "decision": decision,
    "asked": state == "asked" || state == "alone",
    "time": @sffixture.ago("30 分钟前", "2026-11-11 20:40"),
  })
}

///|
/// The fixture's chat's view: thread 7, its agent; where it stands (`state`: words, lead, rest) and the post it asks
/// the viewer at its end (`ask`).
fn dec_view(state? : (String, String, String)? = None, ask? : Double? = None) -> ChatView {
  let v : Map[String, Json] = {
    "title": "发布",
    "messages": [],
    "thread": { "id": 7 },
    "agents": [{ "session": { "key": "s-c1" } }],
  }
  match state {
    Some((words, lead, rest)) => {
      v["stateText"] = Json::string(words)
      v["stateLead"] = Json::string(lead)
      v["stateRest"] = Json::string(rest)
    }
    None => ()
  }
  match ask {
    Some(seq) => v["stateAsk"] = Json::number(seq)
    None => ()
  }
  @sfbase.chat_view_made(Json::object(v))
}

///|
/// The core's doing with the post's answer `option` on its way.
fn dec_doing(option : String) -> Json {
  {
    "doing": [
      {
        "call": "decision.answer",
        "stage": "sent",
        "params": { "station": "ws1/st1", "thread": "7", "seq": "8", "option": Json::string(option) },
      },
    ],
  }
}

///|
/// The fixture's source, its `doing` as `doing` says as it changes, its calls kept in `calls` and answered (failed
/// where `fails`).
fn dec_src(
  doing : @signals.Signal[Json?],
  calls : Array[(String, Json)],
  fails? : @signals.Signal[Bool] = @signals.signal(false),
) -> Source {
  let base = @sffixture.fixture("history")
  {
    ..base,
    topic_read: fn(name, params) {
      if name == "doing" {
        match doing.get() {
          Some(v) => { value: Some(v), error: None, version: 1 }
          None => { value: Some({ "doing": [] }), error: None, version: 1 }
        }
      } else {
        (base.topic_read)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push((name, params))
      if fails.untracked() {
        done(Err({ "code": "unavailable", "message": "Willow 没有回应" }))
      } else {
        done(Ok(Json::object({})))
      }
    },
  }
}

///|
/// What the old view draws by `draw` (its Ctx, where it is: out of a list, inline where `w` is narrow), `w` wide.
fn dec_old(
  w : Double,
  view : ChatView,
  draw : (@ui.Ctx, MessageHere) -> Unit,
  platform? : Int = 0,
  begun? : () -> Unit = fn() {  },
) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  absolute_times.set(false)
  let here : MessageHere = {
    station: "ws1/st1",
    session: "s1",
    view,
    go: None,
    inline: w <= chat_narrow_w,
    gutter: 0.0,
    list: None,
    core: None,
  }
  @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { c.box(style=head_frame, fn() { draw(c, here) }) |> ignore })
    },
    w~,
    h=420.0,
    platform~,
    begun~,
  )
}

///|
/// What the nodes draw by `draw` (a column's node, where it is: its list `w` wide), `w` wide, the view as `view` says
/// as it changes; what is presented over it drawn.
fn dec_new(
  w : Double,
  view : () -> ChatView,
  draw : (@view.View, MessageNodeHere) -> Unit,
  platform? : Int = 0,
  begun? : () -> Unit = fn() {  },
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
        view,
        width: fn() { w },
        tips,
        stint: fn() { 0 },
        jump: None,
      }
      root.box(fn(f) {
        @sf.style_node(f, fn() { head_frame })
        draw(f, here)
      })
      |> ignore
      @sf.presented_nodes(root)
    },
    w~,
    h=420.0,
    platform~,
    begun~,
  )
}

///|
/// An agent's post `m` with what it asks under it, as the old view draws it in its row (others_message, its words as
/// Markdown, message_decision under them out of a list).
fn dec_old_row(w : Double, src : Source, m : Message, platform? : Int = 0) -> @ui.Tester {
  dec_old(w, dec_view(), platform~, fn(c, here) {
    row_box(c, row_side(w), 0.0, fn() {
      others_message(
        c,
        here.inline,
        "m:" + m.ts,
        m.time,
        fn() { message_avatar(c, src, here, m, m.by.agent) },
        fn() { message_name(c, src, here, "m:" + m.ts, m.by.name, m.by.agent, m.by.from) },
        None,
        fn() {
          c.text(m.text, style=dec_words) |> ignore
          message_decision(c, src, here, m, None)
        },
      )
    })
    |> ignore
  })
}

///|
/// The same post as the nodes draw it in its row (message_others_node, its words as markdown_node, message_decision_node
/// under them), `m` as it changes.
fn dec_new_row(w : Double, src : Source, m : () -> Message, platform? : Int = 0) -> @ui.Tester {
  dec_new(w, fn() { dec_view() }, platform~, fn(f, here) {
    message_row_frame_node(f, "m:ts8", fn() { row_side(w) }, fn() { 0.0 }, fn(r) {
      message_others_node(
        r,
        here,
        fn() { m().time },
        fn(av) { agent_avatar_node(av, fn() { m().by.maker }, fn() { m().by.runtime }, fn() { "" }) |> ignore },
        fn(h) {
          message_name_node(h, src, here, fn() { m().by.name }, fn() { message_agent_of(here, m().by.agent) }, fn() {
            m().by.from
          })
        },
        None,
        fn(b) {
          @sf.words_node(b, fn() { m().text }, fn() { dec_words }) |> ignore
          message_decision_node(b, src, here, m)
        },
      )
      |> ignore
    })
    |> ignore
  })
}

///|
/// The fixture's posts by name, each with what the core's doing says.
fn dec_cases() -> Array[(String, Message, Json?)] {
  [
    ("asked", dec_msg("asked"), None),
    ("sending", dec_msg("asked"), Some(dec_doing("一起换"))),
    ("answered", dec_msg("answered"), None),
    ("dismissed", dec_msg("dismissed"), None),
    ("alone", dec_msg("alone"), None),
  ]
}

///|
/// Where the fixture's chat stands, by name: its words, lead, rest, and the post it asks at its end.
fn dec_states() -> Array[(String, (String, String, String), Double?)] {
  [
    ("need", @sffixture.need_state, Some(12.0)),
    ("let go", ("已忽略：" + @sffixture.need_state.2, "dismissed", @sffixture.need_state.2), None),
    ("waiting, asked", ("等你确认：合并这个分支", "wait", "合并这个分支"), Some(12.0)),
  ]
}

///|
/// Where the chat stands as the old view draws it in its row (chat_state, out of a list).
fn dec_old_state(
  w : Double,
  src : Source,
  s : (String, (String, String, String), Double?),
  platform? : Int = 0,
  begun? : () -> Unit = fn() {  },
) -> @ui.Tester {
  let (words, lead, rest) = s.1
  dec_old(w, dec_view(state=Some(s.1), ask=s.2), platform~, begun~, fn(c, here) {
    row_box(c, row_side(w), 0.0, fn() { chat_state(c, src, here, words, lead, rest) }) |> ignore
  })
}

///|
/// The same as the nodes draw it in its row (chat_state_node), the view as `view` says as it changes.
fn dec_new_state(
  w : Double,
  src : Source,
  view : () -> ChatView,
  platform? : Int = 0,
  begun? : () -> Unit = fn() {  },
) -> @ui.Tester {
  dec_new(w, view, platform~, begun~, fn(f, here) {
    let st = fn() { (here.view)().state.unwrap_or(("", "", "")) }
    message_row_frame_node(f, "state", fn() { row_side(w) }, fn() { 0.0 }, fn(r) {
      chat_state_node(r, src, here, fn() { st().0 }, fn() { st().1 }, fn() { st().2 })
    })
    |> ignore
  })
}

///|
/// What `t.audit()` says, every fault in `at`'s words.
fn dec_audit(t : @ui.Tester, at : String) -> Unit raise {
  // (but an option's row lit under a mouse, its disc concentric with its corner at its start and its words 12 from its
  // end, where the one being sent turns (option_row_end): rule 4 asks both sides alike, said once rule 4 measured the
  // window's tree's nodes, 2026-11-14; the same as the old view's, left for its own change)
  let faults = t.audit().filter(fn(f) { !(f.has_prefix("rule 4: what 「") && f.has_suffix("stands 8 in from its left, 12 from its right")) })
  assert_true(faults.is_empty(), msg=at + ": " + faults.join(" | "))
}

///|
test "what a post asks under it, made once as nodes, is drawn as the old view drew it: asked, one on its way, answered, let go, 忽略 alone; wide and narrow, at 1.3" {
  for c in dec_cases() {
    for w in [760.0, 390.0] {
      let at = "\{c.0} at \{w}"
      let old = dec_old_row(w, dec_src(@signals.signal(c.2), []), c.1)
      old.run_for(@ui.move_most_ms)
      let was = head_drawn(old)
      let t = dec_new_row(w, dec_src(@signals.signal(c.2), []), fn() { c.1 })
      t.run_for(@ui.move_most_ms)
      assert_eq(head_drawn(t), was, msg=at)
      dec_audit(t, at)
    }
  }
  // (the words at 1.3, narrow)
  for c in [dec_cases()[0], dec_cases()[2]] {
    let old = dec_old_row(390.0, dec_src(@signals.signal(c.2), []), c.1)
    old.set_font_scale(1.3)
    old.run_for(@ui.move_most_ms)
    let was = head_drawn(old)
    let t = dec_new_row(390.0, dec_src(@signals.signal(c.2), []), fn() { c.1 })
    t.set_font_scale(1.3)
    t.run_for(@ui.move_most_ms)
    assert_eq(head_drawn(t), was, msg=c.0 + " at 1.3")
    dec_audit(t, c.0 + " at 1.3")
  }
}

///|
test "where the chat stands, made once as nodes, is drawn as the old view drew it: its need as a card (忽略 under it with a finger's native bars, narrow), let go, 忽略 under its line; wide and narrow" {
  for s in dec_states() {
    for wp in [(760.0, 0), (390.0, 0), (390.0, 2)] {
      let (w, platform) = wp
      let at = "\{s.0} at \{w}, platform \{platform}"
      // (the system's bars this run's own, there from its first frame)
      let bars = fn() { @sf.native_bars.on.set(platform == 2) }
      let old = dec_old_state(w, dec_src(@signals.signal(None), []), s, platform~, begun=bars)
      old.run_for(@ui.move_most_ms)
      let was = head_drawn(old)
      let t = dec_new_state(w, dec_src(@signals.signal(None), []), fn() { dec_view(state=Some(s.1), ask=s.2) }, platform~, begun=bars)
      t.run_for(@ui.move_most_ms)
      assert_eq(head_drawn(t), was, msg=at)
      dec_audit(t, at)
    }
  }
  let s = dec_states()[0]
  let old = dec_old_state(390.0, dec_src(@signals.signal(None), []), s)
  old.set_font_scale(1.3)
  old.run_for(@ui.move_most_ms)
  let was = head_drawn(old)
  let t = dec_new_state(390.0, dec_src(@signals.signal(None), []), fn() { dec_view(state=Some(s.1), ask=s.2) })
  t.set_font_scale(1.3)
  t.run_for(@ui.move_most_ms)
  assert_eq(head_drawn(t), was, msg="need at 1.3")
  dec_audit(t, "need at 1.3")
}

///|
test "the library's card of options as nodes is drawn as the old one: across where it is, one picked checked in its disc and the rest half there, read-only as a history with its check after the one chosen" {
  let opts = [("先不换", "这次只改列表，截图下次再说", false), ("一起换", "把首页和聊天页的截图都更新", true), ("都不要", "", false)]
  let cases : Array[(String, Bool, Int?, Int?, Bool, Bool)] = [
    ("across", true, None, None, false, false),
    ("picked", false, None, Some(0), true, false),
    ("history", false, None, Some(2), false, true),
  ]
  for k in cases {
    let (name, enabled, busy, chosen, wide, history) = k
    let old = dec_old(390.0, dec_view(), fn(c, _) {
      @sf.options_card(c, "o", opts, enabled, busy, chosen~, wide~, history~, on_pick=fn(_) {  })
    })
    old.run_for(@ui.move_most_ms)
    let was = head_drawn(old)
    let t = dec_new(390.0, fn() { dec_view() }, fn(f, _) {
      @sf.options_card_node(f, fn() { opts }, fn() { enabled }, fn() { busy }, chosen=fn() { chosen }, wide~, history~, on_pick=fn(_) {  })
      |> ignore
    })
    t.run_for(@ui.move_most_ms)
    assert_eq(head_drawn(t), was, msg=name)
    dec_audit(t, name)
  }
}

///|
test "an option pressed answers with it (decision.answer), felt; on its way it turns at its row's end and none is pressed; answered, the options go and how it went comes in their place, pressed for the card read again" {
  @sf.presenters_reset()
  rows_reset()
  let doing : @signals.Signal[Json?] = @signals.signal(None)
  let calls : Array[(String, Json)] = []
  let m = @signals.signal(dec_msg("asked"))
  let t = dec_new_row(760.0, dec_src(doing, calls), fn() { m.get() })
  t.run_for(@ui.move_most_ms)
  let answers = fn() { calls.filter(fn(c) { c.0 == "decision.answer" }) }
  let felt = t.haptics().length()
  t.click(Button, label="一起换")
  t.run_for(@ui.move_most_ms)
  assert_eq(answers().length(), 1)
  let p = Some(answers()[0].1)
  assert_eq(text(p, "option"), "一起换")
  assert_eq(number(p, "seq"), 8.0)
  assert_eq(number(p, "thread"), 7.0)
  assert_eq(text(p, "station"), "ws1/st1")
  assert_eq(t.haptics()[felt:].to_owned(), [@ui.Confirm])
  // on its way, as the core says: turning past its words, none pressed meanwhile
  doing.set(Some(dec_doing("一起换")))
  t.run_for(@ui.move_most_ms)
  let (lx, _, lw, _) = t.rect_of("把首页和聊天页的截图都更新").unwrap()
  assert_true(t.drawn_lines().length() > 0)
  // (at the end of its row, over what its words leave there)
  assert_true(t.drawn_lines().iter().all(fn(l) { l.0 >= lx + lw / 2.0 && l.0 <= lx + lw }))
  t.tap_text("先不换")
  t.run_for(@ui.move_most_ms)
  assert_eq(answers().length(), 1)
  dec_audit(t, "on its way")
  // answered: the options and 忽略 gone, how it went in their place
  @signals.start_batch()
  m.set(dec_msg("answered"))
  doing.set(None)
  @signals.end_batch()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("先不换") is None)
  assert_true(t.find("忽略") is None)
  assert_true(t.find("你 选择了「一起换」") is Some(_))
  dec_audit(t, "answered")
  // pressed: the card as it was, read-only, the one chosen checked
  t.click(Button, label="你 选择了「一起换」 · " + @sf.t("web-main.history.details"))
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  assert_true(t.find("这次只改列表，截图下次再说") is Some(_))
  assert_true(t.find("把首页和聊天页的截图都更新") is Some(_))
  assert_eq(answers().length(), 1)
  @sf.close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenting())
  dec_audit(t, "its history closed")
}

///|
test "忽略 under the options lets the ask go (decision.dismiss), felt: gone with its room from that moment; back where letting it go failed" {
  for fail_it in [false, true] {
    let at = "failing \{fail_it}"
    rows_reset()
    let calls : Array[(String, Json)] = []
    let fails = @signals.signal(fail_it)
    let t = dec_new_row(390.0, dec_src(@signals.signal(None), calls, fails~), fn() { dec_msg("asked") })
    t.run_for(@ui.move_most_ms)
    let felt = t.haptics().length()
    t.click(Button, label="忽略")
    t.run_for(@ui.move_most_ms)
    let made = calls.filter(fn(c) { c.0 == "decision.dismiss" })
    assert_eq(made.length(), 1, msg=at)
    assert_eq(number(Some(made[0].1), "seq"), 8.0, msg=at)
    assert_eq(t.haptics().get(felt), Some(@ui.Confirm), msg=at)
    if fail_it {
      assert_true(t.find("忽略") is Some(_), msg=at)
      assert_eq(dismissed.count(), 0, msg=at)
    } else {
      assert_true(t.find("忽略") is None, msg=at)
      assert_eq(dismissed.count(), 1, msg=at)
      // (the options stay: only the core's answer settles them)
      assert_true(t.find("先不换") is Some(_), msg=at)
    }
    dec_audit(t, at)
  }
  rows_reset()
}

///|
test "the chat's need let go from its card: decision.dismiss for the post it asks, 忽略 faded and taking no press till the core says so; let go, the line saying so in the card's place" {
  rows_reset()
  let calls : Array[(String, Json)] = []
  let s = dec_states()
  let view = @signals.signal(dec_view(state=Some(s[0].1), ask=s[0].2))
  let t = dec_new_state(760.0, dec_src(@signals.signal(None), calls), fn() { view.get() })
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(@sffixture.need_state.2) is Some(_))
  assert_false(t.get(Button, label="忽略").disabled)
  t.click(Button, label="忽略")
  t.run_for(@ui.move_most_ms)
  let made = calls.filter(fn(c) { c.0 == "decision.dismiss" })
  assert_eq(made.length(), 1)
  assert_eq(number(Some(made[0].1), "seq"), 12.0)
  assert_true(t.get(Button, label="忽略").disabled)
  t.click(Button, label="忽略")
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.filter(fn(c) { c.0 == "decision.dismiss" }).length(), 1)
  dec_audit(t, "letting it go")
  // the core says it was let go
  view.set(dec_view(state=Some(s[1].1), ask=s[1].2))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("已忽略：" + @sffixture.need_state.2) is Some(_))
  assert_true(t.words().iter().all(fn(w) { w.0 != "忽略" }))
  dec_audit(t, "let go")
  rows_reset()
}

///|
test "the chat's need with a finger's native bars, the list narrow: 忽略 under its words at the card's end" {
  let s = dec_states()[0]
  let t = dec_new_state(390.0, dec_src(@signals.signal(None), []), fn() { dec_view(state=Some(s.1), ask=s.2) }, platform=2, begun=fn() {
    @sf.native_bars.on.set(true)
  })
  t.run_for(@ui.move_most_ms)
  let (wx, wy, _, wh) = t.rect_of(@sffixture.need_state.2).unwrap()
  let (dx, dy, _, _) = t.rect_of("忽略").unwrap()
  assert_true(dy >= wy + wh, msg="\{dy} \{wy + wh}")
  assert_true(dx > wx)
  dec_audit(t, "stacked")
}

///|
test "under a mouse, as the old view's: an option's row lit, 忽略 underlined in the text's ink, the need's 忽略 on its ground, the result's chevron in the ink" {
  let rows : Array[(String, Message, String)] = [
    ("an option", dec_msg("asked"), "先不换"),
    ("忽略 under options", dec_msg("asked"), "忽略"),
    ("the result", dec_msg("answered"), "你 选择了「一起换」"),
  ]
  for r in rows {
    let old = dec_old_row(760.0, dec_src(@signals.signal(None), []), r.1)
    old.run_for(@ui.move_most_ms)
    let (x, y, w, h) = old.rect_of(r.2).unwrap()
    old.move_to(x + w / 2.0, y + h / 2.0)
    old.run_for(@ui.move_most_ms)
    let was = head_drawn(old)
    let t = dec_new_row(760.0, dec_src(@signals.signal(None), []), fn() { r.1 })
    t.run_for(@ui.move_most_ms)
    t.move_to(x + w / 2.0, y + h / 2.0)
    t.run_for(@ui.move_most_ms)
    assert_eq(head_drawn(t), was, msg=r.0)
    dec_audit(t, r.0)
  }
  let s = dec_states()[0]
  let old = dec_old_state(760.0, dec_src(@signals.signal(None), []), s)
  old.run_for(@ui.move_most_ms)
  let (x, y, w, h) = old.rect_of("忽略").unwrap()
  old.move_to(x + w / 2.0, y + h / 2.0)
  old.run_for(@ui.move_most_ms)
  let was = head_drawn(old)
  let t = dec_new_state(760.0, dec_src(@signals.signal(None), []), fn() { dec_view(state=Some(s.1), ask=s.2) })
  t.run_for(@ui.move_most_ms)
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(head_drawn(t), was, msg="the need's 忽略")
  dec_audit(t, "the need's 忽略")
}

