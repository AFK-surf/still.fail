// What a structure shows or lets go along a row, said `along_row` (view's along_row.mbt), as a host draws it: where
// what is after it stands at each moment said is its way's (flex's come_way) from the moment of its cause, at any
// frame rate, and judged frame to frame on the way (MBUI_TEST_MOTION).

///|
/// Where the words `w` are drawn across (x), and how wide.
fn along_row_at(t : Tester, w : String) -> (Double, Double)? {
  match t.words().iter().find_first(fn(d) { d.0 == w }) {
    Some(d) => Some((d.1, d.3))
    None => None
  }
}

///|
/// The moments looked at after the cause (ms), the last past the way's end.
let along_row_moments : Array[Double] = [20.0, 60.0, 120.0, 200.0, 400.0]

///|
test "shown and let go along a row, said so: what is after it where its way has it at each moment, at any frame rate" {
  let on = @signals.signal(false)
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("左")) |> ignore }) |> ignore
      // (its words in what it holds, cut by it as it makes its way: a box's own words are drawn whole, uncut)
      r.show(along_row=true, fn() { on.get() }, fn(v) {
        v.width(Is(Some(30.0))) |> ignore
        v.box(fn(w) { w.words(Is("旁")) |> ignore }) |> ignore
      })
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("右")) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.run_for(along_row_before)
  let x0 = along_row_at(t, "左").unwrap().0
  for showing in [true, false] {
    let asked = t.time()
    on.set(showing)
    for m in along_row_moments {
      t.run_for(asked + m - t.time())
      let (way, _) = @flex.come_way(if showing { 0.0 } else { 30.0 }, 0.0, if showing { 30.0 } else { 0.0 }, m)
      let x = along_row_at(t, "右").unwrap().0
      // (what it holds laid out whole at the width it comes to, all along)
      match along_row_at(t, "旁") {
        Some((_, w)) => assert_true(w == 30.0, msg="旁 laid out \{w} wide at \{m}")
        None => ()
      }
      assert_true((x - (x0 + 20.0 + way)).abs() <= 0.5, msg="\{if showing { "shown" } else { "let go" }} at \{m}: 右 at \{x}, its way \{way}")
    }
  }
  assert_true(along_row_at(t, "旁") is None)
}

///|
/// How long the test runs before it shows it (any while: at rest by then).
let along_row_before : Double = 100.0
