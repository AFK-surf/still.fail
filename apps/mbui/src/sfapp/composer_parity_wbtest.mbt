// The chat page's composer as the app draws it (the retained page, app_tree), held to what it did before the page
// moved to the retained tree (2026-11-04, 723b5ba19c): send at the composer's right end and ＋ at its left in every
// shape and every frame between them, and a picture pasted, picked or dropped going into the draft and out with
// Enter or send. The old composer's tests (desk_composer_wbtest.mbt) drive the composer the new chat page still
// builds, not this one.

///|
/// The windows the page is drawn in: a desktop's wide frame, a medium one, a phone's.
let parity_windows : Array[(Double, Double, Int)] = [(1280.0, 800.0, 0), (740.0, 900.0, 0), (390.0, 844.0, 2)]

///|
/// The fixture's chat open in a window `w` by `h`, the page in use: on a medium screen the chat's panel is the one in
/// use only once it is pressed (the sidebar's otherwise, the chat showing its edge).
fn parity_chat(calls : Array[Made], w : Double, h : Double, platform : Int) -> @ui.Tester {
  let t = wide_tester(calls, mode="chat", w~, h~, platform~)
  t.run_for(@ui.move_most_ms)
  if w > 600.0 && w < 840.0 {
    t.tap(w - 24.0, h / 2.0)
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
/// The composer's ＋ and send as drawn now (their marks' centres): send the rightmost arrow, its ＋ the one on its row
/// (the rail has a ＋ and an arrow of its own: a new chat, the update).
fn parity_ends(t : @ui.Tester) -> ((Double, Double), (Double, Double))? {
  let sends = t.locate("icon:arrow-up")
  guard !sends.is_empty() else { return None }
  let send = sends.iter().fold(init=sends[0], fn(a, b) { if b.0 > a.0 { b } else { a } })
  let row = t.locate("icon:plus").filter(fn(p) { (p.1 - send.1).abs() < 40.0 })
  guard !row.is_empty() else { return None }
  Some((row.iter().fold(init=row[0], fn(a, b) { if b.0 > a.0 { b } else { a } }), send))
}

///|
/// Each frame for a motion's longest: send right of ＋ by most of the composer, never at its left.
fn parity_frames(t : @ui.Tester, what : String, w : Double) -> Unit raise {
  let until = t.time() + @ui.move_most_ms
  let mut first = true
  while first || t.time() < until {
    first = false
    match parity_ends(t) {
      Some(((px, _), (sx, _))) =>
        // (the composer is at least half the window wide in each frame; ＋ and send stand at its two ends)
        if sx - px < w * 0.4 {
          fail("\{what} at \{w}: send at \{sx}, ＋ at \{px} (t=\{t.time()})")
        }
      None => fail("\{what} at \{w}: no ＋ or send drawn (t=\{t.time()})")
    }
    t.frame()
  }
}

///|
test "a chat's composer keeps send at its right end and ＋ at its left: let go of, focused, written in, a picture waiting, lines, sent, let go of again" {
  for win in parity_windows {
    let (w, h, platform) = win
    let calls : Array[Made] = []
    let t = parity_chat(calls, w, h, platform)
    parity_frames(t, "let go of", w)
    t.tap_text("发消息")
    parity_frames(t, "focused", w)
    t.type_text("看一下第三项")
    parity_frames(t, "written in", w)
    t.clipboard_gives_png(@pixels.png(2, 2, FixedArray::make(16, b'\xff')))
    t.key(@ui.key_of_char('v'), mods=if platform == 0 { @ui.mod_cmd } else { @ui.mod_ctrl })
    parity_frames(t, "a picture waiting", w)
    ignore(t.key_named("shift+enter"))
    t.type_text("还有签名")
    parity_frames(t, "two lines", w)
    if platform == 0 { t.enter() } else { tap_send(t) }
    parity_frames(t, "sent", w)
    t.key(@ui.key_escape)
    t.tap(w / 2.0, h / 3.0)
    parity_frames(t, "let go of again", w)
  }
}

///|
/// The chat's draft (ws1/st1:s-c1) in the fixture's Willow.
fn parity_draft() -> @sfbase.Writing {
  match @sfbase.writings.get("ws1/st1:s-c1") {
    Some(d) => d
    None => abort("no draft")
  }
}

///|
test "a picture pasted into a chat's composer goes in as a file and goes with Enter, no words with it, on a desktop" {
  for w in [1280.0, 740.0] {
    let calls : Array[Made] = []
    let t = parity_chat(calls, w, 800.0, 0)
    t.tap_text("发消息")
    t.clipboard_gives_png(@pixels.png(2, 2, FixedArray::make(16, b'\xff')))
    t.key(@ui.key_of_char('v'), mods=@ui.mod_cmd)
    t.run_for(@ui.move_most_ms)
    assert_eq(parity_draft().files.get().map(fn(f) { text(Some(f), "name") }), ["image.png"], msg="at \{w}")
    t.enter()
    t.run_for(@ui.move_most_ms)
    let sends = named(calls, "chat.send")
    assert_eq(sends.length(), 1, msg="at \{w}: \{calls.map(fn(c) { c.name })}")
    assert_eq(items(Some(sends[0].params), "attachments").length() + items(Some(sends[0].params), "uploads").length(), 1,
      msg="at \{w}: \{sends[0].params.stringify()}")
    assert_eq(parity_draft().files.get().length(), 0, msg="at \{w}")
  }
}

///|
test "a picture picked with a chat's ＋ goes in as a file and goes with send, on a desktop" {
  for w in [1280.0, 740.0] {
    let calls : Array[Made] = []
    let t = parity_chat(calls, w, 800.0, 0)
    t.picks([("截图.png", @pixels.png(2, 2, FixedArray::make(16, b'\xff')))])
    match parity_ends(t) {
      Some(((x, y), _)) => t.tap(x, y)
      None => fail("at \{w}: no ＋")
    }
    t.run_for(@ui.move_most_ms)
    assert_eq(parity_draft().files.get().map(fn(f) { text(Some(f), "name") }), ["截图.png"], msg="at \{w}")
    tap_send(t)
    t.run_for(@ui.move_most_ms)
    assert_eq(named(calls, "chat.send").length(), 1, msg="at \{w}: \{calls.map(fn(c) { c.name })}")
    assert_eq(parity_draft().files.get().length(), 0, msg="at \{w}")
  }
}

///|
test "a chat's composer says its ＋ and send to the system's accessibility, on a desktop as on a phone" {
  for win in parity_windows {
    let (w, h, platform) = win
    let calls : Array[Made] = []
    let t = parity_chat(calls, w, h, platform)
    for label in [@sf.t("web-main.composer.attach"), @sf.t("web-main.composer.send")] {
      ignore(t.get(Button, label~)) catch {
        e => fail("at \{w}: \{label} not said: \{e}")
      }
    }
  }
}
