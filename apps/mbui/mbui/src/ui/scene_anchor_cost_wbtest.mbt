// What a frame of the window's tree costs is what changed (docs/retained.md rules 14 and 15), counted: a spinner
// turning over a chat's long list draws as much, and works out as much of where the window changed, as the same
// spinner over an empty page, each of its frames drawn by the tree alone.

///|
/// How long the spinners turn as they are counted.
let anchor_spinning_ms : Double = 1000.0

///|
/// How long a spinner takes to turn once.
let anchor_spin_period_ms : Double = 800.0

///|
/// A spinner turning on the resident clock over a chat's list of `n` messages (none: an empty page): what drawing the
/// tree did while it turned for anchor_spinning_ms (after its first turn), and where its last frame of the tree alone drew again.
fn anchor_spinner_over(n : Int) -> (SceneWork, Array[(Double, Double, Double, Double)]) {
  let t = Tester::new(fn(_) {  }, w=400.0, h=600.0)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(400.0))).height(Is(Some(600.0))).ground(Is(0xFFFFFFFFL)) |> ignore
      page.box(fn(s) {
        s
        .offset(Is((360.0, 0.0)))
        .width(Is(Some(24.0)))
        .height(Is(Some(24.0)))
        .radius(Is(6.0))
        .ground(Is(0x1559C4FFL))
        .turn(By(fn() { s.cycle_resident(anchor_spin_period_ms) * 2.0 * 3.141592653589793 }))
        |> ignore
      })
      |> ignore
      if n > 0 {
        page.box(fn(list) {
          list.width(Is(Some(400.0))).height(Is(Some(540.0)))
          .scrolls_anchored(@view.Scroll::list(), fn() { Array::makei(n, fn(i) { i }) }, est=48.0, from_end=true, fn(
            row,
            k,
          ) {
            row.height(Is(Some(48.0))).ground(Is(if k % 2 == 0 { 0xF2F2F2FFL } else { 0xFFFFFFFFL })) |> ignore
            row.box(fn(w) { w.words(Is("message")) |> ignore }) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  t.draw()
  // (its first turn as the frames after the window's first are: the old frame built once more for what it read)
  t.run_for(anchor_spinning_ms)
  scene.full_whys.clear()
  let before = scene_done()
  t.run_for(anchor_spinning_ms)
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
    [scene.alone_reach],
  )
}

///|
test "an anchored spinner over a chat's 3000 messages costs what it costs over an empty page: its own drawing, its own part" {
  let (empty, empty_parts) = anchor_spinner_over(0)
  let (long, long_parts) = anchor_spinner_over(3000)
  // (it turned, each step a frame of the tree alone; what the old frame painted meanwhile copied the rest as kept)
  assert_true(empty.alone > 0, msg="\{empty}: \{scene_alone_why()}")
  // (the same work each way: the layers drawn, their instances, what was reached of where the window changed)
  // (the instances copied as kept by what the old frame painted meanwhile: an adapter's, as many as there are, no work
  // of the scene's)
  // (what the old frame painted meanwhile, for its own, aside: what the spinner's own frames drew and worked out)
  let work = fn(w : SceneWork) { (w.alone, w.alone_recorded, w.alone_parts) }
  assert_eq(work(long), work(empty), msg="over the list \{long}, over nothing \{empty}; last frame: \{scene_alone_why()}")
  // (and its step drawn again where the spinner reaches, before and now: its turn's circle, its edge's reach, nothing
  // of the list)
  assert_eq(long_parts, empty_parts)
  let (x0, y0, x1, y1) = empty_parts[0]
  assert_true(x1 - x0 > 0.0 && x1 - x0 < 48.0 && y1 - y0 > 0.0 && y1 - y0 < 48.0, msg="\{empty_parts}")
}

///|
test "a row of an anchored long list changed: the row drawn again, the rest copied as kept, the same however long the list" {
  let words = @signals.signal("first")
  let why = Ref("")
  let made = fn(n : Int) -> SceneWork {
    let t = Tester::new(fn(_) {  }, w=400.0, h=600.0)
    set_view_app(fn(root) {
      root
      .width(Is(Some(400.0)))
      .height(Is(Some(600.0)))
      .scrolls_anchored(@view.Scroll::list(), fn() { Array::makei(n, fn(i) { i }) }, est=48.0, from_end=true, fn(row, k) {
        row.height(Is(Some(48.0))) |> ignore
        row.box(fn(w) { w.words(By(fn() { if k == n - 1 { words.get() } else { "message" } })) |> ignore }) |> ignore
      })
      |> ignore
    })
    t.draw()
    let before = scene_done()
    // (the same number of letters: the row comes to as many instances)
    words.set(if words.get() == "first" { "fresh" } else { "first" })
    t.draw()
    let after = scene_done()
    why.val = "painted: \{t.painted_why()}, built: \{t.built_why()}, alone: \{scene_alone_why()}"
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
    }
  }
  let short = made(30)
  let long = made(3000)
  // (what comes from outside builds the old frame, which paints the frame: the rows kept copied, the one changed drawn)
  assert_true(short.copied > 0, msg="\{short}: \{why.val}")
  assert_eq(long, short, msg="3000 rows \{long}, 30 rows \{short}")
}
