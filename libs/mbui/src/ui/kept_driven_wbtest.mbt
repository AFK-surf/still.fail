// What the window's tree keeps is held to what working it out whole gives as each frame is presented (tester.mbt's
// kept_at_present), not as the frame ends: a scripted run's step comes after the frame is drawn (drive_frame), and what
// its input commits there (a page's list's rows filled as a finger's move scrolls it, Tree::order_put_in) is the next
// frame's to lay out and order. Looked at as each frame ended, a drag ended every frame with the order due, and two in
// a row stopped the run as never held to the whole (#5620's checks, on still.fail's bench from #5620 on: paged, list30
// and list1500, whose list scene this is, src/sfbench/list_scene.mbt, dragged as scripts/bench/list.drive drags it).

///|
test "a page's list dragged by a script's steps, rows filled after each frame is drawn, is held to the whole as each is presented" {
  let keys = @signals.signal(Array::makei(30, fn(i) { i }), same=fn(a, b) { a == b })
  let scroll = @view.Scroll::list()
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let made = Ref(0)
  // (as a bench's Tester runs, film/bench.mbt: a finger on a phone's window, none of a test's own checks of each frame
  // but the window's tree's, a list's rows on the device's pixels)
  let t = Tester::new(
    fn(_c) {  },
    w=390.0,
    h=844.0,
    platform=2,
    pointing=Finger,
    corners_held=false,
    words_over_held=false,
    keeps_sources=false,
  )
  t.check_looks(false)
  t.corners_look(false)
  t.set_rows_on_pixels(true)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      col.box(fn(bar) { bar.height(Is(Some(44.0))) |> ignore }) |> ignore
      col.box(fn(o) {
        o.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        o.scrolls_window(scroll, fn() { keys.get() }, est=60.0, follows=fn() { true }, place~, fn(b, k) {
          made.val = made.val + 1
          b.box(fn(r) {
            r
            .height(Is(Some(if k % 3 == 0 { 64.0 } else { 44.0 })))
            .words(Is("message \{k}: words as a chat's line has them, a few of them"))
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let before = made.val
  let logs = t.drive(
    "drag 195 300 0 430 1000\ndrag 195 300 0 430 1000\ndrag 195 300 0 600 90\nwait 3700\nexit",
  )
  assert_true(logs.iter().any(fn(line) { line == "EXIT 0" }), msg=logs.join("\n"))
  // (rows filled on the way, each after the frame before it was drawn)
  assert_true(made.val - before > 5, msg="rows made on the drags: \{made.val - before}")
}
