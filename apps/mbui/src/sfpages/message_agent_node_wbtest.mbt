// What an agent said as nodes (message_agent_node.mbt's agent_said_node) set beside the old view's (message.mbt
// message_row: others_message with prose_with_files) on the same fixture: the same words where they were, the same
// rectangles drawn, wide and narrow, at 1.3; its words as Markdown (a heading, a list, a table, code, links of each
// kind: a web address, a chat's written bare, its agent's file's path), the file it places where it places it, its
// other files under its words, still.fail's own, links to a station's screens and a web service (their cards); what it
// asks under it, asked, answered, let go, 忽略 alone; a path and a link held, their menus.

///|
/// The core's reading of an agent's words (markdown.ts's tree): `kind` "prose" a heading, a paragraph with a link and
/// code in it, a list, a table, a block of code; "links" a chat's link written bare and its agent's file's path;
/// "placed" a paragraph of only a link to a file it places, then another.
fn ag_tree(kind : String) -> Json {
  let s = fn(x : String) { Json::string(x) }
  let el = fn(name : String, kids : Array[Json]) { Json::array([s(name), Json::array(kids)]) }
  let p = fn(xs : Array[Json]) { el("p", xs) }
  let a = fn(href : String, words : String, bare : Bool) {
    Json::array([s("a"), Json::array([s(words)]), Json::object({ "href": s(href), "bare": Json::boolean(bare) })])
  }
  let code = fn(x : String) { Json::array([s("code"), Json::array([]), Json::object({ "content": s(x) })]) }
  let li = fn(kids : Array[Json]) { Json::array([s("li"), Json::array(kids), Json::object({})]) }
  match kind {
    "links" =>
      Json::array([
        p([s("发布的事在 "), a(said_chat, said_chat, true), s(" 里说过了。")]),
        p([s("改动在 "), a("stillfail-path:12:/w/src/list/place.mbt", "place.mbt:12", false), s("，看一下。")]),
      ])
    "placed" =>
      Json::array([
        p([s("说明写好了：")]),
        p([a("notes.pdf", "notes.pdf", false)]),
        p([s("别的文件在下面。")]),
      ])
    _ =>
      Json::array([
        Json::array([s("h"), Json::array([s("今天的进度")]), Json::object({ "depth": Json::number(2.0) })]),
        p([s("改好了列表的 "), code("each"), s("，见 "), a("https://example.com/notes", "说明", false), s("。")]),
        el("list", [li([s("第一项")]), li([s("第二项，稍微长一点，长到窄排法下要折一行才放得下")])]),
        el("table", [
          el("tr", [el("th", [s("文件")]), el("th", [s("改动")])]),
          el("tr", [el("td", [s("list.mbt")]), el("td", [s("+12 −3")])]),
        ]),
        Json::array([s("pre"), Json::array([]), Json::object({ "code": s("moon test src/sfpages"), "lang": s("sh"), "ink": s("") })]),
      ])
  }
}

///|
/// One of the fixture's messages of an agent of the chat's (`by` "agent"; "stillfail" still.fail's own), its words read
/// as ag_tree(`kind`) says; the files it has (`files`), of which it places `placed`. `kind` "screens": its words
/// chat_fixture's screens_answer, read by the core (chat-screens' fixture reads them).
fn ag_msg(kind : String, by? : String = "agent", files? : Array[String] = [], placed? : Array[String] = []) -> Message {
  if kind == "screens" {
    return @sfbase.message_of({
      "seq": 9,
      "thread": 7,
      "ts": "ts9",
      "authorKind": "agent",
      "author": "codex",
      "text": Json::string(@sffixture.screens_answer),
      "by": { "name": "Codex", "agent": "s-c1", "maker": { "id": "openai" }, "runtime": "codex" },
      "createdAt": 9,
      "time": @sffixture.ago("1 分钟前", "2026-11-11 21:07"),
    })
  }
  @sfbase.message_of({
    "seq": 9,
    "thread": 7,
    "ts": "ts9",
    "authorKind": Json::string(by),
    "author": "codex",
    "text": Json::string("（ag_tree 的原文：" + kind + "）"),
    "md": ag_tree(kind),
    "chats": [{ "href": Json::string(said_chat), "title": "发布" }],
    "by": { "name": "Codex", "agent": "s-c1", "maker": { "id": "openai" }, "runtime": "codex" },
    "placed": Json::array(placed.map(fn(n) { Json::string(n) })),
    "attachments": Json::array(
      files.map(fn(n) {
        Json::object({
          "name": Json::string(n),
          "path": Json::string("/w/uploads/" + n),
          "size": Json::number(12345.0),
          "owner": Json::string("s-c1"),
        })
      }),
    ),
    "createdAt": 9,
    "time": @sffixture.ago("1 分钟前", "2026-11-11 21:07"),
  })
}

///|
/// An agent's message as the nodes draw it in its row (agent_said_node), as `m` says; the source `src` where given, `h`
/// high.
fn ag_new_row(w : Double, m : () -> Message, platform? : Int = 0, src? : Source, h? : Double = 320.0) -> @ui.Tester {
  said_new(w, platform~, src?, h~, fn(f, src, here) {
    agent_said_node(f, src, here, "m:ts9", fn() { row_side((here.width)()) }, fn() { 0.0 }, m) |> ignore
  })
}

///|
/// What a Tester draws (head_drawn's), each place and size to a hundredth of a point (the old view's sums leave tails
/// the nodes' do not).
fn ag_drawn(t : @ui.Tester) -> String {
  let r = fn(x : Double) { (x * 100.0).round() / 100.0 }
  t.words().map(fn(w) { "\{w.0}@\{r(w.1)},\{r(w.2)} \{r(w.3)}x\{r(w.4)} a\{w.5}" }).join("\n") +
  "\n" +
  t.drawn_rects().map(fn(d) { "\{r(d.0)},\{r(d.1)} \{r(d.2)}x\{r(d.3)} \{d.4}" }).join("\n")
}

///|
/// How many rooms `t.audit()` finds short in a case named `name` (ag_cases'), `w` wide, of its head's time (「1 分钟前」,
/// sfpages/message_head_node.mbt): narrow, where the first line of its words is a link right under the head, the time
/// is pressed in 44×34 where 36 is due, 2 short (links: 1; the rest none). That line is drawn as the old view drew it,
/// each item alike (this file's first test), so it is the old arrangement's, not mended where the rule is changed: known,
/// held exactly, only to fall (the coordinator of the migration, 2026-11-12; xfer/chat-wire-list.md).
fn ag_rooms(_name : String, _w : Double) -> Int {
  0
}

///|
/// The fixture's states, by name, each with the source it is read from (None: history's). A window as high as the
/// screens' cards take (ag_high), the others the rows' 320.
fn ag_cases() -> Array[(String, Message, Source?)] {
  [
    ("prose", ag_msg("prose"), None),
    ("links", ag_msg("links"), None),
    ("placed", ag_msg("placed", files=["notes.pdf", "other.zip"], placed=["notes.pdf"]), None),
    ("still.fail's", ag_msg("prose", by="stillfail"), None),
    ("screens", ag_msg("screens"), Some(sl_src())),
  ]
}

///|
test "what an agent said, made once as nodes, is drawn as the old view drew it: its Markdown, its links, a file it places and its others, still.fail's own, wide and narrow" {
  let said : Array[String] = []
  for c in ag_cases() {
    for w in [760.0, 390.0] {
      let at = "\{c.0} at \{w}"
      // (in a chat's list, as the nodes' rows are: its words and its files one piece there, pickable's)
      let old = said_old_row(w, c.1, src?=c.2, h=ag_high(c.0), listed=true)
      old.run_for(@ui.move_most_ms)
      let was = ag_drawn(old)
      let t = ag_new_row(w, fn() { c.1 }, src?=c.2, h=ag_high(c.0))
      t.run_for(@ui.move_most_ms)
      assert_eq(ag_drawn(t), was, msg=at)
      let faults = t.audit()
      let time = faults.filter(fn(f) {
        f.has_prefix("room: ") &&
        f.contains("stillfail/src/sfpages/message_head_node.mbt:") &&
        f.contains("to be pressed in, under 36")
      })
      if time.length() != ag_rooms(c.0, w) {
        said.push(at + ": its head's time short of room \{time.length()} times, \{ag_rooms(c.0, w)} known: " + time.join(" | "))
      }
      for f in faults {
        if !time.contains(f) {
          said.push(at + ": " + f)
        }
      }
    }
  }
  assert_eq(said, [], msg=said.join("\n"))
}

///|
/// How high a case's window is: the screens' cards' 760, the others 320.
fn ag_high(name : String) -> Double {
  if name == "screens" {
    760.0
  } else {
    320.0
  }
}

///|
/// At the system's words set to 1.3 (narrow): the same, a code block's bar too (#5507), its keys then as high as a
/// press takes. Not the screens' cards: at 1.3 their title and its line each as high as their words, where the old
/// view's ran over each other (screen_links_node_wbtest, #5524).
test "what an agent said at the system's words set to 1.3 is drawn as the old view drew it: its Markdown, its links, a file it places and its others, still.fail's own" {
  for c in ag_cases() {
    guard c.0 != "screens" else { continue }
    let old = said_old_row(390.0, c.1, src?=c.2, h=ag_high(c.0), listed=true)
    old.set_font_scale(1.3)
    old.run_for(@ui.move_most_ms)
    let was = ag_drawn(old)
    let t = ag_new_row(390.0, fn() { c.1 }, src?=c.2, h=ag_high(c.0))
    t.set_font_scale(1.3)
    t.run_for(@ui.move_most_ms)
    assert_eq(ag_drawn(t), was, msg=c.0)
    let faults = t.audit()
    assert_eq(faults, [], msg=c.0 + ": " + faults.join(" | "))
  }
}

///|
/// An agent's post asking what dec_msg's asks (`state`: asked, answered, dismissed; alone: 忽略 alone), its words read
/// as one paragraph.
fn ag_dec_msg(state : String) -> Message {
  let d = dec_msg(state)
  { ..d, md: Some(Json::array([Json::array([Json::string("p"), Json::array([Json::string(d.text)])])])) }
}

///|
/// The old view's row of an agent's post in a chat's list (message_row's others_message with prose_with_files, then
/// message_decision under it: what a row out of a list draws without it), `w` wide.
fn ag_dec_old(w : Double, m : Message) -> @ui.Tester {
  let src = dec_src(@signals.signal(None), [])
  dec_old(w, dec_view(), fn(c, here) {
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
          picking(here, c, src, m.ts, m.seq, m.by.name, "agent", m.text, fn() {
            prose_with_files(c, src, here, m, beside_quotes(m.quotes, m.attachments))
          })
          message_decision(c, src, here, m, None)
        },
      )
    })
    |> ignore
  })
}

///|
test "what an agent's post asks under it, in its row made once as nodes, is drawn as the old view's row in a list drew it: asked, answered, let go, 忽略 alone; wide and narrow" {
  for state in ["asked", "answered", "dismissed", "alone"] {
    for w in [760.0, 390.0] {
      let at = "\{state} at \{w}"
      let m = ag_dec_msg(state)
      let old = ag_dec_old(w, m)
      old.run_for(@ui.move_most_ms)
      let was = ag_drawn(old)
      let src = dec_src(@signals.signal(None), [])
      let t = dec_new(w, fn() { dec_view() }, fn(f, here) {
        agent_said_node(f, src, here, "m:ts8", fn() { row_side(w) }, fn() { 0.0 }, fn() { m }) |> ignore
      })
      t.run_for(@ui.move_most_ms)
      assert_eq(ag_drawn(t), was, msg=at)
      dec_audit(t, at)
    }
  }
}

///|
test "a link in what an agent said opens where it leads tapped; right clicked, its menu; its agent's file's path, held, offers nothing where nothing opens beside the chat, as the old view's" {
  @sf.presenters_reset()
  let t = ag_new_row(760.0, fn() { ag_msg("prose") })
  t.run_for(@ui.move_most_ms)
  let (x, y) = said_piece(t, "说明")
  t.tap(x, y)
  t.draw()
  assert_eq(t.opened(), ["https://example.com/notes"])
  t.right_click(x, y)
  t.draw()
  assert_true(@sf.presenting(), msg="its menu")
  @sf.close_all_presented()
  t.draw()
  assert_false(@sf.presenting())
  let t = ag_new_row(760.0, fn() { ag_msg("links") })
  t.run_for(@ui.move_most_ms)
  let (x, y) = said_piece(t, "place.mbt:12")
  t.right_click(x, y)
  t.draw()
  assert_false(@sf.presenting(), msg="nothing opens beside it here")
  let faults = t.audit()
  assert_eq(faults, [], msg=faults.join(" | "))
  @sf.presenters_reset()
}

///|
test "an agent's message with a card in its words' place draws none of its words yet" {
  let m = @sfbase.message_of({
    "seq": 9,
    "thread": 7,
    "ts": "ts9",
    "authorKind": "agent",
    "author": "codex",
    "text": "要一个 vault 里的东西",
    "by": { "name": "Codex", "agent": "s-c1" },
    "card": { "type": "vault", "vaultAsk": { "name": "deploy key", "reason": "部署要用" } },
    "createdAt": 9,
    "time": @sffixture.ago("1 分钟前", "2026-11-11 21:07"),
  })
  let t = ag_new_row(760.0, fn() { m })
  t.run_for(@ui.move_most_ms)
  assert_true(agent_card_kind(m) != "", msg="the fixture's card")
  assert_true(t.find("Codex") is Some(_))
  assert_true(t.find("要一个 vault 里的东西") is None)
}

