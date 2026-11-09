// The spacing rules (gaps.mbt) measure nothing in what scrolls: in an old box that scrolls (Ctx::capped, a sideways
// one) and in what a node of the window's tree scrolls (View::scrolls' held), an old view hosted there; what stands
// beside what a node scrolls in it (put there after it, staying as that moves) measured as ever.

///|
/// Two blocks 3 apart (off the spacing scale), each 100×20 with a ground.
fn off_scale_pair(c : Ctx) -> Unit {
  c.box(gap=3.0, fn() {
    c.box(w=Px(100.0), h=Px(20.0), bg=0x336699FFL, fn() {  }) |> ignore
    c.box(w=Px(100.0), h=Px(20.0), bg=0x336699FFL, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// Whether the spacing rules find the pair 3 apart (rule 6) where it is put: `how` 0 the old frame's, as it is; 1 in an old
/// box that scrolls; 2 an old view hosted in what a node of the tree scrolls; 3 an old view hosted beside that, in the
/// node that scrolls, put there after what it scrolls.
fn off_scale_found(how : Int) -> Bool {
  let t = if how < 2 {
    Tester::new(
      fn(c) {
        if how == 0 {
          off_scale_pair(c)
        } else {
          c.capped("pair", 200.0, fn() { off_scale_pair(c) }) |> ignore
        }
      },
      w=400.0,
      h=300.0,
    )
  } else {
    let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
    set_view_app(fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(200.0))).height(Is(Some(200.0))) |> ignore
        o.scrolls(@view.Scroll::new(), fn(s) {
          if how == 2 {
            old(s, natural=true, fn(c) { off_scale_pair(c) }) |> ignore
          }
        })
        |> ignore
        if how == 3 {
          o.box(fn(f) {
            f.over(Is(true)).width(Is(Some(200.0))) |> ignore
            old(f, natural=true, fn(c) { off_scale_pair(c) }) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    t
  }
  t.frame()
  t.gap_faults().iter().any(fn(f) { f.has_prefix("rule 6") })
}

///|
test "the spacing rules: a pair 3 apart found as it is; not in an old box that scrolls, nor in an old view in what a node scrolls; found again beside that, in the node that scrolls" {
  assert_eq((off_scale_found(0), off_scale_found(1), off_scale_found(2), off_scale_found(3)), (true, false, false, true))
}
