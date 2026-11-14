// A message's link with its row kept as its nodes (mbui's kept_nodes.mbt), built as a host builds (no frame built once
// more keeping none: check_looks(false)): what its build said of it (the pointer's shape over it, a press on it, its
// menu: mbui's Ctx::mark_id) holds while the row is kept, as where it is built.

///|
test "a link in a message left still with a mouse: the hand over it, its right click the link's menu alone" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.check_looks(false)
  t.drawn_again(true)
  let link = "example.com/bench/list"
  // (the chat scrolled till the link is clear of its bar and its composer)
  t.move_to(900.0, 400.0)
  for _ in 0..<12 {
    let dy = match t.run_rects(link) {
      [(_, y, _, h), ..] if y + h / 2.0 > 160.0 && y + h / 2.0 < 600.0 => break
      [(_, y, _, h), ..] if y + h / 2.0 >= 600.0 => 200.0
      _ => -300.0
    }
    t.wheel(900.0, 400.0, dy)
  }
  for _ in 0..<3 {
    t.run_for(kept_rows_still_ms)
  }
  assert_true(t.rows_kept() > 0)
  let (x, y, w, h) = t.run_rects(link)[0]
  t.move_to(x + w / 2.0, y + h / 2.0)
  assert_eq(t.cursor(), Hand)
  t.run_for(kept_rows_still_ms)
  assert_eq(t.cursor(), Hand)
  t.move_to(x + w / 2.0 + 1.0, y + h / 2.0)
  assert_eq(t.cursor(), Hand)
  t.right_click(x + w / 2.0 + 1.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  let came = t.words().map(fn(w) { w.0 })
  assert_true(came.contains("在浏览器中打开链接") && came.contains("复制链接"), msg="\{Repr(came)}")
  assert_true(!came.contains("复制消息") && !came.contains("复制消息链接") && !came.contains("多选"), msg="\{Repr(came)}")
}

///|
/// What chat `mode`, opened `w` by `h` and left still, says of its targets (its `hit` lines, each with what was said of
/// it as it was built: ` marks `) at each of eight moments, built as a host builds, the rows kept (`again`) or built
/// every frame; and how many rows were kept in all.
fn kept_link_hits(mode : String, again : Bool, w : Double, h : Double) -> (Array[Array[String]], Int) {
  let t = kept_rows_open(mode, w, h)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.drawn_again(again)
  t.said() |> ignore
  let out = []
  let mut kept = 0
  for _ in 0..<8 {
    t.run_for(kept_rows_still_ms)
    out.push(t.said().split("\n").filter(fn(l) { l.has_prefix("hit ") }).map(fn(l) { l.to_owned() }).collect())
    kept = kept + t.rows_kept()
  }
  (out, kept)
}

///|
test "the links of a chat left still say, with their rows kept, what they say built every frame" {
  for mode in ["chat-file-links", "chat-long"] {
    for size in [(390.0, 844.0), (720.0, 800.0), (1280.0, 800.0)] {
      let (w, h) = size
      let (kept, rows) = kept_link_hits(mode, true, w, h)
      let (built, _) = kept_link_hits(mode, false, w, h)
      assert_true(rows > 0, msg="\{mode} \{w}x\{h}: no row kept")
      for k in 0..<8 {
        let marked = fn(ls : Array[String]) { ls.filter(fn(l) { l.contains(" marks ") }).length() }
        assert_eq(
          kept[k],
          built[k],
          msg="\{mode} \{w}x\{h} at step \{k}: \{marked(kept[k])} marked kept, \{marked(built[k])} built",
        )
      }
    }
  }
}

///|
test "a link in a message left still on a phone, held by a finger: its menu, no words picked, not followed" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.drawn_again(true)
  let link = "example.com/bench/list"
  scroll_run_clear(t, link) |> ignore
  // (what the scroll set going (the way to the newest coming in over the list) gone its way, the chat left still)
  t.run_for(@ui.move_most_ms)
  for _ in 0..<3 {
    t.run_for(kept_rows_still_ms)
  }
  // (the page built again with its rows kept: the list moved a point by the wheel, no row of it changed; left still
  // nothing builds it, its old pictures there at once, not brushed in over a second as they were)
  t.wheel(195.0, 400.0, -1.0)
  t.run_for(kept_rows_still_ms)
  assert_true(t.rows_kept() > 0)
  let (x, y, w, h) = t.run_rects(link)[0]
  t.press_at(x + w / 2.0, y + h / 2.0)
  t.run_for(long_press_ms)
  t.release(x + w / 2.0, y + h / 2.0)
  assert_eq(t.opened().length(), 0)
  // (its menu, the presenters': a sheet with a finger, in)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  let came = t.words().map(fn(w) { w.0 })
  assert_true(came.contains("打开链接") && came.contains("复制链接"), msg="\{Repr(came)}")
  assert_eq(t.haptics(), [@ui.Haptic::LongPress])
  // (the message's own hold picks its words)
  assert_eq(pk.ts, "")
}
