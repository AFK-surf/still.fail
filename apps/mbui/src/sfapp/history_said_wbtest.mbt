// An agent's history, what an agent and a station wrote in its details at their longest (squeeze_said_wbtest.mbt's
// said_longest): the model that runs it and the station it runs on, each a name and what follows it on a line
// (@sf.name_line_node), the name whole while it may be, what follows it giving way first, never cut to nothing, nothing
// run out of its line (the model's name ran 1500 wide out of the page over the row's mark; the station's 1287 wide out
// of its line, what its machine is cut to nothing after it: 2026-11-11).

///|
/// In `t`, the words starting `name` and those starting `rest` after them on their line, each as Tester::words says
/// it: the name as wide as the line leaves beside what follows it, that no narrower than its least, both in `w` across,
/// a glyph of it at least seen between its dot and its ellipsis, and nothing squeezed of what `made` (a page's file)
/// made. What is wrong, said with `at`; none, "".
fn name_line_wrong(t : @ui.Tester, at : String, name : String, rest : String, w : Double, made : String) -> String {
  let names = t.words().filter(fn(x) { x.0.has_prefix(name) })
  let rests = t.words().filter(fn(x) { x.0.has_prefix(rest) })
  guard names.length() >= 1 && rests.length() >= 1 else { return "\{at}: \{Repr(names)} \{Repr(rests)}" }
  let (n, r) = (names[0], rests[0])
  let seen = t
    .glyphs_seen()
    .filter(fn(g) { (g.0 + g.2) / 2.0 > r.1 && (g.0 + g.2) / 2.0 < r.1 + r.3 && (g.1 + g.3) / 2.0 > r.2 && (g.1 + g.3) / 2.0 < r.2 + r.4 })
  let faults = t.squeeze_faults().filter(fn(f) { f.contains(made) })
  if !(n.3 > 0.0 && n.1 + n.3 <= r.1 + 0.5) {
    "\{at}: the name at \{Repr(n)}, what follows it at \{Repr(r)}"
  } else if !(r.3 >= @sf.name_line_rest_least - 0.5 && r.1 + r.3 <= w + 0.5) {
    "\{at}: what follows the name at \{Repr(r)}, no narrower than \{@sf.name_line_rest_least}"
  } else if seen.length() < 3 {
    "\{at}: of what follows the name, \{seen.length()} glyphs seen (its dot, one at least, its ellipsis): \{Repr(seen)}"
  } else if faults.length() > 0 {
    "\{at}: \{Repr(faults)}"
  } else {
    ""
  }
}

///|
test "the history's details on a phone, the model's name at its longest, at the default size of words and at 1.3: cut short on its line, what follows it still read after it, nothing over the mark at the row's end" {
  guard corner_windows.search_by(w => w.0 == "phone") is Some(i) else { fail("no phone window in corner_windows") }
  let win = corner_windows[i]
  for scale in [1.0, 1.3] {
    let t = screen_in("history-details", win, "zh", said=true, font_scale=scale)
    let wrong = name_line_wrong(t, "phone, words at \{scale}", "Opus 5.5 — ", " · ", win.1, "sfapp/history.mbt")
    assert_eq(wrong, "")
  }
}

///|
test "the station an agent's history runs on, its name at its longest beside a chat: cut short on its line, what its machine is still read after it, nothing cut off by what holds it" {
  for name in ["touch", "desk", "tablet"] {
    guard corner_windows.search_by(w => w.0 == name) is Some(i) else { fail("no \{name} window in corner_windows") }
    let win = corner_windows[i]
    for mode in ["history", "history-details"] {
      let t = screen_in(mode, win, "zh", said=true)
      let wrong = name_line_wrong(t, "\{name} \{mode}", "Willow — ", " · MacBook", win.1, "sfdesk/history.mbt")
      assert_eq(wrong, "")
    }
  }
}
