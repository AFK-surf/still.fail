///|
test "a moved selectable row retains its drawing and can still select its words" {
  let painted = Ref(0)
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    c.mouse_drags_lists(false)
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.selectable(fn() {
      c.list("rows", items.length(), 40.0, fn(k) {
        let item = items[k]
        let n = c.box(h=Px(40.0), fn() {
          c.rich([@text.plain("message \{item} words")], key="message/\{item}") |> ignore
        })
        if item == 2 {
          c.bg_by(n, fn() {
            painted.val += 1
            0xCC6633FFL
          })
        }
      }, rows_read=true, sized=rows.sized()) |> ignore
    })
  }, w=300.0, h=160.0, pointing=Mouse)
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
  assert_true(after.1 < before.1, msg="the row must move")
  let (x, y, w, h) = t.run_rects("message 2 words")[0]
  t.drag(x + 0.5, y + h / 2.0, x + w + 2.0, y + h / 2.0)
  assert_true(t.ctx().selected_text().contains("message 2 words"),
    msg="the words must be selectable at their moved position: \{t.ctx().selected_text()}")
  assert_eq(paints_after, paints, msg="an unselected row can retain its drawing and selection target")
}
