// What is under one's own message on a chat's page made with its inside nodes (sfpages' mine_said_node: the one row a
// message sent is and the message it becomes), its state changing while the row shows: a delivery (正在发送, then its
// time) and a refusal (未发送, 重试 and 删除 coming). From the send to rest no glyph of the last two rows of the chat's
// list is drawn cut at any look 10 ms apart: a glyph (words drawn) drawn at all opaque whose box is not wholly inside
// what shows of it (each holder that clips it) is the fault, the edge of the composer's ground excepted (what comes up
// from behind it is covered by it, cr_foot_top's); and a state and the one in its place are never both seen. Its
// states one in another's place say `leave` (the coordinator of the migration, 2026-11-13: what it showed fades where
// it is, its place closes after, what comes shows once the place holds it whole). On 小屏 and 大屏, at every rate, the
// list's rows on the host's pixels as every device's host sets them. Its helpers chat_line_room_wbtest's.

///|
/// The rows of the chat's list in sight now, top to bottom (the list among those seen that holds `words` drawn): each
/// where it is drawn (x, y, w, h).
fn orp_rows(words : String) -> Array[(Double, Double, Double, Double)] {
  let tree = @ui.view_tree().unwrap()
  guard tree.drawn().iter().find_first(fn(d) { d.words == words && d.alpha > 0.0 }) is Some(d) else { return [] }
  let (mx, my) = (d.x + d.w / 2.0, d.y + d.h / 2.0)
  for l in tree.lists_seen() {
    let rows = l.rows.map(fn(r) { r.2 })
    if rows.iter().any(fn(r) { mx >= r.0 && mx <= r.0 + r.2 && my >= r.1 && my <= r.1 + r.3 }) {
      return rows
    }
  }
  []
}

///|
/// Whether drawn box `d` lies over any of `rows` (x, y, w, h).
fn orp_over(d : @view.Drawn, rows : Array[(Double, Double, Double, Double)]) -> Bool {
  rows.iter().any(fn(r) { d.x < r.0 + r.2 && d.x + d.w > r.0 && d.y < r.1 + r.3 && d.y + d.h > r.1 })
}

///|
/// Where a glyph of the last two rows of the chat's list (the one holding `sent`) is drawn cut now (see the file's
/// head): none, or what.
fn orp_cut(t : @ui.Tester, sent : String) -> String? {
  let rows = orp_rows(sent)
  let last = if rows.length() > 2 { rows[rows.length() - 2:].to_owned() } else { rows }
  let foot_top = cr_foot_top(t)
  let held = @ui.view_tree().unwrap().drawn_held()
  for i, e in held {
    let (d, _, _) = e
    guard d.words != "" && d.alpha > 0.0 && orp_over(d, last) else { continue }
    let mut lo = @double.neg_infinity
    let mut hi = @double.infinity
    let mut k = held[i].1
    while k >= 0 {
      let (c, up, _) = held[k]
      if c.clips {
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
    let whole = seen_lo <= d.y + 0.01 && seen_hi >= d.y + d.h - 0.01
    let at_foot = match foot_top {
      Some(f) => (seen_hi - f).abs() < 0.51 && seen_lo <= d.y + 0.01
      None => false
    }
    if !whole && !at_foot {
      return Some("\{d.words} drawn \{d.y}..\{d.y + d.h} at \{d.alpha}, seen \{seen_lo}..\{seen_hi}")
    }
  }
  None
}

///|
/// Which of `ws` are drawn seen now in the last two rows of the chat's list (the one holding `sent`).
fn orp_seen(sent : String, ws : Array[String]) -> Array[String] {
  let rows = orp_rows(sent)
  let last = if rows.length() > 2 { rows[rows.length() - 2:].to_owned() } else { rows }
  let drawn = @ui.view_tree().unwrap().drawn()
  ws.filter(fn(w) { drawn.iter().any(fn(d) { d.words == w && d.alpha > 0.0 && orp_over(d, last) }) })
}

///|
/// The fixture's chat on `screen` with its inside nodes, its station delivering after `deliver` ms, `words` sent (with
/// 失败 in them its station refuses them), looked at every cr_look_ms from the send for `ms`: the first look a glyph of
/// the last two rows is drawn cut (none, or when and what), the first at which `one` and `other` are both seen (none,
/// or when), whether `one` was seen at any, and which of `rest` are drawn at the last look.
fn orp_walk(
  screen : (String, Double, Double, Int),
  deliver : Double,
  words : String,
  one : String,
  other : String,
  rest : Array[String],
  ms : Double,
) -> (String?, String?, Bool, Array[String]) raise {
  let t = cr_open(screen, (deliver, 1.0e7, 1.0e7), on_pixels=true)
  cr_send(t, words)
  let from = t.time()
  let mut cut : String? = None
  let mut both : String? = None
  let mut one_seen = false
  while t.time() < from + ms {
    let at = t.time() - from
    if cut is None {
      cut = orp_cut(t, words).map(fn(c) { "+\{at} ms: \{c}" })
    }
    let seen = orp_seen(words, [one, other])
    if seen.contains(one) {
      one_seen = true
    }
    if both is None && seen.length() == 2 {
      both = Some("+\{at} ms")
    }
    t.run_for(cr_look_ms)
  }
  (cut, both, one_seen, orp_seen(words, rest))
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: a message sent and delivered, 正在发送 under it and then its time: no glyph of the last two rows drawn cut from the send to rest, never both seen" {
  for screen in cr_screens {
    // (delivered 1500 ms after it was sent: 正在发送 seen from sending_shows_ms on, its time then in its place)
    let (cut, both, seen, at_rest) = orp_walk(screen, 1500.0, cr_sent, "正在发送", "刚刚", [cr_sent, "刚刚"], 2500.0)
    match cut {
      Some(c) => fail("\{screen.0}: \{c}")
      None => ()
    }
    match both {
      Some(at) => fail("\{screen.0}: 正在发送 and its time both seen at \{at}")
      None => ()
    }
    assert_true(seen, msg="\{screen.0}: 正在发送 never seen")
    assert_eq(at_rest, [cr_sent, "刚刚"], msg="\{screen.0}: at rest")
  }
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: a message sent and refused, 未发送, 重试 and 删除 coming under it: no glyph of the last two rows drawn cut from the send to rest" {
  // (the words as the app's tables say them in Chinese: read before a run has begun they would be another run's)
  let (sending, unsent, retry, delete) = ("正在发送", "未发送", "重试", "删除")
  for screen in cr_screens {
    let words = "这条会失败"
    let (cut, both, _, at_rest) = orp_walk(screen, fix_deliver_ms, words, sending, unsent, [words, unsent, retry, delete], 2500.0)
    match cut {
      Some(c) => fail("\{screen.0}: \{c}")
      None => ()
    }
    match both {
      Some(at) => fail("\{screen.0}: 正在发送 and 未发送 both seen at \{at}")
      None => ()
    }
    assert_eq(at_rest, [words, unsent, retry, delete], msg="\{screen.0}: at rest")
  }
}
