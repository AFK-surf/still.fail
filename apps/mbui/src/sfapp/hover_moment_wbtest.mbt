// A hover card's delays (@kit.hover_card through sfpages' hover: a station's card under its tag) counted from when the
// pointer came to the trigger or left it, as the host says that was, not from the frame that first saw it there.

///|
/// A mouse's, a chat with no agent yet on 大屏: where its station's tag is in the chat's bar.
fn hover_tag_tester() -> (@ui.Tester, Double, Double) raise {
  let t = decide_core([], "chat-station-tag", wide=true)
  let tag = t.locate("Studio").filter(fn(p) { p.1 < 40.0 })
  guard tag.length() > 0 else { fail("no station's tag") }
  (t, tag[0].0, tag[0].1)
}

///|
/// How far before and after its moment a hover card is looked at.
let hover_around_ms : Double = 20.0

///|
test "a hover card opens hover_open_ms after the pointer came to its trigger, as the host says it came, a frame late or not" {
  let seen : Array[(Double, Bool)] = []
  for late in [0.0, 200.0] {
    let (t, x, y) = hover_tag_tester()
    let came = t.time()
    // (the move handed on now; the first frame `late` after it)
    t.touch_at(1, x, y, came)
    t.advance(late)
    t.frame()
    t.run_for(@sfpages.hover_open_ms - (t.time() - came) - hover_around_ms)
    seen.push((t.time() - came, t.find("机器详情") is Some(_)))
    t.run_for(2.0 * hover_around_ms)
    seen.push((t.time() - came, t.find("机器详情") is Some(_)))
  }
  assert_eq(seen.map(fn(s) { s.1 }), [false, true, false, true], msg="(ms after it came, open): \{seen}")
}

///|
test "a hover card closes hover_close_ms after the pointer left its trigger, as the host says it left, a frame late or not" {
  let seen : Array[(Double, Bool)] = []
  for late in [0.0, 80.0] {
    let (t, x, y) = hover_tag_tester()
    t.move(x, y)
    t.run_for(@sfpages.hover_open_ms * 2.0)
    assert_true(t.find("机器详情") is Some(_), msg="opened")
    let left = t.time()
    t.touch_at(1, 900.0, 400.0, left)
    t.advance(late)
    t.frame()
    t.run_for(@sfpages.hover_close_ms - (t.time() - left) - hover_around_ms / 2.0)
    seen.push((t.time() - left, t.find("机器详情") is Some(_)))
    t.run_for(hover_around_ms + @kit.presence_out_ms)
    seen.push((t.time() - left, t.find("机器详情") is Some(_)))
  }
  assert_eq(seen.map(fn(s) { s.1 }), [true, false, true, false], msg="(ms after it left, open): \{seen}")
}

///|
test "a hover card opens hover_open_ms after the pointer first came to its trigger, moved on it since, the first frame late" {
  // (where it moves on to is the tag's too: resting there opens its card)
  let (t, x, y) = hover_tag_tester()
  t.move(x + 2.0, y)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  assert_true(t.find("机器详情") is Some(_), msg="2 on is the tag's")
  let (t, x, y) = hover_tag_tester()
  let came = t.time()
  let seen : Array[(Double, Bool)] = []
  // (come to the tag, moved on within it 100 ms later, the first frame 200 ms after it came)
  t.touch_at(1, x, y, came)
  t.advance(@sfpages.hover_open_ms / 3.2)
  t.touch_at(1, x + 2.0, y, t.time())
  t.advance(@sfpages.hover_open_ms / 3.2)
  t.frame()
  t.run_for(@sfpages.hover_open_ms - (t.time() - came) - hover_around_ms)
  seen.push((t.time() - came, t.find("机器详情") is Some(_)))
  t.run_for(2.0 * hover_around_ms)
  seen.push((t.time() - came, t.find("机器详情") is Some(_)))
  assert_eq(seen.map(fn(s) { s.1 }), [false, true], msg="(ms after it came, open): \{seen}")
}

///|
test "a hover card waited for, the pointer off its trigger and back between frames: waited for again from when it came back, as with a frame between" {
  let seen : Array[(Double, Bool)] = []
  for framed in [false, true] {
    let (t, x, y) = hover_tag_tester()
    t.touch_at(1, x, y, t.time())
    t.frame()
    t.run_for(@sfpages.hover_open_ms / 2.0)
    t.touch_at(1, 900.0, 400.0, t.time())
    if framed {
      t.frame()
    }
    t.advance(hover_around_ms)
    let back = t.time()
    t.touch_at(1, x, y, back)
    t.frame()
    t.run_for(@sfpages.hover_open_ms - (t.time() - back) - hover_around_ms)
    seen.push((t.time() - back, t.find("机器详情") is Some(_)))
    t.run_for(2.0 * hover_around_ms)
    seen.push((t.time() - back, t.find("机器详情") is Some(_)))
  }
  assert_eq(seen.map(fn(s) { s.1 }), [false, true, false, true], msg="(ms after it came back, open): \{seen}")
}

///|
test "a hover card closes hover_close_ms after the pointer left the window, as the host says it left, the frame late" {
  let (t, x, y) = hover_tag_tester()
  t.move(x, y)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  assert_true(t.find("机器详情") is Some(_), msg="opened")
  let left = t.time()
  // (out of the window: kind 7)
  t.touch_at(7, -1.0, -1.0, left)
  t.advance(@sfpages.hover_close_ms * 2.0 / 3.0)
  t.frame()
  let seen : Array[(Double, Bool)] = []
  t.run_for(@sfpages.hover_close_ms - (t.time() - left) - hover_around_ms / 2.0)
  seen.push((t.time() - left, t.find("机器详情") is Some(_)))
  t.run_for(hover_around_ms + @kit.presence_out_ms)
  seen.push((t.time() - left, t.find("机器详情") is Some(_)))
  assert_eq(seen.map(fn(s) { s.1 }), [true, false], msg="(ms after it left, open): \{seen}")
}

///|
test "a hover card opens hover_open_ms after a press carried onto its trigger is let go, a frame while it is held or none" {
  let seen : Array[(Double, Bool)] = []
  for framed in [false, true] {
    let (t, x, y) = hover_tag_tester()
    // (down beside the bar, carried onto the tag, let go there 100 ms later; the first frame 100 ms after that)
    t.touch_at(0, 900.0, 400.0, t.time())
    t.touch_at(1, x, y, t.time())
    if framed {
      t.frame()
    }
    t.advance(@sfpages.hover_open_ms / 3.2)
    let up = t.time()
    t.touch_at(2, x, y, up)
    t.advance(@sfpages.hover_open_ms / 3.2)
    t.frame()
    t.run_for(@sfpages.hover_open_ms - (t.time() - up) - hover_around_ms)
    seen.push((t.time() - up, t.find("机器详情") is Some(_)))
    t.run_for(2.0 * hover_around_ms)
    seen.push((t.time() - up, t.find("机器详情") is Some(_)))
  }
  assert_eq(seen.map(fn(s) { s.1 }), [false, true, false, true], msg="(ms after it was let go, open): \{seen}")
}
