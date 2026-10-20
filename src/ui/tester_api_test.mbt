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
test "draw: a layout read back that moves once is placed again in the frame that takes it, and then is still" {
  let t = reading_back(0.0)
  // (the display's next frame: built again in it, no frame owed after)
  let at = t.next_frame_time()
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
test "a scripted run tells each line of its script as it begins, as written, and a line that acts as it does" {
  let t = @ui.Tester::new(fn(c) { c.text("go", wrap=false) |> ignore })
  let told : Array[String] = []
  @ui.trace_steps(fn(step, moment) { told.push((if moment == @ui.Acted { "acted " } else { "" }) + step) })
  let log = t.drive("# a note\nuntil go\nnow wait 50\ntap go\nexit")
  @ui.trace_steps(fn(_, _) {  })
  assert_eq(told, ["# a note", "until go", "now wait 50", "tap go", "acted tap go", "exit"], msg=log.join("\n"))
}

///|
test "a tap's input told as handed over: after the frames it waits for its words to hold still, in the frame it goes" {
  // the words come down for a while (a sheet rising), then hold: the tap begins as they show, acts once they hold
  let y = Ref::new(200.0)
  let clicked_at = Ref::new(-1.0)
  let t = @ui.Tester::new(fn(c) {
    let id = c.id("go")
    if c.clicked(id) && clicked_at.val < 0.0 {
      clicked_at.val = c.now()
    }
    c.box(fn() {
      c.box(h=Px(y.val), fn() {  }) |> ignore
      c.box(id~, fn() { c.text("go", wrap=false) |> ignore }) |> ignore
    })
    |> ignore
    if y.val > 100.0 {
      y.val = y.val - 25.0
      c.request_frame()
    }
  })
  let began = Ref::new(-1.0)
  let acted = Ref::new(-1.0)
  @ui.trace_steps(fn(step, moment) {
    if step == "tap go" {
      match moment {
        @ui.Began => began.val = t.time()
        @ui.Acted => acted.val = t.time()
      }
    }
  })
  let log = t.drive("tap go\nexit")
  @ui.trace_steps(fn(_, _) {  })
  assert_true(began.val >= 0.0 && acted.val > began.val, msg="began \{began.val}, acted \{acted.val}\n" + log.join("\n"))
  // handed over in the frame it was told (the drive's turn after that frame was drawn): the app takes it in the
  // display's next frame (the grid's next after `acted`, a frame on)
  assert_eq(clicked_at.val, t.display_frame(acted.val + t.frame_period() / 2.0), msg="acted \{acted.val}")
  let tap = log.search_by(fn(l) { l.has_prefix("DRIVE tap go at") }).unwrap()
  assert_true(tap >= 0)
}

///|
test "a scripted run's answered lines each wait for an answer of their own: two lines, two answers" {
  // the core answers x.get once in the second frame and again in the fortieth
  let frames = Ref::new(0)
  let t = @ui.Tester::new(fn(c) {
    frames.val += 1
    if frames.val == 2 || frames.val == 40 {
      let rt = @ui.runtime()
      rt.outside_end(rt.outside_start("core: x.get (call \{frames.val})"))
      @ui.log("answered at \{frames.val}")
    }
    c.text("page", wrap=false) |> ignore
  })
  let log = t.drive("answered x.get\nanswered x.get\nexit")
  let at = fn(p : String) { log.search_by(fn(l) { l.has_prefix(p) }).unwrap_or(-1) }
  let oks = log.iter().filter(fn(l) { l.has_prefix("DRIVE ok answered x.get") }).count()
  assert_eq(oks, 2, msg=log.join("\n"))
  // the second line passed once the second answer came, not on the first again
  let second = log.mapi(fn(i, l) { (i, l) }).filter(fn(p) { p.1.has_prefix("DRIVE ok answered x.get") })[1].0
  assert_true(at("answered at 40") >= 0 && at("answered at 40") < second, msg=log.join("\n"))
}

///|
test "a scripted run's answered line takes an answer come before the step that acted ahead of it" {
  // the core answers x.get in the run's first frame (the Tester's second), before the tap the line comes after acts
  // (once its words hold still, a frame on)
  let frames = Ref::new(0)
  let t = @ui.Tester::new(fn(c) {
    frames.val += 1
    if frames.val == 2 {
      let rt = @ui.runtime()
      rt.outside_end(rt.outside_start("core: x.get (call 1)"))
    }
    c.text("page", wrap=false) |> ignore
  })
  let log = t.drive("timeout 500\ntap page\nanswered x.get\nexit")
  // (the answer came before the tap)
  let tap = log.search_by(fn(l) { l.has_prefix("DRIVE tap page") }).unwrap()
  assert_true(frames.val > 2 && tap >= 0, msg=log.join("\n"))
  assert_true(log.iter().any(fn(l) { l.has_prefix("DRIVE ok answered x.get") }), msg=log.join("\n"))
  assert_true(log.iter().any(fn(l) { l.contains("DRIVE PASS") }), msg=log.join("\n"))
}

///|
test "a scripted run taps words only where a finger reaches them: not under what lies over them" {
  // a row's words under a bar over the page's foot (a composer): tapped only once the bar has gone from over them
  let covered = Ref::new(true)
  let tapped = Ref::new(0)
  let t = @ui.Tester::new(
    fn(c) {
      let row = c.id("row")
      if c.clicked(row) {
        tapped.val += 1
      }
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(h=Px(80.0), fn() {  }) |> ignore
        c.box(id=row, h=Px(20.0), fn() { c.text("忽略", wrap=false) |> ignore }) |> ignore
        if covered.val {
          c.layer(fn() {
            c.box(h=Px(60.0), fn() {  }) |> ignore
            c.box(id=c.id("bar"), w=Fill(1.0), h=Px(60.0), bg=0xFFFFFFFFL, fn() {  }) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    },
    w=200.0,
    h=200.0,
  )
  let log = t.drive("timeout 300\ntap =忽略\nexit")
  assert_eq(tapped.val, 0)
  assert_true(log.iter().any(fn(l) { l.contains("under something else to press") }), msg=log.join("\n"))
  covered.val = false
  let log2 = t.drive("timeout 300\ntap =忽略\nexit")
  assert_eq(tapped.val, 1, msg=log2.join("\n"))
}

///|
test "a box built where a box placed by its size was the frame before is where it is laid out, not placed the same" {
  // the first frame: a menu's box placed by its size (at 50, 60); the next: a plain box built in its slot
  let menu = Ref::new(true)
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        if menu.val {
          let i = c.box(id=c.id("menu"), w=Px(40.0), h=Px(20.0), fn() {  })
          c.place_by_size(i, fn(_, _) { (50.0, 60.0) })
        } else {
          c.box(id=c.id("plain"), w=Px(40.0), h=Px(20.0), fn() {  }) |> ignore
        }
      })
      |> ignore
    },
    w=200.0,
    h=200.0,
  )
  let (mx, my, _, _) = t.ctx().rect_of(t.ctx().id("menu")).unwrap()
  assert_eq((mx, my), (50.0, 60.0))
  menu.val = false
  t.frame()
  let (px, py, _, _) = t.ctx().rect_of(t.ctx().id("plain")).unwrap()
  assert_eq((px, py), (0.0, 0.0))
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


///|
test "set_frame_times: every frame at the times given (an input's, run_for's, draw's), then on the period from the last" {
  let taps : Array[Double] = []
  let t = @ui.Tester::new(fn(c) { if c.button("Go") { taps.push(c.now()) } }, w=200.0, h=200.0)
  let now = t.time()
  // a run's own frames: not evenly apart
  let times = Array::makei(12, fn(k) { now + 15.0 * (k + 1).to_double() + (if k % 3 == 0 { 1.5 } else { 0.0 }) })
  t.set_frame_times(times)
  assert_eq(t.next_frame_time(), times[0])
  assert_eq(t.display_frame(times[0] + 0.5), times[1])
  assert_eq(t.display_frame(times[1]), times[1])
  // a frame: the first of them
  t.frame()
  assert_eq(t.time(), times[0])
  // a tap: taken at the next of them, the frames it causes each one of them
  t.tap_text("Go")
  assert_eq(taps, [times[1]])
  let k = times.search(t.time()).unwrap()
  // run_for: to the first of them at or past its end
  t.run_for(times[k + 2] - 1.0 - t.time())
  assert_eq(t.time(), times[k + 2])
  t.frame()
  assert_eq(t.time(), times[k + 3])
  // past the last: on the period from it
  t.run_for(times[11] - t.time())
  t.frame()
  assert_eq(t.time(), times[11] + t.frame_period())
  // the period set again: no times left
  t.set_frame_times([t.time() + 5.0])
  t.set_frame_period(10.0)
  let from = t.time()
  t.frame()
  assert_eq(t.time(), from + 10.0)
}

///|
test "panic set_frame_times: a time not later than the one before is said, and which" {
  let t = @ui.Tester::new(fn(c) { c.text("x") |> ignore }, w=100.0, h=100.0)
  t.set_frame_times([t.time() + 10.0, t.time() + 10.0])
}

///|
test "panic set_frame_times: a time not later than now is said" {
  let t = @ui.Tester::new(fn(c) { c.text("x") |> ignore }, w=100.0, h=100.0)
  t.set_frame_times([t.time()])
}
