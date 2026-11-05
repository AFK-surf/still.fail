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
/// A person's words in the runs the core draws them in (refLinks.ts draftWords): each mark `@[title]` a reference to
/// its chat, its title its text; the rest as written.
fn draft_runs(words : String) -> Json {
  let out : Array[Json] = []
  let mut rest = words
  while true {
    match rest.find("@[") {
      Some(i) => {
        let after = rest.unsafe_substring(start=i + 2, end=rest.length())
        match after.find("]") {
          Some(j) => {
            if i > 0 {
              out.push({ "text": Json::string(rest.unsafe_substring(start=0, end=i)) })
            }
            out.push({ "text": Json::string(after.unsafe_substring(start=0, end=j)), "ref": true })
            rest = after.unsafe_substring(start=j + 1, end=after.length())
          }
          None => break
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
/// A person's words with each mark `@[title]` the link the core makes of it once sent (`[title](its page)`, refs.ts):
/// the chats' pages by their titles in `links`.
fn marks_linked(words : String, links : Map[String, String]) -> String {
  let mut out = words
  for title, link in links {
    out = out.replace_all(old="@[" + title + "]", new="[" + title + "](" + link + ")")
  }
  out
}

///|
/// `v` as the core says it: each entry of the outbox that holds a mark with its words read (draftWords: its `words`),
/// each message its marks made links (`links`).
fn with_draft_runs(v : Json, links : Map[String, String]) -> Json {
  match v {
    Object(m) => {
      let o : Map[String, Json] = {}
      for k, x in m {
        o[k] = with_draft_runs(x, links)
      }
      match (m.get("text"), m.get("seq"), m.get("state"), m.get("words")) {
        (Some(String(t)), Some(_), _, _) if t.contains("@[") => o["text"] = Json::string(marks_linked(t, links))
        (Some(String(t)), None, Some(_), None) if t.contains("@[") => o["words"] = draft_runs(t)
        _ => ()
      }
      Json::object(o)
    }
    Array(a) => Json::array(a.map(fn(x) { with_draft_runs(x, links) }))
    _ => v
  }
}

///|
/// The fixture, its core saying a person's words as the core does (`links`: the pages of the chats a mark names).
fn reads_refs_as_core(links : Map[String, String]) -> (Source) -> Source {
  fn(s) {
    {
      ..s,
      topic: fn(name, params) {
        let tv = (s.topic)(name, params)
        { ..tv, value: tv.value.map(fn(x) { with_draft_runs(x, links) }) }
      },
    }
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
/// The grounds under a piece: what is drawn round it no bigger than it with a few points either way (a chip's, not a
/// bubble's or the page's).
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
    let holds = rx <= x + 1.0 && ry <= y + 1.0 && rx + rw >= x + w - 1.0 && ry + rh >= y + h - 1.0
    if holds && rw <= w + 24.0 && rh <= h + 12.0 && !out.contains(colour) {
      out.push(colour)
    }
  }
  out.sort()
  out
}

///|
/// What a frame drew of words sent: for each place `title` is drawn (the reference), the pieces of the same line that
/// hold one of `around`, each against it; the one of them like `like` if any (else the first).
fn ref_pieces(t : @ui.Tester, title : String, around : Array[String], like : Array[RefPiece]?) -> Array[RefPiece]? {
  let words = t.words().filter(fn(d) { d.5 >= 0.05 })
  let glyphs = t.drawn_glyphs()
  let rects = t.drawn_rects()
  let mut first : Array[RefPiece]? = None
  for a in words {
    if a.0 != title {
      continue
    }
    let (_, ax, ay, aw, ah, _) = a
    let out : Array[RefPiece] = [
      { words: title, dx: 0.0, dy: 0.0, w: aw, h: ah, inks: ref_inks_in(glyphs, ax, ay, aw, ah), grounds: ref_grounds_in(rects, ax, ay, aw, ah) },
    ]
    for d in words {
      let (dw, x, y, w, h, _) = d
      if dw != title && around.iter().any(fn(s) { dw.contains(s) }) && (y + h / 2.0 - (ay + ah / 2.0)).abs() < ah * 2.0 {
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
    out[0] = { ..out[0], w: aw.round(), h: ah.round() }
    out.sort_by(fn(p, q) { if p.dx < q.dx { -1 } else if p.dx > q.dx { 1 } else { 0 } })
    match like {
      Some(l) if l == out => return Some(out)
      _ => ()
    }
    if first is None && out.length() > 1 {
      first = Some(out)
    }
  }
  first
}

///|
test "words sent with a reference picked from the @ menu are drawn as their message has them in every frame from the tap on" {
  let out : Array[String] = []
  let title = "首页的列表改成按天分组"
  let around = ["这个吧"]
  for s in seen_screens {
    let (name, w, h, platform) = s
    let calls : Array[Made] = []
    let t = wide_tester(calls, mode="chat", w~, h~, platform~, wrap=reads_refs_as_core({ "首页的列表改成按天分组": "https://app.still.fail/w/ws1/s/st1/chats/s-c2" }))
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
    // sent: each frame drawn, kept as a host shows it, till the message is in the chat
    let seen : Array[(Double, Array[RefPiece]?)] = []
    let landed_at = Ref(-1.0)
    t.record_host()
    t.host_frames() |> ignore
    t.each_frame(Some(fn() { seen.push((t.time(), ref_pieces(t, title, around, None))) }))
    seen_send(t)
    t.run_as_host(fix_deliver_ms + @ui.move_most_ms)
    t.each_frame(None)
    ignore(landed_at)
    // (its message, once in the chat and still: what every frame before is held to)
    let message = ref_pieces(t, title, around, None)
    match message {
      None => out.push("\{name}: 「\{typed}」 sent: no message with 「\{title}」 and its words in the chat at the end")
      Some(m) => {
        let asked : Map[String, Bool] = {}
        for f in t.host_frames() {
          asked[f.at.to_string()] = f.asked || !f.changed
        }
        let mut shown : Array[RefPiece]? = None
        for e in seen {
          let (at, _) = e
          if asked.get(at.to_string()).unwrap_or(true) {
            shown = ref_pieces_again(e, m)
          }
          match shown {
            Some(p) if p == m => ()
            other => {
              out.push("\{name}: at \{at.round()} ms the words sent drawn as \{other}, their message as \{m}")
              break
            }
          }
        }
      }
    }
  }
  assert_eq(out, [])
}

///|
/// A frame's pieces as caught (the first place found), kept to compare.
fn ref_pieces_again(e : (Double, Array[RefPiece]?), _like : Array[RefPiece]) -> Array[RefPiece]? {
  e.1
}
