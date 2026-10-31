// A request's 本对话内 (the library's chooser: how long what is allowed lasts, vault_ask.mbt) dismissed by the hand:
// Escape, a press on the page, at that input's moment; pressed again with its menu open, then Escape at once, closed
// and staying closed.

///|
/// A mouse's, a request to use GitHub token in its chat, its card in place of its post.
fn scope_tester() -> @ui.Tester {
  new_run()
  let src = vault_src(["r1"], true, [])
  let t = @ui.Tester::new(fn(c) { ask_card(c, src) }, w=900.0, h=700.0, platform=0, pointing=Mouse)
  t.draw()
  t
}

///|
/// Its menu opened from 本对话内, dismissed by `how` (as the host hands it on, no frame after it): whether it is open
/// then, as it is dismissed, once a frame is drawn, as 本对话内 opens it again and a frame after.
fn scope_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] raise {
  let t = scope_tester()
  guard t.query(Button, label="本对话内") is Some(s) else { fail("no 本对话内") }
  let (x, y) = (s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
  let open = fn() { @settings.vault_menu_open() != "" }
  t.tap(x, y)
  t.frame()
  let shown = t.find("仅这一次") is Some(_)
  let seen = [open()]
  how(t)
  seen.push(open())
  t.draw()
  seen.push(open())
  t.tap(x, y)
  t.frame()
  seen.push(open())
  t.draw()
  seen.push(open())
  assert_true(shown, msg="its lengths shown: \{seen}")
  seen
}

///|
test "a request's length menu dismissed by Escape: closed as the key is taken; the frame after closes nothing more, opened again its own" {
  assert_eq(scope_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false, true, true])
}

///|
test "a request's length menu dismissed by a press on the page: closed as it goes down; the frame after closes nothing more, opened again its own" {
  let down : Array[Bool] = []
  let seen = scope_dismissed(fn(t) {
    t.touch_at(0, 880.0, 680.0, t.time())
    down.push(@settings.vault_menu_open() != "")
    t.touch_at(2, 880.0, 680.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false, true, true]))
}

///|
test "a request's 本对话内 pressed again with its menu open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  let run = fn(frames : Bool) raise {
    button_then_escape(scope_tester(), "本对话内", fn() { @settings.vault_menu_open() != "" }, frames)
  }
  assert_eq((run(false), run(true)), ([false, false, false], [false, false, false]))
}
