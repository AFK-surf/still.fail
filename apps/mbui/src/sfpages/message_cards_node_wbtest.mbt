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
/// The core's doing with `call` about `request` on the chat's station under way.
fn card_doing(call : String, request? : String = "r-1") -> Json {
  {
    "doing": [
      { "call": Json::string(call), "stage": "sent", "params": { "station": "ws1/st1", "request": Json::string(request) } },
    ],
  }
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
/// card by `card`), answered with the settings' core over `src`, `w` wide; `begun` done as its run begins, before its
/// first frame (what the host has: a password manager).
fn card_old(
  w : Double,
  src : Source,
  m : Message,
  list : String,
  card : (@ui.Ctx, MessageHere) -> Unit,
  platform? : Int = 0,
  begun? : () -> Unit = fn() {  },
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
    begun~,
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
/// The corner rule's fault known in a phone's request (Tester::corners_known), kept till the card is put in the chat
/// (the coordinator of the migration, 2026-11-12; xfer's list of what is shown before that): the key at its foot saying
/// how long it lasts (14 round, a capsule 28 tall), under the hand or with the focus, stands 10 in from the card's side
/// and 12 over its foot in its 26 corner, as the old card's does: as far from neither edge as from the other, so no
/// corner of it is concentric there (26 − 12 = 14 by its foot, 26 − 10 = 16 by its side). What would mend it: the key
/// 12 in from the side too.
// kept across runs: a value (no field of it changes)
let card_phone_corners_known : Array[String] = [
  "「闲置 1 小时后失效」 (at 186,133 143×28, node 48) (corner 14) in the bottom right of 「允许这个对话的 agent 调试你的手机？ 装上…」 (at 16,52 323×121, node 20) (corner 26): 10 and 12 from its edges",
]

///|
/// The same post as the nodes draw it in its row (message_others_node, its words' place by `body`: message_card_node
/// unless it says otherwise), `m` as it changes; `begun`: card_old's.
fn card_new(
  w : Double,
  src : Source,
  m : () -> Message,
  platform? : Int = 0,
  body? : ((@view.View, MessageNodeHere, @settings.Core?) -> Unit)? = None,
  begun? : () -> Unit = fn() {  },
) -> @ui.Tester {
  @settings.reset()
  @sf.set_words(@sfbase.fill)
  absolute_times.set(false)
  let t = @ui.Tester::new(
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
        jump: None,
      }
      let core = Some(@sfbase.settings_core(src, card_ws))
      root.box(fn(f) {
        @sf.style_node(f, fn() { head_frame })
        message_row_frame_node(f, "m:ts63", fn() { row_side(w) }, fn() { 0.0 }, fn(r) {
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
              match body {
                Some(f) => f(b, here, core)
                None => message_card_node(b, here, core, m)
              }
            },
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
    begun~,
  )
  t.corners_known(card_phone_corners_known)
  t
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
/// How many of card_audit's rooms the rig's request `c` (card_rig_cases') has: none while it is asked; decided, the
/// head's name and time, and the line saying how it went where it is short enough that its middle is under the time
/// (「已批准，等它上线」 112 wide, 「已拒绝使用这台 station」 148, from 40; 「已允许使用这台 station · 8 小时后失效」 and an
/// ended one's are longer).
fn card_rig_rooms(c : (String, String, Message, Json?)) -> Int {
  match c.0 {
    "granted" | "ended" => 2
    "away" | "denied" => 3
    _ => 0
  }
}

///|
/// What `t.audit()` says, the rooms of what stands over and under each other where the line saying how a request went
/// is right under its post's head (in place of its words) aside: the head's name and time and that line, each
/// left 32 high to be pressed in by the other (laid out as the old view's is, whose rooms nothing checks). Exactly
/// `rooms` of those, nothing else. Each is measured as a press lands, along the lines through its middle: the line is
/// said where its middle is under the head's time (card_rig_rooms), not where it is long enough that its middle is past
/// it, though its start is as near.
fn card_audit(t : @ui.Tester, at : String, rooms : Int) -> Unit raise {
  let faults = t.audit()
  let stacked = fn(f : String) {
    f.has_prefix("room: ") &&
    f.contains("×32 to be pressed in, under 36") &&
    (f.contains("stillfail/src/sfpages/message_head_node.mbt:") || f.contains("stillfail/src/sfapp/settings/ask_answered_node.mbt:"))
  }
  // (the corner rule's fault known at a phone's request's foot, where it shows: card_phone_corners_known)
  let cornered = card_phone_corners_known.map(@ui.corner_fault_unplaced)
  let rest = faults.filter(fn(f) { !stacked(f) && !cornered.contains(@ui.corner_fault_unplaced(f)) })
  assert_true(rest.is_empty(), msg=at + ": " + rest.join(" | "))
  assert_eq(faults.filter(stacked).length(), rooms, msg=at + ": " + faults.join(" | "))
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
) -> (String, String, @ui.Tester) {
  let at = "rig \{c.0} \{w} \{scale} \{over} \{press}"
  let old = card_old(w, card_src(c.1, doing=c.3), c.2, at, fn(x, here) { card_old_rig(x, here, c.2) })
  old.set_font_scale(scale)
  old.run_for(@ui.move_most_ms)
  let mut point = (0.0, 0.0)
  if over != "" {
    let (x, y, ww, h) = old.rect_of(over).unwrap()
    point = (x + ww / 2.0, y + h / 2.0)
    old.move_to(point.0, point.1)
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
    t.move_to(point.0, point.1)
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
      card_audit(t, at, card_rig_rooms(c))
    }
  }
  let cases = card_rig_cases()
  for c in [cases[0], cases[6]] {
    let at = "\{c.0} at 1.3"
    let (was, now, t) = card_rig_both(c, 390.0, scale=1.3)
    assert_eq(now, was, msg=at)
    card_audit(t, at, card_rig_rooms(c))
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
  // (granted: its line's middle past the head's time, card_rig_rooms)
  card_audit(t, "decided", 2)
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

///|
/// A login of the chat's station as the core says it (`state`, active or not), `more` over it.
fn card_login(active : Bool, state : String, more? : Map[String, Json] = {}) -> Json {
  let l : Map[String, Json] = {
    "id": "login-1",
    "title": "在 Willow 上登录 gh",
    "state": Json::string(state),
    "active": Json::boolean(active),
    "statusText": "等你在浏览器里登录",
    "domain": "github.com",
  }
  for k, v in more {
    l[k] = v
  }
  Json::object(l)
}

///|
/// The fixture's source, its station's login as `login` says (None: none it knows), finished here where `can`; its
/// calls kept in `calls`, never answered.
fn card_login_src(login : Json?, can? : Bool = true, calls? : Array[(String, Json)] = []) -> Source {
  let base = @sffixture.fixture("chat")
  {
    ..base,
    topic_read: fn(name, params) {
      match name {
        "machineLogin" => { value: Some(login.unwrap_or(Json::null())), error: None, version: 1 }
        "machineLogins" => { value: Some({ "canLogin": Json::boolean(can), "canRelay": true }), error: None, version: 1 }
        _ => (base.topic_read)(name, params)
      }
    },
    call: fn(name, params, _) { calls.push((name, params)) },
  }
}

///|
/// The agent's post asking its login to be finished (`who`: who is to finish it; `asked`: 忽略 under it; `settled`:
/// answered; `station`: another station of the workspace's, by its name there).
fn card_login_post(who? : String = "", asked? : Bool = false, settled? : Bool = false, station? : String = "") -> Message {
  let card : Map[String, Json] = { "type": "login", "login": "login-1" }
  if station != "" {
    card["station"] = Json::string(station)
  }
  if who != "" {
    card["assigneeText"] = Json::string(who)
  }
  card_said_then(
    @sffixture.msg(9, "agent", @sffixture.by_agent("Anthropic", "claude", "s-c1"), "在 Willow 上登录一下 gh，我再接着推。", "", {
      "card": Json::object(card),
      "asked": Json::boolean(asked),
      "decision": if settled { { "resolved": true } } else { { "resolved": false } },
    }),
  )
}

///|
/// The login's states by name: its source, the post.
fn card_login_cases() -> Array[(String, Source, Message)] {
  [
    ("under way", card_login_src(Some(card_login(true, "browser"))), card_login_post()),
    ("not here", card_login_src(Some(card_login(true, "browser")), can=false), card_login_post()),
    ("whose, asked", card_login_src(Some(card_login(true, "browser"))), card_login_post(who="等 林 完成", asked=true)),
    ("settled", card_login_src(Some(card_login(true, "browser"))), card_login_post(who="等 林 完成", asked=true, settled=true)),
    ("done", card_login_src(Some(card_login(false, "done", more={ "statusText": "已在 Willow 上登录 gh" }))), card_login_post()),
    ("failed", card_login_src(Some(card_login(false, "failed", more={ "statusText": "登录失败" }))), card_login_post()),
    ("unknown, asked", card_login_src(None), card_login_post(asked=true)),
  ]
}

///|
/// The login's post `m` over `src` as the old view draws it (its words plain, message_decision under them in a list's
/// row), `w` wide at `scale`; then as the nodes do (message_decision_node with the core): both, and the new one's Tester.
fn card_login_both(
  src : Source,
  m : Message,
  w : Double,
  at : String,
  scale? : Double = 1.0,
) -> (String, String, @ui.Tester) {
  let old = card_old(w, src, m, at, fn(x, here) {
    x.text(m.text, style=dec_words) |> ignore
    message_decision(x, src, here, m, here.list.map(fn(l) { l.turns }))
  })
  old.set_font_scale(scale)
  old.run_for(@ui.move_most_ms)
  let was = head_drawn(old)
  let t = card_login_new(w, src, fn() { m })
  t.set_font_scale(scale)
  t.run_for(@ui.move_most_ms)
  (was, head_drawn(t), t)
}

///|
/// The login's post `m` (as it changes) over `src` as the nodes draw it, `w` wide.
fn card_login_new(w : Double, src : Source, m : () -> Message) -> @ui.Tester {
  card_new(w, src, m, body=Some(fn(b, here, core) {
    @sf.words_node(b, fn() { m().text }, fn() { dec_words }) |> ignore
    message_decision_node(b, src, here, m, core~)
  }))
}

///|
test "a login's card under its post, made once as nodes, is drawn as the old view drew it: under way, not to be finished here, whose it is with 忽略, answered, done, failed, one the core does not know; wide and narrow, at 1.3" {
  let cases = card_login_cases()
  for w in [760.0, 390.0] {
    let drawn : Map[String, String] = Map([])
    for c in cases {
      let at = "\{c.0} at \{w}"
      let (was, now, t) = card_login_both(c.1, c.2, w, at)
      assert_eq(now, was, msg=at)
      drawn[c.0] = now
      dec_audit(t, at)
    }
    // (each state drawn as it is, not as the one it is told from: under way, or answered from whose it is)
    for c in cases {
      let from = if c.0 == "settled" { "whose, asked" } else { "under way" }
      if c.0 != from {
        assert_true(drawn.get(c.0) != drawn.get(from), msg="\{c.0} at \{w}: drawn as \{from}")
      }
    }
  }
  for i in [0, 2] {
    let c = cases[i]
    let at = "\{c.0} at 1.3"
    let (was, now, t) = card_login_both(c.1, c.2, 390.0, at, scale=1.3)
    assert_eq(now, was, msg=at)
    dec_audit(t, at)
  }
}

///|
test "a login's card ended while it shows goes as an answered post's options go: faded and smaller as its room closes, who is to finish it with it, then its line fading in in its place; not one put in the other's place at once" {
  let login = @signals.signal(card_login(true, "browser"))
  let base = @sffixture.fixture("chat")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      match name {
        "machineLogin" => { value: Some(login.get()), error: None, version: 1 }
        "machineLogins" => { value: Some({ "canLogin": Json::boolean(true), "canRelay": true }), error: None, version: 1 }
        _ => (base.topic_read)(name, params)
      }
    },
  }
  let m = card_login_post(who="等 林 完成", asked=true)
  let t = card_old(760.0, src, m, "login-ends", fn(x, here) {
    x.text(m.text, style=dec_words) |> ignore
    message_decision(x, src, here, m, here.list.map(fn(l) { l.turns }))
  })
  t.run_for(@ui.move_most_ms)
  let line = "已在 Willow 上登录 gh"
  let seen = fn(words : String) {
    t.words().iter().fold(init=0.0, fn(a, w) { if w.0 == words && w.5 > a { w.5 } else { a } })
  }
  assert_eq(seen("在 Willow 上登录 gh"), 1.0)
  login.set(card_login(false, "done", more={ "statusText": line, "endedText": line }))
  // (early in the options' going: the card and who is to finish it fading where they are, the line not yet)
  t.run_for(@sfbase.options_out_ms / 5.0)
  let card = seen("在 Willow 上登录 gh")
  assert_true(card > 0.0 && card < 1.0, msg="card at \{card}")
  assert_true(seen("等 林 完成") > 0.0)
  assert_eq(seen(line), 0.0)
  // (gone, and the line come whole in its place)
  t.run_for(@ui.move_most_ms)
  assert_eq(seen("在 Willow 上登录 gh"), 0.0)
  assert_eq(seen("等 林 完成"), 0.0)
  assert_eq(seen(line), 1.0)
  assert_true(card_has(t, "忽略"))
}

///|
test "a login's card under its post: its × cancels it on the card's station (another of the workspace's where the card says so), 忽略 lets the ask go" {
  for other in ["", "st2"] {
    let calls : Array[(String, Json)] = []
    let src = card_login_src(Some(card_login(true, "browser")), calls~)
    let t = card_login_new(760.0, src, fn() { card_login_post(asked=true, station=other) })
    t.run_for(@ui.move_most_ms)
    t.click(Button, label=@sf.t("web-main.logins.cancelWhat"))
    t.run_for(@ui.move_most_ms)
    let made = calls.filter(fn(c) { c.0 == "machineLogin.cancel" })
    assert_eq(made.length(), 1, msg=other)
    assert_eq(text(Some(made[0].1), "station"), if other == "" { "ws1/st1" } else { "ws1/st2" }, msg=other)
    assert_eq(text(Some(made[0].1), "id"), "login-1", msg=other)
    dec_audit(t, "cancelled " + other)
  }
  rows_reset()
  let calls : Array[(String, Json)] = []
  let src = card_login_src(Some(card_login(true, "browser")), calls~)
  let t = card_login_new(390.0, src, fn() { card_login_post(asked=true) })
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="忽略")
  t.run_for(@ui.move_most_ms)
  let made = calls.filter(fn(c) { c.0 == "decision.dismiss" })
  assert_eq(made.length(), 1)
  assert_eq(number(Some(made[0].1), "seq"), 9.0)
  assert_false(card_has(t, "忽略"))
  assert_true(card_has(t, "在 Willow 上登录 gh"))
  dec_audit(t, "let go")
  rows_reset()
}

///|
/// chat-phone's post asking for the viewer's phone, decided as `state` says ("": waiting; granted, denied, ended), its
/// station holding it as `link` says once granted; `lasts`: the longest its owner lets it be granted for; `theirs`:
/// another's to answer (陈's).
fn card_phone(state : String, link? : String = "", lasts? : String = "", theirs? : Bool = false) -> Message {
  @sffixture.fix_phone.val = state
  @sffixture.fix_phone_link.val = link
  let j = @sffixture.phone_post()
  @sffixture.fix_phone.val = ""
  @sffixture.fix_phone_link.val = ""
  match j {
    Object(o) =>
      match o.get("card") {
        Some(Object(card)) => {
          if theirs {
            card["assignee"] = "chen@example.com"
            card["assigneeText"] = "等 陈 决定"
          }
          match card.get("phoneAsk") {
            Some(Object(ask)) => {
              if lasts != "" {
                ask["lasts"] = Json::string(lasts)
              }
              if state == "ended" {
                ask["why"] = "对话已归档"
              }
            }
            _ => ()
          }
        }
        _ => ()
      }
    _ => ()
  }
  card_said_then(j)
}

///|
/// The fixture `mode`'s source for a phone's request (card_src's), its `adbShare` saying the request comes from a station
/// from before signatures where `old`.
fn card_phone_src(mode : String, doing? : Json? = None, old? : Bool = false, calls? : Array[(String, Json)] = []) -> Source {
  let base = card_src(mode, doing~, calls~)
  if !old {
    return base
  }
  {
    ..base,
    topic_read: fn(name, params) {
      if name == "adbShare" {
        { value: Some({ "on": true, "grants": [{ "id": "p-1", "status": "pending", "oldStation": true }] }), error: None, version: 1 }
      } else {
        (base.topic_read)(name, params)
      }
    },
  }
}

///|
/// The phone's request's states by name: its source, the post.
fn card_phone_cases() -> Array[(String, Source, Message)] {
  [
    ("waiting", card_phone_src("chat-phone"), card_phone("")),
    ("an hour alone", card_phone_src("chat-phone"), card_phone("", lasts="hour")),
    ("theirs", card_phone_src("chat-phone"), card_phone("", theirs=true)),
    ("not approved", card_phone_src("chat-phone-outside"), card_phone("")),
    ("old station", card_phone_src("chat-phone", old=true), card_phone("")),
    ("under way", card_phone_src("chat-phone", doing=Some(card_doing("adb.decide", request="p-1"))), card_phone("")),
    ("granted", card_phone_src("chat-phone"), card_phone("granted")),
    ("granted, held", card_phone_src("chat-phone-linked-connected"), card_phone("granted", link="connected")),
    ("granted, to pair", card_phone_src("chat-phone-linked-unpaired-desk"), card_phone("granted", link="unpaired")),
    ("granted, off", card_phone_src("chat-phone-linked-off"), card_phone("granted", link="off")),
    ("denied", card_phone_src("chat-phone"), card_phone("denied")),
    ("ended", card_phone_src("chat-phone"), card_phone("ended")),
  ]
}

///|
/// How many of card_audit's rooms the phone's request named `name` (card_phone_cases') has `w` wide: none while it is
/// asked; decided, the head's name and time, and the line saying how it went where its middle is under the time (as
/// card_rig_rooms: 「已允许调试手机 · 本对话内」 166 wide, 「已拒绝调试手机」 100, 「调试手机已结束：对话已归档」 172, from 40),
/// not where the line goes on past the time to say how the phone is held (granted, held; granted, off; to be paired on
/// the phone, wide), its middle past it; to be paired, narrow, on two lines, tall enough to leave the head its room.
fn card_phone_rooms(name : String, w : Double) -> Int {
  match name {
    "granted" | "denied" | "ended" => 3
    "granted, held" | "granted, off" => 2
    "granted, to pair" => if w < 760.0 { 0 } else { 2 }
    _ => 0
  }
}

///|
/// The phone's request `m` over `src` as the old view draws it (phone_ask_card in a list's row), `w` wide at `scale`;
/// then as the nodes do: both, and the new one's Tester.
fn card_phone_both(src : Source, m : Message, w : Double, at : String, scale? : Double = 1.0) -> (String, String, @ui.Tester) {
  let old = card_old(w, src, m, at, fn(x, here) {
    match m.card {
      Some({ phone: Some(ask), .. } as card) => phone_ask_card(x, here, m, card, ask)
      _ => ()
    }
  })
  old.set_font_scale(scale)
  old.run_for(@ui.move_most_ms)
  let was = head_drawn(old)
  let t = card_new(w, src, fn() { m })
  t.set_font_scale(scale)
  t.run_for(@ui.move_most_ms)
  (was, head_drawn(t), t)
}

///|
test "a phone's request in place of its post's words, made once as nodes, is drawn as the old view drew it: waiting, an hour alone, another's, this device not approved, a station from before, under way; granted, held, to be paired on the phone, its debugging off, refused, ended; wide and narrow, at 1.3" {
  let cases = card_phone_cases()
  for w in [760.0, 390.0] {
    let mut waiting = ""
    for c in cases {
      let at = "\{c.0} at \{w}"
      let (was, now, t) = card_phone_both(c.1, c.2, w, at)
      assert_eq(now, was, msg=at)
      if c.0 == "waiting" {
        waiting = now
      } else {
        assert_true(now != waiting, msg=at + ": drawn as waiting")
      }
      card_audit(t, at, card_phone_rooms(c.0, w))
    }
  }
  // (at 1.3 narrow, waiting with its length's choice, the old view's foot goes on to a second line whose choice breaks
  // the corner rule, which stops its Tester: an hour alone, no choice, in its place)
  for i in [1, 8] {
    let c = cases[i]
    let at = "\{c.0} at 1.3"
    let (was, now, t) = card_phone_both(c.1, c.2, 390.0, at, scale=1.3)
    assert_eq(now, was, msg=at)
    card_audit(t, at, 0)
  }
}

///|
test "a phone's request allowed: adb.decide for its station and request, for the length chosen at its card's foot; refused, with none; this device not approved, 查看步骤 in 允许's place asks nothing" {
  @sf.presenters_reset()
  let calls : Array[(String, Json)] = []
  let t = card_new(760.0, card_phone_src("chat-phone", calls~), fn() { card_phone("") })
  t.run_for(@ui.move_most_ms)
  let scope = fn(s : String) { @sf.t("android-settings.vault.scope." + s) }
  t.click(Button, label=scope("idle"))
  t.run_for(@ui.move_most_ms)
  for s in ["hour", "eight", "chat"] {
    assert_true(card_has(t, scope(s)), msg=s)
  }
  t.tap_text(scope("chat"))
  t.run_for(@ui.move_most_ms)
  assert_false(card_has(t, scope("hour")))
  t.click(Button, label="允许")
  t.run_for(@ui.move_most_ms)
  let made = calls.filter(fn(c) { c.0 == "adb.decide" })
  assert_eq(made.length(), 1)
  let p = Some(made[0].1)
  assert_eq(text(p, "station"), "ws1/st1")
  assert_eq(text(p, "request"), "p-1")
  assert_eq(text(p, "scope"), "chat")
  assert_true(t.get(Button, label="允许").disabled)
  assert_true(t.get(Button, label="拒绝").disabled)
  card_audit(t, "allowed", 0)
  let calls : Array[(String, Json)] = []
  let t = card_new(390.0, card_phone_src("chat-phone", calls~), fn() { card_phone("") })
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="拒绝")
  t.run_for(@ui.move_most_ms)
  let made = calls.filter(fn(c) { c.0 == "adb.decide" })
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].1), "scope"), "")
  card_audit(t, "refused", 0)
  let calls : Array[(String, Json)] = []
  let t = card_new(390.0, card_phone_src("chat-phone-outside", calls~), fn() { card_phone("") })
  t.run_for(@ui.move_most_ms)
  assert_false(card_has(t, "允许"))
  t.click(Button, label=@sf.t("android-misc.adb.ask.how"))
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.filter(fn(c) { c.0 == "adb.decide" }).length(), 0)
}

///|
test "a phone's request decided as its card shows: the card goes, the line saying how it went in its place; pressed, what was asked read again" {
  @sf.presenters_reset()
  let m = @signals.signal(card_phone(""))
  let t = card_new(390.0, card_phone_src("chat-phone"), fn() { m.get() })
  t.run_for(@ui.move_most_ms)
  m.set(card_phone("granted"))
  t.run_for(@ui.move_most_ms)
  assert_false(card_has(t, "允许"))
  let line = "已允许调试手机 · 本对话内"
  assert_true(card_has(t, line))
  card_audit(t, "decided", 3)
  t.click(Button, label=line + " · " + @sf.t("web-main.history.details"))
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  assert_true(card_has(t, "装上刚编好的测试包，看首屏在折叠屏展开时排得对不对"))
  @sf.close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenting())
}

///|
/// Post `m` as the old view draws it whole in a list's row `list` (message_row: its card in its words' place, what it
/// asks under it), answered with the settings' core over `src`, `w` wide.
fn card_row_old(w : Double, src : Source, m : Message, list : String) -> @ui.Tester {
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
        c.box(style=head_frame, fn() { row_box(c, row_side(w), 0.0, fn() { message_row(c, src, here, m) }) |> ignore })
        |> ignore
      })
    },
    w~,
    h=420.0,
  )
}

///|
/// The same post as the nodes draw it whole in its row (agent_said_node, answered with the core over `src`), `w` wide.
fn card_row_new(w : Double, src : Source, m : Message) -> @ui.Tester {
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
        jump: None,
      }
      root.box(fn(f) {
        @sf.style_node(f, fn() { head_frame })
        // (offering itself as the old list's row does: message_row's share)
        agent_said_node(f, src, here, "m:" + m.ts, fn() { row_side(w) }, fn() { 0.0 }, fn() { m }, share=message_share_of(
          src,
          here,
          fn() { m },
        ), core=Some(@sfbase.settings_core(src, card_ws)))
        |> ignore
      })
      |> ignore
      @sf.presented_nodes(root)
    },
    w~,
    h=420.0,
  )
}

///|
test "an agent's post whole in its row, made once as nodes, is drawn as the old view drew it: a rig's request in its words' place, a login's card under its words, wide and narrow" {
  let cases = [
    ("rig", card_src("chat-rig"), card_rig("")),
    ("rig granted", card_src("chat-rig"), card_rig("granted")),
    // (its words' Markdown as the core reads it: no word asked of a core this test does not keep)
    ("login", card_login_src(Some(card_login(true, "browser"))), {
      ..card_login_post(),
      md: Some([["p", ["在 Willow 上登录一下 gh，我再接着推。"]]]),
    }),
  ]
  for c in cases {
    for w in [760.0, 390.0] {
      let at = "\{c.0} at \{w}"
      let old = card_row_old(w, c.1, c.2, at)
      old.run_for(@ui.move_most_ms)
      let was = head_drawn(old)
      let t = card_row_new(w, c.1, c.2)
      t.run_for(@ui.move_most_ms)
      let now = head_drawn(t)
      // (where they differ, each line one has that the other has not)
      let olds = was.split("\n").map(fn(l) { l.to_owned() }).collect()
      let news = now.split("\n").map(fn(l) { l.to_owned() }).collect()
      let only_old = olds.filter(fn(l) { !news.contains(l) })
      let only_new = news.filter(fn(l) { !olds.contains(l) })
      assert_true(only_old.is_empty() && only_new.is_empty(), msg=at + ": \{only_old.length()}/\{only_new.length()} NEW " + only_new.iter().take(3).collect().join(" | ") + " OLD " + only_old.iter().take(3).collect().join(" | "))
      assert_eq(now, was, msg=at)
    }
  }
}
