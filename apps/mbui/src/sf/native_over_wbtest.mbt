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

// What is up over the window said by more than one (native_bars.mbt's claims): the highest of those still up handed,
// of two as high the one said last; one gone, the one under it as it said it last.

///|
/// The system's bars there (native_on), none said yet.
fn over_begun() -> Unit {
  native_bars_reset()
  native_bars.on.set(true)
}

///|
/// What is handed: its title and its actions' ids.
fn handed() -> (String, Array[String]) {
  (native_over.title, native_over.acts.map(fn(a) { a.0 }))
}

///|
test "what is up over the window said by a page and by what is over it: the one over it handed, the page saying it again under it; that one gone, the page's as it said it last" {
  over_begun()
  let page_up = Ref(true)
  let over_up = Ref(true)
  native_over_up("page", alive=fn() { page_up.val }) |> ignore
  native_over_act("a", "A", "a", fn() {  })
  native_over_up("viewer", alive=fn() { over_up.val }, owner="viewer", over=2) |> ignore
  native_over_act("close", "Close", "close", fn() {  }, lead=true)
  assert_eq(handed(), ("viewer", ["lead/over/close"]), msg="the one over it")
  // (the page built again under it, said again: another action)
  native_over_up("page", alive=fn() { page_up.val }) |> ignore
  native_over_act("b", "B", "b", fn() {  })
  native_over_gone()
  assert_eq(handed(), ("viewer", ["lead/over/close"]), msg="still the one over it")
  over_up.val = false
  native_over_gone()
  assert_eq(handed(), ("page", ["over/b"]), msg="gone: the page's, as it said it last")
  page_up.val = false
  native_over_gone()
  assert_true(!native_over.up, msg="none up")
  native_bars_reset()
}

///|
test "what is up over the window said by two as high, A then B then A: the one said last handed each time" {
  over_begun()
  native_over_up("A", alive=fn() { true }, owner="a") |> ignore
  assert_eq(handed().0, "A")
  native_over_up("B", alive=fn() { true }, owner="b") |> ignore
  assert_eq(handed().0, "B", msg="B said last")
  native_over_up("A", alive=fn() { true }, owner="a") |> ignore
  assert_eq(handed().0, "A", msg="A said last again")
  native_bars_reset()
}
