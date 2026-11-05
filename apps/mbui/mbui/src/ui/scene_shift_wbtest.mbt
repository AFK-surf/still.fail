// A list's rows kept as drawn while it is scrolled (docs/retained.md rule 16): what holds them moved as a whole, each
// row's layer copied moved with it, its cut met with the list's that stays, and only a row coming in or lying on the
// list's edge where it comes in drawn again (Ctx::scene_copied's shift, scene_shiftable). Every frame is checked as
// every Tester checks it (scene_check: painted again with nothing kept, instance for instance the same).

///|
/// How far one wheel scrolls the list as it is counted.
let shift_wheel : Double = -6.0

///|
/// How long the list is let go still after each wheel.
let shift_rest_ms : Double = 400.0

///|
/// A list of 40 rows 48 tall in a window 540 tall, each a ground and a mark, scrolled `wheels` times by shift_wheel:
/// what drawing the tree did for those scrolls, and how many instances the list's frame draws.
fn scrolled_list_work(wheels : Int) -> (SceneWork, Int) {
  let t = Tester::new(fn(_) {  }, w=400.0, h=600.0)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(400.0))).height(Is(Some(600.0))).ground(Is(0xFFFFFFFFL)) |> ignore
      page.box(fn(list) {
        list.width(Is(Some(400.0))).height(Is(Some(540.0)))
        .scrolls_window(@view.Scroll::list(), fn() { Array::makei(40, fn(i) { i }) }, est=48.0, from_end=true, fn(
          row,
          k,
        ) {
          row.height(Is(Some(48.0))).ground(Is(if k % 2 == 0 { 0xF2F2F2FFL } else { 0xFFFFFFFFL })) |> ignore
          // (a mark in it, no words: words are set on the pixels where they are drawn, drawn anew where they move)
          row.box(fn(m) { m.width(Is(Some(24.0))).height(Is(Some(24.0))).radius(Is(6.0)).ground(Is(0x1559C4FFL)) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.run_for(shift_rest_ms)
  let drawn = g().ninst
  let before = scene_done()
  for _ in 0..<wheels {
    t.wheel(200.0, 300.0, shift_wheel)
    t.run_for(shift_rest_ms)
  }
  let after = scene_done()
  (
    {
      layers: after.layers - before.layers,
      recorded: after.recorded - before.recorded,
      copied: after.copied - before.copied,
      copied_insts: after.copied_insts - before.copied_insts,
      alone: after.alone - before.alone,
      full: after.full - before.full,
      parts: after.parts - before.parts,
      alone_recorded: after.alone_recorded - before.alone_recorded,
      alone_parts: after.alone_parts - before.alone_parts,
    },
    drawn,
  )
}

///|
test "a list scrolled a little: its rows' layers copied moved with it, only those at its edge drawn again" {
  let (work, drawn) = scrolled_list_work(4)
  println("SHIFTWORK \{work} drawn=\{drawn}")
  // (each scroll's frames: the rows in sight, 12 of them, copied moved; what is drawn again, the rows at the edge where
  // the list comes in and what holds them, less than a quarter of a frame's instances each scroll)
  assert_true(work.copied > 0, msg="\{work}: \{scene.copy_why}")
  assert_true(work.recorded < drawn, msg="recorded \{work.recorded} over 4 scrolls of a frame of \{drawn}: \{work}; \{scene.copy_why}")
}
