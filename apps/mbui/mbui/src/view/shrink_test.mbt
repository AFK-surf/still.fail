// How much a node gives way (View::shrink) and how wide it is at least (View::min_width): each its own binding to its
// own field, whichever is said first, whatever the other is changed to after.

///|
/// A row 100 wide holding two boxes 80 wide, the second giving no way, the first giving way by `share`, at least `least` wide (said before its
/// share where `least_first`): how wide the first is laid out as `share` goes from 1 to 0.5 to 0.
fn shrunk_widths(least : Double?, least_first : Bool) -> Array[Double] {
  let share = @signals.signal(1.0, same=fn(a, b) { a == b })
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(row) {
        row.row(Is(true)).width(Is(Some(100.0))) |> ignore
        row.box(fn(a) {
          id.val = Some(a.id())
          a.width(Is(Some(80.0))).height(Is(Some(10.0))) |> ignore
          if least_first {
            a.min_width(Is(least)).shrink(By(fn() { share.get() })) |> ignore
          } else {
            a.shrink(By(fn() { share.get() })).min_width(Is(least)) |> ignore
          }
        })
        |> ignore
        row.box(fn(b) { b.width(Is(Some(80.0))).height(Is(Some(10.0))).shrink(Is(0.0)) |> ignore }) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let out = []
  t.frame(400.0, 300.0) |> ignore
  out.push(t.drawn_of(id.val.unwrap()).unwrap().w)
  for i, s in [0.5, 0.0] {
    t.event(10.0 * (i + 1).to_double(), fn() { share.set(s) })
    t.frame(400.0, 300.0) |> ignore
    out.push(t.drawn_of(id.val.unwrap()).unwrap().w)
  }
  out
}

///|
test "shrink and min_width: a node at least 60 wide gives way to 60, its share changed or not, said before or after its share; at least nothing, to nothing (by half where it gives half); giving no way, as wide as it is" {
  let got = shrunk_widths(Some(60.0), false)
  assert_eq(got, [60.0, 60.0, 80.0], msg="least said after its share: \{got}")
  let got = shrunk_widths(Some(60.0), true)
  assert_eq(got, [60.0, 60.0, 80.0], msg="least said before its share: \{got}")
  let got = shrunk_widths(Some(0.0), false)
  // (its share half: half of what the row is short of given way, as flexbox gives where the shares come to less than 1)
  assert_eq(got, [20.0, 50.0, 80.0], msg="at least nothing: \{got}")
}
