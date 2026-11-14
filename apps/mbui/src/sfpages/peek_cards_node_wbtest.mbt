// A station's card over where a chat names it, and its part under an agent's card, as nodes in a hover card
// (settings' station_peek_card_node, station_peek_part_node in @sf.hover_card_node), set beside the old view's
// (station_peek_card, station_peek_part in hover) on the same fixture: the same words where they were, the same
// rectangles drawn, up (by a relay, a way still chosen, coming back) and down, a mark of its own or none, its name
// long, its screens' menu open (with screens and with none).

///|
/// The fixture's station.
// kept across runs: a value
let peek_at : String = "ws1/st1"

///|
/// The fixture's source (chat-station-tag), what the core says of its station changed by `change` (the topic's name,
/// what it says): as the station whole (`station`), its row (`stations`) and its screens.
fn peek_src(change : (String, Json?) -> Json?) -> Source {
  let base = @sffixture.fixture("chat-station-tag")
  {
    ..base,
    topic_read: fn(topic, params) {
      let got = (base.topic_read)(topic, params)
      { ..got, value: change(topic, got.value) }
    },
  }
}

///|
/// `v`, the station (the station's own topic, or the station among `stations`' rows) its fields `kv` said in place of
/// its own.
fn peek_said_as(v : Json?, kv : Array[(String, Json)]) -> Json? {
  let one = fn(x : Json) -> Json {
    match x {
      Object(m) => {
        let o = m.copy()
        for p in kv {
          o[p.0] = p.1
        }
        Json::object(o)
      }
      _ => x
    }
  }
  match v {
    Some(Array(a)) => Some(Json::array(a.map(fn(x) { if text(Some(x), "station") == peek_at { one(x) } else { x } })))
    Some(x) => Some(one(x))
    None => None
  }
}

///|
/// The states compared, by name: what each changes.
fn peek_cases() -> Array[(String, (String, Json?) -> Json?)] {
  let station = fn(kv : Array[(String, Json)]) {
    fn(topic : String, v : Json?) { if topic == "station" { peek_said_as(v, kv) } else { v } }
  }
  [
    ("as the fixture", fn(_t, v) { v }),
    ("by a relay", station([("way", { "path": "中继", "via": "relay" })])),
    ("a way chosen", station([("way", { "via": "choosing" })])),
    ("coming back", station([("reconnecting", true)])),
    ("down", station([("online", false)])),
    ("down, updating", station([("online", false), ("problems", [{ "key": "updating", "text": "正在更新，马上回来" }])])),
    ("no mark", station([("icon", ""), ("emoji", "")])),
    ("an emoji", station([("icon", ""), ("emoji", "🌳")])),
    (
      "a long name",
      fn(topic, v) {
        if topic == "stations" {
          peek_said_as(v, [("name", "Willow 的工作站，放在三楼机房最里面那排的第二台")])
        } else {
          v
        }
      },
    ),
    (
      "with screens",
      fn(topic, v) {
        if topic == "screens" {
          Some({ "screens": [{ "id": "desktop", "title": "Willow 的屏幕", "kind": "desktop" }] })
        } else {
          v
        }
      },
    ),
  ]
}

///|
/// Where the trigger is (as the chat's bar's tag): 40 in, 40 down, 120 by 32.
// kept across runs: a value
let peek_trigger : (Double, Double, Double, Double) = (40.0, 40.0, 120.0, 32.0)

///|
/// A Tester's words and rectangles, a line each (message_words_node_wbtest's said_drawn_back, nothing moved).
fn peek_drawn(t : @ui.Tester) -> Array[String] {
  t.words().filter(fn(w) { w.5 > 0.0 || w.3 > 0.0 }).map(fn(w) { "\{w.0}@\{w.1},\{w.2} \{w.3}x\{w.4} a\{w.5}" }) +
  t.drawn_rects().map(fn(r) { "\{r.0},\{r.1} \{r.2}x\{r.3} \{r.4}" })
}

///|
/// What differs of two lists of lines (the first 24): each line of one the other lacks.
fn peek_differ(old : Array[String], new : Array[String]) -> Array[String] {
  let out = []
  for l in old {
    if !new.contains(l) {
      out.push("old only: " + l)
    }
  }
  for l in new {
    if !old.contains(l) {
      out.push("new only: " + l)
    }
  }
  out
}

///|
/// The pointer resting on the trigger till a card is in whole; then, `menu` (its words' key), on that card's row of
/// those words till its menu is.
fn peek_rest_on(t : @ui.Tester, menu : String) -> Unit {
  let (x, y, w, h) = peek_trigger
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(hover_open_ms + @ui.move_most_ms)
  if menu != "" {
    // (`menu` the words' key, read now the run's Tester is made)
    let menu = @sf.t(menu)
    match t.find(menu) {
      Some((mx, my)) => {
        t.move_to(mx, my)
        t.run_for(@ui.move_most_ms)
      }
      None => @halt.saying("no \{menu} drawn")
    }
  }
}

///|
/// What the old view draws: the trigger, `body` in a hover card over it (`tile`, padded or not), the pointer resting on
/// it; the fixture's station's states as `change` says; the card's row `menu` rested on too.
fn peek_old(change : (String, Json?) -> Json?, body : (@ui.Ctx) -> Unit, padded? : Bool = false, menu? : String = "") -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  hover_reset()
  let src = peek_src(change)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      match @sfbase.workspace_in_view(src).0 {
        Some(w) => @settings.panels_frame(@sfbase.settings_core(src, w), w.id)
        None => ()
      }
      c.with_theme(@sf.ui_theme(), fn() {
        let (x, y, w, h) = peek_trigger
        let id = c.id("peek-trigger")
        c.box(style=@ui.style(pl=@sf.room_of(x), pt=@sf.room_of(y)), fn() {
          c.box(style=@ui.style(w=Fixed(w), h=Fixed(h)), id~, fn() {  }) |> ignore
        })
        |> ignore
        hover(c, "peek", id, tile=true, padded~, fn() { body(c) }) |> ignore
      })
    },
    w=1280.0,
    h=800.0,
    platform=0,
  )
  peek_rest_on(t, menu)
  t
}

///|
/// What the nodes draw: the trigger, `body` in a hover card over it (a tile, padded or not; a finger's tap its own, as
/// the chat's bar's tag), the pointer resting on it; as peek_old.
fn peek_new(change : (String, Json?) -> Json?, body : (@view.View) -> Unit, padded? : Bool = false, menu? : String = "") -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  let src = peek_src(change)
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
          k.width(Is(Some(w))).height(Is(Some(h))).says(Is(Some(@view.said(Text, label="peek-trigger")))) |> ignore
          @sf.hover_card_node(tips, k, body, tile=true, padded~, tapped=fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=1280.0,
    h=800.0,
    platform=0,
  )
  peek_rest_on(t, menu)
  t
}

///|
/// What a fault of t.audit() says, where it says it, without where it was made: what it names (its words), where it
/// is (at x,y) and what is wrong (after its last "): "), so that one of the old view's and one of the nodes' compare.
fn peek_fault_said(f : String) -> String {
  let what = match f.find(" (") {
    Some(i) => f.exact_view(end=i).to_owned()
    None => f
  }
  let at = match f.find(" at ") {
    Some(i) => {
      let rest = f.exact_view(start=i + 4)
      match rest.find(" ") {
        Some(j) => rest.exact_view(end=j).to_owned()
        None => rest.to_owned()
      }
    }
    None => ""
  }
  let wrong = match f.rev_find("): ") {
    Some(i) => f.exact_view(start=i + 3).to_owned()
    None => ""
  }
  what + " at " + at + ": " + wrong
}

///|
/// The nodes' faults (`new`) the old card's (`old`) did not have, as peek_fault_said says them: what the old card had
/// (a machine faded while it is reconnecting, its figures' words fainter than the contrast asks: 2.55:1) kept as it
/// was, nothing more.
fn peek_faults_new(new : Array[String], old : Array[String]) -> Array[String] {
  let was = old.map(peek_fault_said)
  new.filter(fn(f) { !was.contains(peek_fault_said(f)) })
}

///|
/// Of the nodes' faults the old card's had not, those of its machine faded while it is reconnecting (peek_faded,
/// 0.45: its allowance's chips' words and its network's then fainter than the contrast asks, as the old card's are drawn the same, the
/// old view not holding faded words to it), and the rest. Kept as it is, its colour the product's (BRIEF: contrast is
/// how it looks): said exactly `peek_faded_faults` times where it is coming back, so that mended, this goes.
fn peek_faded_apart(faults : Array[String], name : String) -> (Array[String], Array[String]) {
  let faded = faults.filter(fn(f) {
    name == "coming back" &&
    f.has_prefix("words ") &&
    f.contains(":1, under 4.5") &&
    (f.contains("stillfail/src/sf/quota_node.mbt:") || f.contains("stillfail/src/sfapp/settings/station_peek.mbt:"))
  })
  (faded, faults.filter(fn(f) { !faded.contains(f) }))
}

///|
/// How many such a reconnecting station's card has: its three chips' marks and figures, its network's words.
let peek_faded_faults : Int = 14

///|
test "a station's card as nodes: the same words where they were and the same rectangles as the old card's, in each state" {
  let faults = []
  let mut first : Array[String] = []
  for case in peek_cases() {
    let (name, change) = case
    let to = peek_old(change, fn(c) { @settings.station_peek_card(c, peek_at) })
    let old = peek_drawn(to)
    let old_faults = to.audit()
    // (each state drawn otherwise than the fixture's, but its screens, which show only in its menu)
    if first.length() == 0 {
      first = old
    } else if name != "with screens" && old == first {
      faults.push("\{name}: drawn as the fixture is")
    }
    let t = peek_new(change, fn(b) { @settings.station_peek_card_node(b, peek_at, fn() { 0 }) })
    let new = peek_drawn(t)
    assert_true(old.length() > 4, msg="\{name}: the old card drawn: \{Repr(old)}")
    let d = peek_differ(old, new)
    if d.length() > 0 {
      faults.push("\{name}:\n  " + d.join("\n  "))
    }
    let (faded, a) = peek_faded_apart(peek_faults_new(t.audit(), old_faults), name)
    if a.length() > 0 {
      faults.push("\{name}: audit, the old card's not: \{Repr(a)}")
    }
    if faded.length() != (if name == "coming back" { peek_faded_faults } else { 0 }) {
      faults.push("\{name}: \{faded.length()} faded words fainter than the contrast asks: \{Repr(faded)}")
    }
  }
  assert_eq(faults, [], msg=faults.join("\n"))
}

///|
/// What stands over a station's part in its card in the tests (its agent's card in the app): 40 high.
// kept across runs: a value (no field of it changes)
let peek_over_part : @ui.Style = @ui.css("w=Full h=S10")

///|
test "a station's part as nodes (under its agent's, in one card): the same as the old part's, in each state" {
  let faults = []
  for case in peek_cases() {
    let (name, change) = case
    // (under something as its agent's card is, not in the card's corner: its square is round as a block within)
    let to = peek_old(change, fn(c) {
      c.box(style=peek_over_part, fn() {  }) |> ignore
      @settings.station_peek_part(c, peek_at)
    })
    let old = peek_drawn(to)
    let old_faults = to.audit()
    let t = peek_new(change, fn(b) {
      b.box(fn(o) { @sf.style_node(o, fn() { peek_over_part }) }) |> ignore
      @settings.station_peek_part_node(b, peek_at, fn() { 0 })
    })
    let new = peek_drawn(t)
    assert_true(old.length() > 4, msg="\{name}: the old part drawn: \{Repr(old)}")
    let d = peek_differ(old, new)
    if d.length() > 0 {
      faults.push("\{name}:\n  " + d.join("\n  "))
    }
    let (faded, a) = peek_faded_apart(peek_faults_new(t.audit(), old_faults), name)
    if a.length() > 0 {
      faults.push("\{name}: audit, the old card's not: \{Repr(a)}")
    }
    if faded.length() != (if name == "coming back" { peek_faded_faults } else { 0 }) {
      faults.push("\{name}: \{faded.length()} faded words fainter than the contrast asks: \{Repr(faded)}")
    }
  }
  assert_eq(faults, [], msg=faults.join("\n"))
}

///|
test "a station's card as nodes, its 屏幕 rested on: its menu beside it, the same as the old card's, with screens and with none" {
  let faults = []
  for case in peek_cases().filter(fn(c) { c.0 == "as the fixture" || c.0 == "with screens" }) {
    let (name, change) = case
    // (its 屏幕's words read once the run's Tester is made: peek_rest_on's)
    let menu = "android-misc.screen.section"
    let old = peek_drawn(peek_old(change, fn(c) { @settings.station_peek_card(c, peek_at) }, menu~))
    let t = peek_new(change, fn(b) { @settings.station_peek_card_node(b, peek_at, fn() { 0 }) }, menu~)
    let new = peek_drawn(t)
    let d = peek_differ(old, new)
    if d.length() > 0 {
      faults.push("\{name}:\n  " + d.join("\n  "))
    }
  }
  assert_eq(faults, [], msg=faults.join("\n"))
}

