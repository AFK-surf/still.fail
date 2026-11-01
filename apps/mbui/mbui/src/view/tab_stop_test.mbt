// Tab's stop on a node said as it changes (View::tab_stop): the last said of it holds (said again, what was said
// before let go of; View::focusable said after it, its `tab`); whether the node takes the focus changing leaves it
// alone; a node let go of, nothing of what was said of it lives on in what is made in its place.

///|
/// Whether node `id` is among the stops of Tab's (Tree::focus_order).
fn tab_has(t : @view.Tree, id : @view.NodeId) -> Bool {
  t.focus_order().iter().any(fn(f) { f.id == id })
}

///|
test "tab_stop: said twice, the first's condition changing after does nothing; the second's, the stop" {
  let (a, b) = (@signals.signal(true), @signals.signal(false))
  let ids : Map[String, @view.NodeId] = {}
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(x) {
        ids["x"] = x.id()
        x.focusable(Is(true), tab=false).tab_stop(By(fn() { a.get() })).tab_stop(By(fn() { b.get() })) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let x = ids["x"]
  let said = tab_has(t, x)
  a.set(false)
  t.frame(390.0, 844.0) |> ignore
  a.set(true)
  t.frame(390.0, 844.0) |> ignore
  let first_changed = tab_has(t, x)
  b.set(true)
  t.frame(390.0, 844.0) |> ignore
  assert_eq((said, first_changed, tab_has(t, x)), (false, false, true))
}

///|
test "tab_stop: said after focusable, whether the node takes the focus going off and on again: a stop again, as tab_stop says" {
  let on = @signals.signal(true)
  let ids : Map[String, @view.NodeId] = {}
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(x) {
        ids["x"] = x.id()
        x.focusable(By(fn() { on.get() }), tab=false).tab_stop(Is(true)) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let x = ids["x"]
  let first = tab_has(t, x)
  on.set(false)
  t.frame(390.0, 844.0) |> ignore
  let off = tab_has(t, x)
  on.set(true)
  t.frame(390.0, 844.0) |> ignore
  assert_eq((first, off, tab_has(t, x)), (true, false, true))
}

///|
test "tab_stop: focusable said after it, its tab holds, tab_stop's condition changing after does nothing" {
  let c = @signals.signal(false)
  let ids : Map[String, @view.NodeId] = {}
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(x) {
        ids["x"] = x.id()
        x.tab_stop(By(fn() { c.get() })).focusable(Is(true)) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let x = ids["x"]
  let first = tab_has(t, x)
  c.set(true)
  t.frame(390.0, 844.0) |> ignore
  c.set(false)
  t.frame(390.0, 844.0) |> ignore
  assert_eq((first, tab_has(t, x)), (true, true))
}

///|
test "tab_stop: its node let go of, one made after in its place, said to take the focus with Tab: the old condition changing does nothing to it" {
  let (one, two, c) = (@signals.signal(true), @signals.signal(false), @signals.signal(false))
  let ids : Map[String, @view.NodeId] = {}
  let t = @view.Tree::new(
    fn(root) {
      root.show(fn() { one.get() }, fn(x) {
        ids["one"] = x.id()
        x.focusable(Is(true), tab=false).tab_stop(By(fn() { c.get() })) |> ignore
      })
      root.show(fn() { two.get() }, fn(y) {
        ids["two"] = y.id()
        y.focusable(Is(true)) |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  one.set(false)
  t.frame(390.0, 844.0) |> ignore
  two.set(true)
  t.frame(390.0, 844.0) |> ignore
  let y = ids["two"]
  let made = tab_has(t, y)
  c.set(true)
  t.frame(390.0, 844.0) |> ignore
  c.set(false)
  t.frame(390.0, 844.0) |> ignore
  assert_eq((made, tab_has(t, y), ids["one"].at == y.at), (true, true, true), msg="one at \{ids["one"].at} two at \{y.at}")
}
