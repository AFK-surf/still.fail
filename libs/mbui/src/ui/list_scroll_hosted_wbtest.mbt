///|
test "a list hosted in a moved view scrolls without layout and keeps its targets" {
  let rows : ListRows[Int] = ListRows::new()
  let pressed : Array[Int] = []
  let t = Tester::new(fn(_) {  }, w=400.0, h=220.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(Is(Some(400.0))).height(Is(Some(220.0))).padding(Is((30.0, 20.0, 0.0, 0.0))) |> ignore
      old(b, fn(c) {
        let ids = Array::makei(30, fn(i) { i })
        let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
        c.list("rows", items.length(), 40.0, fn(k) {
          let item = items[k]
          let id = c.id("row/\{item}")
          c.on_press(id, fn() { pressed.push(item) })
          c.box(id~, h=Px(40.0), bg=0x224466FFL, fn() {
            c.text("row \{item}", wrap=false) |> ignore
          }) |> ignore
        }, rows_read=true, sized=rows.sized()) |> ignore
      }).width(Is(Some(240.0))).height(Is(Some(160.0))).offset(Is((8.0, 5.0))) |> ignore
    }) |> ignore
  })
  t.check_looks(true)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  assert_false(old_whole.val, msg="the list must really be hosted in a smaller moved view")
  t.wheel_told(130.0, 100.0, 0.0, 20.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 16.0)
  guard t.row(2) is Some(before) else { fail("row 2 not shown before the scroll") }
  let reason = Ref("")
  let hits : Ref[Array[Int]] = Ref([])
  let rects : Ref[Array[Double]] = Ref([])
  let clips : Ref[Array[Double]] = Ref([])
  frame_hook.val = Some(fn() {
    reason.val = painted_why.val
    hits.val = g().hit_ids.copy()
    rects.val = g().hit_rects.copy()
    clips.val = g().hit_clips.copy()
  })
  t.wheel_told(130.0, 100.0, 0.0, 5.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  frame_hook.val = None
  guard t.row(2) is Some(after) else { fail("row 2 not shown after the scroll") }
  assert_true(after.1 < before.1, msg="the hosted list must move")
  let c = g()
  assert_eq(hits.val, c.hit_ids, msg="targets must match the same frame built whole")
  assert_eq(rects.val, c.hit_rects, msg="target rectangles must match the same frame built whole")
  assert_eq(clips.val, c.hit_clips, msg="target clips must match the same frame built whole")
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.item == 2 && n.parent >= 0 && c.nodes[n.parent].kind == kind_list {
      // (where the old view is drawn off where its frame lays it, said of the node of it that holds the island, the
      // row's or one over it; none where it is drawn where it is laid)
      let mut up = i
      while up >= 0 && c.island_now(up) is None {
        up = c.nodes[up].parent
      }
      let (px, py, qx, qy, scale) = if up >= 0 {
        c.island_now(up).unwrap()
      } else {
        (0.0, 0.0, 0.0, 0.0, 1.0)
      }
      t.tap(qx + (n.x + n.fw / 2.0 - px) * scale, qy + (n.y + n.fh / 2.0 - py) * scale)
      break
    }
  }
  assert_eq(pressed, [2], msg="the moved hosted row must receive its click")
  assert_eq(reason.val, "a list scrolled without changing its rows",
    msg="a stable host transform should not force another list layout")
}
