// A boundary: what faults under it shown in its place, the run going on (boundary.mbt).

///|
/// `f` run as an app's run on a host runs (a fault told, not stopping the run); what was told said back.
fn faults_kept(f : () -> Unit) -> Array[String] {
  let told : Array[String] = []
  @view.faults_stop.val = false
  @view.fault_told.val = Some(fn(said) { told.push(said) })
  f()
  @view.faults_stop.val = true
  @view.fault_told.val = None
  told
}

///|
test "a fault under a boundary: its fallback in place of what faulted from the next frame, told once" {
  let faults = @signals.signal(0, same=fn(a, b) { a == b })
  let made : Ref[@view.View?] = Ref(None)
  let fell : Ref[@view.View?] = Ref(None)
  let beside : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(fn(root) {
    beside.val = Some(root.box(fn(v) { v.words(Is("旁边")) |> ignore }))
    root.boundary(
      fn(b) {
        made.val = Some(
          b.box(fn(v) {
            // (asked twice of it in one go: told once)
            v.words(By(fn() {
              if faults.get() > 0 {
                v.fault("a test's fault")
                v.fault("a test's fault")
              }
              "里面"
            }))
            |> ignore
          }),
        )
      },
      fn(b, said) { fell.val = Some(b.box(fn(v) { v.words(Is("出错了：" + said)) |> ignore })) },
    )
  })
  let before = Ref(true)
  let told = faults_kept(fn() {
    t.frame(390.0, 844.0) |> ignore
    before.val = fell.val is None
    faults.set(1)
    t.frame(390.0, 844.0) |> ignore
    t.frame(390.0, 844.0) |> ignore
  })
  assert_true(before.val)
  assert_eq(told, ["a test's fault"])
  assert_true(fell.val is Some(_))
  assert_eq(t.drawn_of(fell.val.unwrap().id()).unwrap().words, "出错了：a test's fault")
  // what faulted let go, what is beside the boundary as it was
  assert_true(t.drawn_of(made.val.unwrap().id()) is None)
  assert_eq(t.drawn_of(beside.val.unwrap().id()).unwrap().words, "旁边")
  assert_false(faults.watched())
}
