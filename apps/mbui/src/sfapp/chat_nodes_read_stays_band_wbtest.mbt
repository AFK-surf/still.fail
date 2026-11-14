// chat_nodes_read_stays_wbtest's (what the reader has before their eyes does not move: its head says the rule and how
// it is held): a message whose words start in the room the list keeps under the chat's bar. The bar is drawn only so
// far (rs_bar: 小屏's glass, 大屏's ground); the room under it is the list's, in sight. A message whose words start
// there is the one read, and held by where they start, whatever comes: its own words told longer (they go on down from
// where they start), the row over it told longer, the page before. Till the page told the list what covers its top as
// the bar and that room together, it held the next one, and the one seen moved as it grew.

///|
/// The room the list keeps under the chat's bar on screen `s`, over its first row: 小屏's sfapp list_room, 大屏's
/// sfdesk list_head_gap.
fn rs_band_room(s : (String, Double, Double, Int)) -> Double {
  if s.3 == 2 {
    14.0
  } else {
    24.0
  }
}

///|
/// The list moved by the hand so its content goes up by `by` (down where less than 0): a slow finger on 小屏 (no
/// fling after it), the wheel on 大屏.
fn rs_band_by(t : @ui.Tester, s : (String, Double, Double, Int), by : Double) -> Unit {
  let (_, w, h, platform) = s
  if platform == 2 {
    t.drag(w / 2.0, h * 0.5, w / 2.0, h * 0.5 - by, steps=30)
  } else {
    t.move_to(w * 0.6, h / 2.0)
    t.wheel(w * 0.6, h / 2.0, by)
  }
  rs_rest(t, long_rest_ms * 2.0)
}

///|
/// The list moved by the hand till the message read (rs_read's) has its words start in the room under the bar, a few
/// points into it: that message's number, else None (not come to in a few strokes).
fn rs_band_put(t : @ui.Tester, k : RsCore, s : (String, Double, Double, Int)) -> Int? {
  let room = rs_band_room(s)
  // (the hand's slop: a stroke that moved nothing asked again, further)
  let mut more = 0.0
  for _ in 0..<10 {
    guard rs_bar(t, s.2) is Some(bar) && rs_read(t, k, s) is Some((n, y)) else { return None }
    if y > bar + 2.0 && y < bar + room - 2.0 {
      return Some(n)
    }
    let off = y - (bar + room / 2.0)
    let ask = if off > 0.0 { off + more } else { off - more }
    rs_band_by(t, s, ask)
    match rs_top(t, n) {
      Some(now) if (now - y).abs() < 1.0 => more += 12.0
      _ => more = 0.0
    }
  }
  None
}

///|
/// On screen `s`: a message's words put in the room under the bar, then its own words told longer, the row over it told
/// longer; then, over a core 120 ms late, the page before asked and come with a message's words put there again.
fn rs_band(s : (String, Double, Double, Int)) -> Array[String] {
  let broken : Array[String] = []
  let (t, _, k) = rs_open(s)
  rs_read_up(t, s)
  match rs_band_put(t, k, s) {
    Some(n) => {
      rs_push(
        broken,
        rs_read_held(t, k, s, "\{s.0}: its words in the room under the bar, told longer", fn() {
          rs_told(k, fn() { k.grown.push(n) })
        }),
      )
      rs_push(
        broken,
        rs_read_held(t, k, s, "\{s.0}: its words in the room under the bar, the row over it (第\{n - 1}条) told longer", fn() {
          rs_told(k, fn() { k.grown.push(n - 1) })
        }),
      )
    }
    None => broken.push("\{s.0}: no message's words put in the room under the bar (the cause not made)")
  }
  // (the page before: strokes up, what they ask held, till one is asked; a message's words put there again; let come)
  k.late = 120.0
  let mut strokes = 0
  while k.held.is_empty() && k.l.first.get() > 1 && strokes < 30 {
    k.gate.val = true
    rs_up(t, s, s.2 * 0.4)
    strokes += 1
    rs_rest(t, long_rest_ms * 2.0)
  }
  if k.held.is_empty() {
    k.gate.val = false
    broken.push("\{s.0}: the page before not asked in \{strokes} strokes (the cause not made)")
    return broken
  }
  match rs_band_put(t, k, s) {
    Some(_) =>
      rs_push(
        broken,
        rs_read_held(t, k, s, "\{s.0} late 120: its words in the room under the bar, the page before came", fn() {
          rs_open_gate(k)
        }),
      )
    None => {
      rs_open_gate(k)
      broken.push("\{s.0}: no message's words put in the room under the bar with the page before asked (the cause not made)")
    }
  }
  broken
}

///|
test "read up on a chat's page made as nodes, 小屏: a message's words start in the room under the bar, then it and the row over it are told longer and the page before comes; that message stays where it is in every frame" {
  assert_eq(rs_band(long_screens[0]), [])
}

///|
test "read up on a chat's page made as nodes, 大屏: a message's words start in the room under the bar, then it and the row over it are told longer and the page before comes; that message stays where it is in every frame" {
  assert_eq(rs_band(long_screens[1]), [])
}
