// What a person wrote as nodes (message_words_node.mbt): the viewer's own in their bubble (mine_said_node), someone
// else's under their head (person_said_node), set beside the old view's (message.mbt message_row, person_words) on the
// same fixture: the same words where they were, the same rectangles drawn, wide and narrow, short and wrapped, with
// links and a chat's chip, followed by the next, its time pressed, its words at 1.3, words found.

///|
/// The fixture's web link, and the chat its reference is to.
// kept across runs: a value
let said_link : String = "https://example.com/release/notes"

///|
// kept across runs: a value
let said_chat : String = "https://still.fail/c/ws1/st1/s2"

///|
/// A message's words in pieces as the core gives them: each its words, where it leads ("" nowhere), whether it is a
/// chat's reference. A long one wraps in a bubble and a row, a link and a chat's reference among its words.
fn said_parts(long : Bool) -> Array[(String, String, Bool)] {
  if long {
    [
      ("安装包签名已经核对完了，发布说明在 ", "", false),
      (said_link, said_link, false),
      ("，测试的结果也和昨天的一样，接下来按 ", "", false),
      (said_chat, said_chat, true),
      (" 里说好的顺序一台一台换，换完一台在这里说一声，有问题随时停下来。", "", false),
    ]
  } else {
    [("好，就这么办", "", false)]
  }
}

///|
/// One of the fixture's messages: the viewer's (`mine`) or Ana's; `long` its words wrapped, with links; `followed` by
/// their next; `from`, the chat Ana's name is a link to; its agents yet to take it (`waiting`); the runtime it waits
/// for, as the core says it (`blocked`: missing, installing).
fn said_msg(
  mine? : Bool = false,
  long? : Bool = false,
  followed? : Bool = false,
  from? : String = "",
  waiting? : Bool = false,
  blocked? : String = "",
) -> Message {
  let parts = said_parts(long)
  let runs = parts.map(fn(p) {
    let o : Map[String, Json] = { "text": Json::string(p.0) }
    if p.1 != "" {
      o["link"] = Json::string(p.1)
    }
    if p.2 {
      o["ref"] = Json::boolean(true)
    }
    Json::object(o)
  })
  @sfbase.message_of({
    "seq": 5,
    "thread": 7,
    "ts": "ts5",
    "authorKind": "person",
    "author": "ana@example.com",
    "mine": mine,
    "text": Json::string(parts.map(fn(p) { p.0 }).join("")),
    "words": Json::array(runs),
    "chats": [{ "href": Json::string(said_chat), "title": "发布" }],
    "by": { "name": "Ana", "from": Json::string(from) },
    "followed": followed,
    "waiting": waiting,
    "blocked": if blocked == "" {
      Json::null()
    } else {
      {
        "runtime": "codex",
        "state": Json::string(blocked),
        "title": "Willow 上没有 codex",
        "action": "安装",
        "percent": if blocked == "installing" { Json::number(40.0) } else { Json::null() },
      }
    },
    "createdAt": 5,
    "time": @sffixture.ago("2 分钟前", "2026-11-11 21:06"),
  })
}

///|
/// The middle of where the words `s` of a paragraph in pieces are drawn, its first line's (a link's, a line's).
fn said_piece(t : @ui.Tester, s : String) -> (Double, Double) {
  match t.run_rects(s).get(0) {
    Some(r) => (r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
    None => @halt.saying("no words drawn holding \{s}")
  }
}

///|
/// The fixture's chat's view.
fn said_view() -> ChatView {
  @sfbase.chat_view_made({ "title": "发布", "messages": [], "agents": [{ "session": { "key": "s-c1" } }] })
}

///|
/// What the old view draws by `draw` (its Ctx, the fixture's source, where it is: out of a list, or in a chat's list
/// where `listed`, as the nodes' rows are; inline where `w` is narrow), `w` wide (`h` high), in a row's room; the
/// source `src` where it is given (else history's).
fn said_old(
  w : Double,
  draw : (@ui.Ctx, Source, MessageHere) -> Unit,
  platform? : Int = 0,
  src? : Source,
  h? : Double = 320.0,
  listed? : Bool = false,
) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  absolute_times.set(false)
  let src = src.unwrap_or(@sffixture.fixture("history"))
  let view = said_view()
  let here : MessageHere = {
    station: "ws1/st1",
    session: "s1",
    view,
    go: None,
    inline: w <= chat_narrow_w,
    gutter: 0.0,
    list: if listed {
      Some({ rk: "said", turns: @sfbase.turns_of("said"), emits: @sfbase.emits_of("said"), flight: None })
    } else {
      None
    },
    core: None,
  }
  @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { c.box(style=head_frame, fn() { draw(c, src, here) }) |> ignore })
    },
    w~,
    h~,
    platform~,
  )
}

///|
/// A message `m` as the old view draws it in its row (message_row in row_box).
fn said_old_row(w : Double, m : Message, platform? : Int = 0, src? : Source, h? : Double = 320.0, listed? : Bool = false) -> @ui.Tester {
  said_old(w, platform~, src?, h~, listed~, fn(c, src, here) { row_box(c, row_side(w), 0.0, fn() { message_row(c, src, here, m) }) |> ignore })
}

///|
/// What the nodes draw by `draw` (a column's node, the fixture's source, where it is: its list `w` wide, or as
/// `width_now` says), `w` wide; what is presented over it drawn where `presents`; the source `src` where it is given
/// (else history's).
fn said_new(
  w : Double,
  draw : (@view.View, Source, MessageNodeHere) -> Unit,
  platform? : Int = 0,
  width_now? : @signals.Signal[Double],
  presents? : Bool = false,
  src? : Source,
  h? : Double = 320.0,
) -> @ui.Tester {
  @sf.set_words(@sfbase.fill)
  absolute_times.set(false)
  let src = src.unwrap_or(@sffixture.fixture("history"))
  let view = said_view()
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
        width: match width_now {
          Some(s) => fn() { s.get() }
          None => fn() { w }
        },
        tips,
        stint: fn() { 0 },
        jump: None,
      }
      root.box(fn(f) {
        @sf.style_node(f, fn() { head_frame })
        draw(f, src, here)
      })
      |> ignore
      if presents {
        @sf.presented_nodes(root)
      }
    },
    w~,
    h~,
    platform~,
  )
}

///|
/// A message as the nodes draw it in its row: the viewer's (mine_said_node) or someone else's (person_said_node), as
/// `m` says as it changes; `made`, the row made; someone else's offering itself as `share` says (its ⋯), what is
/// presented over it drawn.
fn said_new_row(
  w : Double,
  m : () -> Message,
  platform? : Int = 0,
  width_now? : @signals.Signal[Double],
  made? : Ref[MessageRowNode?] = Ref(None),
  share? : MessageShare? = None,
) -> @ui.Tester {
  said_new(w, platform~, width_now?, presents=share is Some(_), fn(f, src, here) {
    let side = fn() { row_side((here.width)()) }
    let top = fn() { 0.0 }
    made.val = Some(
      if @signals.untracked(m).mine {
        mine_said_node(f, src, here, "m:ts5", side, top, m)
      } else {
        person_said_node(f, src, here, "m:ts5", side, top, m, share~)
      },
    )
  })
}

///|
/// The contrast faults `t.audit()` says of a chat's reference's `@` in what a person wrote: words drawn there in the
/// theme's accent made fainter (sfbase's ref_at_alpha). As the old view draws it, the same colours (on the bubble's
/// ground 2.43:1, on the pane's 2.64:1, under 4.5); its title in the accent itself passes. Kept as it is: its colour is
/// the product's, the owner's to change or not (the coordinator keeps it, 2026-11-11).
fn said_ref_at_faint(t : @ui.Tester) -> Array[String] {
  let accent = @sf.theme().p.accent
  let at = t
    .drawn_glyphs()
    .filter(fn(g) { (g.2 >> 8) == (accent >> 8) && (g.2 & 0xFFL) < (accent & 0xFFL) })
  t
  .audit()
  .filter(fn(f) { f.contains(":1, under ") && at.iter().any(fn(g) { f.contains(" at \{g.0.round()},\{g.1.round()} ") }) })
}

///|
/// What `t.audit()` says of these rows, but a chat's reference's `@` too faint (said_ref_at_faint), said exactly
/// `refs` times (one a reference drawn): one more or one fewer is a fault, so that its colour mended, this is taken out.
fn said_audit(t : @ui.Tester, refs : Int) -> Array[String] {
  let known = said_ref_at_faint(t)
  let faults = t.audit().filter(fn(f) { !known.contains(f) })
  if known.length() != refs {
    faults.push("a chat's reference's @ too faint \{known.length()} times, \{refs} known: " + known.join(" | "))
  }
  faults
}

///|
/// The fixture's states, by name.
fn said_cases() -> Array[(String, Message)] {
  [
    ("mine", said_msg(mine=true)),
    ("mine long", said_msg(mine=true, long=true)),
    ("mine followed", said_msg(mine=true, followed=true)),
    ("mine waiting", said_msg(mine=true, waiting=true)),
    ("mine blocked", said_msg(mine=true, blocked="missing")),
    ("mine installing", said_msg(mine=true, blocked="installing", waiting=true)),
    ("ana", said_msg()),
    ("ana long", said_msg(long=true)),
    ("ana from a chat", said_msg(from=said_chat)),
  ]
}

///|
test "what a person wrote, made once as nodes, is drawn as the old view drew it: the viewer's and another's, short and wrapped, wide and narrow, its time pressed, at 1.3" {
  for c in said_cases() {
    for w in [760.0, 390.0] {
      let at = "\{c.0} at \{w}"
      let old = said_old_row(w, c.1)
      old.run_for(@ui.move_most_ms)
      let was = head_drawn(old)
      let t = said_new_row(w, fn() { c.1 })
      t.run_for(@ui.move_most_ms)
      assert_eq(head_drawn(t), was, msg=at)
      let faults = said_audit(t, if c.0.contains("long") { 1 } else { 0 })
      assert_true(faults.is_empty(), msg=at + ": " + faults.join(" | "))
    }
  }
  // its time pressed: when it was, in both
  for mine in [true, false] {
    let old = said_old_row(760.0, said_msg(mine~))
    old.run_for(@ui.move_most_ms)
    old.tap_text("2 分钟前")
    old.run_for(@ui.move_most_ms)
    let was = head_drawn(old)
    absolute_times.set(false)
    let t = said_new_row(760.0, fn() { said_msg(mine~) })
    t.run_for(@ui.move_most_ms)
    t.tap_text("2 分钟前")
    t.run_for(@ui.move_most_ms)
    assert_eq(head_drawn(t), was, msg="mine \{mine}")
    absolute_times.set(false)
  }
  // the words at 1.3, narrow
  for mine in [true, false] {
    let old = said_old_row(390.0, said_msg(mine~, long=true))
    old.set_font_scale(1.3)
    old.run_for(@ui.move_most_ms)
    let was = head_drawn(old)
    let t = said_new_row(390.0, fn() { said_msg(mine~, long=true) })
    t.set_font_scale(1.3)
    t.run_for(@ui.move_most_ms)
    assert_eq(head_drawn(t), was, msg="mine \{mine}")
    let faults = said_audit(t, 1)
    assert_true(faults.is_empty(), msg=faults.join(" | "))
  }
}

///|
test "the words found are drawn as the old view's person_words draws them found" {
  let m = said_msg(long=true)
  let found = ["签名", "顺序"]
  let old = said_old(760.0, fn(c, _, _) { person_words(c, m.text, "m:ts5", found~, chat_title=chat_title_of(m), runs=m.words) })
  old.run_for(@ui.move_most_ms)
  let was = head_drawn(old)
  let t = said_new(760.0, fn(f, _, _) { person_words_node(f, fn() { m }, found=fn() { found }) |> ignore })
  t.run_for(@ui.move_most_ms)
  assert_eq(head_drawn(t), was)
}

///|
test "the viewer's words in their bubble at the column's end, as wide as the composer sets them at most; the list narrowed, at once as wide as it sets them then" {
  let now = @signals.signal(760.0)
  let t = said_new_row(760.0, fn() { said_msg(mine=true, long=true) }, width_now=now)
  t.run_for(@ui.move_most_ms)
  // (its ground: the neutral one round its words)
  let bubble_of = fn(t : @ui.Tester) {
    let (wx, wy, _, _) = t.rect_of("安装包签名已经核对完了，发布说明在").unwrap()
    t.drawn_rects().filter(fn(r) { r.4 != 0L && r.0 < wx && r.1 < wy && r.0 + r.2 > wx && r.1 + r.3 > wy }).iter().fold(
      init=None,
      fn(a : (Double, Double, Double, Double, Int64)?, r) {
        match a {
          Some(b) if b.2 * b.3 <= r.2 * r.3 => a
          _ => Some(r)
        }
      },
    ).unwrap()
  }
  let b = bubble_of(t)
  assert_true(b.2 <= mine_most_of(760.0) + 0.5, msg="\{Repr(b)}")
  assert_true((b.0 + b.2 - (760.0 - row_side(760.0))).abs() < 0.5, msg="at the column's end: \{Repr(b)}")
  // (its time under it, at its end too)
  let (tx, ty, tw, _) = t.rect_of("2 分钟前").unwrap()
  assert_true(ty > b.1 + b.3 && (tx + tw - (b.0 + b.2)).abs() < 1.0, msg="\{Repr((tx, ty, tw))} \{Repr(b)}")
  // narrowed: drawn so in the frame it is, as one made so
  now.set(390.0)
  t.resize(390.0, 320.0)
  let turned = head_drawn(t)
  let made = said_new_row(390.0, fn() { said_msg(mine=true, long=true) })
  made.run_for(@ui.move_most_ms)
  assert_eq(turned, head_drawn(made))
  let faults = said_audit(made, 1)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "the viewer's time goes once their next message follows it, making its way; and comes back as it does not" {
  let followed = @signals.signal(false)
  let t = said_new_row(760.0, fn() { said_msg(mine=true, followed=followed.get()) })
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("2 分钟前") is Some(_))
  followed.set(true)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("2 分钟前") is None)
  let gone = said_new_row(760.0, fn() { said_msg(mine=true, followed=true) })
  gone.run_for(@ui.move_most_ms)
  let was = head_drawn(gone)
  followed.set(false)
  let t2 = said_new_row(760.0, fn() { said_msg(mine=true, followed=followed.get()) })
  t2.run_for(@ui.move_most_ms)
  assert_true(t2.find("2 分钟前") is Some(_))
  followed.set(true)
  t2.run_for(@ui.move_most_ms)
  assert_eq(head_drawn(t2), was)
  let faults = said_audit(t2, 0)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "a link in what a person wrote opens where it leads tapped; right clicked, its menu; the words beside it, neither" {
  @sf.presenters_reset()
  for mine in [true, false] {
    let t = said_new_row(760.0, fn() { said_msg(mine~, long=true) })
    t.run_for(@ui.move_most_ms)
    let (x, y) = said_piece(t, "https://example.com")
    t.tap(x, y)
    t.draw()
    assert_eq(t.opened(), [said_link], msg="mine \{mine}")
    t.right_click(x, y)
    t.draw()
    assert_true(@sf.presenting(), msg="mine \{mine}: its menu")
    @sf.close_all_presented()
    t.draw()
    assert_false(@sf.presenting())
    let (x, y) = said_piece(t, "安装包签名")
    t.right_click(x, y)
    t.draw()
    assert_false(@sf.presenting(), msg="mine \{mine}: the words beside it")
    let faults = said_audit(t, 1)
    assert_true(faults.is_empty(), msg="mine \{mine}: " + faults.join(" | "))
  }
  @sf.presenters_reset()
}

///|
test "someone else's: their picture out in the margin before the name, the time after it, the words under them; the row found by its key" {
  let made : Ref[MessageRowNode?] = Ref(None)
  let t = said_new_row(760.0, fn() { said_msg(long=true) }, made~)
  t.run_for(@ui.move_most_ms)
  let (nx, ny, _, _) = t.rect_of("Ana").unwrap()
  let (tx, ty, _, _) = t.rect_of("2 分钟前").unwrap()
  let (wx, wy, _, _) = t.rect_of("安装包签名已经核对完了，发布说明在").unwrap()
  assert_true(nx < tx && (ty - ny).abs() < 4.0 && wy > ny && wx < tx, msg="\{Repr((nx, ny, tx, ty, wx, wy))}")
  let picture = t.drawn_rects().filter(fn(r) { r.2 == 18.0 && r.3 == 18.0 })
  assert_true(picture.length() == 1 && picture[0].0 + picture[0].2 <= nx, msg="\{Repr(picture)}")
  guard made.val is Some(row) else { fail("no row") }
  assert_eq(row.key, "m:ts5")
  assert_true(row.node.alive())
  let faults = said_audit(t, 1)
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}


///|
/// What the fixture's message offers of itself (MessageShare): its key, a link, its words; its turn shared counted in
/// `went`.
fn said_share(m : Message, went : Ref[Int]) -> MessageShare {
  { key: "m:ts5", link: fn() { "https://app.still.fail/m/5" }, words: fn() { m.text }, go: fn() { went.val += 1 } }
}

///|
/// Someone else's message `m` as the old view draws it offering itself (others_message with `share`: as in a chat's
/// list, its ⋯ and a right click's offer), its words a person's, in its row.
fn said_old_shared(w : Double, m : Message) -> @ui.Tester {
  said_old(w, fn(c, src, here) {
    row_box(c, row_side(w), 0.0, fn() {
      others_message(
        c,
        here.inline,
        "m:ts5",
        m.time,
        share=Some(fn() {  }),
        share_link="https://app.still.fail/m/5",
        share_words=m.text,
        fn() { message_avatar(c, src, here, m, "") },
        fn() { message_name(c, src, here, "m:ts5", m.by.name, "", m.by.from) },
        None,
        fn() { person_words(c, m.text, "m:ts5", chat_title=chat_title_of(m), runs=m.words) },
      )
    })
    |> ignore
  })
}

///|
/// Where a Tester has the ⋯ of a message (its button, as a screen reader is told it: none while it is not shown).
fn said_more(t : @ui.Tester) -> (Double, Double, Double, Double)? {
  t.query(Button, label=@sf.t("web-main.menu.more")).map(fn(s) { s.rect })
}

///|
test "someone else's offering itself: drawn as the old view drew it, its ⋯ at the head's end shown under the pointer alone, wide and narrow" {
  for w in [760.0, 390.0] {
    for long in [false, true] {
      let m = said_msg(long~)
      let at = "\{w} long \{long}"
      let old = said_old_shared(w, m)
      old.run_for(@ui.move_most_ms)
      let was = head_drawn(old)
      assert_true(said_more(old) is None, msg=at + ": the old one's ⋯ not under the pointer")
      let (wx, wy) = said_piece(old, if long { "安装包签名" } else { "好，就这么办" })
      old.move_to(wx, wy)
      old.run_for(@ui.move_most_ms)
      let was_hovered = head_drawn(old)
      let more = said_more(old)
      assert_true(more is Some(_), msg=at + ": the old one's ⋯ under the pointer")
      let t = said_new_row(w, fn() { m }, share=Some(said_share(m, Ref(0))))
      t.run_for(@ui.move_most_ms)
      assert_eq(head_drawn(t), was, msg=at)
      assert_true(said_more(t) is None, msg=at + ": its ⋯ not under the pointer")
      t.move_to(wx, wy)
      t.run_for(@ui.move_most_ms)
      assert_eq(head_drawn(t), was_hovered, msg=at + ", under the pointer")
      assert_eq(said_more(t), more, msg=at + ": its ⋯ where the old one's was")
      let faults = said_audit(t, if long { 1 } else { 0 })
      assert_true(faults.is_empty(), msg=at + ": " + faults.join(" | "))
    }
  }
  @sf.presenters_reset()
}

///|
test "its ⋯ opens the message's menu beside it, the row saying so; closed with the pointer gone, the ⋯ goes and nothing has the focus" {
  @sf.presenters_reset()
  let m = said_msg()
  let went = Ref(0)
  let made : Ref[MessageRowNode?] = Ref(None)
  let t = said_new_row(760.0, fn() { m }, share=Some(said_share(m, went)), made~)
  t.run_for(@ui.move_most_ms)
  guard made.val is Some(row) else { fail("no row") }
  assert_false((row.menu_on)())
  let (wx, wy) = said_piece(t, "好，就这么办")
  t.move_to(wx, wy)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label=@sf.t("web-main.menu.more"))
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  assert_true((row.menu_on)())
  // (its items: its words, its link, its turn)
  assert_true(t.find(@sf.t("web-main.chat.copyMessage")) is Some(_))
  assert_true(t.find(@sf.t("web-main.chat.copyMessageLink")) is Some(_))
  assert_true(t.find(@sf.t("web-main.chat.selectMessages")) is Some(_))
  // (the pointer off the row, the menu open: its ⋯ still there)
  t.move_to(5.0, 300.0)
  t.run_for(@ui.move_most_ms)
  // (what is under a modal menu is hidden from a screen reader: its ⋯ is there as the row says its menu open)
  assert_true((row.menu_on)())
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenting())
  assert_false((row.menu_on)())
  assert_true(said_more(t) is None)
  // (its menu opened by the pointer, nothing had the focus: none has it as it closes, none left on a ⋯ gone)
  assert_true(t.focused() is None, msg="\{Repr(t.focused().map(fn(s) { s.label }))}")
  // chosen: its turn shared
  t.move_to(wx, wy)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label=@sf.t("web-main.menu.more"))
  t.run_for(@ui.move_most_ms)
  t.tap_text(@sf.t("web-main.chat.selectMessages"))
  t.run_for(@ui.move_most_ms)
  assert_eq(went.val, 1)
  assert_false((row.menu_on)())
  @sf.presenters_reset()
  @sfbase.pick_reset()
}

///|
test "right clicked, someone else's offers itself to the window's menu, at the click, as the old one did" {
  @sfbase.pick_reset()
  let m = said_msg()
  let t = said_new_row(760.0, fn() { m }, share=Some(said_share(m, Ref(0))))
  t.run_for(@ui.move_most_ms)
  let (x, y) = said_piece(t, "好，就这么办")
  t.right_click(x, y)
  t.draw()
  match @sfbase.share_offered.get() {
    Some((ox, oy, _, link, words, key)) => {
      assert_eq((ox, oy), (x, y))
      assert_eq((link, words, key), ("https://app.still.fail/m/5", m.text, "m:ts5"))
    }
    None => fail("nothing offered")
  }
  @sfbase.pick_reset()
}

///|
/// A right click on its name or its time (each pressed, neither with a menu of its own) asks outward to the first that
/// holds it and says on_menu (mbui's Tree::asked_at): the row, as the old view's row offered it there.
test "right clicked on its name or its time, the row's offer: the window's tree asks out to the first that holds it and has one" {
  for words in ["Ana", "2 分钟前"] {
    @sfbase.pick_reset()
    let m = said_msg(from=said_chat)
    let t = said_new_row(760.0, fn() { m }, share=Some(said_share(m, Ref(0))))
    t.run_for(@ui.move_most_ms)
    let (x, y) = t.find(words).unwrap()
    t.right_click(x, y)
    t.draw()
    assert_true(@sfbase.share_offered.get() is Some(_), msg=words)
  }
  @sfbase.pick_reset()
}

///|
test "under the viewer's message, its time gives way to the runtime it waits for, then to its agents yet to take it, then back, one in the other's place" {
  let state = @signals.signal(("", false))
  let t = said_new_row(760.0, fn() {
    let (blocked, waiting) = state.get()
    said_msg(mine=true, blocked~, waiting~)
  })
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("2 分钟前") is Some(_))
  // (each step's: what the row drew once the way was over, read before another Tester is made)
  let steps = [("missing", false), ("installed", true), ("", false)]
  let turned : Array[String] = []
  for step in steps {
    state.set(step)
    t.run_for(@ui.move_most_ms)
    turned.push(head_drawn(t))
    let faults = said_audit(t, 0)
    assert_true(faults.is_empty(), msg="\{Repr(step)}: " + faults.join(" | "))
  }
  for i, step in steps {
    let (blocked, waiting) = step
    let made = said_new_row(760.0, fn() { said_msg(mine=true, blocked~, waiting~) })
    made.run_for(@ui.move_most_ms)
    assert_eq(turned[i], head_drawn(made), msg="\{Repr(step)}")
  }
}

///|
test "a name pressed shorter than a press's room stands compactly with its time msg_head_gap after it: a keyboard and mouse's, a finger's" {
  let msg_head_gap = 6.0
  for platform in [0, 2] {
    let t = said_new_row(760.0, fn() { said_msg(from=said_chat) }, platform~)
    t.run_for(@ui.move_most_ms)
    let (nx, _, nw, _) = t.rect_of("Ana").unwrap()
    let (tx, _, _, _) = t.rect_of("2 分钟前").unwrap()
    assert_true((tx - (nx + nw + msg_head_gap)).abs() < 0.5, msg="platform \{platform}: \{Repr((nx, nw, tx))}")
    let faults = said_audit(t, 0)
    assert_true(faults.is_empty(), msg="platform \{platform}: " + faults.join(" | "))
  }
  // (not pressed: as it was, the time its gap after it)
  let t = said_new_row(760.0, fn() { said_msg() })
  t.run_for(@ui.move_most_ms)
  let (nx, _, nw, _) = t.rect_of("Ana").unwrap()
  let (tx, _, _, _) = t.rect_of("2 分钟前").unwrap()
  assert_true((tx - (nx + nw + msg_head_gap)).abs() < 0.5, msg="\{Repr((nx, nw, tx))}")
}

///|
/// One of the fixture's messages (said_msg's: the viewer's where `mine`) with files `names` (none a picture: their cards).
fn said_with_files(mine : Bool, names : Array[String]) -> Message {
  {
    ..said_msg(mine~),
    attachments: names.map(fn(n) {
      @sfbase.attachment_of({
        "name": Json::string(n),
        "path": Json::string("/w/uploads/" + n),
        "size": Json::number(12345.0),
      })
    }),
  }
}

///|
test "what a person wrote with files, made once as nodes, is drawn as the old view drew it: the viewer's between what it quotes and its words, another's under their words, wide and narrow" {
  for mine in [true, false] {
    for w in [760.0, 390.0] {
      let at = "\{if mine { "mine" } else { "ana" }} at \{w}"
      let m = said_with_files(mine, ["notes.pdf", "release.zip"])
      let old = said_old_row(w, m)
      old.run_for(@ui.move_most_ms)
      let was = head_drawn(old)
      // (a file's card says its name's stem and its kind apart: message_file_card's)
      assert_true(was.contains("notes@") && was.contains(".pdf@"), msg=at + ": the old view draws its file")
      let t = said_new_row(w, fn() { m })
      t.run_for(@ui.move_most_ms)
      assert_eq(head_drawn(t), was, msg=at)
      let faults = said_audit(t, 0)
      assert_true(faults.is_empty(), msg=at + ": " + faults.join(" | "))
    }
  }
}
