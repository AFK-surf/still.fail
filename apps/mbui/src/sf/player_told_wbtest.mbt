// The player's speeds (speed_menu) dismissed by the hand, Escape or a press beside them, at that input's moment, and
// its speed pressed again as it is let go; the frame after closing nothing more.

///|
fn speeds_open() -> Bool {
  player_views.values().any(fn(v) { v.rates })
}

///|
/// A desktop's player, its speeds opened from 1×, dismissed by `how` (as the host hands it on, no frame after it):
/// whether they are open then, as they are dismissed, and once a frame is drawn.
fn speeds_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] raise {
  let t = player_tester(false, "a.mp4", [], [], [])
  t.draw()
  t.tap_text("1×")
  t.frame()
  let shown = t.find("0.25×") is Some(_)
  let seen = [speeds_open()]
  how(t)
  seen.push(speeds_open())
  t.draw()
  seen.push(speeds_open())
  assert_true(shown, msg="its speeds shown: \{seen}")
  seen
}

///|
test "a desktop's speeds dismissed by Escape: closed as the key is taken; the frame after closes nothing more" {
  assert_eq(speeds_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false])
}

///|
test "a desktop's speeds dismissed by a press beside them: closed as it goes down; the frame after closes nothing more" {
  let down : Array[Bool] = []
  let seen = speeds_dismissed(fn(t) {
    t.touch_at(0, 640.0, 200.0, t.time())
    down.push(speeds_open())
    t.touch_at(2, 640.0, 200.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false]))
}

///|
/// The speed pressed again with its speeds open (as the host hands it on), a frame between or not, then Escape at
/// once: whether they are open after it is let go, after Escape, once a frame is drawn.
fn speed_again_then_escape(frames : Bool) -> Array[Bool] raise {
  let t = player_tester(false, "a.mp4", [], [], [])
  t.host_says_finger(Some(false))
  t.draw()
  guard t.query(Button, label="web-pages.drive.player.rate") is Some(s) else { fail("no speed") }
  let (x, y) = (s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
  t.tap(x, y)
  t.frame()
  assert_true(speeds_open(), msg="opened")
  t.touch_at(0, x, y, t.time())
  t.touch_at(2, x, y, t.time())
  let seen = [speeds_open()]
  if frames {
    t.frame()
  }
  t.key_told(@ui.key_escape, 0, t.time())
  seen.push(speeds_open())
  t.draw()
  seen.push(speeds_open())
  seen
}

///|
test "a desktop's speed pressed again with its speeds open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  assert_eq((speed_again_then_escape(false), speed_again_then_escape(true)), ([false, false, false], [false, false, false]))
}
