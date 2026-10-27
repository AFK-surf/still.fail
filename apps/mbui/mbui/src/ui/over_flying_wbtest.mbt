// put_over's 2 under what is over it (Ctx::over_flying): what flies from the composer to the list is drawn over the
// composer and under the bar over the list, as what it lands in is; with nothing said to be over it, over everything.

///|
/// A page of a box 50 by 30 flying (put_over's 2), a composer 60 by 20 after it, then a bar 70 by 40, said to be over
/// what flies with `bar_over`.
fn flying_page(bar_over : Bool) -> (Ctx) -> Unit {
  fn(c) {
    c.column(fn() {
      let b = c.box(w=Px(50.0), h=Px(30.0), bg=0x336699FFL, fn() {  })
      c.put_over(b, z=2)
      c.layer(fn() { c.box(w=Px(60.0), h=Px(20.0), bg=0x993366FFL, fn() {  }) |> ignore }) |> ignore
      let bar = c.layer(fn() { c.box(w=Px(70.0), h=Px(40.0), bg=0x669933FFL, fn() {  }) |> ignore })
      if bar_over {
        c.over_flying(bar)
      }
    })
    |> ignore
  }
}

///|
test "what flies is drawn over what was built after it and under what is said to be over it" {
  let t = Tester::new(flying_page(true), w=400.0, h=300.0)
  t.frame()
  let flying = painted_at(50.0, 30.0)
  let composer = painted_at(60.0, 20.0)
  let bar = painted_at(70.0, 40.0)
  assert_true(flying >= 0 && composer >= 0 && bar >= 0)
  assert_true(composer < flying)
  assert_true(flying < bar)
}

///|
test "with nothing said to be over it, what flies is drawn over everything" {
  let t = Tester::new(flying_page(false), w=400.0, h=300.0)
  t.frame()
  let flying = painted_at(50.0, 30.0)
  let bar = painted_at(70.0, 40.0)
  assert_true(flying >= 0 && bar >= 0)
  assert_true(bar < flying)
}
