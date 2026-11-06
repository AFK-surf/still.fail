// Who drew each instance (inst_owners: a Tester's, words over words, what is seen whole, a frame exported) is kept
// beside what the scene keeps and never decides how a layer is drawn: kept or not, a list wheeled and a row changed
// are copied, moved and drawn again the same way, and come to the same frames; asked for from a frame on, after none
// was kept, everything is drawn anew once, and who drew each instance is as if it had been kept all along.

///|
/// A list of 300 rows wheeled down in steps, then a row's words changed, who drew each instance kept from the start or
/// not (`track`), and kept from the last frame on either way: each frame's instances, what the scene did for them,
/// and who drew each of the last frame's.
fn owners_kept_run(track : Bool) -> (Array[Array[Array[Double]]], Array[SceneWork], Array[(Int, @view.NodeId?)]) {
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
    work.push({
      ..after,
      layers: after.layers - before.layers,
      recorded: after.recorded - before.recorded,
      copied: after.copied - before.copied,
      copied_insts: after.copied_insts - before.copied_insts,
    })
  }
  // (kept from here on: a test asking who drew what, as Tester::export_frames and hold_seen_whole do)
  inst_owners.track = true
  words.set("fresh")
  t.clock_frame()
  frames.push(t.drawn_instances_keyed())
  let n = g().ninst
  let owners = Array::makei(n, fn(k) {
    (
      if k < inst_owners.owner.length() { inst_owners.owner[k] } else { -2 },
      if k < inst_owners.tree.length() { inst_owners.tree[k] } else { None },
    )
  })
  (frames, work, owners)
}

///|
test "who drew each instance, kept or not, changes nothing of what the scene does or draws, and kept from a frame on is whole" {
  let (kept_frames, kept_work, kept_owners) = owners_kept_run(true)
  let (frames, work, owners) = owners_kept_run(false)
  inst_owners.track = true
  let said = fn(w : SceneWork) { (w.layers, w.recorded, w.copied, w.copied_insts) }
  assert_eq(work.map(said), kept_work.map(said))
  assert_eq(frames, kept_frames)
  // (asked for once none was kept: as if it had been kept all along, nobody's where somebody drew)
  assert_eq(owners, kept_owners)
}
