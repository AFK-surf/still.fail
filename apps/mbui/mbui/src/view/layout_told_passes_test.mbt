// What a layout tells a binding is worked out, and laid out by what it sets, in that same frame (Tree::laid_out); a
// binding that tells itself again in every layout it is laid out by is given so many passes and no more, and told as a
// fault, the run going on.

///|
/// `f` run as an app's run on a host runs it (a fault told, not stopping the run); what was told said back.
fn told_passes_faults(f : () -> Unit) -> Array[String] {
  let told : Array[String] = []
  @view.faults_stop.val = false
  @view.fault_told.val = Some(fn(said) { told.push(said) })
  f()
  @view.faults_stop.val = true
  @view.fault_told.val = None
  told
}

///|
test "a binding a layout tells again in every layout it is laid out by: given its passes, then told as a fault, and the run goes on" {
  // (the room of a box made by it, read outside it by the width of what holds it: each layout gives the room another
  // width, which tells the binding again, which gives what holds it another width)
  let room : @signals.Signal[@view.Room?] = @signals.signal(None, same=fn(a, b) { a is None && b is None })
  let runs = Ref(0)
  let faults = told_passes_faults(fn() {
    let t = @view.Tree::new(fn(root) {
      root.box(fn(o) {
        o.height(Is(Some(100.0))) |> ignore
        o.width(By(fn() {
          runs.val = runs.val + 1
          match room.get() {
            Some(r) => Some(r.width() + 1.0)
            None => Some(100.0)
          }
        }))
        |> ignore
        o.by_room(fn(_held, r) { room.set(Some(r)) }) |> ignore
      })
      |> ignore
    })
    t.frame(390.0, 844.0) |> ignore
    // (the run goes on: frames after it drawn)
    t.frame(390.0, 844.0) |> ignore
    t.frame(390.0, 844.0) |> ignore
  })
  assert_true(
    faults.length() == 1 && faults[0].contains("left with no frame asked for it"),
    msg="faults told: \{Repr(faults)}, the binding run \{runs.val} times",
  )
  // (bounded: in each of the three frames, as it is due and once a pass, the passes at most four)
  assert_true(runs.val >= 2 && runs.val <= 20, msg="the binding run \{runs.val} times")
}
