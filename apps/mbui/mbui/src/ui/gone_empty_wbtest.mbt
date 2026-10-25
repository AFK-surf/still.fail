// A box said to be `gone_empty` (Ctx::box) takes no room while it holds nothing, its padding and margins none, and
// all of them while it holds something.

///|
test "a box gone_empty: none of its room while it holds nothing, all of it while it holds something" {
  let holds = Ref(false)
  let t = Tester::new(
    fn(c) {
      c.box(fn() {
        c.box(pt=18.0, pb=24.0, mt=4.0, gone_empty=true, fn() {
          if holds.val {
            c.text("里面") |> ignore
          }
        })
        |> ignore
        c.text("下面") |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=200.0,
  )
  t.frame()
  let (_, y, _, _) = t.rect_of("下面").unwrap()
  assert_eq(y, 0.0)
  holds.val = true
  t.frame()
  let (_, iy, _, ih) = t.rect_of("里面").unwrap()
  let (_, y, _, _) = t.rect_of("下面").unwrap()
  assert_eq(iy, 22.0)
  assert_eq(y, iy + ih + 24.0)
}
