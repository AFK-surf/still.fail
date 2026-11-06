// Who drew each instance (inst_owners: a Tester's, words over words) is kept beside what the scene keeps and never
// decides what the scene does: kept or not, a list wheeled and a row changed are copied, moved and drawn again the
// same way, and come to the same frames.

///|
/// A list of 300 rows wheeled down in steps, then a row's words changed, with who drew each instance kept or not
/// (`track`): each frame's instances, and what the scene did for them.
fn owners_run(track : Bool) -> (Array[Array[Array[Double]]], Array[SceneWork]) {
  let words = @signals.signal("first")
  let t = Tester::new(fn(_) {  }, w=400.0, h=600.0)
  inst_owners.track = track
  set_view_app(fn(root) {
    root
    .width(Is(Some(400.0)))
    .height(Is(Some(600.0)))
    .scrolls_window(@view.Scroll::list(), fn() { Array::makei(300, fn(i) { i }) }, est=48.0, fn(row, k) {
      row.height(Is(Some(48.0))).ground(Is(if k % 2 == 0 { 0xF2F2F2FFL } else { 0xFFFFFFFFL })) |> ignore
      row.box(fn(w) { w.words(By(fn() { if k == 3 { words.get() } else { "message \{k}" } })) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  let frames = []
  let work = []
  for _ in 0..<6 {
    let before = scene_done()
    t.wheel(200.0, 300.0, 37.0)
    t.clock_frame()
    frames.push(t.drawn_instances_keyed())
    let after = scene_done()
    work.push({ ..after, layers: after.layers - before.layers, recorded: after.recorded - before.recorded, copied: after.copied - before.copied, copied_insts: after.copied_insts - before.copied_insts })
  }
  words.set("fresh")
  t.clock_frame()
  frames.push(t.drawn_instances_keyed())
  (frames, work)
}

///|
test "who drew each instance, kept or not, changes nothing of what the scene does or draws" {
  let (kept_frames, kept_work) = owners_run(true)
  let (frames, work) = owners_run(false)
  inst_owners.track = true
  let said = fn(w : SceneWork) { (w.layers, w.recorded, w.copied, w.copied_insts) }
  assert_eq(work.map(said), kept_work.map(said))
  assert_eq(frames, kept_frames)
}
