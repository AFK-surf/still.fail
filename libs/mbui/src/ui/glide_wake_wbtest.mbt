///|
/// A page's list flung and let come to rest, on a host keeping groups and on one keeping none: the app at rest, waiting
/// for nothing (the list's heads' wake at the glide's end was said waited for, and a frame of the looks alone never put
/// it down: Tester's frames on every display frame after the rest at a rate, at_rest never true, till 2026-11-12).
fn glide_rest_why(groups : Bool) -> String {
  let list = @view.Scroll::list()
  let t = Tester::new(fn(_c) {  }, w=300.0, h=400.0, platform=0)
  t.set_rows_on_pixels(true)
  t.set_groups(groups)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(list, fn() { Array::makei(40, fn(i) { i }) }, est=40.0, follows=fn() { true }, fn(
        b,
        k,
      ) {
        b.box(fn(r) { r.height(Is(Some(40.0))).ground(Is(0xFF336699L)).words(Is("row \{k}")) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drag(150.0, 50.0, 150.0, 250.0, steps=20)
  // (on to the glide's own end, as the list says it, and no further: what is left waited for there is what keeps the
  // app from its rest)
  guard list.glides_till() is Some(end) else { return "not flung: no glide" }
  t.run_for(end - t.time())
  t.rest_why()
}

///|
test "a list flung comes to rest on a host keeping groups as on one keeping none" {
  inspect(glide_rest_why(false), content="")
  inspect(glide_rest_why(true), content="")
}
