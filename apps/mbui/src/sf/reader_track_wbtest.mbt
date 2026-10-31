///|
test "the reader's track jumps on a tap with no frame drawn while pressed" {
  let r = reading_for("track-tap")
  let book : Book = {
    title: "Book",
    id: 1,
    text: "abcd",
    chunks: ["a", "b", "c", "d"],
    starts: [0, 1, 2, 3],
    parts: [],
    length: 4,
    chapters: [],
    heads: Map([]),
    encoding: "UTF-8",
    truncated: false,
    markdown: false,
  }
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() { narrow_track(c, r, book, reader_paper("white"), true) })
  }, w=390.0, h=120.0, platform=2)
  let (x, y, w, h) = t.get(Slider).rect
  t.tap(x + w * 0.75, y + h / 2.0)
  assert_true(r.jump_step > 0, msg="a tap jumps to the place on the track")
  assert_eq(r.jump.0, 3, msg="the tap reaches the selected part")
  // Start a drag in one frame, then move and release before the next.
  t.touch(0, x + w * 0.2, y + h / 2.0)
  t.draw()
  t.touch(1, x + w * 0.9, y + h / 2.0)
  t.touch(2, x + w * 0.9, y + h / 2.0)
  t.draw()
  assert_eq(r.jump.0, 3, msg="the drag reaches where it ended")
  reader_let_go("track-tap")
}

///|
test "a short book's track reaches the middle of its text" {
  let r = reading_for("track-short")
  let words = "0123456789".repeat(10)
  let book : Book = {
    title: "Short book",
    id: 2,
    text: words,
    chunks: [words],
    starts: [0],
    parts: [],
    length: words.length(),
    chapters: [],
    heads: Map([]),
    encoding: "UTF-8",
    truncated: false,
    markdown: false,
  }
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() { narrow_track(c, r, book, reader_paper("white"), true) })
  }, w=390.0, h=120.0, platform=2)
  let (x, y, w, h) = t.get(Slider).rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(r.jump.0, 0)
  assert_eq(r.jump.1, 50, msg="the middle of the track reaches the middle of the text")
  reader_let_go("track-short")
}

///|
test "tapping the middle of a short book's track scrolls its text" {
  let r = reading_for("track-short-scroll")
  let words = "小说正文".repeat(225)
  let book : Book = {
    title: "Short book",
    id: 4,
    text: words,
    chunks: [words],
    starts: [0],
    parts: [],
    length: words.length(),
    chapters: [],
    heads: Map([]),
    encoding: "UTF-8",
    truncated: false,
    markdown: false,
  }
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() {
      c.box(h=Px(300.0), fn() {
        reader_column(c, r, book, reader_style_default, reader_paper("white"), left=0.0, right=0.0, top=0.0, foot=0.0)
      }) |> ignore
      narrow_track(c, r, book, reader_paper("white"), true)
    })
  }, w=390.0, h=350.0, platform=2)
  let (x, y, w, h) = t.get(Slider).rect
  t.tap(x + w / 2.0, y + h / 2.0)
  let (first, offset, _) = t.ctx().list_place(reader_list_key(r)).unwrap()
  assert_eq(first, 1)
  assert_true(offset > 0.0, msg="the text moved down from its beginning")
  reader_let_go("track-short-scroll")
}

///|
test "a book's track follows text position when its blocks have different lengths" {
  let r = reading_for("track-uneven")
  let first = "a".repeat(90)
  let last = "b".repeat(10)
  let book : Book = {
    title: "Uneven book",
    id: 3,
    text: first + last,
    chunks: [first, last],
    starts: [0, 90],
    parts: [],
    length: 100,
    chapters: [],
    heads: Map([]),
    encoding: "UTF-8",
    truncated: false,
    markdown: false,
  }
  r.chunk = 0
  r.within = 0.5
  assert_true((reader_fraction(r, book) - 0.45).abs() < 0.000001, msg="halfway through the first 90 characters is 45% of the book")
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() { narrow_track(c, r, book, reader_paper("white"), true) })
  }, w=390.0, h=120.0, platform=2)
  let (x, y, w, h) = t.get(Slider).rect
  t.tap(x + 11.0 + (w - 22.0) * 0.95, y + h / 2.0)
  assert_eq(r.jump.0, 1)
  assert_eq(r.jump.1, 5, msg="95% reaches the middle of the last 10 characters")
  reader_let_go("track-uneven")
}
