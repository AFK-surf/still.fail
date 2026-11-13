// Tester::audit leaves the Tester as it found it: what is read right after it (the words, the rectangles, every
// instance of the draw list, the clock) is what was read right before, a breath that goes with the clock where it
// was, not where contrast's own frame put it (each loop at its start).

///|
/// How long a breath here takes.
let audit_breath_ms : Double = 1600.0

///|
/// How long the screen runs before it is audited: a breath's third, so that nothing that breathes is at its start.
let audit_into_breath_ms : Double = audit_breath_ms / 3.0

///|
/// What a reader reads of the frame just drawn: its words, its rectangles, every instance of its draw list, the clock.
fn audit_read(
  t : Tester,
) -> (
  Array[(String, Double, Double, Double, Double, Double)],
  Array[(Double, Double, Double, Double, Int64)],
  Array[Double],
  Double,
) {
  let c = t.ctx()
  let insts = Array::makei(c.ninst * inst_size, fn(k) { c.inst[k] })
  (t.words(), t.drawn_rects(), insts, t.time())
}

///|
test "audit: what is read right after it, a breath of the window's tree's at its moment among it, is what was read right before" {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.ground(Is(0xFFFFFFFFL)).padding(Is((16.0, 16.0, 16.0, 16.0))).gap(Is(8.0)) |> ignore
      b.box(fn(w) { w.words(Is("等着的东西")) |> ignore }) |> ignore
      // (a waiting mark's breath, as @sf.waiting_node's: its alpha by a cycle, where it is drawn)
      b.box(fn(bone) {
        bone
        .width(Is(Some(200.0)))
        .height(Is(Some(16.0)))
        .ground(Is(0xDDDDDDFFL))
        .alpha(By(fn() { 0.5 + 0.5 * bone.cycle(audit_breath_ms) }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.run_for(audit_into_breath_ms)
  let before = audit_read(t)
  t.audit() |> ignore
  let after = audit_read(t)
  assert_true(after.2 == before.2, msg="the draw list's instances differ after audit")
  assert_eq(after.0, before.0)
  assert_eq(after.1, before.1)
  assert_eq(after.3, before.3)
}

///|
test "audit: what is read right after it, an old view's words worked out of a cycle among it, is what was read right before" {
  let t = Tester::new(
    fn(c) {
      c.box(w=Px(300.0), padx=10.0, fn() {
        c.text("turned \{(c.cycle(audit_breath_ms) * 360.0).to_int()}", size=12.0) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=200.0,
    platform=0,
  )
  t.draw()
  t.run_for(audit_into_breath_ms)
  let before = audit_read(t)
  t.audit() |> ignore
  let after = audit_read(t)
  assert_true(after.2 == before.2, msg="the draw list's instances differ after audit")
  assert_eq(after.0, before.0)
  assert_eq(after.1, before.1)
  assert_eq(after.3, before.3)
}
