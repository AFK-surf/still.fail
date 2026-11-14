// An agent's card as nodes in a hover card (agent_card_node in @sf.hover_card_node), set beside the old view's
// (agent_card in hover) on the same fixture (chat-agent-card): the same words where they were, the same rectangles
// drawn, at rest and at work, waiting, the core not having said its card yet, an account running low, what is wrong,
// its context filling, no jobs, a long account's name, its badge; and in a tile with its station's part under it.

///|
/// The fixture's agent.
// kept across runs: a value
let agent_at : String = "s-c1"

///|
/// The fixture's chat.
fn agent_ref() -> ChatRef {
  { station: "ws1/st1", session: agent_at, title: "整理发布清单", station_name: "Willow" }
}

///|
/// `v` an object with its fields `kv` said in place of its own.
fn agent_said_as(v : Json, kv : Array[(String, Json)]) -> Json {
  match v {
    Object(m) => {
      let o = m.copy()
      for p in kv {
        o[p.0] = p.1
      }
      Json::object(o)
    }
    _ => v
  }
}

///|
/// The fixture's source (chat-agent-card), its agent as `agent` changes it (its session as `session` does), its card
/// (`agentCard`) as `card` does.
fn agent_src(agent : (Json) -> Json, session : (Json) -> Json, card : (Json?) -> Json?) -> Source {
  let base = @sffixture.fixture("chat-agent-card")
  {
    ..base,
    topic_read: fn(topic, params) {
      let got = (base.topic_read)(topic, params)
      match (topic, got.value) {
        ("chat", Some(Object(m))) if params.get("session") == Some(Json::string(agent_at)) => {
          let o = m.copy()
          o["agents"] = Json::array(
            items(got.value, "agents").map(fn(a) {
              let a = agent(a)
              match field(Some(a), "session") {
                Some(s) => agent_said_as(a, [("session", session(s))])
                None => a
              }
            }),
          )
          { ..got, value: Some(Json::object(o)) }
        }
        ("agentCard", v) => { ..got, value: card(v) }
        _ => got
      }
    },
  }
}

///|
/// The fixture's card with its fields `kv` said in place of its own.
fn agent_card_as(kv : Array[(String, Json)]) -> (Json?) -> Json? {
  fn(v) { v.map(fn(c) { agent_said_as(c, kv) }) }
}

///|
/// The states compared, by name: the source of each.
fn agent_cases() -> Array[(String, Source)] {
  let same = fn(j : Json) { j }
  let card_same = fn(v : Json?) { v }
  let now = (@sffixture.fixture("chat-agent-card").now)()
  [
    ("as the fixture", agent_src(same, same, card_same)),
    ("its card not said yet", agent_src(same, same, fn(_) { None })),
    (
      "at work",
      agent_src(
        fn(a) { agent_said_as(a, [("status", "running"), ("since", Json::number(now - 65000.0)), ("badge", "run")]) },
        fn(s) { agent_said_as(s, [("statusText", "正在干活"), ("tone", "blue")]) },
        card_same,
      ),
    ),
    (
      "waiting on a person",
      agent_src(
        fn(a) {
          agent_said_as(a, [
            ("status", "running"),
            ("wait", { "since": Json::number(now - 30000.0), "seconds": 600 }),
            ("badge", "block"),
          ])
        },
        fn(s) { agent_said_as(s, [("statusText", "在等你回答"), ("tone", "amber")]) },
        card_same,
      ),
    ),
    (
      "its account running out",
      agent_src(
        fn(a) {
          agent_said_as(a, [
            (
              "account",
              {
                "name": "林的 Max",
                "quota": {
                  "state": "ok",
                  "windows": [{ "label": "5 小时", "mark": "5H", "left": 3, "level": "red", "refills": "20 分钟后刷新" }],
                },
              },
            ),
          ])
        },
        same,
        agent_card_as([("attention", [{ "kind": "account", "level": "red", "text": "林的 Max 快用完了，换一个账号" }])]),
      ),
    ),
    (
      "something wrong",
      agent_src(
        fn(a) { agent_said_as(a, [("badge", "failed")]) },
        fn(s) { agent_said_as(s, [("statusText", "失败了"), ("tone", "red")]) },
        agent_card_as([
          ("attention", [{ "level": "red", "text": "上一轮失败：请求超时" }, { "level": "amber", "text": "上下文快满了" }]),
        ]),
      ),
    ),
    (
      "its context filling, compacted",
      agent_src(
        same,
        fn(s) { agent_said_as(s, [("canCompact", true), ("canClear", true)]) },
        agent_card_as([("context", { "percent": 86, "text": "86%", "level": "amber" })]),
      ),
    ),
    (
      "its context full",
      agent_src(same, same, agent_card_as([("context", { "percent": 97, "text": "97%", "level": "red" })])),
    ),
    (
      "its context unknown",
      agent_src(same, same, agent_card_as([("context", { "unknown": true, "text": "不知道多少" })])),
    ),
    ("no jobs, no figures", agent_src(same, same, agent_card_as([("jobs", ""), ("cost", ""), ("cache", Json::null()), ("context", Json::null())]))),
    (
      "a long account's name",
      agent_src(
        fn(a) {
          match field(Some(a), "account") {
            Some(acc) => agent_said_as(a, [("account", agent_said_as(acc, [("name", "claude-team-account-5@example.com")]))])
            None => a
          }
        },
        same,
        card_same,
      ),
    ),
    ("its work in a line", agent_src(same, same, agent_card_as([("workLine", "后台 2 · 清单 2/6：改列表的测试")]))),
  ]
}

///|
/// What the old view draws: the trigger, `body` in a hover card over it (a tile, `padded`), the pointer resting on it.
fn agent_old(src : Source, body : (@ui.Ctx, Source) -> Unit, padded? : Bool = true) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  hover_reset()
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      match @sfbase.workspace_in_view(src).0 {
        Some(w) => @settings.panels_frame(@sfbase.settings_core(src, w), w.id)
        None => ()
      }
      c.with_theme(@sf.ui_theme(), fn() {
        let (x, y, w, h) = peek_trigger
        let id = c.id("agent-trigger")
        c.box(style=@ui.style(pl=@sf.room_of(x), pt=@sf.room_of(y)), fn() {
          c.box(style=@ui.style(w=Fixed(w), h=Fixed(h)), id~, fn() {  }) |> ignore
        })
        |> ignore
        hover(c, "agent", id, tile=true, padded~, fn() { body(c, src) }) |> ignore
      })
    },
    w=1280.0,
    h=800.0,
    platform=0,
  )
  peek_rest_on(t, "")
  t
}

///|
/// What the nodes draw: the trigger, `body` in a hover card over it (a tile, `padded`; pressed for nothing here), its
/// hand's card given to it, kept open while what it says is; the pointer resting on it.
fn agent_new(
  src : Source,
  body : (@view.View, Source, @sf.TipLayer, () -> @view.View?) -> (() -> Bool),
  padded? : Bool = true,
) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      match @sfbase.workspace_in_view(src).0 {
        Some(w) => @settings.panels_frame(@sfbase.settings_core(src, w), w.id)
        None => ()
      }
      let tips = @sf.TipLayer::new(fn() { Some(root) })
      let (x, y, w, h) = peek_trigger
      root.box(fn(f) {
        f.padding(Is((x, y, 0.0, 0.0))) |> ignore
        f.box(fn(k) {
          k.width(Is(Some(w))).height(Is(Some(h))).says(Is(Some(@view.said(Button, label="agent-trigger")))) |> ignore
          let hand : Ref[@sf.HoverHand?] = Ref(None)
          let held : Ref[() -> Bool] = Ref(fn() { false })
          let card = fn() {
            match hand.val {
              Some(hh) => (hh.card)()
              None => None
            }
          }
          hand.val = Some(
            @sf.hover_card_node(tips, k, fn(b) { held.val = body(b, src, tips, card) }, tile=true, padded~, held=fn() {
              (held.val)()
            }, press=fn() {  }),
          )
        })
        |> ignore
      })
      |> ignore
      @sf.presented_nodes(root)
    },
    w=1280.0,
    h=800.0,
    platform=0,
  )
  peek_rest_on(t, "")
  t
}

///|
/// What a Tester draws as peek_drawn lists it, its figures' row (usage_tiles, `card` saying them: their grounds 55
/// high, their figures and names) apart: the rest, then the figures' row.
fn agent_tiles_apart(lines : Array[String], card : Json?) -> (Array[String], Array[String]) {
  let context = field(card, "context")
  let words = [
    text(card, "cost"),
    text(field(card, "cache"), "text"),
    text(context, "text"),
    number(context, "percent").round().to_int().to_string() + "%",
    @sf.t("web-main.chat.agentCard.cost"),
    @sf.t("web-main.chat.agentCard.cache"),
    @sf.t("web-main.chat.agentCard.context"),
    @sf.t("web-mobile.agent.contextCompactable"),
  ].filter(fn(w) { w != "" })
  let tile = fn(l : String) {
    match l.find("@") {
      Some(i) => words.contains(l.exact_view(end=i).to_owned())
      None => l.contains("x\{agent_tile_h} ")
    }
  }
  (lines.filter(fn(l) { !tile(l) }), lines.filter(tile))
}

///|
/// How tall a figure's tile is drawn (usage_tiles').
let agent_tile_h : Int = 55

///|
/// The widths of the figures' grounds of a figures' row (agent_tiles_apart's).
fn agent_tile_widths(tiles : Array[String]) -> Array[String] {
  tiles
  .filter(fn(l) { !l.contains("@") && l.contains("x\{agent_tile_h} ") })
  .map(fn(l) {
    match l.find(" ") {
      Some(i) => {
        let rest = l.exact_view(start=i + 1)
        match rest.find("x") {
          Some(j) => rest.exact_view(end=j).to_owned()
          None => ""
        }
      }
      None => ""
    }
  })
}

///|
/// The press rooms t.audit() finds too small in an agent's card as nodes: what the old card drew and was never held
/// to (the old view checks no room), kept the size it was (the coordinator, 2026-11-11: pinned here, cleared before
/// the card goes into the app, xfer/rc2-card-rooms.md), each by what it is: its latest lines (each 18 high, 2 apart:
/// rooms 20 to 28 under 36), its stop (24 round: 36×34), its work's line (288×31), its jobs and an account that cannot
/// run when one is under the other (288×28). Those of `faults` that are these, and the rest.
fn agent_rooms_known(faults : Array[String], card : Json?) -> (Array[String], Array[String]) {
  let names = items(card, "latest").map(fn(l) { "「" + text(Some(l), "text") + "」" })
  names.push("「" + text(card, "workLine") + "」")
  names.push("「" + text(card, "jobs") + "」")
  for x in items(card, "attention") {
    names.push("「" + text(Some(x), "text") + "」")
  }
  let known = faults.filter(fn(f) {
    f.has_prefix("room: ") &&
    f.contains("stillfail/src/sfpages/agent_card_node.mbt:") &&
    (names.iter().any(fn(n) { f.has_prefix("room: " + n + " ") }) || (f.has_prefix("room: a box ") && f.contains(" 24×24, ")))
  })
  (known, faults.filter(fn(f) { !known.contains(f) }))
}

///|
/// How many of agent_rooms_known's each state has (rc2-20): its three latest lines in each but where its card is not
/// said; its stop where it works or waits; its work's line where it has one; its jobs and its account's link where both.
fn agent_rooms_expected(_name : String) -> Int {
  0
}

///|
test "an agent's card as nodes: the same words where they were and the same rectangles as the old card's, in each state; its figures' row in three shares" {
  let faults = []
  for case in agent_cases() {
    let (name, src) = case
    let to = agent_old(src, fn(c, src) {
      match agent_json(src.topic("chat", chat_params(agent_ref())).get().value, agent_at) {
        Some(j) => agent_card(c, src, agent_ref(), j)
        None => ()
      }
    })
    let old = peek_drawn(to)
    let old_faults = to.audit()
    let t = agent_new(src, fn(b, src, tips, card) { agent_card_node(b, src, agent_ref(), agent_at, tips, card) })
    let new = peek_drawn(t)
    assert_true(old.length() > 4, msg="\{name}: the old card drawn: \{Repr(old)}")
    // (its figures: the library's usage_tiles_node, three shares alike, where the old's were 97.33, 97.33 and 81.33,
    // the context's 16 less for what held it: the coordinator, 2026-11-11, a difference said)
    let card = (src.topic_read)("agentCard", { "station": Json::string("ws1/st1"), "key": Json::string(agent_at) }).value
    let (old_rest, old_tiles) = agent_tiles_apart(old, card)
    let (new_rest, new_tiles) = agent_tiles_apart(new, card)
    let d = peek_differ(old_rest, new_rest)
    if d.length() > 0 {
      faults.push("\{name}:\n  " + d.join("\n  "))
    }
    let widths = agent_tile_widths(new_tiles)
    if agent_tile_widths(old_tiles).length() != widths.length() || widths.iter().any(fn(w) { w != widths[0] }) {
      faults.push("\{name}: its figures \{Repr(agent_tile_widths(old_tiles))} as \{Repr(widths)}, not in shares alike")
    }
    let (known, rest) = agent_rooms_known(t.audit(), card)
    if known.length() != agent_rooms_expected(name) {
      faults.push("\{name}: \{known.length()} rooms known, \{agent_rooms_expected(name)} said: \{Repr(known)}")
    }
    // (what else it says, the old card said too: its context's words cut short where it is not known)
    if rest.length() != old_faults.length() {
      faults.push("\{name}: audit: \{Repr(rest)}, the old card's \{Repr(old_faults)}")
    }
  }
  assert_eq(faults, [], msg=faults.join("\n"))
}

///|
/// What holds an agent's card in a tile with its station's part (the chat's bar's tile_card_agent): 10 in.
// kept across runs: a value (no field of it changes)
let agent_tile_room : @ui.Style = @ui.css("w=Full p=S2_5")

///|
test "an agent's card with its station's part in one tile (a finger's hold on the bar's tile) as nodes: the same as the old one, as wide as the wider" {
  let faults = []
  for case in agent_cases().filter(fn(c) { c.0 == "as the fixture" || c.0 == "a long account's name" }) {
    let (name, src) = case
    let old = peek_drawn(
      agent_old(src, padded=false, fn(c, src) {
        match agent_json(src.topic("chat", chat_params(agent_ref())).get().value, agent_at) {
          Some(j) => c.box(style=agent_tile_room, fn() { agent_card(c, src, agent_ref(), j, across=true) }) |> ignore
          None => ()
        }
        @settings.station_peek_part(c, "ws1/st1")
      }),
    )
    let t = agent_new(src, padded=false, fn(b, src, tips, card) {
      let held = Ref(fn() { false })
      b.box(fn(o) {
        @sf.style_node(o, fn() { agent_tile_room })
        held.val = agent_card_node(o, src, agent_ref(), agent_at, tips, card, across=true)
      })
      |> ignore
      @settings.station_peek_part_node(b, "ws1/st1", fn() { 0 })
      held.val
    })
    let new = peek_drawn(t)
    let card = (src.topic_read)("agentCard", { "station": Json::string("ws1/st1"), "key": Json::string(agent_at) }).value
    let (old_rest, _) = agent_tiles_apart(old, card)
    let (new_rest, new_tiles) = agent_tiles_apart(new, card)
    let d = peek_differ(old_rest, new_rest)
    if d.length() > 0 {
      faults.push("\{name}:\n  " + d.join("\n  "))
    }
    let widths = agent_tile_widths(new_tiles)
    if widths.length() != 3 || widths.iter().any(fn(w) { w != widths[0] }) {
      faults.push("\{name}: its figures \{Repr(widths)}, not three shares alike")
    }
    let (known, rest) = agent_rooms_known(t.audit(), card)
    if known.length() != agent_rooms_expected(name) || rest.length() > 0 {
      faults.push("\{name}: \{known.length()} rooms known, \{agent_rooms_expected(name)} said; audit: \{Repr(rest)}")
    }
  }
  assert_eq(faults, [], msg=faults.join("\n"))
}

///|
/// An agent's card's triggers as the chat's rows put them: in a row 300 by 44 at 40, 40 (20 in) that opens what it is of
/// (`pressed` "行": an activity row), an avatar 18 across that says neither (hold alone); 60 after it a name 60 by 20 that
/// says its press (`pressed` "名": a message's name, its card's words starting where the name's do). `platform` 0 a
/// mouse's, 1 a touch screen's. Their hands, by "头像" and "名".
fn agent_triggers(platform : Int, pressed : Map[String, Int], hands : Map[String, @sf.HoverHand]) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  let src = @sffixture.fixture("chat-agent-card")
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let tips = @sf.TipLayer::new(fn() { Some(root) })
      let count = fn(k : String) { fn() { pressed[k] = pressed.get(k).unwrap_or(0) + 1 } }
      let card_of = fn(name : String) {
        fn() {
          match hands.get(name) {
            Some(h) => (h.card)()
            None => None
          }
        }
      }
      root.box(fn(f) {
        f.padding(Is((40.0, 40.0, 0.0, 0.0))) |> ignore
        f.box(fn(row) {
          row.row(Is(true)).width(Is(Some(300.0))).height(Is(Some(44.0))).padding(Is((20.0, 0.0, 0.0, 0.0))).lines_up(Is(Some(Middle))) |> ignore
          row.says(Is(Some(@view.said(Button, label="行")))) |> ignore
          @sf.presses_node(row, count("行"))
          row.box(fn(a) {
            a.width(Is(Some(18.0))).height(Is(Some(18.0))).says(Is(Some(@view.said(Image, label="头像")))) |> ignore
            let held = Ref(fn() { false })
            hands["头像"] = @sf.hover_card_node(tips, a, fn(b) {
              held.val = agent_card_node(b, src, agent_ref(), agent_at, tips, card_of("头像"))
            }, tile=true, held=fn() { (held.val)() })
          })
          |> ignore
          row.box(fn(g) { g.width(Is(Some(60.0))) |> ignore }) |> ignore
          row.box(fn(n) {
            n.width(Is(Some(60.0))).height(Is(Some(20.0))).says(Is(Some(@view.said(Link, label="名")))) |> ignore
            let held = Ref(fn() { false })
            hands["名"] = @sf.hover_card_node(
              tips,
              n,
              fn(b) { held.val = agent_card_node(b, src, agent_ref(), agent_at, tips, card_of("名")) },
              tile=true,
              along_offset=-@sf.panel_pad - hover_words_in,
              held=fn() { (held.val)() },
              press=count("名"),
            )
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      @sf.presented_nodes(root)
    },
    w=1280.0,
    h=800.0,
    platform~,
  )
  t
}

///|
/// Whether the card of trigger `name` is open.
fn agent_trigger_open(hands : Map[String, @sf.HoverHand], name : String) -> Bool {
  match hands.get(name) {
    Some(h) => @signals.untracked(h.open)
    None => false
  }
}

///|
test "an activity row's avatar says neither: a finger's tap on it the row's (opened), no card; held long_press_ms, its agent's card, the row not pressed" {
  let pressed : Map[String, Int] = Map([])
  let hands : Map[String, @sf.HoverHand] = Map([])
  let t = agent_triggers(1, pressed, hands)
  t.run_for(@ui.move_most_ms)
  // (the avatar: 40 + 20, the row's middle)
  let (x, y) = (69.0, 62.0)
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(pressed.get("行").unwrap_or(0), 1, msg="tapped: the row opened")
  assert_false(agent_trigger_open(hands, "头像"), msg="tapped: no card")
  t.touch(0, x, y)
  t.run_for(@ui.long_press_ms + @ui.move_most_ms)
  t.touch(2, x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(agent_trigger_open(hands, "头像"), msg="held: its card")
  assert_eq(pressed.get("行").unwrap_or(0), 1, msg="held: the row not pressed again")
  assert_true(t.find("Claude · Opus 5.5") is Some(_), msg="held: what its card says")
  // (the card's rooms known as they are pinned in the comparison: agent_rooms_known)
  let card = (@sffixture.fixture("chat-agent-card").topic_read)("agentCard", {
    "station": Json::string("ws1/st1"),
    "key": Json::string(agent_at),
  }).value
  let (_, rest) = agent_rooms_known(t.audit(), card)
  // (the card is in this rig's own layer over the row (its TipLayer's, not one presented over all, View::over_all), so
  // from 7 under the avatar and the name it takes the press: they are said as 44×37 and 60×37. Known, these two
  // exactly (the coordinator of the migration, 2026-11-12); none once the card is put in the presented layer, as the
  // app is to put it (presented_nodes' tips))
  let over_row = rest.filter(fn(f) {
    f.has_prefix("room: a box (a node of the window's tree's at ") &&
    f.contains("made at stillfail/src/sfpages/agent_card_node_wbtest.mbt:") &&
    (f.contains(" at 60,53 18×18, ") || f.contains(" at 138,52 60×20, "))
  })
  assert_eq(over_row.length(), 0, msg="held: \{Repr(rest)}")
  assert_eq(rest.filter(fn(f) { !over_row.contains(f) }), [], msg="held: \{Repr(rest)}")
}

///|
test "a message's name says its press: clicked, its own (the agent's history); the mouse resting on it, its card, its words starting where the name's do" {
  let pressed : Map[String, Int] = Map([])
  let hands : Map[String, @sf.HoverHand] = Map([])
  let t = agent_triggers(0, pressed, hands)
  t.run_for(@ui.move_most_ms)
  // (the name: 40 + 20 + 18 + 60, the row's middle)
  let (x, y) = (168.0, 62.0)
  t.move_to(x, y)
  t.run_for(hover_open_ms + @ui.move_most_ms)
  assert_true(agent_trigger_open(hands, "名"), msg="rested on: its card")
  match @signals.untracked(hands["名"].card) {
    Some(c) => {
      let (cx, _, _, _) = c.placed_window_now()
      assert_eq(cx, 138.0 - @sf.panel_pad - hover_words_in, msg="its card back by its padding and its words' inset")
    }
    None => fail("open, no card")
  }
  t.touch(0, x, y)
  t.touch(2, x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(pressed.get("名").unwrap_or(0), 1, msg="clicked: its own")
  assert_eq(pressed.get("行").unwrap_or(0), 0, msg="clicked: not the row's")
}
