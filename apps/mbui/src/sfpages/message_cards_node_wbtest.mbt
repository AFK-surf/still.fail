// An agent's request as its card in place of its post's words, as nodes (message_cards_node.mbt; settings'
// rig_ask_node, ask_answered_node; the library's ask_card_node), set beside the old view's (decision.mbt's
// rig_ask_card, in a list's row so that how it went is pressed for the card read again, as there) on the same
// fixture: a rig's request waiting, someone else's, on a web page, on a device not approved, for one device, under way;
// granted, waiting for the rig, ended, refused; wide, narrow, at 1.3.

///|
/// The workspace the fixture's chat is of.
let card_ws : Workspace = { id: "ws1", name: "星火工作室", emoji: "", icon: "", email: "" }

///|
/// The fixture's chat's view: thread 7, its agent, the viewer lin@example.com (whose the rig is).
fn card_view() -> ChatView {
  @sfbase.chat_view_made({
    "title": "修 CI",
    "messages": [],
    "thread": { "id": 7 },
    "agents": [{ "session": { "key": "s-c1" } }],
    "me": { "email": "lin@example.com" },
  })
}

///|
/// The core's doing with `call` about request r-1 on the chat's station under way.
fn card_doing(call : String) -> Json {
  { "doing": [{ "call": Json::string(call), "stage": "sent", "params": { "station": "ws1/st1", "request": "r-1" } }] }
}

///|
/// The fixture `mode`'s source, its `doing` as `doing` says (none: the fixture's), its calls kept in `calls` and never
/// answered (what was pressed stays under way).
fn card_src(mode : String, doing? : Json? = None, calls? : Array[(String, Json)] = []) -> Source {
  let base = @sffixture.fixture(mode)
  {
    ..base,
    topic_read: fn(name, params) {
      match (name, doing) {
        ("doing", Some(d)) => { value: Some(d), error: None, version: 1 }
        _ => (base.topic_read)(name, params)
      }
    },
    call: fn(name, params, _) { calls.push((name, params)) },
  }
}

///|
/// chat-rig's post asking for the rig build-box (`mine`: the viewer's; `device`: one of its devices alone), decided as
/// `state` says ("": waiting; granted, away, ended, denied); said 30 分钟前, as the other rows' fixtures are (the
/// head's own, not what is compared here: 刚刚's room is its neighbour's, message_head_node's).
fn card_rig(state : String, mine? : Bool = true, device? : Bool = false) -> Message {
  @sffixture.fix_rig.val = state
  let j = @sffixture.rig_post(mine, device~)
  @sffixture.fix_rig.val = ""
  card_said_then(j)
}

///|
/// Post `j` said 30 分钟前.
fn card_said_then(j : Json) -> Message {
  match j {
    Object(o) => o["time"] = @sffixture.ago("30 分钟前", "2026-11-11 20:40")
    _ => ()
  }
  @sfbase.message_of(j)
}

///|
/// Post `m` with its card in place of its words as the old view draws it in a list's row `list` (others_message, the
/// card by `card`), answered with the settings' core over `src`, `w` wide.
fn card_old(
  w : Double,
  src : Source,
  m : Message,
  list : String,
  card : (@ui.Ctx, MessageHere) -> Unit,
  platform? : Int = 0,
) -> @ui.Tester {
  @settings.reset()
  @sf.set_words(@sfbase.fill)
  absolute_times.set(false)
  let view = card_view()
  @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      let here : MessageHere = {
        station: "ws1/st1",
        session: "s-c1",
        view,
        go: None,
        inline: w <= chat_narrow_w,
        gutter: 0.0,
        list: Some({ rk: list, turns: @sfbase.turns_of(list), emits: @sfbase.emits_of(list), flight: None }),
        core: Some(@sfbase.settings_core(src, card_ws)),
      }
      c.with_theme(@sf.ui_theme(), fn() {
        c.box(style=head_frame, fn() {
          row_box(c, row_side(w), 0.0, fn() {
            others_message(
              c,
              here.inline,
              "m:" + m.ts,
              m.time,
              fn() { message_avatar(c, src, here, m, m.by.agent) },
              fn() { message_name(c, src, here, "m:" + m.ts, m.by.name, m.by.agent, m.by.from) },
              None,
              fn() { card(c, here) },
            )
          })
          |> ignore
        })
        |> ignore
      })
    },
    w~,
    h=420.0,
    platform~,
  )
}

///|
/// The old view's rig card for post `m` (rig_ask_card).
fn card_old_rig(c : @ui.Ctx, here : MessageHere, m : Message) -> Unit {
  match m.card {
    Some({ rig: Some(ask), .. } as card) => rig_ask_card(c, here, m, card, ask)
    _ => ()
  }
}

///|
/// The same post as the nodes draw it in its row (message_others_node, message_card_node), `m` as it changes.
fn card_new(w : Double, src : Source, m : () -> Message, platform? : Int = 0) -> @ui.Tester {
  @settings.reset()
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
        session: "s-c1",
        view: card_view,
        width: fn() { w },
        tips,
        stint: fn() { 0 },
      }
      let core = Some(@sfbase.settings_core(src, card_ws))
      root.box(fn(f) {
        @sf.style_node(f, fn() { head_frame })
        message_row_frame_node(f, "m:ts63", fn() { row_side(w) }, fn() { 0.0 }, fn(r) {
          message_others_node(
            r,
            here,
            fn() { m().time },
            fn(av) { agent_avatar_node(av, fn() { m().by.maker }, fn() { m().by.runtime }, fn() { "" }) },
            fn(h) {
              message_name_node(h, src, here, fn() { m().by.name }, fn() { message_agent_of(here, m().by.agent) }, fn() {
                m().by.from
              })
            },
            None,
            fn(b) { message_card_node(b, here, core, m) },
          )
          |> ignore
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
/// The rig's request's states by name: the fixture's mode, the post, the core's doing.
fn card_rig_cases() -> Array[(String, String, Message, Json?)] {
  [
    ("waiting", "chat-rig", card_rig(""), None),
    ("theirs", "chat-rig-other", card_rig("", mine=false), None),
    ("web", "chat-rig-web", card_rig(""), None),
    ("outside", "chat-rig-outside", card_rig(""), None),
    ("device", "chat-rig-device", card_rig("", device=true), None),
    ("under way", "chat-rig", card_rig(""), Some(card_doing("rig.decide"))),
    ("granted", "chat-rig", card_rig("granted"), None),
    ("away", "chat-rig", card_rig("away"), None),
    ("ended", "chat-rig", card_rig("ended"), None),
    ("denied", "chat-rig", card_rig("denied"), None),
  ]
}


///|
/// What `t.audit()` says, the rooms of what stands over and under each other where the line saying how a request went
/// is right under its post's head (in place of its words) aside: the head's name and time and that line, each
/// left 32 high to be pressed in by the other (laid out as the old view's is, whose rooms nothing checks). Exactly
/// `rooms` of those, nothing else.
fn card_audit(t : @ui.Tester, at : String, rooms : Int) -> Unit raise {
  let faults = t.audit()
  let stacked = fn(f : String) {
    f.has_prefix("room: ") &&
    f.contains("×32 to be pressed in, under 36") &&
    (f.contains("stillfail/src/sfpages/message_head_node.mbt:") || f.contains("stillfail/src/sfapp/settings/ask_answered_node.mbt:"))
  }
  let rest = faults.filter(fn(f) { !stacked(f) })
  assert_true(rest.is_empty(), msg=at + ": " + rest.join(" | "))
  assert_eq(faults.length() - rest.length(), rooms, msg=at + ": " + faults.join(" | "))
}

///|
/// The old view's drawing of the rig's request `c` (card_rig_cases'), `w` wide at `scale`, as a mouse is moved to the
/// middle of `over` ("" none) or a finger presses `press` ("" none), then the same drawn by the nodes: both, and the
/// new one's Tester.
fn card_rig_both(
  c : (String, String, Message, Json?),
  w : Double,
  scale? : Double = 1.0,
  over? : String = "",
  press? : String = "",
) -> (String, String, @ui.Tester) raise {
  let at = "rig \{c.0} \{w} \{scale} \{over} \{press}"
  let old = card_old(w, card_src(c.1, doing=c.3), c.2, at, fn(x, here) { card_old_rig(x, here, c.2) })
  old.set_font_scale(scale)
  old.run_for(@ui.move_most_ms)
  let mut point = (0.0, 0.0)
  if over != "" {
    let (x, y, ww, h) = old.rect_of(over).unwrap()
    point = (x + ww / 2.0, y + h / 2.0)
    old.move(point.0, point.1)
    old.run_for(@ui.move_most_ms)
  }
  if press != "" {
    old.tap_text(press)
    old.run_for(@ui.move_most_ms)
  }
  let was = head_drawn(old)
  let t = card_new(w, card_src(c.1, doing=c.3), fn() { c.2 })
  t.set_font_scale(scale)
  t.run_for(@ui.move_most_ms)
  if over != "" {
    t.move(point.0, point.1)
    t.run_for(@ui.move_most_ms)
  }
  if press != "" {
    t.tap_text(press)
    t.run_for(@ui.move_most_ms)
  }
  (was, head_drawn(t), t)
}

///|
test "a rig's request in place of its post's words, made once as nodes, is drawn as the old view drew it: waiting, another's, on a web page, on a device not approved, one device, under way; granted, waiting for the rig, ended, refused; wide and narrow, at 1.3, under a mouse, pressed" {
  for w in [760.0, 390.0] {
    let mut waiting = ""
    for c in card_rig_cases() {
      let at = "\{c.0} at \{w}"
      let (was, now, t) = card_rig_both(c, w)
      assert_eq(now, was, msg=at)
      // (each state drawn as it is, not as the one it starts from)
      if c.0 == "waiting" {
        waiting = now
      } else {
        assert_true(now != waiting, msg=at + ": drawn as waiting")
      }
      card_audit(t, at, if c.2.card is Some({ rig: Some({ status: "", .. }), .. }) { 0 } else { 3 })
    }
  }
  let cases = card_rig_cases()
  for c in [cases[0], cases[6]] {
    let at = "\{c.0} at 1.3"
    let (was, now, t) = card_rig_both(c, 390.0, scale=1.3)
    assert_eq(now, was, msg=at)
    card_audit(t, at, if c.0 == "waiting" { 0 } else { 3 })
  }
  for over in ["拒绝", "闲置 1 小时"] {
    let (was, now, t) = card_rig_both(cases[0], 760.0, over~)
    assert_eq(now, was, msg="under a mouse: " + over)
    card_audit(t, "under a mouse: " + over, 0)
  }
  let (was, now, t) = card_rig_both(cases[0], 760.0, press="允许")
  assert_eq(now, was, msg="pressed")
  card_audit(t, "pressed", 0)
}

///|
test "a rig's request allowed: rig.decide with what the card said of the chat and the time asked; the button turning, neither pressed again till the core has it; refused, asked with no time" {
  let calls : Array[(String, Json)] = []
  let t = card_new(760.0, card_src("chat-rig", calls~), fn() { card_rig("") })
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="允许")
  t.run_for(@ui.move_most_ms)
  let made = calls.filter(fn(c) { c.0 == "rig.decide" })
  assert_eq(made.length(), 1)
  let p = Some(made[0].1)
  assert_eq(text(p, "station"), "ws1/st1")
  assert_eq(text(p, "request"), "r-1")
  assert_true(flag(p, "allow"))
  assert_eq(text(p, "timeoutKind"), "idle")
  assert_eq(number(p, "timeoutSeconds"), 3600.0)
  let ask = field(p, "ask")
  assert_eq(text(ask, "rig"), "aa11")
  assert_eq(text(ask, "session"), "s-c1")
  assert_eq(text(ask, "chat"), "CHAT/1")
  assert_eq(text(ask, "title"), "修 CI")
  assert_eq(text(ask, "by"), "lin@example.com")
  // (turning past its words, neither taking a press)
  assert_true(t.drawn_lines().length() > 0)
  assert_true(t.get(Button, label="允许").disabled)
  assert_true(t.get(Button, label="拒绝").disabled)
  t.click(Button, label="拒绝")
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.filter(fn(c) { c.0 == "rig.decide" }).length(), 1)
  card_audit(t, "allowed", 0)
  let calls : Array[(String, Json)] = []
  let t = card_new(390.0, card_src("chat-rig", calls~), fn() { card_rig("") })
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="拒绝")
  t.run_for(@ui.move_most_ms)
  let made = calls.filter(fn(c) { c.0 == "rig.decide" })
  assert_eq(made.length(), 1)
  assert_false(flag(Some(made[0].1), "allow"))
  assert_eq(text(Some(made[0].1), "timeoutKind"), "")
  card_audit(t, "refused", 0)
}

///|
test "a rig's request's time chosen at its card's foot: its menu of every time, the one asked checked; 8 hours chosen, said so and allowed for them" {
  @sf.presenters_reset()
  let calls : Array[(String, Json)] = []
  let t = card_new(760.0, card_src("chat-rig", calls~), fn() { card_rig("") })
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="闲置 1 小时")
  t.run_for(@ui.move_most_ms)
  for words in ["闲置 1 小时后失效", "1 小时后失效", "8 小时后失效", "1 天后失效", "7 天后失效"] {
    assert_true(card_has(t, words), msg=words)
  }
  t.tap_text("8 小时后失效")
  t.run_for(@ui.move_most_ms)
  assert_false(card_has(t, "1 天后失效"))
  assert_true(card_has(t, "固定 8 小时"))
  t.click(Button, label="允许")
  t.run_for(@ui.move_most_ms)
  let made = calls.filter(fn(c) { c.0 == "rig.decide" })
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].1), "timeoutKind"), "fixed")
  assert_eq(number(Some(made[0].1), "timeoutSeconds"), 28800.0)
  card_audit(t, "8 hours", 0)
}

///|
test "a rig's request decided as its card shows: the card goes, the line saying how it went in its place; pressed, what was asked read again" {
  @sf.presenters_reset()
  let m = @signals.signal(card_rig(""))
  let t = card_new(760.0, card_src("chat-rig"), fn() { m.get() })
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("在 Linux 上跑一遍完整的 station 测试") is Some(_))
  m.set(card_rig("granted"))
  t.run_for(@ui.move_most_ms)
  assert_false(card_has(t, "允许"))
  assert_true(t.find("在 Linux 上跑一遍完整的 station 测试") is None)
  let line = "已允许使用这台 station · 8 小时后失效"
  assert_true(t.find(line) is Some(_))
  card_audit(t, "decided", 3)
  t.click(Button, label=line + " · " + @sf.t("web-main.history.details"))
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  assert_true(t.find("允许这个对话的 agent 使用 station「build-box」？") is Some(_))
  assert_true(t.find("在 Linux 上跑一遍完整的 station 测试") is Some(_))
  @sf.close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenting())
}

///|
/// Whether `t` draws `words` as a run of its own (Tester::find also finds them within others).
fn card_has(t : @ui.Tester, words : String) -> Bool {
  t.words().iter().any(fn(w) { w.0 == words })
}
