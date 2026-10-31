// The composer's 抄送 menu (sfpages' cc_chooser: the chat's Slack and Feishu threads to copy to) dismissed by the hand:
// Escape, a press on the page, at that input's moment; 抄送 pressed again with it open, then Escape at once, closed and
// staying closed.

///|
/// A mouse's, a chat's composer whose agents are in a Slack thread and a Feishu one (none ticked).
fn cc_tester(calls? : Array[Made] = []) -> @ui.Tester {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let t = @ui.Tester::new(
    fn(c) {
      @sf.set_words(fill)
      let _ = @sf.begin(c)
      let ws : Workspace = { id: "ws1", name: "Acme", emoji: "", icon: "", email: "" }
      let v = chat_view_made({
        "title": "整理发布清单",
        "thread": { "id": 7 },
        "cc": [
          { "thread": 21, "place": "#still-fail", "via": "slack", "on": false },
          { "thread": 22, "place": "产品讨论", "via": "feishu", "on": false },
        ],
      })
      @sfpages.chat_composer(c, src, ws, r, Some(v))
      @sf.presented(c)
    },
    w=900.0,
    h=500.0,
    pointing=Mouse,
  )
  t.draw()
  t
}

///|
/// Its menu opened from 抄送, dismissed by `how` (as the host hands it on, no frame after it): whether it is open then,
/// as it is dismissed, once a frame is drawn, as 抄送 opens it again and a frame after.
fn cc_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] raise {
  let t = cc_tester()
  let cc = @sf.t("web-main.composer.ccLabel")
  guard t.query(Button, label=cc) is Some(s) else { fail("no 抄送") }
  let (x, y) = (s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
  let open = fn() { @sfpages.composer_cc_open() }
  t.tap(x, y)
  t.frame()
  let shown = t.find("产品讨论") is Some(_)
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
  assert_true(shown, msg="its threads shown: \{seen}")
  seen
}

///|
test "抄送's menu dismissed by Escape: closed as the key is taken; the frame after closes nothing more, opened again its own" {
  assert_eq(cc_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false, true, true])
}

///|
test "抄送's menu dismissed by a press on the page: closed as it goes down; the frame after closes nothing more, opened again its own" {
  let down : Array[Bool] = []
  let seen = cc_dismissed(fn(t) {
    t.touch_at(0, 450.0, 60.0, t.time())
    down.push(@sfpages.composer_cc_open())
    t.touch_at(2, 450.0, 60.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false, true, true]))
}

///|
test "抄送 pressed again with its menu open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  let run = fn(frames : Bool) raise {
    let t = cc_tester()
    // (its words as the tester's build set them)
    button_then_escape(t, @sf.t("web-main.composer.ccLabel"), fn() { @sfpages.composer_cc_open() }, frames)
  }
  assert_eq((run(false), run(true)), ([false, false, false], [false, false, false]))
}

///|
/// One of the two threads ticked (as the host hands the press on), then Escape at once, a frame between or not: whether
/// the menu is open as Escape is taken and once a frame is drawn, and what was asked of the core.
fn cc_ticked_then_escape(frames : Bool) -> (Array[Bool], Array[Json]) raise {
  let calls : Array[Made] = []
  let t = cc_tester(calls~)
  t.host_says_finger(Some(false))
  t.draw()
  t.click(Button, label=@sf.t("web-main.composer.ccLabel"))
  t.frame()
  assert_true(@sfpages.composer_cc_open(), msg="opened")
  guard t.query(MenuItemCheckbox, label="#still-fail") is Some(s) else { fail("no #still-fail") }
  let (x, y) = (s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
  t.touch_at(0, x, y, t.time())
  t.touch_at(2, x, y, t.time())
  if frames {
    t.frame()
  }
  t.key_told(@ui.key_escape, 0, t.time())
  let seen = [@sfpages.composer_cc_open()]
  t.draw()
  seen.push(@sfpages.composer_cc_open())
  (seen, calls.filter(fn(m) { m.name == "chat.cc" }).map(fn(m) { m.params }))
}

///|
test "one of 抄送's two threads ticked, then Escape at once: the tick asked once, the menu closed and staying closed, a frame between or none" {
  let asked : Json = { "station": "ws1/st1", "thread": 7, "to": 21, "on": true }
  assert_eq(
    (cc_ticked_then_escape(false), cc_ticked_then_escape(true)),
    (([false, false], [asked]), ([false, false], [asked])),
  )
}
