///|
test "a text slot reused as an image then shorter text measures the new words" {
  // Narrow, unwrapped text aborts while taking the ellipsis's prefix. With more room or wrapping it silently
  // draws the old words instead. All three must agree with a layout made afresh.
  for (width, wrap) in [(100.0, false), (600.0, false), (100.0, true)] {
    same_both_ways("text after image", fn() {
      let stage = Ref(0)
      let t = Tester::new(fn(c) {
        c.box(w=Px(width), fn() {
          if stage.val == 1 {
            c.image("x", w=Px(width), h=Px(20.0)) |> ignore
          } else {
            c.text(if stage.val == 0 { "a long line of words that needs an ellipsis" } else { "x" }, wrap~) |> ignore
          }
        }) |> ignore
      }, w=800.0, h=200.0)
      for next in [0, 1, 2, 2] {
        stage.val = next
        t.frame()
      }
    }) |> ignore
  }
}
