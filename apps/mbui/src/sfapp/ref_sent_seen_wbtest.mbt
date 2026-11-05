// Words sent with a reference to another chat in them, picked from the @ menu as a person picks it: from the tap on
// send to their message, every frame shows them as their message has them once it is in the chat (the user,
// 2026-11-05: 「为什么消息发送过程中的 at 消息依然不是渲染好的？」「不是说了渲染用户消息的地方都用同一个逻辑？」). Held on what is
// drawn alone: the words' pieces, where each is against the reference's, how big, in what inks, and what ground is
// drawn under the reference; nothing of how the app draws them.
//
// What the app asks the core of the words (`ref.at`, `ref.words`…) is the real core's answer (src/sfkept); the
// made-up core's outbox and messages are made to hold their words as the core reads them (core-ts refLinks.ts
// draftWords: their `words`), which the fixture leaves out.

///|
/// A person's words as sent (their marks links, `[title](its page)`: refs.ts expand) in the runs the core draws them in
/// (refLinks.ts personWords): each link to a chat a reference, its title its text; the rest as written.
fn person_runs(words : String) -> Json {
  let out : Array[Json] = []
  let mut rest = words
  while true {
    match rest.find("](https://app.still.fail/") {
      Some(j) => {
        let head = rest.unsafe_substring(start=0, end=j)
        match (head.rev_find("["), rest.unsafe_substring(start=j + 2, end=rest.length()).find(")")) {
          (Some(i), Some(k)) => {
            if i > 0 {
              out.push({ "text": Json::string(head.unsafe_substring(start=0, end=i)) })
            }
            let link = rest.unsafe_substring(start=j + 2, end=j + 2 + k)
            out.push({
              "text": Json::string(head.unsafe_substring(start=i + 1, end=head.length())),
              "link": Json::string(link),
              "ref": true,
              "to": { "chat": true },
            })
            rest = rest.unsafe_substring(start=j + 3 + k, end=rest.length())
          }
          _ => break
        }
      }
      None => break
    }
  }
  if rest != "" {
    out.push({ "text": Json::string(rest) })
  }
  Json::array(out)
}

///|
/// Words going out with each mark of a chat picked its link, as the core sends them (the fixture's links kept for
/// marks: chat.ref).
fn outbox_linked(words : String) -> String {
  let mut out = words
  for title, link in @sffixture.fix_ref_links {
    out = out.replace_all(old="@[" + title + "]", new="[" + title + "](" + link + ")")
  }
  out
}

///|
/// `v` as the core says it (views.ts): each entry of the outbox and each person's message with its words in runs (its
/// marks, as the core sends them, links: the fixture's own are made links as it delivers them).
fn with_draft_runs(v : Json) -> Json {
  match v {
    Object(m) => {
      let o : Map[String, Json] = {}
      for k, x in m {
        o[k] = with_draft_runs(x)
      }
      match (m.get("text"), m.get("seq"), m.get("state"), m.get("authorKind"), m.get("words")) {
        (Some(String(t)), Some(_), _, Some(String("person")), None) => o["words"] = person_runs(t)
        // (an entry of the outbox: its text with its marks made links as it goes out, refs.ts expand, in the runs a
        // message's are: views.ts personWords)
        (Some(String(t)), None, Some(_), _, None) if t != "" => o["words"] = person_runs(outbox_linked(t))
        _ => ()
      }
      Json::object(o)
    }
    Array(a) => Json::array(a.map(with_draft_runs))
    _ => v
  }
}

///|
/// The fixture, its core saying a person's words as the core does.
fn reads_refs_as_core(s : Source) -> Source {
  {
    ..s,
    topic: fn(name, params) {
      let tv = (s.topic)(name, params)
      { ..tv, value: tv.value.map(with_draft_runs) }
    },
  }
}

///|
/// A piece of words as drawn: its words, where against the reference, its size, the inks of the glyphs in it, and the
/// colours of what is drawn under it (a reference's ground).
priv struct RefPiece {
  words : String
  dx : Double
  dy : Double
  w : Double
  h : Double
  inks : Array[Int64]
  grounds : Array[Int64]
} derive(Show, Eq)

///|
fn ref_inks_in(glyphs : Array[(Double, Double, Int64)], x : Double, y : Double, w : Double, h : Double) -> Array[Int64] {
  let out : Array[Int64] = []
  for g in glyphs {
    if g.0 >= x - 1.0 && g.0 <= x + w + 1.0 && g.1 >= y - 1.0 && g.1 <= y + h + 1.0 && !out.contains(g.2) {
      out.push(g.2)
    }
  }
  out.sort()
  out
}

///|
/// The grounds drawn within a piece: what is drawn round some of its words, no bigger than it with a few points
/// either way (a reference's chip in its line), not a bubble's or the page's: each its place in the piece and colour.
fn ref_grounds_in(
  rects : Array[(Double, Double, Double, Double, Int64)],
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> Array[Int64] {
  let out : Array[Int64] = []
  for r in rects {
    let (rx, ry, rw, rh, colour) = r
    let (cx, cy) = (rx + rw / 2.0, ry + rh / 2.0)
    let within = cx >= x && cx <= x + w && cy >= y && cy <= y + h
    if within && rw < w + 2.0 && rh <= h + 12.0 && !out.contains(colour) {
      out.push(colour)
    }
  }
  out.sort()
  out
}

///|
/// What a frame drew of words sent: for each place words holding `title` (the reference) are drawn with one of
/// `around` in them or on their line, those pieces, each against the first; the first such place found.
fn ref_pieces(t : @ui.Tester, title : String, around : Array[String], like : Array[RefPiece]?) -> Array[RefPiece]? {
  ignore(like)
  let words = t.words().filter(fn(d) { d.5 >= 0.05 })
  let glyphs = t.drawn_glyphs()
  let rects = t.drawn_rects()
  let has_around = fn(s : String) { around.iter().any(fn(a) { s.contains(a) }) }
  for a in words {
    // (the agent's answer quotes the words: not them)
    if !a.0.contains(title) || a.0.contains("收到") {
      continue
    }
    let (_, ax, ay, _, ah, _) = a
    let out : Array[RefPiece] = []
    for d in words {
      let (dw, x, y, w, h, _) = d
      let same_line = (y + h / 2.0 - (ay + ah / 2.0)).abs() < ah * 2.0
      if same_line && !dw.contains("收到") && (dw.contains(title) || has_around(dw)) && (x - ax).abs() < 800.0 {
        out.push({
          words: dw,
          dx: (x - ax).round(),
          dy: (y - ay).round(),
          w: w.round(),
          h: h.round(),
          inks: ref_inks_in(glyphs, x, y, w, h),
          grounds: ref_grounds_in(rects, x, y, w, h),
        })
      }
    }
    out.sort_by(fn(p, q) { if p.dx < q.dx { -1 } else if p.dx > q.dx { 1 } else { 0 } })
    if out.iter().any(fn(p) { has_around(p.words) }) {
      return Some(out)
    }
  }
  None
}

///|
test "words sent with a reference picked from the @ menu are drawn as their message has them in every frame from the tap on" {
  let out : Array[String] = []
  let title = "首页的列表改成按天分组"
  let around = ["这个吧"]
  for s in seen_screens {
    let (name, w, h, platform) = s
    let calls : Array[Made] = []
    let t = wide_tester(calls, mode="chat", w~, h~, platform~, wrap=reads_refs_as_core)
    t.set_frame_period(if platform == 0 { 1000.0 / 60.0 } else { 1000.0 / 120.0 })
    t.run_for(@ui.move_most_ms)
    seen_tap(t, "发消息")
    t.run_as_host(@ui.move_most_ms)
    t.text_told("@首页", t.time())
    t.run_as_host(@ui.move_most_ms)
    // (the chat picked from the menu: its row's button over the composer)
    match t.query(Button, label=title) {
      Some(b) => {
        let (x, y) = (b.rect.0 + b.rect.2 / 2.0, b.rect.1 + b.rect.3 / 2.0)
        t.touch_at(0, x, y, t.time())
        t.touch_at(2, x, y, t.time())
      }
      None => abort("no 「\{title}」 in the @ menu: \{t.words().map(fn(w) { w.0 })}")
    }
    t.run_as_host(@ui.move_most_ms)
    t.text_told("这个吧", t.time())
    t.run_as_host(@ui.move_most_ms)
    let typed = t.ime().1
    // sent: each frame's glyphs (where, in what ink), kept as a host shows it, till the message is in the chat
    let seen : Array[(Double, Array[(Double, Double, Int64)])] = []
    t.record_host()
    t.host_frames() |> ignore
    t.each_frame(Some(fn() { seen.push((t.time(), t.drawn_glyphs())) }))
    seen_send(t)
    t.run_as_host(fix_deliver_ms + @ui.move_most_ms)
    t.each_frame(None)
    let asked : Map[String, Bool] = {}
    for f in t.host_frames() {
      asked[f.at.to_string()] = f.asked || !f.changed
    }
    // (and on, its agent's answer and its turn over: the message as the chat has it from then)
    t.run_as_host(fix_answer_ms + fix_turn_end_ms + @ui.move_most_ms)
    // (its message, once in the chat and still: its glyphs, each against its first, what every frame before is held to)
    match ref_pieces(t, title, around, None) {
      None => out.push("\{name}: 「\{typed}」 sent: no message with 「\{title}」 and its words in the chat at the end")
      Some(m) => {
        let line = t.words().filter(fn(d) { d.0 == m[0].words && d.5 >= 0.05 && !d.0.contains("收到") })
        let (lx, ly, lw, lh) = (line[0].1, line[0].2, line[0].3, line[0].4)
        let mine = t.drawn_glyphs().filter(fn(g) { g.0 >= lx - 1.0 && g.0 <= lx + lw + 1.0 && g.1 >= ly - 1.0 && g.1 <= ly + lh + 1.0 })
        mine.sort_by(fn(p, q) { if p.0 < q.0 { -1 } else if p.0 > q.0 { 1 } else { 0 } })
        let shape = mine.map(fn(g) { (g.0 - mine[0].0, g.1 - mine[0].1, g.2) })
        let mut shown : Array[(Double, Double, Int64)] = []
        for e in seen {
          let (at, glyphs) = e
          if asked.get(at.to_string()).unwrap_or(true) {
            shown = glyphs
          }
          let (best, inks) = ref_shape_in(shown, shape)
          if best < shape.length() {
            out.push("\{name}: at \{at.round()} ms the words sent are not drawn as their message is: \{best} of its \{shape.length()} glyphs where and in the ink they are in it (its inks \{shape.map(fn(g) { g.2 })}, there \{inks})")
            break
          }
        }
      }
    }
  }
  assert_eq(out, [])
}

///|
/// How much of `shape` (glyphs each against the first: where, in what ink) is drawn among `glyphs` at its best place:
/// how many of its glyphs, and the inks drawn where they are there.
fn ref_shape_in(glyphs : Array[(Double, Double, Int64)], shape : Array[(Double, Double, Int64)]) -> (Int, Array[Int64]) {
  let mut best = 0
  let mut best_inks : Array[Int64] = []
  for g in glyphs {
    // (a place its first glyph could be: one in its ink, or any while none is found)
    if shape.length() > 0 && g.2 != shape[0].2 && best > 0 {
      continue
    }
    let mut n = 0
    let inks : Array[Int64] = []
    for s in shape {
      let (dx, dy, ink) = s
      let mut here : Int64 = -1L
      for o in glyphs {
        if (o.0 - g.0 - dx).abs() < 1.0 && (o.1 - g.1 - dy).abs() < 1.0 {
          here = o.2
          if o.2 == ink {
            break
          }
        }
      }
      if here == ink {
        n += 1
      }
      inks.push(here)
    }
    if n > best {
      best = n
      best_inks = inks
    }
    if best == shape.length() {
      break
    }
  }
  (best, best_inks)
}
