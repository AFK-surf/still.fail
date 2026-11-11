// The list stays with the sidebar when it changes between its open and floating looks.

///|
test "大屏 on a Mac: pinning and floating the sidebar keep the list at its position at the cause" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", window_corner=16.0, window_inset=true)
  let press_lit = fn() {
    let (x, y, w, h) = t.query(Button, label="对话").unwrap().rect
    t.tap(x + w / 2.0, y + h / 2.0)
  }
  let list_y = fn() { t.rect_of("今天").unwrap().1 }
  // The press starts the move at this same moment; its first frame must still have the list where it was.
  let open = list_y()
  press_lit()
  assert_true(@sfdesk.wide.folded.get() && @sfdesk.wide.peeking.get())
  let floating_start = list_y()
  assert_true((floating_start - open).abs() < 0.5, msg="open \{open}, floating starts \{floating_start}")
  t.run_for(@ui.move_most_ms)
  let floating = list_y()
  press_lit()
  assert_false(@sfdesk.wide.folded.get())
  let open_start = list_y()
  assert_true((open_start - floating).abs() < 0.5, msg="floating \{floating}, open starts \{open_start}")
}

///|
/// The bell, two places and settings, as read out with their full room to press.
fn floating_rail_places(t : @ui.Tester) -> Array[(Double, Double)] {
  ["待处理", "对话", "文件", @sf.t("web-pages.settings.title")].map(fn(label) {
    let (x, y, _, _) = t.query(Button, label~).unwrap().rect
    (x, y)
  })
}

///|
/// The rail at each of the declared moments over the move, including its first frame and its end.
fn floating_rail_trace(t : @ui.Tester) -> Array[Array[(Double, Double)]] {
  let start = t.time()
  let seen = [floating_rail_places(t)]
  for i in 1..=100 {
    t.frame_at(start + i.to_double() * 5.0)
    seen.push(floating_rail_places(t))
  }
  seen
}

///|
/// Each icon stays between its two ends throughout the move, without a detour and snap back.
fn floating_rail_stays_between(seen : Array[Array[(Double, Double)]]) -> Unit raise {
  let first = seen[0]
  let last = seen[seen.length() - 1]
  for frame, places in seen {
    for i, p in places {
      let a = first[i]
      let b = last[i]
      assert_true(
        p.0 >= dmin(a.0, b.0) - 0.75 && p.0 <= dmax(a.0, b.0) + 0.75 &&
        p.1 >= dmin(a.1, b.1) - 0.75 && p.1 <= dmax(a.1, b.1) + 0.75,
        msg="icon \{i}, frame \{frame}: \{Repr(p)}, endpoints \{Repr(a)} and \{Repr(b)}",
      )
    }
  }
}

///|
test "大屏 on a Mac: the bell and rail icons move continuously between open and floating, in both directions" {
  let t = wide_tester([], mode="chat", window_corner=16.0, window_inset=true)
  let press_lit = fn() {
    let (x, y, w, h) = t.query(Button, label="对话").unwrap().rect
    t.tap(x + w / 2.0, y + h / 2.0)
  }
  press_lit()
  assert_true(@sfdesk.wide.folded.get() && @sfdesk.wide.peeking.get())
  floating_rail_stays_between(floating_rail_trace(t))
  press_lit()
  assert_false(@sfdesk.wide.folded.get())
  floating_rail_stays_between(floating_rail_trace(t))
}
