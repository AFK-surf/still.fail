// A page can retain its business keys while a block's version reads another signal.
///|
fn page_external_version_motion(hz : Int) -> (Double, Double, Double, Double, Double, Int64) {
  let items = @signals.signal(["a", "b"])
  let external = @signals.signal(0)
  let blocks_out : Ref[PageBlocks[String]?] = Ref(None)
  let nodes : Map[String, @view.View] = Map([])
  let t = @ui.Tester::new(fn(_) { }, w=300.0, h=300.0, stable=false)
  @ui.set_view_app(fn(root) {
    let blocks = page_blocks(root, fn() { items.get() }, fn(it) { it },
      fn(it) { if it == "a" { external.get().to_string() } else { "0" } },
      animated=true, moves=true, continuity=fn(_) { true })
    blocks_out.val = Some(blocks)
    root.height(Is(Some(300.0))).scrolls_window(@view.Scroll::list(), blocks.keys, est=60.0,
      rooms=blocks.rooms.unwrap(), fn(row, k) {
        nodes[k] = row
        (blocks.lend)(row, k)
        row.height(By(fn() { Some(if k == "a" && external.get() == 1 { 120.0 } else { 60.0 }) }))
        .words(Is(k)) |> ignore
      }) |> ignore
  })
  t.draw()
  let blocks = blocks_out.val.unwrap()
  let at = t.time()
  @ui.view_tree().unwrap().event(at, fn() { external.set(1) })
  t.frame_at(at)
  let start_height = (blocks.rooms.unwrap()())("a", 120.0, 300.0).height
  if hz > 0 {
    let period = 1000.0 / hz.to_double()
    let mut time = at + period
    while time < at + @ui.row_size_ms / 2.0 {
      t.frame_at(time)
      time += period
    }
  }
  t.frame_at(at + @ui.row_size_ms / 2.0)
  let mid_height = (blocks.rooms.unwrap()())("a", 120.0, 300.0).height
  let mid_b = nodes["b"].laid_window_now().1
  if hz > 0 {
    let period = 1000.0 / hz.to_double()
    let mut time = at + @ui.row_size_ms / 2.0 + period
    while time < at + @ui.row_size_ms {
      t.frame_at(time)
      time += period
    }
  }
  t.frame_at(at + @ui.row_size_ms)
  let end_height = (blocks.rooms.unwrap()())("a", 120.0, 300.0).height
  let end_b = nodes["b"].laid_window_now().1
  (start_height, mid_height, end_height, mid_b, end_b, t.frame_hash())
}

///|
test "a page block follows an independent version change with or without intermediate frames" {
  let direct = page_external_version_motion(0)
  assert_eq(direct.0, 60.0, msg="the changed block begins at its previous room")
  assert_true(direct.1 > 60.0 && direct.1 < 120.0, msg="the changed block is in its height transition")
  assert_eq(direct.2, 120.0, msg="the changed block reaches its new room")
  assert_true(direct.3 > 60.0 && direct.3 < 120.0, msg="the next block follows the changed room")
  assert_eq(direct.4, 120.0, msg="the next block reaches its new place")
  assert_eq(page_external_version_motion(60), direct)
  assert_eq(page_external_version_motion(120), direct)
}
