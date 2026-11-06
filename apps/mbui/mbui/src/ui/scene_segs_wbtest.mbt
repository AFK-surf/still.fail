// The check of a frame against its layers' blocks and runs (scene_segs_check): a run left out, or one said twice, told;
// the frame as drawn, the same.

///|
/// A page of a few layers moved: its frame drawn, the check of its runs as they are, with the last left out, with the
/// first said twice.
test "a frame's runs: as said the frame; one left out, or one twice, told" {
  let y = @signals.signal(10.0)
  let t = Tester::new(fn(_) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      for i in 0..<3 {
        page.show(fn() { true }, fn(b) {
          b.offset(By(fn() { (10.0 + i.to_double() * 60.0, y.get()) })).width(Is(Some(50.0))).height(Is(Some(30.0))).ground(Is(0x336699FFL))
          |> ignore
          b.box(fn(w) { w.words(Is("r\{i}")) |> ignore }) |> ignore
        })
      }
    })
    |> ignore
  })
  t.draw()
  y.set(14.0)
  t.draw()
  let c = g()
  let n = c.ninst
  let a = FixedArray::make(n * inst_size + 1, 0.0)
  c.inst.blit_to(a, len=n * inst_size)
  assert_true(scene_segs.length() > 0)
  assert_eq(scene_segs_check(a, n, c.scale), None)
  // (the last left out)
  let last = scene_segs.pop().unwrap()
  let left = scene_segs_check(a, n, c.scale)
  assert_true(left is Some(s) && s.contains("in 0 runs"), msg="\{left}")
  scene_segs.push(last)
  // (the first twice)
  scene_segs.push(scene_segs[0])
  let twice = scene_segs_check(a, n, c.scale)
  assert_true(twice is Some(s) && s.contains("in 2 runs"), msg="\{twice}")
  scene_segs.pop() |> ignore
  assert_eq(scene_segs_check(a, n, c.scale), None)
}
