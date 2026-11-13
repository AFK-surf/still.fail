// What a structure said `at_once` notes as it makes or lets go by a change (at_once_said.mbt): a show going and coming,
// a pick put in another's place, each by how much what holds it came out taller; none as it is first made; none kept
// where the tree keeps no sources.

///|
/// A column holding a show said at once (22 tall while `on`) and a pick said at once (as tall as 10 times its key and
/// 10), in a tree keeping sources where `sources`; drawn once.
fn aos_case(
  on : @signals.Signal[Bool],
  which : @signals.Signal[Int],
  sources : Bool,
) -> @view.Tree {
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(col) {
        col.show(fn() { on.get() }, at_once=true, fn(p) { p.height(Is(Some(22.0))).shrink(Is(0.0)) |> ignore })
        col.pick(fn() { which.get() }, at_once=true, fn(p, k) {
          p.height(Is(Some(10.0 * k.to_double() + 10.0))).shrink(Is(0.0)) |> ignore
        })
      })
      |> ignore
    },
    time=fn() { 0.0 },
    sources~,
  )
  t.frame(300.0, 200.0) |> ignore
  t
}

///|
/// What was noted since the `after`th, each by how much: the moments left out.
fn aos_since(t : @view.Tree, after : Int) -> Array[Double] {
  t.at_once_said_since(after).map(fn(c) { c.2 })
}

///|
test "at once said: a show said at once going and coming, a pick at once put in another's place: each noted by how much what holds it came out taller; none as first made; none where no sources are kept" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let which = @signals.signal(0, same=fn(a, b) { a == b })
  let t = aos_case(on, which, true)
  // (as first made: none)
  assert_eq(t.at_once_said_count(), 0)
  on.set(false)
  t.frame(300.0, 200.0) |> ignore
  assert_eq(aos_since(t, 0), [-22.0])
  let n = t.at_once_said_count()
  on.set(true)
  t.frame(300.0, 200.0) |> ignore
  assert_eq(aos_since(t, n), [22.0])
  let n = t.at_once_said_count()
  which.set(2)
  t.frame(300.0, 200.0) |> ignore
  assert_eq(aos_since(t, n), [20.0])
  assert_eq(aos_since(t, t.at_once_said_count()), [])
  // (no sources kept: none)
  let on2 = @signals.signal(true, same=fn(a, b) { a == b })
  let t2 = aos_case(on2, @signals.signal(0), false)
  on2.set(false)
  t2.frame(300.0, 200.0) |> ignore
  assert_eq(t2.at_once_said_count(), 0)
}
