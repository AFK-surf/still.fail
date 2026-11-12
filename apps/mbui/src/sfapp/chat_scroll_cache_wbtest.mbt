///|
test "a chat scroll within its visible messages keeps their layout and reports the new place" {
  let t = chat_tester("chat")
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.scroll_to(8)
  t.frame()
  // (row 8 at the top, the list moved off its end with less than a screen above it: the page before is asked and comes
  // in, and the way to the newest fades in, chat_list.mbt chat_short_above; let come to rest before the measured step)
  t.run_for(@ui.move_most_ms * 2.0)
  let start = t.time()
  // First put the list between row boundaries. The measured input moves it only a little farther.
  t.wheel_told(195.0, 400.0, 0.0, 20.0, 0, start + 1.0)
  t.frame_at(start + 16.0)
  t.frame_at(start + 16.0)
  let visible = t.visible()
  let row = t.row(visible.0).unwrap()
  let reading = readings.get("ws1/st1\u{1}s-c1").unwrap()
  let place = reading.top_off
  t.wheel_told(195.0, 400.0, 0.0, 5.0, 0, start + 17.0)
  t.frame_at(start + 32.0)
  let next_visible = t.visible()
  let next_row = t.row(visible.0).unwrap()
  let next_place = reading.top_off
  let perf = t.frame_perf()
  let detail = "visible \{Repr(visible)} -> \{Repr(next_visible)}, row \{Repr(row)} -> \{Repr(next_row)}, reported \{place} -> \{next_place}, perf \{Repr(perf)}, build \{t.built_why()}, paint \{t.painted_why()}"
  assert_eq(next_visible, visible, msg="the measured scroll must keep the same visible rows: \{detail}")
  assert_true(next_row.1 < row.1, msg="the visible message must move: \{detail}")
  assert_true(next_place < place, msg="the chat must report its new reading place: \{detail}")
  assert_eq(perf.laid, 0, msg="existing chat rows should not be laid out for this scroll: \{detail}")
  assert_eq(t.painted_why(), "a list scrolled without changing its rows", msg="the chat must take the scroll-only path: \{detail}")
}

///|
fn chat_scrolled_reference(keep : Bool) -> (Double, Double, String) raise {
  let t = chat_tester("chat")
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.drawn_again(keep)
  t.draw()
  let title = "首页的列表改成按天分组"
  scroll_run_clear(t, title) |> ignore
  let before = t.run_rects(title)[0]
  let visible = t.visible()
  let at = t.time()
  t.wheel_told(195.0, 400.0, 0.0, 5.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  let after = t.run_rects(title)[0]
  assert_eq(t.visible(), visible, msg="the short scroll must keep the same chat rows")
  assert_true(after.1 < before.1, msg="the reference must move with its message: \{Repr(before)} -> \{Repr(after)}")
  t.tap_run(title)
  let opened = match app.nav.top() {
    Chat(r) => r.session
    _ => ""
  }
  t.drawn_again(true)
  (before.1, after.1, opened)
}

///|
test "a scrolled chat reference opens the same chat with or without kept rows" {
  let ordinary = chat_scrolled_reference(false)
  let kept = chat_scrolled_reference(true)
  println("CHAT_SCROLL_REFERENCE ordinary=\{Repr(ordinary)} retained=\{Repr(kept)}")
  assert_eq(ordinary.2, "s-c2", msg="the reference must open its chat after the scroll")
  assert_eq(kept, ordinary, msg="retained rows must move and respond as the ordinary path")
}
