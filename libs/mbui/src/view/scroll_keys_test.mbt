// A column's keys (scroll_keys.mbt): two columns 100 tall in a window, each of ten rows of 40 (300 to go), the first
// holding a column of its own 40 tall in its third row (five rows of 20: 60 to go), the second a row that takes the
// focus. Each key goes to one column, at once at its moment, by the old view's list's amounts (Ctx::list_key).

///|
priv struct KeysCase {
  tree : @view.Tree
  a : @view.Scroll
  inner : @view.Scroll
  b : @view.Scroll
  b_row : Ref[@view.NodeId?]
}

///|
fn keys_case() -> KeysCase {
  let now = Ref(0.0)
  let a = @view.Scroll::new()
  let inner = @view.Scroll::new()
  let b = @view.Scroll::new()
  let b_row : Ref[@view.NodeId?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
        o.box(fn(v) {
          v
          .height(Is(Some(100.0)))
          .scrolls(a, fn(held) {
            for i in 0..<10 {
              if i == 2 {
                held.box(fn(r) {
                  r
                  .width(Is(Some(300.0)))
                  .height(Is(Some(40.0)))
                  .scrolls(inner, fn(h2) {
                    for _ in 0..<5 {
                      h2.box(fn(q) { q.width(Is(Some(300.0))).height(Is(Some(20.0))) |> ignore }) |> ignore
                    }
                  })
                  |> ignore
                })
                |> ignore
              } else {
                held.box(fn(r) { r.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
              }
            }
          })
          |> ignore
        })
        |> ignore
        o.box(fn(v) {
          v
          .height(Is(Some(100.0)))
          .scrolls(b, fn(held) {
            for i in 0..<10 {
              held.box(fn(r) {
                r.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore
                if i == 0 {
                  r.focusable(Is(true)) |> ignore
                  b_row.val = Some(r.id())
                }
              })
              |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0) |> ignore
  { tree, a, inner, b, b_row }
}

///|
/// Key `code` at `t`, none held (and the facts of the focus: a field's), then a frame: whether one took it.
fn keys_at(k : KeysCase, code : Int, t : Double, facts? : Array[String] = []) -> Bool {
  let took = k.tree.stroke(code, 0, t, from=k.tree.focused_now().0, facts~)
  k.tree.frame(390.0, 844.0) |> ignore
  took
}

///|
test "a column's keys go to the column under the pointer, at once, by the old list's amounts, held at its ends" {
  let k = keys_case()
  // (its second row, clear of its inner column wherever it is scrolled to here)
  k.tree.point_at(150.0, 60.0)
  let took = [
    keys_at(k, 16, 10.0),
    keys_at(k, 6, 20.0),
  ]
  let after_page_line = k.a.at(k.tree)
  let took2 = [keys_at(k, 9, 30.0)]
  let at_foot = k.a.at(k.tree)
  // (at its foot: the key its still, nothing else moved)
  let took3 = [keys_at(k, 16, 40.0), keys_at(k, 15, 50.0)]
  let after_up = k.a.at(k.tree)
  let took4 = [keys_at(k, 8, 60.0), keys_at(k, 5, 70.0)]
  assert_eq(
    (took, after_page_line, took2, at_foot, took3, after_up, took4, k.a.at(k.tree), k.b.at(k.tree)),
    ([true, true], 100.0, [true], 300.0, [true, true], 240.0, [true, true], 0.0, 0.0),
  )
}

///|
test "the column the focus is in takes a column's key before the one under the pointer" {
  let k = keys_case()
  k.tree.point_at(150.0, 10.0)
  ignore(k.tree.focus_to(k.b_row.val))
  let took = keys_at(k, 16, 10.0)
  assert_eq((took, k.a.at(k.tree), k.b.at(k.tree)), (true, 0.0, 60.0))
}

///|
test "a column's keys move nothing while a field has the focus" {
  let k = keys_case()
  k.tree.point_at(150.0, 10.0)
  let took = keys_at(k, 16, 10.0, facts=["Field"])
  assert_eq((took, k.a.at(k.tree)), (false, 0.0))
}

///|
test "a column in a column takes the key under the pointer, and keeps it at its end" {
  let k = keys_case()
  // (its third row, 80 down: the inner column)
  k.tree.point_at(150.0, 90.0)
  let took = [keys_at(k, 6, 10.0), keys_at(k, 9, 20.0), keys_at(k, 6, 30.0)]
  assert_eq((took, k.inner.at(k.tree), k.a.at(k.tree)), ([true, true, true], 60.0, 0.0))
}

///|
test "an old view's list under the pointer keeps a column's key (Tree::on_old_scroll)" {
  let k = keys_case()
  k.tree.on_old_scroll(fn() { true })
  k.tree.point_at(150.0, 10.0)
  let took = keys_at(k, 16, 10.0)
  assert_eq((took, k.a.at(k.tree)), (false, 0.0))
}
