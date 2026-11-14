// What a message quotes as nodes (message_quotes_node.mbt, the library's quote_card_node) set beside the old view's
// (message.mbt quotes, sf's quote_card) in the same row on the same fixture, state by state: the viewer's, a
// person's and an agent's message; one quote, one cut at two lines, one with what is said of it, a page's and an
// image's mark, a picture of its own (decoded, never had), a video's, two of them; leading to its message or not, its
// ts none; wide and narrow, at 1.3; under the pointer (lit, its tip); pressed.

///|
/// A quote as the core gives it.
fn qt_quote(author? : String = "Ana", text? : String = "先把签名核对一遍", ts? : String = "ts2", role? : String = "person", comment? : String = "", file? : String = "") -> Json {
  {
    "author": Json::string(author),
    "text": Json::string(text),
    "ts": Json::string(ts),
    "role": Json::string(role),
    "comment": Json::string(comment),
    "file": Json::string(file),
  }
}

///|
/// A message of `kind` (mine, person, agent) quoting `quotes`, its files `files` (cmp_picture's).
fn qt_msg(kind : String, quotes : Array[Json], files : Array[Attachment]) -> Message {
  let m : Map[String, Json] = {
    "seq": 5,
    "thread": 7,
    "ts": "ts5",
    "authorKind": Json::string(if kind == "agent" { "agent" } else { "person" }),
    "author": "ana@example.com",
    "mine": Json::boolean(kind == "mine"),
    "text": "好，就这么办",
    "words": [{ "text": "好，就这么办" }],
    "by": { "name": "Ana" },
    "quotes": Json::array(quotes),
    "attachments": Json::array(
      files.map(fn(a) {
        {
          "name": Json::string(a.name),
          "path": Json::string(a.path),
          "size": Json::number(a.size),
          "owner": "ag",
          "width": Json::number(a.width),
          "height": Json::number(a.height),
          "thumbhash": Json::string(a.thumbhash),
          "duration": Json::number(a.duration),
        }
      }),
    ),
    "createdAt": 5,
    "time": @sffixture.ago("2 分钟前", "2026-11-11 21:06"),
  }
  // (an agent's words as the core read their Markdown, one paragraph: asked of nothing, both views reading it)
  if kind == "agent" {
    m["md"] = [["p", ["好，就这么办"]]]
  }
  @sfbase.message_of(Json::object(m))
}

///|
/// A state: its name, its message, its picture's answer (None: never had), whether it leads to its message.
priv struct QtState {
  name : String
  m : Message
  answer : Result[(Json, Bytes?), Json]?
  jumps : Bool
}

///|
fn qt_states() -> Array[QtState] {
  let hash = "1QcSHQRnh493V4dIh4eXh1h4kJUI"
  let pic = cmp_picture("here.png", 800.0, 600.0, thumbhash=hash)
  let clip = cmp_picture("clip.mp4", 1280.0, 720.0)
  let long = "安装包签名已经核对完了，发布说明也写好了，测试的结果和昨天的一样，接下来按说好的顺序一台一台换，换完一台在这里说一声，有问题随时停下来。"
  let out = []
  for kind in ["mine", "person", "agent"] {
    out.push({ name: kind + " one", m: qt_msg(kind, [qt_quote()], []), answer: None, jumps: true })
    out.push({ name: kind + " one, nowhere", m: qt_msg(kind, [qt_quote()], []), answer: None, jumps: false })
    out.push({ name: kind + " no ts", m: qt_msg(kind, [qt_quote(ts="")], []), answer: None, jumps: true })
    out.push({ name: kind + " long", m: qt_msg(kind, [qt_quote(text=long)], []), answer: None, jumps: true })
    out.push({ name: kind + " comment", m: qt_msg(kind, [qt_quote(comment="这句再看看")], []), answer: None, jumps: true })
    out.push({ name: kind + " page", m: qt_msg(kind, [qt_quote(author="发布说明 · 标记 2", role="page", text="第一行\n第二行")], []), answer: None, jumps: false })
    out.push({ name: kind + " image mark", m: qt_msg(kind, [qt_quote(author="图 12", role="image", ts="")], []), answer: None, jumps: true })
    out.push({ name: kind + " picture", m: qt_msg(kind, [qt_quote(file="here.png")], [pic]), answer: Some(cmp_here_bytes(800, 600)), jumps: true })
    out.push({ name: kind + " picture never", m: qt_msg(kind, [qt_quote(file="here.png")], [pic]), answer: None, jumps: true })
    out.push({ name: kind + " video", m: qt_msg(kind, [qt_quote(file="clip.mp4")], [clip]), answer: None, jumps: true })
    out.push({ name: kind + " two", m: qt_msg(kind, [qt_quote(), qt_quote(author="Bo", text="第二条", ts="ts3")], []), answer: None, jumps: true })
  }
  out
}

///|
/// A state's row drawn old (`old`: message_row in row_box) or as nodes, `w` wide, at `scale`, looked at cmp_at; then
/// the pointer on its first quote's words (`hover`): looked at before its tip is due and once it is in; then that
/// pressed (`press`): what it led to. Each look cmp_drawn's.
fn qt_seen(
  s : QtState,
  old : Bool,
  w : Double,
  scale? : Double = 1.0,
  hover? : Bool = false,
) -> (Array[Array[String]], Array[(String, String)], Array[String]) {
  let asks = []
  let a = match s.m.attachments.get(0) {
    Some(a) => a
    None => cmp_picture("none.png", 1.0, 1.0)
  }
  let src = cmp_src({ name: s.name, a, answer: s.answer, coming: None, sent: "" }, asks)
  @sf.set_words(@sfbase.fill)
  absolute_times.set(false)
  let jumped = []
  let view = said_view()
  let pictures = [("mem:cmp/" + a.name, a.width.to_int(), a.height.to_int()), ("cmp/still.png", 1280, 720)]
  let t = if old {
    let here : MessageHere = {
      station: "st",
      session: "s1",
      view,
      go: if s.jumps { Some(fn(seq, text) { jumped.push((seq.to_string(), text)) }) } else { None },
      inline: w <= chat_narrow_w,
      gutter: 0.0,
      list: None,
      core: None,
    }
    @ui.Tester::new(
      fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() {
          c.box(style=head_frame, fn() { row_box(c, row_side(w), 0.0, fn() { message_row(c, src, here, s.m) }) |> ignore })
          |> ignore
        })
      },
      w~,
      h=420.0,
      platform=0,
      images=pictures,
    )
  } else {
    @ui.Tester::new(
      fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
      },
      tree=fn(root) {
        @ui.set_tree_theme(@sf.ui_theme_now)
        let tips = @sf.TipLayer::new(fn() { Some(root) })
        let here : MessageNodeHere = {
          station: "st",
          session: "s1",
          view: fn() { view },
          width: fn() { w },
          tips,
          stint: fn() { 0 },
          jump: if s.jumps { Some(fn(ts, text) { jumped.push((ts, text)) }) } else { None },
        }
        root.box(fn(f) {
          @sf.style_node(f, fn() { head_frame })
          let side = fn() { row_side(w) }
          let top = fn() { 0.0 }
          if s.m.mine {
            mine_said_node(f, src, here, "m:ts5", side, top, fn() { s.m }) |> ignore
          } else if s.m.author_kind == "agent" {
            agent_said_node(f, src, here, "m:ts5", side, top, fn() { s.m }) |> ignore
          } else {
            person_said_node(f, src, here, "m:ts5", side, top, fn() { s.m }) |> ignore
          }
        })
        |> ignore
      },
      w~,
      h=420.0,
      platform=0,
      images=pictures,
    )
  }
  if scale != 1.0 {
    t.set_font_scale(scale)
  }
  t.decode_after("cmp/still.png", cmp_decode)
  t.draw()
  for ask in asks {
    ask()
  }
  t.run_for(cmp_at - t.time())
  t.run_for(@sf.reveal_ms + cmp_at)
  t.draw()
  let looks = [cmp_drawn(t)]
  if hover {
    let q = s.m.quotes[0]
    let (x, y) = match t.words().iter().find_first(fn(w) { w.0.contains(q.text) || q.text.contains(w.0) }) {
      Some(w) => (w.1 + 4.0, w.2 + w.4 / 2.0)
      None => @halt.saying("\{s.name}: its quote's words not drawn")
    }
    t.move_to(x, y)
    t.run_for(@sf.tip_delay_ms - @ui.move_most_ms)
    looks.push(cmp_drawn(t))
    t.run_for(@ui.move_most_ms)
    t.run_for(@ui.move_most_ms)
    looks.push(cmp_drawn(t))
    t.tap(x, y)
    t.run_for(@ui.move_most_ms)
  }
  (looks, jumped, t.audit())
}

///|
/// What the audit says of the nodes that the old view, which it does not hold to them, drew the same (told the
/// coordinator of the migration, 2026-11-12): a pin's number white on the accent (4.13:1; quote_pin's colours, the
/// old card's), and the room a press has where a card that leads to its message stands close under what else is
/// pressed: its own under the head's time or over its picture, the head's time (message_head_node's) over it. The
/// rest of what it says.
fn qt_unknown(faults : Array[String]) -> Array[String] {
  faults.filter(fn(f) {
    let pin = f.has_prefix("words \"") && f.contains("stillfail/src/sf/quote_card_node.mbt:") &&
      f.contains("#ffffff on #cc5a34 4.13:1")
    let room = f.has_prefix("room: 「") &&
      (f.contains("stillfail/src/sf/quote_card_node.mbt:") || f.contains("stillfail/src/sfpages/message_head_node.mbt:"))
    !pin && !room
  })
}

///|
/// A look with its pictures' opacity left out: a likeness waiting breathes as all of what stands in for a picture
/// does, where the old view's took no picture's instances (an intended difference, message_media_cmp_wbtest's).
fn qt_unbreathed(l : Array[String]) -> Array[String] {
  let out = l.map(fn(x) {
    if x.has_prefix("image ") {
      let parts : Array[String] = x.split(",").map(fn(p) { p.to_owned() }).collect()
      parts.pop() |> ignore
      parts.join(",")
    } else {
      x
    }
  })
  out.sort()
  out
}

///|
/// A look at the system's size of words set to 1.3 with a video's capsule left out: as high as its words' line there,
/// 20.2 where the old one's stayed 18 (an intended difference, the coordinator of the migration, 2026-11-12: the
/// library's video_capsule_node grows with its words, df6c4daa5e, as `fixed_outgrown` holds a box holding words to).
/// The look without it, and the capsule's ground and its words' heights.
fn qt_uncapsuled(l : Array[String]) -> (Array[String], Array[String]) {
  let capsule = fn(x : String) {
    (x.has_prefix("rect ") && x.has_suffix(" 166")) ||
    x.has_prefix("words 0:42@") ||
    (x.has_prefix("shape ") && x.has_suffix(" 4294967295") && x.contains(" 0.36458333333333337 "))
  }
  (l.filter(fn(x) { !capsule(x) }), l.filter(capsule))
}

///|
/// A look at the system's size of words set to 1.3 with a pin's number left out: drawn at its size in its mark (16
/// high) as a badge's are (@sf.mark_words_node, apps/mbui/AGENTS.md: a mark of a size said), where the old pin's grew
/// out of it (an intended difference, the coordinator of the migration, 2026-11-12); and so what is as wide as it is
/// with it (its mark, of two figures; the words after it; the card, the viewer's as wide as it needs). The look
/// without those, and the number.
fn qt_unpinned(l : Array[String], pin : String) -> (Array[String], Array[String]) {
  let number = fn(x : String) { x.has_prefix("words " + pin + "@") }
  let widened = fn(x : String) {
    (x.has_prefix("rect ") && (x.has_suffix(" 3428463871") || x.has_suffix(" 3991660543"))) ||
    x.has_prefix("words 先把签名核对一遍@")
  }
  (l.filter(fn(x) { !number(x) && !widened(x) }), l.filter(number))
}

///|
/// What two looks differ in: each's alone.
fn qt_differ(at : String, old : Array[String], new : Array[String]) -> String? {
  if old == new {
    return None
  }
  let only_old = old.filter(fn(x) { !new.contains(x) })
  let only_new = new.filter(fn(x) { !old.contains(x) })
  if only_old.is_empty() && only_new.is_empty() {
    return Some("\{at}: the same, but \{old.length()} and \{new.length()} of them")
  }
  Some("\{at}:\n  old's alone:\n    \{only_old.join("\n    ")}\n  node's alone:\n    \{only_new.join("\n    ")}")
}

///|
test "what a message quotes as nodes is drawn as the old view draws it, state by state, wide and narrow, at 1.3" {
  let differ = []
  for s in qt_states() {
    for ws in [(760.0, 1.0), (390.0, 1.0), (390.0, 1.3)] {
      let (w, scale) = ws
      let (old, _, _) = qt_seen(s, true, w, scale~)
      let (new, _, faults) = qt_seen(s, false, w, scale~)
      let faults = qt_unknown(faults)
      if faults.length() > 0 {
        differ.push("\{s.name} at \{w}, \{scale}: audit: " + faults.join(" | "))
      }
      let (old, new) = if s.name.has_suffix(" picture never") {
        (qt_unbreathed(old[0]), qt_unbreathed(new[0]))
      } else if (s.name.has_suffix(" page") || s.name.has_suffix(" image mark")) && scale != 1.0 {
        let pin = if s.name.has_suffix(" page") { "2" } else { "12" }
        let (old, old_pin) = qt_unpinned(old[0], pin)
        let (new, new_pin) = qt_unpinned(new[0], pin)
        // (each its number once, the node's otherwise than the old one's grown out of its mark)
        assert_true(old_pin.length() == 1 && new_pin.length() == 1 && old_pin != new_pin, msg="\{s.name}: \{Repr(old_pin)} \{Repr(new_pin)}")
        (old, new)
      } else if s.name.has_suffix(" video") && scale != 1.0 {
        let (old, old_capsule) = qt_uncapsuled(old[0])
        let (new, new_capsule) = qt_uncapsuled(new[0])
        // (the node's: its ground as high as its words, 20.2; the old one's 18 under words 20.2 high)
        assert_true(
          new_capsule.any(fn(x) { x.has_prefix("rect ") && x.contains("x20.2 ") }) &&
          old_capsule.any(fn(x) { x.has_prefix("rect ") && x.contains("x18 ") }),
          msg="\{s.name}: \{Repr(old_capsule)} \{Repr(new_capsule)}",
        )
        (old, new)
      } else {
        (old[0], new[0])
      }
      match qt_differ("\{s.name} at \{w}, \{scale}", old, new) {
        Some(d) => differ.push(d)
        None => ()
      }
    }
  }
  if differ.length() > 0 {
    fail(differ.join("\n"))
  }
}

///|
test "a quote under the pointer as the old view's: its words in the text's ink where it leads, its tip in once due; pressed, its message and passage" {
  let differ = []
  for s in qt_states() {
    if !(s.name.has_suffix(" one") || s.name.has_suffix(" one, nowhere") || s.name.has_suffix(" page")) {
      continue
    }
    let (old, _, _) = qt_seen(s, true, 760.0, hover=true)
    let (new, jumped, faults) = qt_seen(s, false, 760.0, hover=true)
    let faults = qt_unknown(faults)
    if faults.length() > 0 {
      differ.push("\{s.name}: audit: " + faults.join(" | "))
    }
    for i, at in ["at rest", "before its tip", "its tip in"] {
      match qt_differ("\{s.name} \{at}", old[i], new[i]) {
        Some(d) => differ.push(d)
        None => ()
      }
    }
    let q = s.m.quotes[0]
    assert_eq(jumped, if s.jumps && q.ts != "" { [(q.ts, q.text)] } else { [] }, msg=s.name)
  }
  if differ.length() > 0 {
    fail(differ.join("\n"))
  }
}

///|
test "what was sent from here quoting, as nodes, is drawn as outbox_row draws it: sending with a quote, a quote of its own picture; wide and narrow" {
  let cases = [
    ("sending, a quote", out_entry("sending", quotes=[qt_quote()])),
    ("sent, a quote of its picture", out_entry("sent", picture=true, quotes=[qt_quote(file="here.png")])),
  ]
  // (its picture's, as the comparison of a message's pictures asks for them (cmp_src: never had); the core's doing none)
  let src = fn(o : Outgoing) {
    match o.attachments.get(0) {
      Some(a) => cmp_src({ name: "outbox", a, answer: None, coming: None, sent: "" }, [])
      None => dec_src(@signals.signal((None : Json?)), [])
    }
  }
  let lines = fn(s : String) { s.split("\n").map(fn(l) { l.to_owned() }).collect() }
  let differ = []
  for c in cases {
    for w in [760.0, 390.0] {
      let at = "\{c.0} at \{w}"
      let old = out_old(w, src(c.1), c.1)
      old.run_for(sending_shows_ms)
      let was = lines(head_drawn(old))
      let t = out_new(w, src(c.1), fn() { c.1 })
      t.run_for(sending_shows_ms)
      match qt_differ(at, was, lines(head_drawn(t))) {
        Some(d) => differ.push(d)
        None => ()
      }
      let faults = qt_unknown(t.audit())
      if faults.length() > 0 {
        differ.push(at + ": audit: " + faults.join(" | "))
      }
    }
  }
  if differ.length() > 0 {
    fail(differ.join("\n"))
  }
}
