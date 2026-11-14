// A message can contain rich words and a link. Moving a fully visible row should keep its paint while the link follows
// it to its new place. Rows that are not safe to retain must still use the ordinary paint.

///|
test "scrolling retains the drawing of a rich row and moves its link" {
  let painted = Ref(0)
  let opened : Array[String] = []
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let item = items[k]
      let n = c.box(h=Px(40.0), bg=0x224466FFL, fn() {
        c.rich([@text.link("open row \{item}", "row/\{item}")],
          key="message/\{item}", on_link=fn(url) { opened.push(url) }) |> ignore
      })
      if item == 2 {
        c.bg_by(n, fn() {
          painted.val += 1
          0xCC6633FFL
        })
      }
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.frame_at(at + 16.0)
  let before = t.row(2).unwrap()
  let paints = painted.val
  assert_true(paints > 0)
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  let after = t.row(2).unwrap()
  let paints_after = painted.val
  assert_true(after.1 < before.1, msg="the rich row must move")
  t.tap_run("open row 2")
  assert_eq(opened, ["row/2"], msg="the moved link must still open its own message")
  assert_eq(paints_after, paints, msg="a fully visible rich row should reuse its drawing on a scroll")
}

///|
fn rich_row_frames(keep : Bool) -> Array[Array[Array[Double]]] {
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let item = items[k]
      c.box(h=Px(40.0), bg=0x224466FFL, fn() {
        c.rich([@text.plain("message "), @text.link("open \{item}", "row/\{item}")],
          key="message/\{item}") |> ignore
      }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.drawn_again(keep)
  t.draw()
  let at = t.time()
  t.frame_at(at + 16.0)
  let frames = [t.drawn_instances_keyed()]
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  frames.push(t.drawn_instances_keyed())
  let (x, y, w, h) = t.run_rects("open 2")[0]
  t.press_at(x + w / 2.0, y + h / 2.0)
  frames.push(t.drawn_instances_keyed())
  finger(2, x + w / 2.0, y + h / 2.0)
  t.frame_at(at + 48.0)
  frames.push(t.drawn_instances_keyed())
  t.drawn_again(true)
  frames
}

///|
test "retained rich rows match complete drawing while a link moves and is pressed" {
  let retained = rich_row_frames(true)
  let built = rich_row_frames(false)
  assert_eq(retained.length(), built.length())
  for f in 0..<retained.length() {
    assert_eq(retained[f].length(), built[f].length(), msg="frame \{f}")
    for i in 0..<retained[f].length() {
      for j in 0..<retained[f][i].length() {
        assert_true((retained[f][i][j] - built[f][i][j]).abs() < 0.000001,
          msg="frame \{f}, instance \{i}, value \{j}: retained \{retained[f][i][j]}, rebuilt \{built[f][i][j]}")
      }
    }
  }
}
