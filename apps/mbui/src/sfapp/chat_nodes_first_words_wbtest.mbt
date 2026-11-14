// A new chat's first words on 大屏 with the chat's page made as nodes (sfbase's chat_page_nodes): the page becomes
// its chat in the frame they are sent, they in their row over the composer at its foot from that frame, whole in every
// frame after, nothing drawn over them (the composer at the chat's foot as the page becomes it, never going down
// through them: sfpages' composer_laid_here), and the chat's first message over the composer at rest, however late the
// core answers.

///|
/// 大屏 over the fixture's Home, the chat's page made as nodes, the new chat it lands on; where `held` is given, the
/// core's answers to `newChat.create` and `chat.send` kept there (by name: what gives each) and the chat made unread
/// while `unread` says, as a core a round trip away gives them; else the fixture's, at once.
fn first_words_tester(held? : Map[String, () -> Unit], unread? : @signals.Signal[Bool]) -> @ui.Tester {
  new_run()
  @sfbase.chat_page_nodes.set(true)
  let base = fixture("home")
  let src : Source = match (held, unread) {
    (Some(held), Some(unread)) =>
      {
        ..base,
        call: fn(name, params, done) {
          match name {
            "newChat.create" | "chat.send" => (base.call)(name, params, fn(r) { held[name] = fn() { done(r) } })
            _ => (base.call)(name, params, done)
          }
        },
        topic_read: fn(name, params) {
          let got = base.topic(name, params).get().snapshot()
          let made = match params.get("session") {
            Some(String(s)) => s.has_prefix("new:")
            _ => false
          }
          if name == "chat" && made && unread.get() {
            { value: None, error: None, version: 0 }
          } else {
            got
          }
        },
      }
    _ => base
  }
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
}

///|
/// Where words `s` are drawn now, the page's (right of the sidebar): each copy's box, at its ink.
fn first_words_drawn(t : @ui.Tester, s : String) -> Array[(Double, Double, Double, Double, Double)] {
  t.words().filter(fn(w) { w.0 == s && w.1 > @sfdesk.rail_w + 240.0 }).map(fn(w) { (w.1, w.2, w.3, w.4, w.5) })
}

///|
/// Words `s` as this frame draws them: once, at full ink, `size` big where it is given, nothing of glass drawn over
/// any of them (the composer's ground, a bar), over the composer's ground; their box.
fn first_words_whole(
  t : @ui.Tester,
  s : String,
  size? : (Double, Double),
) -> (Double, Double, Double, Double) raise {
  let at = first_words_drawn(t, s)
  guard at.length() > 0 else { fail("「\{s}」 not drawn at \{t.time()}") }
  let (x, y, w, h, ink) = at[0]
  for a in at {
    assert_true((a.0 - x).abs() < 0.5 && (a.1 - y).abs() < 0.5, msg="「\{s}」 drawn twice apart at \{t.time()}: \{Repr(at)}")
  }
  assert_true(ink > 0.99, msg="「\{s}」 at \{ink} of their ink at \{t.time()}")
  match size {
    Some((sw, sh)) =>
      assert_true((w - sw).abs() < 0.5 && (h - sh).abs() < 0.5, msg="「\{s}」 \{Repr((w, h))}, not \{Repr((sw, sh))} at \{t.time()}")
    None => ()
  }
  let over = t.drawn_glass().filter(fn(g) { g.0 < x + w && g.0 + g.2 > x && g.1 < y + h && g.1 + g.3 > y })
  assert_true(over.is_empty(), msg="glass over 「\{s}」 \{Repr((x, y, w, h))} at \{t.time()}: \{Repr(over)}")
  let (_, gy, _, _) = composer_glass(t)
  assert_true(y + h <= gy, msg="「\{s}」 \{Repr((x, y, w, h))} not over the composer at \{gy}, at \{t.time()}")
  (x, y, w, h)
}

///|
/// The new chat's first words `s` typed and sent (Enter), looked at from the frame they are sent through every frame
/// drawn till `till` ms after: whole there, nothing over them, over the composer, where they were put in that frame
/// (nothing after the send moves them). Where they are.
fn first_words_sent(t : @ui.Tester, s : String, till : Double) -> (Double, Double, Double, Double) raise {
  t.frame()
  assert_true(app.nav.top() == NewChat)
  t.tap_text("做任何事")
  t.type_text(s)
  t.draw()
  t.enter()
  t.draw()
  let sent = t.time()
  assert_true(app.nav.top() is Chat(_), msg="not the chat in the frame they are sent")
  let first = first_words_whole(t, s)
  let faults : Array[String] = []
  t.each_frame(
    Some(fn() {
      guard faults.length() < 3 else { return }
      try {
        let now = first_words_whole(t, s, size=(first.2, first.3))
        if (now.0 - first.0).abs() > 0.5 || (now.1 - first.1).abs() > 0.5 {
          faults.push("moved from \{Repr(first)} to \{Repr(now)} at \{t.time()}")
        }
      } catch {
        Failure(m) => faults.push(m)
        _ => faults.push("a fault at \{t.time()}")
      }
    }),
  )
  t.run_shown(sent + till - t.time())
  t.each_frame(None)
  assert_true(faults.is_empty(), msg=faults.join("; "))
  first
}

///|
test "大屏, the chat's page made as nodes, a new chat's first words with the core answering at once: over the composer at the chat's foot in their row from the frame they are sent, whole in every frame, nothing over them; the chat's first message there at rest" {
  let t = first_words_tester()
  let words = "把发布说明写一下"
  // (till the new chat's scene has left and the composer is at rest: the core's answers come at once, an agent's line
  // after them its own cause)
  let at = first_words_sent(t, words, new_leave_ms + @ui.move_most_ms)
  let (_, gy, _, gh) = composer_glass(t)
  assert_true(gy + gh > 800.0 - 30.0, msg="the composer not at the chat's foot: \{Repr((gy, gh))}")
  assert_true(gy - (at.1 + at.3) < 120.0, msg="the words not just over the composer: \{Repr(at)}, \{gy}")
  assert_true(made_by_nodes(t, words), msg="not the new page's message: \{t.sources_of(words)}")
}

///|
test "大屏, the chat's page made as nodes, a new chat's first words with the core answering late: over the composer at the chat's foot in their row from the frame they are sent, whole in every frame, nothing over them, staying there as the core answers" {
  let held : Map[String, () -> Unit] = Map([])
  let unread = @signals.signal(true)
  let t = first_words_tester(held~, unread~)
  let words = "把发布说明写一下"
  // (400 ms of nothing answered)
  let at = first_words_sent(t, words, 400.0)
  for name in ["newChat.create", "chat.send"] {
    match held.get(name) {
      Some(give) => give()
      None => fail("\{name} not asked")
    }
    t.draw()
    let now = first_words_whole(t, words, size=(at.2, at.3))
    assert_true((now.0 - at.0).abs() < 0.5 && (now.1 - at.1).abs() < 0.5, msg="moved as \{name} answered: \{Repr(now)}")
  }
  unread.set(false)
  t.draw()
  let now = first_words_whole(t, words, size=(at.2, at.3))
  assert_true((now.0 - at.0).abs() < 0.5 && (now.1 - at.1).abs() < 0.5, msg="moved as the chat was read: \{Repr(now)}")
  let (_, gy, _, gh) = composer_glass(t)
  assert_true(gy + gh > 800.0 - 30.0, msg="the composer not at the chat's foot: \{Repr((gy, gh))}")
  assert_true(made_by_nodes(t, words), msg="not the new page's message: \{t.sources_of(words)}")
}
