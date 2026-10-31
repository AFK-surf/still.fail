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
  assert_eq(r.jump.0, 2, msg="the tap reaches the selected part")
  // Start a drag in one frame, then move and release before the next.
  t.touch(0, x + w * 0.2, y + h / 2.0)
  t.draw()
  t.touch(1, x + w * 0.9, y + h / 2.0)
  t.touch(2, x + w * 0.9, y + h / 2.0)
  t.draw()
  assert_eq(r.jump.0, 3, msg="the drag reaches where it ended")
  reader_let_go("track-tap")
}
