// What a chat's card holds as nodes (peeks_chat_node.mbt's chat_card_node) set beside the old view's (peeks.mbt
// chat_card) in the same room, as the same core reads the link and the list: the words where they were and the
// rectangles drawn the same, in each state it shows (a chat alone, where it stands; the one message its link names,
// said, read, gone; its agent's execution history; another station's; one archived; one gone; its bones while the link
// is read; its bones while its whole row, when it was last active, is read).

///|
/// The source the card reads: the fixture's, the message its link names as `said` says it (its value, its error), the
/// core's reading of links never answered where `parsed` is false, a chat's whole row (`chatRow`) never answered where
/// `whole` is false.
fn pc_src(said : (Json?, Json?), parsed : Bool, whole~ : Bool = true) -> Source {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  // (what the core said of each link, asked again in each: chats_named is kept across runs)
  chats_named.clear()
  let made = @sffixture.fixture("rich-chat")
  {
    ..made,
    topic_read: fn(name, params) {
      if name == "messagePeek" {
        let (value, error) = said
        { value, error, version: if value is None && error is None { 0 } else { 1 } }
      } else if name == "chatRow" && !whole {
        { value: None, error: None, version: 0 }
      } else {
        made.topic(name, params).get().snapshot()
      }
    },
    call: fn(name, params, done) {
      if name == "link.parse" && !parsed {
        ()
      } else {
        (made.call)(name, params, done)
      }
    },
  }
}

///|
/// The old view's card (chat_card) of `href` read in a chat of `here`, as its message says it (`linked`).
fn pc_old(
  here : String,
  href : String,
  linked : LinkedChat?,
  said : (Json?, Json?),
  parsed : Bool,
  whole : Bool,
) -> @ui.Tester {
  let src = pc_src(said, parsed, whole~)
  let t = @ui.Tester::new(
    fn(c) {
      @sfbase.held_build()
      c.after_build("held/end", fn() { @sfbase.held_end() })
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        c.box(style=pf_frame, fn() {
          c.box(style=hover_inner, fn() { chat_card(c, src, "pc", here, href, linked) }) |> ignore
        })
        |> ignore
      })
    },
    w=400.0,
    h=720.0,
    native=Mouse,
    pointing=Mouse,
  )
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The nodes' card (chat_card_node) of the same, in the same room.
fn pc_new(
  here : String,
  href : String,
  linked : LinkedChat?,
  said : (Json?, Json?),
  parsed : Bool,
  whole : Bool,
) -> @ui.Tester {
  let src = pc_src(said, parsed, whole~)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.box(fn(f) {
        @sf.style_node(f, fn() { pf_frame })
        f.box(fn(inner) {
          @sf.style_node(inner, fn() { hover_inner })
          chat_card_node(inner, src, "pc-node", here, fn() { href }, fn() { linked })
        })
        |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=720.0,
    native=Mouse,
    pointing=Mouse,
  )
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Each state, by name: where it is read, its link, its message's saying, what the core says of the message it names,
/// whether the core reads the link, whether it says the chat's whole row.
fn pc_cases() -> Array[(String, String, String, LinkedChat?, (Json?, Json?), Bool, Bool)] {
  let said = (Some(@sffixture.fixture_message_peek()), None)
  let archived : LinkedChat = { href: "", title: "归档的对话", archived: true, note: "已归档", thread: Some(7.0) }
  let base = "https://app.still.fail/o/ws1/st1/"
  [
    ("a chat alone", "ws1/st1", base + "s-c2", None, said, true, true),
    ("one message, said", "ws1/st1", base + "s-c2?message=2", None, said, true, true),
    ("one message, read", "ws1/st1", base + "s-c2?message=2", None, (None, None), true, true),
    ("one message, gone", "ws1/st1", base + "s-c2?message=999", None, (Some(Json::null()), None), true, true),
    ("its agent's execution history", "ws1/st1", base + "s-c2?history=1", None, said, true, true),
    ("another station's", "ws1/st9", base + "s-c2", None, said, true, true),
    ("archived", "ws1/st1", base + "s-old?message=3", Some(archived), said, true, true),
    ("archived, no note", "ws1/st1", base + "s-old", Some({ ..archived, note: "" }), said, true, true),
    ("gone", "ws1/st1", base + "s-nope", None, said, true, true),
    ("the link read", "ws1/st1", base + "s-c2", None, said, false, true),
    ("its whole row read", "ws1/st1", base + "s-c2", None, said, true, false),
  ]
}

///|
test "a chat's card made once as nodes holds what the old view's did: alone, one message said, read and gone, its history, elsewhere, archived, gone, its bones" {
  for c in pc_cases() {
    let (name, here, href, linked, said, parsed, whole) = c
    let old = pc_old(here, href, linked, said, parsed, whole)
    let was = pf_drawn(old)
    let t = pc_new(here, href, linked, said, parsed, whole)
    assert_eq(pf_drawn(t), was, msg=name)
    assert_eq(t.audit(), [], msg=name)
  }
}

///|
test "a chat's card made once as nodes cuts long words where the old view's did: the message its link names on six lines at most, an archived chat's note on three" {
  let long = "这一条消息说得很长很长：列表按天分组已经做好了，今天和昨天之外的日子都写日期；滚动的时候每一帧的耗时都量过了，" +
    "最慢的一帧是在分组的标题刚进来的时候；接下来想把图片的解码挪到后台去，再看看能不能把分组标题做成固定在顶上的样子，" +
    "这样往回翻的时候也知道自己在哪一天；另外搜索结果里的高亮颜色也要改一下，现在在暗色主题里看不太清楚，最后再补几个测试。"
  let message = fixture_message_obj()
  message["text"] = Json::string(long)
  let said = (Some(Json::object(message)), None)
  let archived : LinkedChat = { href: "", title: "归档的对话", archived: true, note: long, thread: None }
  let base = "https://app.still.fail/o/ws1/st1/"
  for c in [
    ("one message, said at length", base + "s-c2?message=2", None),
    ("archived, its note at length", base + "s-old", Some(archived)),
  ] {
    let (name, href, linked) = c
    let old = pc_old("ws1/st1", href, linked, said, true, true)
    let was = pf_drawn(old)
    let was_lines = old.lines_of("这一条消息")
    let t = pc_new("ws1/st1", href, linked, said, true, true)
    assert_eq(pf_drawn(t), was, msg=name)
    let lines = t.lines_of("这一条消息")
    assert_eq(lines, was_lines, msg=name)
    assert_true(lines.length() == (if linked is None { 6 } else { 3 }) && lines[lines.length() - 1].has_suffix("…"), msg="\{name}: \{Repr(lines)}")
  }
}

///|
/// The made-up message its link names (fixture_message_peek's), its fields to be changed.
fn fixture_message_obj() -> Map[String, Json] {
  match @sffixture.fixture_message_peek() {
    Object(m) => m.copy()
    _ => {}
  }
}
