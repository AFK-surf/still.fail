///|
test "a row gives its fill child the width left after fixed children and gaps" {
  let long = "a bubble long enough to wrap onto a second line here"
  let t = @ui.Tester::new(
    fn(c) {
      c.column(w=Px(220.0), fn() {
        c.row(gap=10.0, align=AStart, fn() {
          c.box(w=Px(36.0), h=Px(36.0), bg=0x0A84FFFFL, fn() {  }) |> ignore
          c.box(w=Fill(1.0), pad=8.0, fn() { c.text(long, size=14.0) |> ignore })
          |> ignore
        })
        |> ignore
        c.text("NEXT", wrap=false) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  let (_, y, _, h) = t.rect_of(long).unwrap()
  let (_, ny, _, _) = t.rect_of("NEXT").unwrap()
  // the text wraps, and the row below starts after all of its lines
  assert_true(h > 30.0)
  assert_true(ny >= y + h)
}

///|
test "the composer takes compositions, commits, deletes and submits" {
  let sent : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    c.column(w=Fill(1.0), h=Fill(1.0), fn() {
      c.spacer()
      let r = c.editor("composer", placeholder="type here")
      match r.submitted {
        Some(s) => sent.push(s)
        None => ()
      }
    })
    |> ignore
  })
  t.tap_text("type here")
  let (active, _, _, _) = t.ime()
  assert_true(active)
  t.compose("ni'hao")
  assert_true(t.dump().contains("editor") && t.dump().contains("\"ni'hao\""))
  // the input method commits a candidate over its composition
  t.type_text("你好")
  t.compose("shi'jie")
  t.type_text("世界 👋")
  let (_, text, a, b) = t.ime()
  assert_eq(text, "你好世界 👋")
  assert_eq((a, b), (7, 7))
  // backspace removes the whole emoji, then the space
  t.backspace()
  t.backspace()
  let (_, text2, _, _) = t.ime()
  assert_eq(text2, "你好世界")
  t.enter()
  assert_eq(sent, ["你好世界"])
  let (_, text3, _, _) = t.ime()
  assert_eq(text3, "")
}

///|
fn chat_view(items : Array[String]) -> (@ui.Ctx) -> Unit {
  fn(c) {
    c.list(
      "msgs",
      items.length(),
      40.0,
      fn(i) {
        c.box(pad=6.0, fn() { c.text(items[i], size=14.0) |> ignore }) |> ignore
      },
      stick_end=true,
    )
    |> ignore
  }
}

///|
test "a list pinned to its end stays there as rows are measured and added" {
  let items = Array::makei(500, fn(i) {
    if i % 3 == 0 {
      "message \{i} that is quite a bit longer so that it wraps onto several lines in a narrow window"
    } else {
      "message \{i}"
    }
  })
  let t = @ui.Tester::new(chat_view(items), w=240.0, h=400.0)
  t.settle() |> ignore
  let rows = t.rows()
  let (last, y, h) = rows[rows.length() - 1]
  assert_eq(last, 499)
  assert_eq((y + h).round(), 400.0)
  // a new message while at the end: still at the end
  items.push("new message")
  t.frame()
  t.settle() |> ignore
  let rows2 = t.rows()
  let (last2, y2, h2) = rows2[rows2.length() - 1]
  assert_eq(last2, 500)
  assert_eq((y2 + h2).round(), 400.0)
}

///|
test "scrolling up keeps the row under the finger in place" {
  let items = Array::makei(300, fn(i) { "row \{i}" })
  let t = @ui.Tester::new(chat_view(items), w=240.0, h=400.0)
  t.settle() |> ignore
  t.wheel(100.0, 200.0, -300.0)
  let rows = t.rows()
  let (first, _, _) = rows[0]
  assert_true(first < 290)
  // dragging moves content with the finger, by the same distance
  let before = t.rows()
  t.drag(100.0, 100.0, 100.0, 160.0)
  t.settle() |> ignore
  let after = t.rows()
  let (i0, y0, _) = before[2]
  let mut moved = 0.0
  for row in after {
    let (i, y, _) = row
    if i == i0 {
      moved = y - y0
    }
  }
  // at least the drag distance (a fling may carry it further)
  assert_true(moved >= 59.0)
}

///|
test "tabs move their indicator on a spring and come to rest" {
  let sel = [0]
  let t = @ui.Tester::new(fn(c) {
    sel[0] = c.segmented("tabs", ["One", "Two", "Three"], sel[0])
  })
  t.tap_text("Three")
  assert_eq(sel[0], 2)
}

///|
test "layout snapshot" {
  let t = @ui.Tester::new(
    fn(c) {
      c.column(pad=10.0, gap=6.0, w=Fill(1.0), fn() {
        c.text("Title", size=20.0, weight=700) |> ignore
        c.row(gap=8.0, fn() {
          c.text("left", wrap=false) |> ignore
          c.spacer()
          c.text("right", wrap=false) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=100.0,
  )
  inspect(
    t.dump(),
    content=(
      #|col 0,0 200x100
      #|  col 0,0 200x75
      #|    text 10,10 180x28 "Title" lines=1
      #|    row 10,44 180x21
      #|      text 10,44 30x21 "left" lines=1
      #|      col 48,44 97x21
      #|      text 153,44 38x21 "right" lines=1
      #|

    ),
  )
}

///|
fn narrow_text(s : String, w : Double) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      c.column(w=Px(w), fn() { c.text(s, size=10.0) |> ignore }) |> ignore
    },
    w=200.0,
    h=200.0,
  )
}

///|
test "lines wrap at UAX #14 opportunities: after hyphens, not inside brackets" {
  // the fake host makes Latin 5 px wide and CJK 10 px at this size
  let t = narrow_text("a well-known word", 50.0)
  assert_eq(t.lines_of("well"), ["a well-", "known word"])
  // no line ends with an opening bracket or starts with closing punctuation
  let t2 = narrow_text("你好世界「引用」", 50.0)
  assert_eq(t2.lines_of("你好"), ["你好世界", "「引用」"])
  let t3 = narrow_text("你好，世界。「引用」好", 50.0)
  assert_eq(t3.lines_of("你好"), ["你好，世", "界。「引", "用」好"])
  // hard line breaks of every kind
  let t4 = narrow_text("one\r\ntwo\u{2028}three", 200.0)
  assert_eq(t4.lines_of("one"), ["one\r\n", "two\u{2028}", "three"])
}

///|
test "the caret, backspace and delete move over whole grapheme clusters" {
  let t = @ui.Tester::new(fn(c) {
    c.column(w=Fill(1.0), h=Fill(1.0), fn() {
      c.spacer()
      c.editor("composer", placeholder="type here") |> ignore
    })
    |> ignore
  })
  t.tap_text("type here")
  // a, e + combining acute, a family (zwj sequence), a flag, x
  t.type_text("ae\u{301}👨\u{200D}👩\u{200D}👧🇯🇵x")
  let left = 3
  let right = 4
  let delete = 2
  t.key(left)
  t.key(left)
  let (_, _, a, _) = t.ime()
  assert_eq(a, 11)
  t.key(left)
  t.key(left)
  let (_, _, b, _) = t.ime()
  assert_eq(b, 1)
  t.key(right)
  t.backspace()
  let (_, text, c, _) = t.ime()
  assert_eq(text, "a👨\u{200D}👩\u{200D}👧🇯🇵x")
  assert_eq(c, 1)
  t.key(delete)
  let (_, text2, _, _) = t.ime()
  assert_eq(text2, "a🇯🇵x")
}

///|
test "one-line text too wide for its box ends in an ellipsis" {
  let t = @ui.Tester::new(
    fn(c) {
      c.column(w=Px(80.0), fn() {
        c.text("a title far too long to fit", wrap=false) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=100.0,
  )
  // the fake host's Latin and the dots are 7.5 wide: nine and the dots
  // fit in 80
  assert_eq(t.lines_of("a title far"), ["a title f…"])
}

///|
test "a composer's field: Enter a new line, a long paste handed over, its words kept in view as they grow" {
  let pasted : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    c.column(w=Fill(1.0), h=Fill(1.0), fn() {
      c.spacer()
      let r = c.editor(
        "composer",
        placeholder="write here",
        plain=true,
        line=21.0,
        max_lines=3,
        enter_sends=false,
        paste_limit=50,
      )
      match r.pasted {
        Some(s) => pasted.push(s)
        None => ()
      }
    })
    |> ignore
  })
  t.tap_text("write here")
  t.type_text("one")
  t.enter()
  t.type_text("two")
  let (_, text, _, _) = t.ime()
  assert_eq(text, "one\ntwo")
  // fifty characters at once: not put in, handed to the app
  t.type_text(String::make(60, 'p'))
  assert_eq(pasted.length(), 1)
  assert_eq(pasted[0].length(), 60)
  let (_, same, _, _) = t.ime()
  assert_eq(same, "one\ntwo")
  // past three lines the field stops growing and its last line (the caret's) shows
  for w in ["three", "four", "five"] {
    t.enter()
    t.type_text(w)
  }
  let (_, y, _, h) = t.rect_of("write here").unwrap()
  assert_true(h <= 3.0 * 21.0 + 0.5)
  let (_, cy, _, _) = t.ime_rect()
  assert_true(cy >= y && cy < y + h)
  // words put in by the app
  t.ctx().set_editor_text("composer", "kept")
  t.frame()
  let (_, kept, a, _) = t.ime()
  assert_eq(kept, "kept")
  assert_eq(a, 4)
}

///|
test "a scripted run (MBUI_DRIVE) taps words on screen, types through the input method and waits on what comes" {
  let taps = Ref::new(0)
  let t = @ui.Tester::new(fn(c) {
    c.column(w=Fill(1.0), h=Fill(1.0), fn() {
      if c.button("按一下") {
        taps.val = taps.val + 1
      }
      c.text("按了 \{taps.val} 次") |> ignore
      c.editor("field", placeholder="写点什么", enter_sends=false) |> ignore
    })
    |> ignore
  })
  let log = t.drive(
    "# a comment\ntap 按一下\nuntil 按了 1 次\ntap 写点什么\nmark ni\ntype 你好\nenter\ntype 第二行\nfield 你好\\n第二行\nexit",
  )
  assert_true(log.contains("DRIVE PASS"))
  assert_true(log.contains("EXIT 0"))
  assert_eq(taps.val, 1)
  let (_, text, _, _) = t.ime()
  assert_eq(text, "你好\n第二行")
  // the field emptied
  let cleared = t.drive("clear\nempty")
  assert_true(cleared.contains("DRIVE PASS"))
  // what never comes fails the run, saying where and what was on screen
  let failed = t.drive("timeout 100\nuntil 没有这句话")
  assert_true(failed.iter().any(fn(l) { l.has_prefix("DRIVE FAIL line 2: until 没有这句话") }))
  assert_true(failed.iter().any(fn(l) { l.contains("按了 1 次") }))
  assert_true(failed.contains("EXIT 1"))
}

///|
test "a scripted step waits for the app to settle: a tap once what moves has stopped and the host's page is in" {
  let frames = Ref::new(0)
  let moving_until = Ref::new(0)
  let ticket = Ref::new(0)
  let opened_at = Ref::new(0)
  let ended_at = Ref::new(0)
  let tapped_at = Ref::new(0)
  let t = @ui.Tester::new(fn(c) {
    frames.val = frames.val + 1
    // something moving (a sheet opening) for 40 frames after 动起来
    if frames.val < moving_until.val {
      c.request_frame()
    }
    // a page the host loads for 30 frames after 打开 (what hostcall.mbt asks of a host: a ticket until its event)
    if ticket.val > 0 && frames.val >= opened_at.val + 30 {
      @ui.runtime().outside_end(ticket.val)
      ticket.val = 0
      ended_at.val = frames.val
    }
    c.column(fn() {
      if c.button("动起来") {
        moving_until.val = frames.val + 40
      }
      if c.button("打开") {
        ticket.val = @ui.runtime().outside_start("page 1 (a slow host)")
        opened_at.val = frames.val
      }
      if c.button("按一下") {
        tapped_at.val = frames.val
      }
    })
    |> ignore
  })
  let log = t.drive("tap 动起来\ntap 按一下\nexit")
  assert_true(log.contains("DRIVE PASS"))
  assert_true(tapped_at.val >= moving_until.val)
  let log = t.drive("tap 打开\ntap 按一下\nexit")
  assert_true(log.contains("DRIVE PASS"))
  assert_true(ended_at.val > opened_at.val)
  assert_true(tapped_at.val > ended_at.val)
  // `now`: at once, the app moving or not
  let log = t.drive("tap 动起来\nnow tap 按一下\nexit")
  assert_true(log.contains("DRIVE PASS"))
  assert_true(tapped_at.val < moving_until.val)
  t.settle() |> ignore
}

///|
test "a scripted step the app never settles for fails, naming what is still awaited or that a frame is still asked for" {
  let spinning = Ref::new(false)
  let t = @ui.Tester::new(fn(c) {
    if spinning.val {
      c.request_frame()
    }
    c.column(fn() {
      if c.button("打开") {
        // a ticket never ended: the host never answers
        @ui.runtime().outside_start("view 7 (a page that never loads)") |> ignore
      }
      if c.button("转起来") {
        spinning.val = true
      }
      c.text("在这里") |> ignore
    })
    |> ignore
  })
  let failed = t.drive("timeout 300\ntap 打开\nuntil 在这里")
  assert_true(
    failed
    .iter()
    .any(fn(l) {
      l.has_prefix(
        "DRIVE FAIL line 3: until 在这里: the app did not settle in 300 ms (在这里 is on screen): awaiting view 7 (a page that never loads) since ",
      )
    }),
  )
  assert_true(failed.contains("EXIT 1"))
  // what does not wait for it still goes (`now`, `wait`)
  let log = t.drive("timeout 300\nnow until 在这里\nwait 50\nnow exit")
  assert_true(log.contains("DRIVE PASS"))
  // a frame asked for every frame (a spinner that never stops)
  let t = @ui.Tester::new(fn(c) {
    if spinning.val {
      c.request_frame()
    }
    c.column(fn() {
      if c.button("转起来") {
        spinning.val = true
      }
    })
    |> ignore
  })
  spinning.val = false
  let failed = t.drive("timeout 300\ntap 转起来\nshot spun")
  // (who asked for it: the view, here)
  assert_true(
    failed
    .iter()
    .any(fn(l) {
      l.has_prefix("DRIVE FAIL line 3: shot spun: the app did not settle in 300 ms: a frame asked for (by ") &&
      l.contains("ui_test.mbt")
    }),
  )
  assert_false(failed.contains("SHOT spun"))
  spinning.val = false
}

///|
test "a scripted shot is taken once settled; a host that cannot take it is given 1.5 s" {
  let frames = Ref::new(0)
  let t = @ui.Tester::new(fn(c) {
    frames.val = frames.val + 1
    if frames.val < 20 {
      c.request_frame()
    }
    c.text("一张图") |> ignore
  })
  frames.val = 0
  let log = t.drive("shot one\nshot two\nexit")
  assert_true(log.contains("SHOT one"))
  assert_true(log.contains("SHOT two"))
  assert_true(log.contains("DRIVE PASS"))
  assert_true(frames.val >= 20 + 2 * (1500 / 16))
}

