// A part of the window drawn otherwise (View::scope): what is made in it, made then or later, and its bindings read
// in it, as what changes them comes; what is beside it, not.

///|
test "scope: a node's scope its own and what it holds, made at once or later; their bindings and makings read in it, again as what they read changes" {
  let shown = @signals.signal(false)
  let tone = @signals.signal(0, same=fn(a, b) { a == b })
  let read_in : Map[String, Int] = {}
  let read = fn(name : String) -> @view.Live[Double?] {
    By(fn() {
      tone.get() |> ignore
      read_in[name] = @view.scope_now()
      Some(10.0)
    })
  }
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(side) {
        side.scope(7).width(read("side")) |> ignore
        side.box(fn(row) {
          read_in["row made"] = @view.scope_now()
          row.height(read("row")) |> ignore
        })
        |> ignore
        // (made later, as what shows it changes)
        side.show(fn() { shown.get() }, fn(later) { later.height(read("later")) |> ignore }) |> ignore
      })
      |> ignore
      root.box(fn(page) { page.height(read("page")) |> ignore }) |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(read_in.get("side"), Some(7))
  assert_eq(read_in.get("row made"), Some(7))
  assert_eq(read_in.get("row"), Some(7))
  assert_eq(read_in.get("page"), Some(0))
  assert_eq(@view.scope_now(), 0)
  t.event(10.0, fn() { shown.set(true) })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(read_in.get("later"), Some(7))
  // read again as what they read changes, each in its own
  read_in.clear()
  t.event(20.0, fn() { tone.set(1) })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(read_in.get("row"), Some(7))
  assert_eq(read_in.get("later"), Some(7))
  assert_eq(read_in.get("page"), Some(0))
  assert_eq(@view.scope_now(), 0)
}
