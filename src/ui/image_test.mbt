///|
test "an image loads at the size it is shown, fades in, and is cropped to cover" {
  let t = @ui.Tester::new(
    fn(c) {
      c.column(fn() {
        c.image("cover.jpg", w=Px(100.0), h=Px(150.0), radius=8.0) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=400.0,
    images=[("cover.jpg", 1200, 900)],
  )
  // 150 points at 2x: 300 pixels, decoded at 512
  assert_eq(t.image_loads(), [("cover.jpg", 512)])
  t.frame()
  let first = t.drawn_images()
  assert_eq(first.length(), 1)
  let im = first[0]
  // a 4:3 picture in a 2:3 box: the middle half of its width
  assert_eq((im[0], im[1], im[2], im[3]), (0.0, 0.0, 100.0, 150.0))
  assert_eq((im[4], im[5], im[6], im[7]), (0.25, 0.0, 0.5, 1.0))
  assert_true(im[8] < 1.0)
  t.settle() |> ignore
  assert_eq(t.drawn_images()[0][8], 1.0)
}

///|
test "an image with a free height takes its proportions once known" {
  let t = @ui.Tester::new(
    fn(c) {
      c.column(w=Px(200.0), fn() {
        c.image("photo.jpg") |> ignore
        c.text("caption", wrap=false) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=400.0,
    images=[("photo.jpg", 4000, 3000)],
  )
  t.draw()
  let (_, y, _, _) = t.rect_of("caption").unwrap()
  assert_eq(y, 150.0)
  let im = t.drawn_images()[0]
  assert_eq((im[2], im[3]), (200.0, 150.0))
  // 200 points at 2x is 400 pixels, so 512
  assert_eq(t.image_loads(), [("photo.jpg", 512)])
}

///|
test "a bigger box loads a sharper decode, showing the small one meanwhile" {
  let big = [false]
  let t = @ui.Tester::new(
    fn(c) {
      let s = if big[0] { 300.0 } else { 60.0 }
      c.image("p.png", w=Px(s), h=Px(s)) |> ignore
    },
    w=400.0,
    h=400.0,
    images=[("p.png", 2000, 2000)],
  )
  t.draw()
  big[0] = true
  t.frame()
  assert_eq(t.image_loads(), [("p.png", 128), ("p.png", 1024)])
  // the small decode stands in this frame
  assert_eq(t.drawn_images().length(), 1)
}

///|
test "contain letterboxes; a missing image draws only its background" {
  let t = @ui.Tester::new(
    fn(c) {
      c.row(fn() {
        c.image("wide.jpg", w=Px(100.0), h=Px(100.0), fit=FitContain) |> ignore
        c.image("missing.jpg", w=Px(100.0), h=Px(100.0)) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=400.0,
    images=[("wide.jpg", 400, 200)],
  )
  t.draw()
  let ims = t.drawn_images()
  assert_eq(ims.length(), 1)
  assert_eq((ims[0][0], ims[0][1], ims[0][2], ims[0][3]), (0.0, 25.0, 100.0, 50.0))
}

///|
test "what is shown is settled once the images it waits on are in, as the test says when" {
  let view = fn(c : @ui.Ctx) {
    c.column(fn() {
      c.image("a.jpg", w=Px(100.0), h=Px(100.0)) |> ignore
      c.image("b.jpg", w=Px(100.0), h=Px(100.0)) |> ignore
    })
    |> ignore
  }
  let t = @ui.Tester::new(view, images=[("a.jpg", 400, 400), ("b.jpg", 400, 400)], finish=false)
  for _ in 0..<5 {
    t.frame()
  }
  assert_eq(t.pending(), [(1, 1), (1, 2)])
  assert_false(t.settled())
  assert_eq(t.awaited(), ["image 1 a.jpg", "image 2 b.jpg"])
  t.finish(1, 2)
  t.settle() |> ignore
  assert_eq(t.awaited(), ["image 1 a.jpg"])
  assert_false(t.settled())
  t.finish(1, 1, ok=false)
  t.settle() |> ignore
  assert_eq(t.pending(), [])
  assert_true(t.settled())
}

///|
test "finish_all brings what is pending in an order drawn from the seed" {
  let names = ["a.jpg", "b.jpg", "c.jpg", "d.jpg"]
  let view = fn(c : @ui.Ctx) {
    c.column(fn() {
      for n in names {
        c.image(n, w=Px(50.0), h=Px(50.0)) |> ignore
      }
    })
    |> ignore
  }
  let run = fn(seed : Int) -> @ui.Tester {
    let t = @ui.Tester::new(view, images=names.map(n => (n, 100, 100)), seed~, finish=false)
    t.frame()
    t.finish_all()
    t.settle() |> ignore
    t
  }
  let t7 = run(7)
  assert_eq(t7.pending(), [])
  assert_true(t7.settled())
  assert_eq(t7.finished_order(), run(7).finished_order())
  let orders = [1, 2, 3, 4, 5, 6, 7, 8].map(s => run(s).finished_order())
  assert_true(orders.iter().any(o => o != orders[0]))
}
