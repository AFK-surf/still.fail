// The player's speeds (speed_menu) dismissed by the hand, Escape or a press beside them, at that input's moment, and
// its speed pressed again as it is let go; the frame after closing nothing more.

///|
fn speeds_open() -> Bool {
  player_views.values().any(fn(v) { v.rates })
}

///|
/// The speed's button, a phone's when `narrow`, else a desktop's, by what it is named.
fn speed_named(narrow : Bool) -> String {
  if narrow {
    "android-misc.drive.player.speed"
  } else {
    "web-pages.drive.player.rate"
  }
}

///|
/// A player (a phone's when `narrow`, else a desktop's), its speeds opened from its speed, dismissed by `how` (as the
/// host hands it on, no frame after it): whether they are open then, as they are dismissed, and once a frame is drawn;
/// the player not left meanwhile (its back not gone to).
fn speeds_dismissed(how : (@ui.Tester) -> Unit, narrow? : Bool = false) -> Array[Bool] raise {
  let backs : Array[Int] = []
  let t = player_tester(narrow, "a.mp4", [], [], backs)
  t.draw()
  t.click(Button, label=speed_named(narrow))
  t.frame()
  let shown = t.find("0.25×") is Some(_)
  let seen = [speeds_open()]
  how(t)
  seen.push(speeds_open())
  assert_eq(backs, [], msg="not left as they are dismissed")
  t.draw()
  seen.push(speeds_open())
  assert_eq(backs, [], msg="not left the frame after")
  assert_true(shown, msg="its speeds shown: \{seen}")
  seen
}

///|
test "a desktop's speeds dismissed by Escape: closed as the key is taken; the frame after closes nothing more" {
  assert_eq(speeds_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false])
}

///|
test "a phone's speeds dismissed by Escape: closed as the key is taken; the frame after closes nothing more" {
  assert_eq(speeds_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }, narrow=true), [true, false, false])
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
/// The speed (a phone's when `narrow`, else a desktop's) pressed again with its speeds open (as the host hands it on),
/// a frame between or not, then Escape at once: whether they are open after it is let go, after Escape, once a frame
/// is drawn; and how often the player was left as Escape is taken and once that frame is drawn (that Escape the
/// second press, with the speeds closed by the first: the player's own Escape where they are gone by then).
fn speed_again_then_escape(frames : Bool, narrow? : Bool = false) -> (Array[Bool], Int, Int) raise {
  let backs : Array[Int] = []
  let t = player_tester(narrow, "a.mp4", [], [], backs)
  if !narrow {
    t.host_says_finger(Some(false))
  }
  t.draw()
  guard t.query(Button, label=speed_named(narrow)) is Some(s) else { fail("no speed") }
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
  let left = backs.length()
  t.draw()
  seen.push(speeds_open())
  (seen, left, backs.length())
}

///|
test "a desktop's speed pressed again with its speeds open, then Escape at once: closed as it is let go, and stays closed, a frame between or none; that Escape the player's own, leaving it" {
  // (the speeds closed by the press, the Escape after it is the second thing done: the player's way back, as the frame
  // after it is built)
  assert_eq(
    (speed_again_then_escape(false), speed_again_then_escape(true)),
    (([false, false, false], 0, 1), ([false, false, false], 0, 1)),
  )
}

///|
test "a phone's speed pressed again with its speeds open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  assert_eq(
    (speed_again_then_escape(false, narrow=true), speed_again_then_escape(true, narrow=true)),
    (([false, false, false], 0, 0), ([false, false, false], 0, 0)),
  )
}
