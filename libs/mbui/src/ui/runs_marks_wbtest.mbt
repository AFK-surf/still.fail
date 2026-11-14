// Parts of a node's words in pieces marked under them (View::runs_marks): each its ground, the one that says so a line
// at its foot, drawn where those words are as they wrap, under what is picked of them; picking and copying them as
// ever. And the box round such a part, as a piece of the node (runs_piece).

///|
/// A node of picked_runs 70 wide (so "hello wide world" wraps), 40 down, in a page whose words are picked, marked by
/// `marks`. The Tester and the node.
fn marked_tester(marks : @signals.Signal[Array[@view.RunsMark]]) -> (Tester, @view.View) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  let words : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.padding(Is((0.0, 40.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
      words_picked(page)
      page.box(fn(n) {
        words.val = Some(n)
        n
        .width(Is(Some(70.0)))
        .words_runs(Is(picked_runs), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 })
        .runs_marks(By(fn() { marks.get() }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  (t, words.val.unwrap())
}

///|
/// The rects drawn in colour `c` (RGBA), in the window.
fn drawn_in(t : Tester, c : Int64) -> Array[(Double, Double, Double, Double)] {
  let ch = fn(k : Int) { ((c >> (24 - 8 * k)) & 0xFFL).to_double() / 255.0 }
  t
  .drawn_instances()
  .filter(fn(a) { a[5] == 0.0 && (a[8] - ch(0)).abs() < 0.01 && (a[9] - ch(1)).abs() < 0.01 && (a[10] - ch(2)).abs() < 0.01 })
  .map(fn(a) { (a[0], a[1], a[2], a[3]) })
}

///|
test "parts of a node's words marked: each a ground where its words are, line by line as they wrap; the one that says so a line at its foot; said again, drawn again; picking them as ever" {
  let marks : @signals.Signal[Array[@view.RunsMark]] = @signals.signal([])
  let (t, n) = marked_tester(marks)
  assert_eq(drawn_in(t, 0xFF0000FFL).length(), 0)
  // ("hello" found; "wide world", across its two lines, the one gone to)
  marks.set([
    { from: 0, to: 5, ground: 0xFF0000FFL, line: 0L, line_w: 0.0, round: 0.0 },
    { from: 6, to: 16, ground: 0x0000FFFFL, line: 0x00FF00FFL, line_w: 2.0, round: 0.0 },
  ])
  t.draw()
  let red = drawn_in(t, 0xFF0000FFL)
  let blue = drawn_in(t, 0x0000FFFFL)
  let green = drawn_in(t, 0x00FF00FFL)
  assert_eq(red.length(), 1)
  assert_true(blue.length() >= 2, msg="a ground each line: \{Repr(blue)}")
  assert_eq(green.length(), blue.length())
  // (each where its part's box says, in the window: runs_piece's, by the node's place)
  let (nx, ny, nw, nh) = n.rect()
  let hello = (runs_piece(n, 0, 5))(nw, nh).unwrap()
  assert_true(
    (red[0].0 - (nx + hello.0)).abs() < 0.01 && (red[0].1 - (ny + hello.1)).abs() < 0.01 && (red[0].2 - hello.2).abs() < 0.01,
    msg="hello: \{Repr(red[0])} piece \{Repr(hello)} at \{Repr((nx, ny))}",
  )
  let rest = (runs_piece(n, 6, 16))(nw, nh).unwrap()
  assert_true(rest.3 > 30.0, msg="across its lines: \{Repr(rest)}")
  // (the line at the foot of each line's ground, 2 high)
  for k in 0..<blue.length() {
    let (bx, by, bw, bh) = blue[k]
    let (gx, gy, gw, gh) = green[k]
    assert_true((gx - bx).abs() < 0.01 && (gw - bw).abs() < 0.01 && (gh - 2.0).abs() < 0.01 && (gy + gh - (by + bh)).abs() < 0.01, msg="\{Repr(blue[k])} \{Repr(green[k])}")
  }
  // (picked as ever: its words, not the marks)
  let next = dragged_at(t, nx + 1.0, ny + 11.0, nx + 69.0, ny + 11.0, t.time(), true)
  t.frame_at(next)
  assert_true(t.ctx().selected_text().has_prefix("hello"), msg=t.ctx().selected_text())
  // (said again with none: none drawn)
  marks.set([])
  t.draw()
  assert_eq(drawn_in(t, 0xFF0000FFL).length() + drawn_in(t, 0x0000FFFFL).length(), 0)
  // (a part its words do not hold: no piece)
  assert_eq((runs_piece(n, 10, 99))(nw, nh), None)
}
