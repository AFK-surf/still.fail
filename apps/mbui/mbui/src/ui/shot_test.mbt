// mbui's shots (shot.mbt): what a view builds drawn whole as one PNG, however long, never on the screen.

///|
fn png_be32(a : Array[Byte], at : Int) -> Int {
  (a[at].to_int() << 24) | (a[at + 1].to_int() << 16) | (a[at + 2].to_int() << 8) | a[at + 3].to_int()
}

///|
test "a shot six windows tall: one PNG of it all at the window's scale, taken in the frame it was asked in, none of it on the screen" {
  let take = Ref::new(false)
  let got : Ref[Bytes?] = Ref::new(None)
  let told = Ref::new(0)
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Px(40.0), bg=0xFF0000FFL, fn() {  }) |> ignore
      if take.val {
        take.val = false
        c.take_shot("long", fn(png) {
          got.val = png
          told.val = told.val + 1
        })
      }
      c.shot("long", 150.0, fn() {
        for i in 0..<30 {
          c.box(w=Fill(1.0), h=Px(25.0), bg=0x336699FFL, fn() { c.text("row \{i}") |> ignore }) |> ignore
        }
      })
    },
    w=200.0,
    h=120.0,
    scale=2.0,
  )
  let before = t.instances()
  take.val = true
  t.draw()
  assert_eq(told.val, 1)
  let png = got.val.unwrap().to_array()
  assert_eq(png[1:4].to_array(), [b'P', b'N', b'G'])
  // 150 × 750 points, two pixels a point
  assert_eq((png_be32(png, 16), png_be32(png, 20)), (300, 1500))
  // what the screen shows is as it was; the shot's words are nowhere once it is taken
  assert_eq(t.instances(), before)
  assert_true(t.find("row 3") is None)
  t.assert_idle()
}

///|
test "a shot whose view no longer builds it is let go, never told" {
  let take = Ref::new(false)
  let shown = Ref::new(true)
  let told = Ref::new(0)
  let t = @ui.Tester::new(
    fn(c) {
      if take.val {
        take.val = false
        c.take_shot("gone", fn(_) { told.val = told.val + 1 })
      }
      if shown.val {
        c.text("here") |> ignore
      }
    },
    w=200.0,
    h=120.0,
  )
  take.val = true
  t.draw()
  t.draw()
  assert_eq(told.val, 0)
  t.assert_idle()
  ignore(shown)
}
