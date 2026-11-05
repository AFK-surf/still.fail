// Layout passes, each telling what marks another, run one after another in a frame, as many as laid_passes_most: past
// that, a fault naming what was told otherwise in the last passes (2026-11-05: they ran in each other, 2000 deep on a
// device, and its stack ran out).

///|
test "a width that flips each time its size is told: the frame's passes stop at the most, a fault said with the size told otherwise" {
  let told : Array[String] = []
  @view.faults_stop.val = false
  @view.fault_told.val = Some(fn(said) { told.push(said) })
  let wide = @signals.signal(false, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(child) {
        child.width(By(fn() { Some(if wide.get() { 120.0 } else { 80.0 }) })).height(Is(Some(10.0))) |> ignore
        // (told its size, it asks for the other: no size it settles at)
        child.reacts(fn() { child.laid_size_told() }, fn(_) { wide.set(!@signals.untracked(fn() { wide.get() })) })
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  @view.faults_stop.val = true
  @view.fault_told.val = None
  tree.dispose()
  assert_true(told.length() > 0, msg="no fault told")
  assert_true(told[0].contains("\{@view.laid_passes_most} layout passes in one"), msg=told[0])
  assert_true(told[0].contains("size Some((80, 10)) -> Some((120, 10))") || told[0].contains("size Some((120, 10)) -> Some((80, 10))"), msg=told[0])
}

///|
test "the trace on: each pass's sizes told otherwise said, from what to what" {
  let said : Array[String] = []
  @view.laid_passes_traced.val = true
  @view.laid_passes_trace.val = fn(s) { said.push(s) }
  let wide = @signals.signal(false, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(child) {
        child.width(By(fn() { Some(if wide.get() { 120.0 } else { 80.0 }) })).height(Is(Some(10.0))) |> ignore
        child.reacts(fn() { child.laid_size_told() }, fn(_) {  })
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  wide.set(true)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  @view.laid_passes_traced.val = false
  @view.laid_passes_trace.val = fn(s) { println(s) }
  tree.dispose()
  assert_true(said.iter().any(fn(s) { s.contains("size Some((80, 10)) -> Some((120, 10))") }), msg="\{said}")
}
