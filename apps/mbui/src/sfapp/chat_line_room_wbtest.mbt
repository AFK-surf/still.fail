// A chat's page made with its inside nodes (sfbase's chat_page_nodes on), its agent's line at the list's foot and the
// turn ending with no reply (the owner, 2026-11-12: a turn that ends with no answer must not carry what is read up and
// let it fall back; the line going fades where it is, the owner, 2026-11-11): what was sent stays where it is from the
// look after the line came to rest, never up and back, never down; the line's words gone; the page at its foot. Then,
// into the room the line left, nothing moving or up only: the next turn's line, a reply, the next message sent (one
// line in the composer: the foot as it was). The line is a key the page marks to go leaving its room (mbui's
// View::scrolls_window `leaves_room`, list_foot_room_test's rule). On 小屏 and 大屏, each look 10 ms apart, at every
// rate. This file's own, not chat_page_nodes_wbtest's helpers: its cases set the fixture's station's pace before the
// chat opens (fix_pace, as send_steady_wbtest does).

///|
/// The words sent, and what the fixture's agent says of them as its reply.
let cr_sent : String = "看一下列表"

///|
let cr_reply : String = "收到：「看一下列表」。我先看一下，有结果再告诉你。"

///|
/// How far apart the looks are, and how long a case is looked at past its last change.
let cr_look_ms : Double = 10.0

///|
let cr_after_ms : Double = 1500.0

///|
/// The screens: name, width, height, platform.
let cr_screens : Array[(String, Double, Double, Int)] = [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)]

///|
/// The fixture's chat with its page's inside nodes on `screen`, its station's pace `pace` (fix_pace's: delivery, the
/// answer after it, the turn's end after that or, less than 0, that long before the answer), at rest. `on_pixels`: its
/// list's rows set on the host's pixels, as every device's host sets them (Tester::set_rows_on_pixels).
fn cr_open(
  screen : (String, Double, Double, Int),
  pace : (Double, Double, Double),
  on_pixels? : Bool = false,
) -> @ui.Tester {
  let (_, w, h, platform) = screen
  new_run()
  @sfbase.chat_page_nodes.set(true)
  fix_pace.val = pace
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  if on_pixels {
    t.set_rows_on_pixels(true)
  }
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// `words` typed in the composer and sent.
fn cr_send(t : @ui.Tester, words : String) -> Unit raise {
  guard composer_field(t) is Some((fx, fy, fw, fh)) else { fail("no composer's field") }
  t.tap(fx + fw / 2.0, fy + fh / 2.0)
  t.type_text(words)
  tap_send(t)
}

///|
/// Where the sent words are drawn (their top, drawn as they are said: not the reply that quotes them), none if not.
fn cr_sent_y(t : @ui.Tester) -> Double? {
  t.drawn_of(cr_sent).map(fn(d) { d.1 })
}

///|
/// Whether the agent's line's words are drawn, and how seen.
fn cr_line(t : @ui.Tester) -> Bool {
  t.find(tr("android-chat.chat.working")) is Some(_)
}

///|
/// Looks every cr_look_ms for `ms`, `then` done first: where the sent words are at each, and whether the line shows.
fn cr_looks(t : @ui.Tester, ms : Double, then? : () -> Unit = fn() {  }) -> Array[(Double?, Bool)] {
  then()
  let out = []
  let end = t.time() + ms
  while t.time() < end {
    t.run_for(cr_look_ms)
    out.push((cr_sent_y(t), cr_line(t)))
  }
  out
}

///|
/// Where among `seen` (from look `from` on, from `before` where said: where they were as it began) the sent words were
/// further down than the highest they had been, by more than half a point: none, or where. (Against the highest, not
/// the look before: a fall of half a point a look is a fall.)
fn cr_down(seen : Array[(Double?, Bool)], from : Int, before? : Double? = None) -> String? {
  let mut high = before
  for i in from..<seen.length() {
    match (high, seen[i].0) {
      (Some(h), Some(y)) if y > h + 0.5 => return Some("look \{i}: down from \{h} to \{y}")
      (Some(h), Some(y)) => high = Some(if y < h { y } else { h })
      (None, Some(y)) => high = Some(y)
      _ => ()
    }
  }
  None
}

///|
/// The sent words, the line come under them, the turn over `x` ms after their delivery with no reply in the time
/// looked at (the answer `answer` ms after delivery: past what is looked at unless said): what was looked at from the
/// send, and the look the line came to rest at.
fn cr_turn(screen : (String, Double, Double, Int), x : Double, answer? : Double = 1.0e7) -> (@ui.Tester, Array[(Double?, Bool)], Int) raise {
  let t = cr_open(screen, (fix_deliver_ms, answer, x - answer))
  cr_send(t, cr_sent)
  // (looked at every cr_look_ms only round what moves: the sent words' way and the line's coming, then from just before
  // the turn's end (and the reply, where it comes in what is looked at) till all of that is at rest; between, nothing
  // moves and one look a Move apart says so; the last look at the end)
  let from = t.time()
  let seen = cr_looks(t, fix_deliver_ms + @ui.move_most_ms + 50.0)
  let ends = fix_deliver_ms + (if answer < 1.0e6 && answer > x { answer } else { x })
  let mut at = t.time() - from
  while at < fix_deliver_ms + x - 20.0 - @ui.move_most_ms {
    t.run_for(@ui.move_most_ms)
    seen.push((cr_sent_y(t), cr_line(t)))
    at = t.time() - from
  }
  let gap = fix_deliver_ms + x - 20.0 - (t.time() - from)
  if gap > 0.0 {
    t.run_for(gap)
  }
  seen.append(cr_looks(t, ends + @ui.move_most_ms + 100.0 - (t.time() - from)))
  let rest = fix_deliver_ms + x + cr_after_ms - (t.time() - from)
  if rest > 0.0 {
    t.run_for(rest)
    seen.push((cr_sent_y(t), cr_line(t)))
  }
  // (the line's first look, and the look its way in is done at: as long as a Move takes at most)
  let mut first = -1
  for i, s in seen {
    if s.1 && first < 0 {
      first = i
    }
  }
  guard first >= 0 else { fail("\{screen.0}, \{x} ms: the line never shown") }
  (t, seen, first + (@ui.move_most_ms / cr_look_ms).to_int())
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: a message sent, the agent's line under it, its turn over with no reply after 100, 300, 1000, 3000 ms: what was sent never down, still from the line's rest on, the line gone, at its foot" {
  for screen in cr_screens {
    for x in [100.0, 300.0, 1000.0, 3000.0] {
      let (t, seen, rest) = cr_turn(screen, x)
      let at = "\{screen.0}, the line \{x} ms"
      match cr_down(seen, 0) {
        Some(d) => fail("\{at}: what was sent \{d}")
        None => ()
      }
      let still = seen[rest.min(seen.length() - 1)].0
      for i in rest..<seen.length() {
        match (still, seen[i].0) {
          (Some(a), Some(y)) => assert_true((y - a).abs() <= 0.5, msg="\{at}, look \{i}: what was sent at \{y}, \{a} at the line's rest")
          _ => fail("\{at}, look \{i}: what was sent not drawn")
        }
      }
      assert_false(cr_line(t), msg="\{at}: the line still shown")
      assert_true(t.at_end(), msg="\{at}: not at its foot")
    }
  }
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: the turn over with no reply, then the next turn's line comes into the room it left: nothing moves" {
  for screen in cr_screens {
    let (t, _, _) = cr_turn(screen, 300.0)
    let at = "\{screen.0}"
    let was = cr_sent_y(t)
    // (every cr_look_ms while the line comes, then a look a Move apart: nothing else moves)
    let seen = cr_looks(t, @ui.move_most_ms + 100.0, then=fn() {
      @sffixture.fix_now(fn() { @sffixture.fix_chat("s-c1").working = 0.0 })
    })
    let end = t.time() + cr_after_ms - @ui.move_most_ms - 100.0
    while t.time() < end {
      t.run_for(@ui.move_most_ms)
      seen.push((cr_sent_y(t), cr_line(t)))
    }
    assert_true(seen.iter().any(fn(s) { s.1 }), msg="\{at}: the next turn's line never shown")
    for i, s in seen {
      match (was, s.0) {
        (Some(a), Some(y)) => assert_true((y - a).abs() <= 0.5, msg="\{at}, look \{i}: what was sent at \{y}, \{a} before")
        _ => fail("\{at}, look \{i}: what was sent not drawn")
      }
    }
  }
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: the turn over with no reply, its reply 500 ms after: into the room, what is over it up only, at its foot" {
  for screen in cr_screens {
    let (t, seen, _) = cr_turn(screen, 300.0, answer=800.0)
    let at = "\{screen.0}"
    match cr_down(seen, 0) {
      Some(d) => fail("\{at}: what was sent \{d}")
      None => ()
    }
    assert_true(t.find(cr_reply) is Some(_), msg="\{at}: the reply not drawn")
    assert_true(t.at_end(), msg="\{at}: not at its foot")
  }
}

///|
/// The composer's ground's top (the lowest wide glass drawn): the pinned foot's top as it is drawn now.
fn cr_foot_top(t : @ui.Tester) -> Double? {
  let mut top : Double? = None
  for g in t.drawn_glass() {
    let (_, y, w, _, _, _) = g
    if w > 150.0 && (top is None || top.unwrap() < y) {
      top = Some(y)
    }
  }
  top
}

///|
/// Where words `ws` are drawn cut in the window's tree: each drawn wholly inside what clips it (every holder that clips,
/// up to the window) or not at all; the one edge that may cross them is the pinned foot's top `foot_top` (what comes up
/// from behind the composer is covered by it, not cut in mid air). None, or what.
fn cr_cut(ws : Array[String], foot_top : Double?) -> String? {
  let held = @ui.view_tree().unwrap().drawn_held()
  for i, e in held {
    let (d, _, _) = e
    guard ws.contains(d.words) && d.alpha > 0.0 else { continue }
    let mut lo = @double.neg_infinity
    let mut hi = @double.infinity
    let mut h = held[i].1
    while h >= 0 {
      let (c, up, _) = held[h]
      if c.clips {
        lo = if c.y > lo { c.y } else { lo }
        hi = if c.y + c.h < hi { c.y + c.h } else { hi }
      }
      h = up
    }
    let top = d.y
    let foot = d.y + d.h
    let seen_lo = if top > lo { top } else { lo }
    let seen_hi = if foot < hi { foot } else { hi }
    guard seen_hi - seen_lo > 0.01 else { continue }
    let whole = seen_lo <= top + 0.01 && seen_hi >= foot - 0.01
    let at_foot_top = match foot_top {
      Some(f) => (seen_hi - f).abs() < 0.51 && seen_lo <= top + 0.01
      None => false
    }
    if !whole && !at_foot_top {
      return Some("\{d.words} drawn \{top}..\{foot}, seen \{seen_lo}..\{seen_hi}")
    }
  }
  None
}

///|
/// Whether the time line under what was sent (刚刚, between it at `sent` and the new words at `new`) is drawn.
fn cr_time_under(sent : Double?, new : Double?) -> Bool {
  guard sent is Some(a) && new is Some(b) else { return false }
  @ui.view_tree().unwrap().drawn().iter().any(fn(d) { d.words == "刚刚" && d.alpha > 0.0 && d.y > a && d.y < b })
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: the turn over with no reply, the next message sent (one line) as one move: the time line under what was sent not drawn from the send's frame, the new words at their resting place against what was sent at every look, what was sent up only, no words drawn cut, at its foot" {
  for screen in cr_screens {
    let (t, _, _) = cr_turn(screen, 300.0)
    let at = "\{screen.0}"
    let next = "再看看"
    let was = cr_sent_y(t)
    cr_send(t, next)
    // (from the send's frame, every cr_look_ms while it moves, then at rest)
    let looks : Array[(Double?, Double?, Bool, String?)] = []
    let look = fn() {
      let sent = cr_sent_y(t)
      let new = t.drawn_of(next).map(fn(d) { d.1 })
      looks.push((sent, new, cr_time_under(sent, new), cr_cut([cr_sent, next, "刚刚"], cr_foot_top(t))))
    }
    t.frame()
    look()
    let from = t.time()
    while t.time() < from + 500.0 {
      t.run_for(cr_look_ms)
      look()
    }
    t.run_for(fix_deliver_ms + cr_after_ms)
    look()
    let rest = looks[looks.length() - 1]
    guard rest.0 is Some(ra) && rest.1 is Some(rb) else { fail("\{at}: not drawn at rest") }
    let want = rb - ra
    let mut high = was
    for i, l in looks {
      assert_false(l.2, msg="\{at}, look \{i}: the time line under what was sent drawn")
      match l.3 {
        Some(w) => fail("\{at}, look \{i}: \{w}")
        None => ()
      }
      match (l.0, l.1) {
        (Some(a), Some(b)) =>
          assert_true(((b - a) - want).abs() <= 0.5, msg="\{at}, look \{i}: the new words \{b - a} under what was sent, \{want} at rest")
        _ => ()
      }
      match (high, l.0) {
        (Some(h), Some(y)) => {
          assert_true(y <= h + 0.5, msg="\{at}, look \{i}: what was sent down from \{h} to \{y}")
          if y < h {
            high = Some(y)
          }
        }
        _ => ()
      }
    }
    assert_true(t.at_end(), msg="\{at}: not at its foot")
  }
}
