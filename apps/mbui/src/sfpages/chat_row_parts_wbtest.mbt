// A chat's row's small parts that hold words, coming and going while the row shows, the chat's list (as nodes,
// chat_body_node; its rows on the host's pixels, body_new's) at its foot: a notice opened and shut (its time under it,
// message_notice_node), a message said elsewhere whose sending fails and then goes after all (发送失败 in where it
// went, message_head_node's elsewhere_route_node). From the cause to rest no glyph of the last two rows of the list is
// drawn cut at any look 10 ms apart: each drawn wholly inside what shows of it (each holder that clips it, up to the
// list's own window) or not at all. Such a part says `leave` (the coordinator of the migration, 2026-11-13). On 小屏 and
// 大屏, at every rate.

///|
/// A chat's view of twelve messages of a person's, then `last` (a message, or one said elsewhere after the last of them).
fn rp_view(last : Json, elsewhere? : Bool = false) -> ChatView {
  let messages : Array[Json] = []
  for i in 0..<12 {
    let m : Map[String, Json] = {
      "seq": Json::number(i.to_double() + 1.0),
      "thread": 7,
      "ts": Json::string("ts\{i + 1}"),
      "authorKind": "person",
      "author": "林",
      "text": Json::string("第\{i + 1}条：列表的高度量过一次就记住"),
      "by": @sffixture.by_person("林"),
      "createdAt": Json::number(i.to_double() + 1.0),
      "time": @sffixture.ago("5 分钟前", "2026-11-11 21:02"),
    }
    if elsewhere && i == 11 {
      m["elsewhere"] = [last]
    }
    messages.push(Json::object(m))
  }
  if !elsewhere {
    messages.push(last)
  }
  @sfbase.chat_view_made({ "title": "发布", "messages": Json::array(messages), "agents": [{ "session": { "key": "s-c1" } }] })
}

///|
/// The last two rows in sight of the list holding `words` drawn (each where it is drawn: x, y, w, h), and that list's
/// own window's top and foot.
fn rp_last_rows(words : String) -> (Array[(Double, Double, Double, Double)], Double, Double) {
  let tree = @ui.view_tree().unwrap()
  guard tree.drawn().iter().find_first(fn(d) { d.words == words && d.alpha > 0.0 }) is Some(d) else {
    return ([], 0.0, 0.0)
  }
  let (mx, my) = (d.x + d.w / 2.0, d.y + d.h / 2.0)
  for l in tree.lists_seen() {
    let rows = l.rows.map(fn(r) { r.2 })
    if rows.iter().any(fn(r) { mx >= r.0 && mx <= r.0 + r.2 && my >= r.1 && my <= r.1 + r.3 }) {
      let last = if rows.length() > 2 { rows[rows.length() - 2:].to_owned() } else { rows }
      let (top, foot) = match tree.drawn_of(l.list) {
        Some(ld) => (ld.y, ld.y + ld.h)
        None => (@double.neg_infinity, @double.infinity)
      }
      return (last, top, foot)
    }
  }
  ([], 0.0, 0.0)
}

///|
/// Whether drawn box `d` lies over any of `rows` (x, y, w, h).
fn rp_over(d : @view.Drawn, rows : Array[(Double, Double, Double, Double)]) -> Bool {
  rows.iter().any(fn(r) { d.x < r.0 + r.2 && d.x + d.w > r.0 && d.y < r.1 + r.3 && d.y + d.h > r.1 })
}

///|
/// Where a glyph of the last two rows of the list holding `anchor` is drawn cut now (see the file's head; the list's
/// own window is no part's way): none, or what.
fn rp_cut(anchor : String) -> String? {
  let (rows, top, foot) = rp_last_rows(anchor)
  let held = @ui.view_tree().unwrap().drawn_held()
  for i, e in held {
    let (d, _, _) = e
    guard d.words != "" && d.alpha > 0.0 && rp_over(d, rows) else { continue }
    let mut lo = @double.neg_infinity
    let mut hi = @double.infinity
    let mut k = held[i].1
    while k >= 0 {
      let (c, up, _) = held[k]
      // (the list's window: what is scrolled out of it is no part's way)
      if c.clips && !(c.y <= top + 0.01 && c.y + c.h >= foot - 0.01) {
        if c.y > lo {
          lo = c.y
        }
        if c.y + c.h < hi {
          hi = c.y + c.h
        }
      }
      k = up
    }
    let seen_lo = if d.y > lo { d.y } else { lo }
    let seen_hi = if d.y + d.h < hi { d.y + d.h } else { hi }
    guard seen_hi - seen_lo > 0.01 else { continue }
    if seen_lo > d.y + 0.01 || seen_hi < d.y + d.h - 0.01 {
      return Some("\{d.words} drawn \{d.y}..\{d.y + d.h} at \{d.alpha}, seen \{seen_lo}..\{seen_hi}")
    }
  }
  None
}

///|
/// How far apart the looks are.
let rp_look_ms : Double = 10.0

///|
/// The most what is over or under a part may move between two looks rp_look_ms apart: a Move of a line's height goes
/// no faster (its height at once is the fault).
let rp_step_most : Double = 6.0

///|
/// Where words `w` are drawn seen now (their top), none if not.
fn rp_y(w : String) -> Double? {
  @ui.view_tree().unwrap().drawn().iter().find_first(fn(d) { d.words == w && d.alpha > 0.0 }).map(fn(d) { d.y })
}

///|
/// `t` looked at every rp_look_ms for `ms`, `then` done first: where a glyph of the last two rows of the list holding
/// `anchor` is drawn cut (none, or the first look and what), whether `part` is drawn seen at the last look, and where
/// any of `steady` moved by rp_step_most or more between two looks (none, or the first look and what).
fn rp_looks(
  t : @ui.Tester,
  anchor : String,
  part : String,
  ms : Double,
  then : () -> Unit,
  steady? : Array[String] = [],
) -> (String?, Bool, String?) {
  then()
  let from = t.time()
  let mut cut : String? = None
  let mut step : String? = None
  let was : Array[Double?] = steady.map(rp_y)
  while t.time() < from + ms {
    if cut is None {
      cut = rp_cut(anchor).map(fn(w) { "+\{t.time() - from} ms: \{w}" })
    }
    for i, w in steady {
      let now = rp_y(w)
      if step is None && now is Some(b) && was[i] is Some(a) && (b - a).abs() >= rp_step_most {
        step = Some("+\{t.time() - from} ms: \{w} from \{a} to \{b} at once")
      }
      was[i] = now
    }
    t.run_for(rp_look_ms)
  }
  let drawn = @ui.view_tree().unwrap().drawn()
  (cut, drawn.iter().any(fn(d) { d.words == part && d.alpha > 0.0 }), step)
}

///|
/// The chat's list as nodes on `s`, its view `v` (as `view` changes), at its foot.
fn rp_open(s : (String, Double, Double, Int), v : ChatView) -> (@ui.Tester, @signals.Signal[ChatView], @signals.Signal[Array[Entry]]) {
  @sfbase.reset()
  reset()
  let src = @sffixture.fixture("chat")
  let view = @signals.signal(v)
  let entries = @signals.signal(@sfbase.entries_of(v))
  let t = body_new(src, s.1, s.2, s.3, view, entries)
  t.run_for(@ui.move_most_ms)
  (t, view, entries)
}

///|
test "a notice at a chat's list's foot, opened and shut, its time coming and going under it: no glyph of the last two rows drawn cut from the press to rest, nothing over or under it moved a step, on 小屏 and 大屏" {
  for s in [body_screens()[0], body_screens()[2]] {
    let words = "Willow 的 codex 这一轮超时了，已经停下"
    let m : Json = {
      "seq": 13,
      "thread": 7,
      "ts": "ts13",
      "authorKind": "ember",
      "system": true,
      "author": "still.fail",
      "text": Json::string(words),
      "by": { "name": "still.fail" },
      "notice": { "failed": false, "words": Json::string(words), "md": [["p", [[0, words.length()]]]] },
      "createdAt": 13,
      "time": @sffixture.ago("1 分钟前", "2026-11-11 21:07"),
    }
    let (t, _, _) = rp_open(s, rp_view(m))
    guard t.rect_of(words) is Some((x, y, _, h)) else { fail("\{s.0}: the notice not drawn") }
    // (the notice's words, the message over it, its time under it)
    let steady = [words, "第12条：列表的高度量过一次就记住", "1 分钟前"]
    let (cut, shown, step) = rp_looks(t, words, "1 分钟前", 800.0, fn() { t.tap(x + 2.0, y + h / 2.0) }, steady~)
    match cut {
      Some(w) => fail("\{s.0}, opened: \{w}")
      None => ()
    }
    match step {
      Some(w) => fail("\{s.0}, opened: \{w}")
      None => ()
    }
    assert_true(shown, msg="\{s.0}: its time not shown once opened")
    guard t.rect_of(words) is Some((x, y, _, h)) else { fail("\{s.0}: the notice not drawn opened") }
    let (cut, shown, step) = rp_looks(t, words, "1 分钟前", 800.0, fn() { t.tap(x + 2.0, y + h / 2.0) }, steady~)
    match cut {
      Some(w) => fail("\{s.0}, shut: \{w}")
      None => ()
    }
    match step {
      Some(w) => fail("\{s.0}, shut: \{w}")
      None => ()
    }
    assert_false(shown, msg="\{s.0}: its time still shown once shut")
  }
}

///|
test "a message said elsewhere at a chat's list's foot whose sending fails, then goes after all, 发送失败 coming and going in where it went: no glyph of the last two rows drawn cut from the change to rest, on 小屏 and 大屏" {
  for s in [body_screens()[0], body_screens()[2]] {
    let text = "安装包签名已经核对完了"
    let said = fn(failed : Bool) -> Json {
      {
        "key": "e9",
        "after": 12,
        "text": text,
        "place": { "name": "星火#发布", "surface": "slack:T1", "url": "https://acme.slack.com/archives/C1/p1" },
        "failed": failed,
        "received": false,
        "by": @sffixture.by_agent("anthropic", "claude", "s-c1"),
        "time": @sffixture.ago("3 分钟前", "2026-11-11 21:04"),
      }
    }
    let (t, view, entries) = rp_open(s, rp_view(said(false), elsewhere=true))
    assert_true(t.rect_of(text) is Some(_), msg="\{s.0}: what was said elsewhere not drawn")
    let failed = @sf.t("web-main.history.sendFailed")
    let to = fn(f : Bool) {
      let v = rp_view(said(f), elsewhere=true)
      view.set(v)
      entries.set(@sfbase.entries_of(v))
    }
    let (cut, shown, _) = rp_looks(t, text, failed, 800.0, fn() { to(true) })
    match cut {
      Some(w) => fail("\{s.0}, failing: \{w}")
      None => ()
    }
    assert_true(shown, msg="\{s.0}: 发送失败 not shown")
    let (cut, shown, _) = rp_looks(t, text, failed, 800.0, fn() { to(false) })
    match cut {
      Some(w) => fail("\{s.0}, gone after all: \{w}")
      None => ()
    }
    assert_false(shown, msg="\{s.0}: 发送失败 still shown")
  }
}
