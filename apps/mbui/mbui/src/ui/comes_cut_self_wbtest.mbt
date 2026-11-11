// What makes its way in or out (view's View::comes) is cut to itself as it goes, its own words with what it holds
// (Content::clips_self): words said on the very node a structure makes, down a column or along a row, drawn no
// further than its way has got, never over the words beside it or under it. Judged frame to frame at 60 and 120
// (words over words), and looked at at each moment said.

///|
/// The moments looked at after each change (ms).
let cut_self_moments : Array[Double] = [10.0, 40.0, 90.0, 160.0, 260.0, 600.0]

///|
/// Shown, then let go, at the moments said after each: no words over words at any of them.
fn cut_self_walk(t : Tester, on : @signals.Signal[Bool]) -> Unit raise {
  t.run_for(cut_self_before)
  for showing in [true, false] {
    let asked = t.time()
    on.set(showing)
    for m in cut_self_moments {
      t.run_for(asked + m - t.time())
      let over = t.words_over_now()
      assert_true(over.is_empty(), msg="\{if showing { "shown" } else { "let go" }} at \{m}: \{Repr(over)}")
    }
  }
}

///|
/// How long a test runs before it shows it (any while: at rest by then).
let cut_self_before : Double = 100.0

///|
test "shown down a column, its words on itself: cut to its way, never over the words under it" {
  let on = @signals.signal(false)
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.show(fn() { on.get() }, fn(v) { v.words(Is("出现的字")) |> ignore })
    root.box(fn(b) { b.words(Is("下面的字")) |> ignore }) |> ignore
  })
  cut_self_walk(t, on)
}

///|
test "shown along a row, its words on itself: cut to its way, never over the words after it" {
  let on = @signals.signal(false)
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      r.box(fn(b) { b.width(Is(Some(20.0))).words(Is("左")) |> ignore }) |> ignore
      r.show(along_row=true, fn() { on.get() }, fn(v) { v.words(Is("出现的字")) |> ignore })
      r.box(fn(b) { b.words(Is("右边的字")) |> ignore }) |> ignore
    })
    |> ignore
  })
  cut_self_walk(t, on)
}
