///|
test "a test finds words as a scripted run does, reads and pastes into the focused field, presses keys by name" {
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      c.text("Send it", wrap=false) |> ignore
      c.text("Send", wrap=false) |> ignore
      c.editor("field", placeholder="words") |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(t.locate("Send").length(), 2)
  assert_eq(t.locate("=Send").length(), 1)
  assert_eq(t.locate("nowhere"), [])
  assert_eq(t.size(), (390.0, 844.0))
  assert_eq(t.field_words(), "")
  t.tap_text("words")
  t.paste("pasted words")
  assert_eq(t.field_words(), "pasted words")
  assert_true(t.key_named("shift+enter"))
  assert_true(t.key_named("cmd+a"))
  assert_false(t.key_named("hyper+q"))
}

///|
test "a test sees the notifications the app shows, and taps one: what it opens is the app's, once" {
  let shown = Ref(false)
  let opened : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    if !shown.val {
      shown.val = true
      @ui.notice_show(channel="chats", tag="c1", title="Ana", body="the build is green", opens="chat:c1")
      @ui.notice_show(channel="chats", tag="c2", title="Lin", body="a question", opens="chat:c2")
      // the same tag again: the one before replaced
      @ui.notice_show(channel="chats", tag="c2", title="Lin", body="two questions", opens="chat:c2")
    }
    let o = @ui.notice_opened()
    if o != "" {
      opened.push(o)
    }
    c.text("app", wrap=false) |> ignore
  })
  t.draw()
  assert_eq(t.notices().map(fn(n) { n.body }), ["the build is green", "two questions"])
  assert_true(t.tap_notice("green"))
  assert_eq(opened, ["chat:c1"])
  assert_eq(t.notices().length(), 1)
  assert_false(t.tap_notice("green"))
  @ui.notice_cancel("c2")
  assert_eq(t.notices(), [])
}

///|
test "idle but for what never ends while shown: a cycle read is said, not a failure; a field cleared" {
  let spin = Ref(true)
  let t = @ui.Tester::new(fn(c) {
    if spin.val {
      // (a declared period, a spinner's)
      let turn_ms = 1000.0
      ignore(c.cycle(turn_ms))
    }
    c.editor("field", placeholder="words") |> ignore
  })
  t.draw()
  t.assert_idle()
  assert_eq(t.cycles().length(), 1)
  assert_true(t.cycles()[0].has_prefix("1000 ms by "))
  spin.val = false
  t.draw()
  t.assert_idle()
  assert_eq(t.cycles(), [])
  t.tap_text("words")
  t.type_text("some words")
  assert_eq(t.field_words(), "some words")
  t.clear()
  assert_eq(t.field_words(), "")
}

///|
/// A box whose words are placed by where they were last laid out: `step` px further in each frame (`step` 0: placed
/// once by them, then where they are).
fn reading_back(step : Double) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      let x = match c.words_of("w") {
        Some(w) if w.pieces.length() > 0 => if step > 0.0 { w.pieces[0].x + step } else { 20.0 }
        _ => 0.0
      }
      c.box(padx=x, fn() {
        let b = c.column(w=Px(100.0), fn() { c.rich([@ui.plain("hello")], size=10.0) |> ignore })
        c.words(b, "w")
      })
      |> ignore
    },
    w=300.0,
    h=100.0,
  )
}

///|
test "draw: a layout read back that moves once is placed again at the same moment, and then is still" {
  let t = reading_back(0.0)
  let at = t.time()
  t.draw()
  assert_eq(t.time(), at)
  assert_eq(t.ctx().words_of("w").unwrap().pieces[0].x, 20.0)
  t.assert_idle()
}

///|
test "panic draw: a layout read back that moves at every frame does not converge, and says whose" {
  let t = reading_back(1.0)
  t.draw()
}

///|
test "the system's pickers are the test's: what it said they give, from the frame after the ask; called off, none" {
  let got : Array[String] = []
  let ask : Ref[@ui.Pick?] = Ref(None)
  let asked = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    if asked.val && ask.val is None {
      ask.val = @ui.pick(Files)
    }
    match ask.val {
      Some(p) =>
        match p.files() {
          Some(fs) => {
            for f in fs {
              got.push(f.name + ":" + f.bytes.length().to_string())
            }
            ask.val = None
            asked.val = false
          }
          None => ()
        }
      None => ()
    }
    c.text("files", wrap=false) |> ignore
  })
  t.picks([("photo.jpg", b"abcd"), ("notes.txt", b"hi")])
  asked.val = true
  t.draw()
  assert_eq(got, ["photo.jpg:4", "notes.txt:2"])
  assert_eq(t.pick_asks().length(), 1)
  assert_true(t.pick_asks()[0] == Files)
  // called off: nothing given
  t.picks([])
  asked.val = true
  t.draw()
  assert_eq(got.length(), 2)
  assert_true(ask.val is None)
  t.assert_idle()
}

///|
test "what the app keeps on the device is the test's to read: its name, kind and bytes, kept from the frame after" {
  let keep : Ref[@ui.Keep?] = Ref(None)
  let states : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    match keep.val {
      Some(k) =>
        match k.kept() {
          KeptAt(w) => {
            states.push(w)
            k.end()
            keep.val = None
          }
          Keeping => states.push("keeping")
          _ => states.push("failed")
        }
      None => ()
    }
    c.text("keep", wrap=false) |> ignore
  })
  match @ui.keep_begin("report.pdf", "application/pdf") {
    Some(k) => {
      assert_true(k.append(b"%PDF"))
      assert_true(k.append(b"-1.7"))
      k.finish()
      keep.val = Some(k)
    }
    None => fail("a Tester keeps files")
  }
  t.draw()
  assert_eq(states, ["Download/report.pdf"])
  assert_eq(t.kept().map(fn(k) { (k.0, k.1, k.2.length()) }), [("report.pdf", "application/pdf", 8)])
  t.assert_idle()
}

///|
test "what moves says what it is and who told it; a test runs to it by its name" {
  let to = Ref(0.0)
  let t = @ui.Tester::new(fn(c) {
    let x = c.spring("knob", to.val)
    c.box(w=Px(10.0), h=Px(10.0), tx=x, fn() {  }) |> ignore
  })
  t.draw()
  assert_eq(t.moving(), [])
  to.val = 100.0
  t.draw()
  let m = t.moving()
  assert_eq(m.length(), 1)
  assert_true(m[0].contains("c.spring \"knob\" to 100"))
  assert_true(m[0].contains("told at src/ui/ctx.mbt") || m[0].contains("tester_api_test.mbt"))
  let rest = t.rest_of("\"knob\"")
  assert_true(rest > t.time() && rest < @double.infinity)
  t.run_for(rest - t.time())
  assert_eq(t.moving(), [])
  assert_eq(t.rest_of("\"knob\""), -1.0)
  t.assert_idle()
}

///|
test "a scripted run waits for a picture decoded by its name, and a frame drawn after it" {
  // (shown once the run has begun: what it waits for ends after its step begins)
  let shown = Ref::new(false)
  let t = @ui.Tester::new(
    fn(c) {
      if shown.val {
        c.image("e2e-photo.jpg", w=Px(100.0), h=Px(100.0)) |> ignore
      }
    },
    images=[("e2e-photo.jpg", 400, 300)],
  )
  shown.val = true
  let log = t.drive("decoded e2e-photo.jpg\nexit")
  assert_true(log.iter().any(fn(l) { l.has_prefix("DRIVE ok decoded e2e-photo.jpg") }), msg=log.join("\n"))
  assert_true(log.iter().any(fn(l) { l.contains("DRIVE PASS") }), msg=log.join("\n"))
  // what has ended is asked by its name
  let rt = @ui.runtime()
  assert_true(rt.outside_ended_since(0).iter().any(fn(w) { w.has_suffix("e2e-photo.jpg") }))
}

///|
test "a scripted run waits for a picture decoded from bytes handed over for it, by its name" {
  // (the bytes as a core's answer brings them: a key of the app's, under which the node shows them)
  let shown = Ref::new(false)
  let t = @ui.Tester::new(fn(c) {
    if shown.val {
      c.image_bytes("core:files/e2e-photo.jpg", b"\xFF\xD8\xFF\xE0 not a whole JPEG")
      c.image("core:files/e2e-photo.jpg", w=Px(100.0), h=Px(100.0)) |> ignore
    }
  })
  shown.val = true
  let log = t.drive("decoded e2e-photo.jpg\nexit")
  assert_true(log.iter().any(fn(l) { l.has_prefix("DRIVE ok decoded e2e-photo.jpg") }), msg=log.join("\n"))
  let rt = @ui.runtime()
  assert_true(
    rt.outside_ended_since(0).iter().any(fn(w) { w.contains("bytes) core:files/e2e-photo.jpg") }),
    msg=rt.outside_ended_since(0).join("; "),
  )
}

///|
test "a scripted run tells each line of its script as it begins, as written" {
  let t = @ui.Tester::new(fn(c) { c.text("go", wrap=false) |> ignore })
  let told : Array[String] = []
  @ui.trace_steps(fn(step) { told.push(step) })
  let log = t.drive("# a note\nuntil go\nnow wait 50\ntap go\nexit")
  @ui.trace_steps(fn(_) {  })
  assert_eq(told, ["# a note", "until go", "now wait 50", "tap go", "exit"], msg=log.join("\n"))
}

///|
test "a scripted run that waits for a call never answered fails within its timeout, saying what is awaited" {
  let t = @ui.Tester::new(fn(c) { c.text("page", wrap=false) |> ignore })
  let log = t.drive("timeout 200\nanswered drive.read\nexit")
  assert_true(log.iter().any(fn(l) { l.contains("DRIVE FAIL") }), msg=log.join("\n"))
}

///|
test "a scripted run finds what it waits for however many others end before it looks (300 pictures in one frame)" {
  let srcs = Array::makei(300, fn(k) { "p\{k}.jpg" })
  let shown = Ref::new(false)
  let t = @ui.Tester::new(
    fn(c) {
      if shown.val {
        c.column(fn() {
          for s in srcs {
            c.image(s, w=Px(2.0), h=Px(2.0)) |> ignore
          }
        })
        |> ignore
      }
    },
    images=srcs.map(fn(s) { (s, 40, 30) }),
  )
  shown.val = true
  let log = t.drive("decoded p0.jpg\nexit")
  assert_true(log.iter().any(fn(l) { l.has_prefix("DRIVE ok decoded p0.jpg") }), msg=log.join("\n"))
}

///|
test "what comes again every so often while shown (a run's time each second) is said, and idle is not broken by it" {
  let second = 1000.0
  let t = @ui.Tester::new(fn(c) {
    let n = c.every(second)
    c.text("\{n} s", wrap=false) |> ignore
  })
  t.draw()
  let at = t.time()
  let n0 = (at / second).floor().to_int()
  assert_true(t.find("\{n0} s") is Some(_))
  t.run_for(second)
  assert_true(t.find("\{n0 + 1} s") is Some(_))
  assert_eq(t.periodic().length(), 1)
  assert_true(t.periodic()[0].has_prefix("every 1000 ms by "))
  t.assert_idle()
}

///|
test "the system's say on notifications is the test's: refused, the app's ask answered no; never answered, nothing" {
  let asked = Ref(false)
  let answers : Array[Bool] = []
  let t = @ui.Tester::new(fn(c) {
    if asked.val && @ui.notice_permission() == "ask" {
      asked.val = false
      ignore(@ui.notice_ask())
    }
    match @ui.notice_answer() {
      Some(a) => answers.push(a)
      None => ()
    }
    c.text(@ui.notice_permission(), wrap=false) |> ignore
  })
  t.draw()
  assert_true(t.find("granted") is Some(_))
  t.set_notice_permission("ask")
  t.set_notice_reply(Some(false))
  asked.val = true
  t.draw()
  assert_eq(t.notice_asks(), 1)
  assert_eq(answers, [false])
  assert_true(t.find("denied") is Some(_))
  // asked again, left unanswered: no answer comes
  t.set_notice_permission("ask")
  t.set_notice_reply(None)
  asked.val = true
  t.draw()
  assert_eq(t.notice_asks(), 2)
  assert_eq(answers, [false])
  t.assert_idle()
  // a host that cannot tell (macOS, Windows, the web: "unknown") has no way to ask: nothing asked, no answer
  t.set_notice_permission("unknown")
  t.set_notice_reply(Some(true))
  t.draw()
  assert_eq(@ui.notice_ask(), false)
  t.draw()
  assert_eq(t.notice_asks(), 2)
  assert_eq(answers, [false])
  assert_true(t.find("unknown") is Some(_))
}

///|
test "how a node is drawn over its layout: its scale and opacity, with what holds it" {
  let shrink = Ref::new(1.0)
  let down = Ref::new(1.0)
  let t = @ui.Tester::new(fn(c) {
    let card = c.box(w=Px(200.0), h=Px(80.0), id=c.id("card"), fn() { c.text("a card", wrap=false) |> ignore })
    c.look(card, @ui.look(scale=shrink.val, sy=down.val * shrink.val, alpha=0.5))
  })
  assert_eq(t.look_of("card"), Some((1.0, 1.0, 0.5)))
  shrink.val = 0.9
  t.draw()
  // the card's, and its words' (held by it)
  assert_eq(t.look_of("card"), Some((0.9, 0.9, 0.5)))
  assert_eq(t.look_of("a card"), Some((0.9, 0.9, 0.5)))
  // shrunk down only: across as it was
  shrink.val = 1.0
  down.val = 0.85
  t.draw()
  assert_eq(t.look_of("card"), Some((1.0, 0.85, 0.5)))
  assert_eq(t.look_of("nothing of that name"), None)
}

///|
test "how a node is drawn, the text node whose words are exactly these (=WORDS): not the first that holds them" {
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      c.text("sent: grey 083209", wrap=false) |> ignore
      let opt = c.box(fn() { c.text("grey 083209", wrap=false) |> ignore })
      c.look(opt, @ui.look(scale=0.9))
    })
    |> ignore
  })
  assert_eq(t.look_of("grey 083209"), Some((1.0, 1.0, 1.0)))
  assert_eq(t.look_of("=grey 083209"), Some((0.9, 0.9, 1.0)))
  assert_eq(t.look_of("=grey"), None)
}

///|
test "a motion going on owes no frame at a moment: draw draws one, run_for draws it on as its time goes" {
  let go = Ref::new(false)
  let t = @ui.Tester::new(fn(c) {
    let x = c.spring("knob-x", if go.val { 100.0 } else { 0.0 })
    c.box(w=Px(10.0), h=Px(10.0), tx=x, fn() {  }) |> ignore
  })
  go.val = true
  t.draw()
  let rest = t.rest_of("\"knob-x\"")
  assert_true(rest > t.time() && rest < @double.infinity)
  // half way: one frame at a moment, though it moves
  t.run_for(((rest - t.time()) / 2.0).floor())
  let before = t.frames
  t.draw()
  assert_eq(t.frames - before, 1)
  t.run_for(rest - t.time())
  t.assert_idle()
}

