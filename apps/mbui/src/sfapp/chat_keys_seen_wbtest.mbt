// A chat's page made with its inside nodes, a row coming on its way as a key of its list (mbui's View::scrolls_window:
// what its block holds drawn as big as how much of it shows, as an old list's row; the user, 2026-10-31 and
// 2026-11-08): the first message sent with nothing given back (no room, the composer one line), and the reply coming
// over the agent's line, which stays last. No glyph of the last two rows drawn cut at any look 10 ms apart: a glyph
// (words drawn) drawn at all opaque whose drawn box is not wholly inside what shows of it (each holder that clips it,
// its key's block cut to itself on its way among them) is the fault, however faint and wherever its edge fades; the
// edge of the composer's ground excepted (what comes up from behind it is covered by it, cr_foot_top's). On 小屏 and
// 大屏, at every rate, its list's rows set on the host's pixels as every device's host sets them (what is judged is where
// glyphs are drawn against what shows of them, on the grid a device draws them on). Its helpers chat_line_room_wbtest's.

///|
/// Where words `ws` are drawn cut in the window's tree now (see the file's head), among the last rows (drawn under
/// `below`: not a head of an older message scrolled under the list's top): none, or what.
fn ks_cut_inked(ws : Array[String], foot_top : Double?, below : Double) -> String? {
  let tree = @ui.view_tree().unwrap()
  let held = tree.drawn_held()
  for i, e in held {
    let (d, _, _) = e
    guard ws.contains(d.words) && d.alpha > 0.0 && d.y > below else { continue }
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
/// `t` looked at every cr_look_ms for `ms` from now: the first look a glyph of `ws` is drawn cut (none, or when and
/// what).
fn ks_page_looks(t : @ui.Tester, ws : Array[String], ms : Double, h : Double) -> String? {
  let from = t.time()
  while t.time() < from + ms {
    match ks_cut_inked(ws, cr_foot_top(t), h / 2.0) {
      Some(w) => return Some("+\{t.time() - from} ms: \{w}")
      None => ()
    }
    t.run_for(cr_look_ms)
  }
  None
}

///|
let ks_words : Array[String] = [cr_sent, cr_reply, "刚刚", "Claude"]

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: the first message sent, nothing given back (no room, the composer one line): no glyph of the last two rows drawn cut at any look, however faint" {
  for screen in cr_screens {
    let t = cr_open(screen, (fix_deliver_ms, 1.0e7, 1.0e7), on_pixels=true)
    cr_send(t, cr_sent)
    t.frame()
    match ks_page_looks(t, ks_words, 600.0, screen.2) {
      Some(w) => fail("\{screen.0}: \{w}")
      None => ()
    }
  }
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: the reply coming over the agent's line, which stays last: no glyph of the last two rows drawn cut at any look, however faint" {
  for screen in cr_screens {
    // (the line under what was sent from its delivery on, the reply 1400 ms after, the turn's end later)
    let t = cr_open(screen, (fix_deliver_ms, 1400.0, 1000.0), on_pixels=true)
    let sent = t.time()
    cr_send(t, cr_sent)
    let gap = sent + fix_deliver_ms + 1400.0 - 50.0 - t.time()
    if gap > 0.0 {
      t.run_for(gap)
    }
    assert_true(cr_line(t), msg="\{screen.0}: the agent's line not shown as the reply comes")
    match ks_page_looks(t, ks_words, 600.0, screen.2) {
      Some(w) => fail("\{screen.0}: \{w}")
      None => ()
    }
    assert_true(t.find(cr_reply) is Some(_), msg="\{screen.0}: the reply not drawn")
  }
}
