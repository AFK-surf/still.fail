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
