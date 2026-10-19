///|
/// The view made once, on the tester's first frame (the fake host is in place by then).
fn once(cell : Ref[@ui.NativeView?], make : () -> @ui.NativeView) -> @ui.NativeView {
  match cell.val {
    Some(v) => v
    None => {
      let v = make()
      cell.val = Some(v)
      v
    }
  }
}

///|
test "a native view shows where it is painted: a hole in the canvas, the host told where, hidden when not painted" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let shown : Ref[Bool] = { val: true }
  let t = @ui.Tester::new(
    fn(c) {
      let v = once(cell, fn() {
        @ui.NativeView::video("video/mp4", fn(_offset, _length, answer) { answer(b"", -1.0) })
      })
      c.box(w=Fill(1.0), h=Fill(1.0), bg=0x000000FFL, fn() {
        c.box(h=Px(100.0), fn() { () }) |> ignore
        if shown.val {
          // a picture of 300 × 200 at (20, 10) in a box of 390 × 220, over which a bar is painted
          c.native(v, h=Px(220.0), content=Some((20.0, 10.0, 300.0, 200.0))) |> ignore
          c.box(h=Px(40.0), w=Fill(1.0), bg=0x121214D9L, ty=-40.0, fn() { () }) |> ignore
        }
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
  )
  let v = cell.val.unwrap()
  assert_true(v.here())
  assert_eq(t.holes(), [(20.0, 110.0, 300.0, 200.0)])
  // the host placed it: its content, its clip (the node), shown
  assert_true(t.views().contains("place 1 20 110 300 200 in 0 100 390 320"))
  // ready at once on the fake host: its picture's size known
  assert_eq(v.state(), 1)
  assert_eq(v.natural(), (640.0, 360.0))
  // not painted: hidden, no hole
  shown.val = false
  t.frame()
  assert_eq(t.holes().length(), 0)
  assert_true(t.views().iter().any(fn(l) { l.has_suffix("hidden") }))
  v.play()
  v.seek(2500.0)
  assert_true(t.views().contains("control 1 1 0"))
  assert_true(t.views().contains("control 1 3 2500"))
  v.close()
  assert_true(t.views().contains("close 1"))
}

///|
test "a native view inside a clip shows only in it: its hole cut to the clip" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let t = @ui.Tester::new(
    fn(c) {
      let v = once(cell, fn() { @ui.NativeView::page("<p>hi</p>") })
      c.box(w=Px(200.0), h=Px(100.0), clip=true, fn() {
        c.native(v, w=Px(300.0), h=Px(300.0)) |> ignore
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
  )
  assert_eq(t.holes(), [(0.0, 0.0, 200.0, 100.0)])
  assert_true(t.views().contains("place 1 0 0 300 300 in 0 0 200 100"))
  cell.val.unwrap().close()
}

///|
test "a PDF's pages are images the host draws at the size they are shown" {
  let cell : Ref[@ui.Pdf?] = { val: None }
  let t = @ui.Tester::new(
    fn(c) {
      let pdf = match cell.val {
        Some(p) => p
        None => {
          let p = @ui.Pdf::open(b"%PDF-1.4")
          cell.val = Some(p)
          p
        }
      }
      c.image(pdf.page_src(1), w=Px(306.0), h=Px(396.0)) |> ignore
    },
    w=390.0,
    h=844.0,
  )
  t.draw()
  let pdf = cell.val.unwrap()
  assert_eq(pdf.pages, 3)
  assert_eq(pdf.sizes[0], (612.0, 792.0))
  assert_eq(@ui.image_state(pdf.page_src(1)), 1)
  assert_eq(@ui.image_natural(pdf.page_src(1)), Some((1224.0, 1584.0)))
}
