///|
/// The ids of the actions handed to the system's bars, in their order.
fn over_ids() -> Array[String] {
  native_over.acts.map(fn(a) { a.0 })
}

///|
test "what is up over the window says its actions as one set: built again, what it no longer says gone, none twice; another up in its place, only its own; kept while it is up, built again or not; gone once it is not" {
  native_bars_reset()
  native_bars.on.set(true)
  let up = Ref(true)
  // (built: three said; built again: one no longer said, one said twice)
  native_over_up("屏幕", alive=fn() { up.val }) |> ignore
  for id in ["close", "center", "full"] {
    native_over_act(id, id, "x", fn() {  })
  }
  native_over_up("屏幕", alive=fn() { up.val }) |> ignore
  native_over_act("close", "close", "x", fn() {  })
  native_over_act("full", "full", "x", fn() {  })
  native_over_act("full", "full", "x", fn() {  })
  let again = over_ids()
  // (another page up in its place)
  native_over_up("文件", alive=fn() { up.val }) |> ignore
  native_over_act("download", "download", "x", fn() {  })
  let other = over_ids()
  // (a frame ends with it still up, its part kept: nothing said again, what it said stays)
  native_over_gone()
  let kept = (native_over.up, over_ids())
  // (it is up no more: gone as the frame ends)
  up.val = false
  native_over_gone()
  let gone = (native_over.up, over_ids())
  native_bars_reset()
  assert_eq((again, other, kept, gone), (
    ["over/close", "over/full"],
    ["over/download"],
    (true, ["over/download"]),
    (false, []),
  ))
}
