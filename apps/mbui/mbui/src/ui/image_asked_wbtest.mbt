// What asks for a picture's decode in the window's tree (view/env.mbt): what draws the tree, as it comes to a picture's
// node (drawn, or gone through outside what shows), and View::image_ask; never View::image_ready, which only says
// whether one is ready.

///|
/// How long each test runs once its tree is made (any while: its pictures decoded and told by then).
let image_asked_test_ms : Double = 100.0

///|
/// How many times the host was asked to decode `src`.
fn image_asked_count(t : Tester, src : String) -> Int {
  t.image_loads().filter(fn(l) { l.0 == src }).length()
}

///|
test "a node reading whether a picture is ready asks for no decode: none is made for a picture nothing draws" {
  let read : Ref[Bool?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, images=[("p.png", 600, 400)])
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.width(Is(Some(60.0))).height(Is(Some(40.0))) |> ignore
      n.reacts(fn() { n.image_ready("p.png", 60.0) }, fn(r) { read.val = Some(r) })
    })
    |> ignore
  })
  t.run_for(image_asked_test_ms)
  assert_eq(read.val, Some(false))
  assert_eq(image_asked_count(t, "p.png"), 0)
}

///|
test "a picture's node has its decode asked by what draws it, in sight or gone through outside what shows, and is told it is ready" {
  let told : Map[String, Bool] = Map([])
  let t = Tester::new(fn(_c) {  }, w=300.0, h=300.0, images=[("seen.png", 600, 400), ("under.png", 600, 400)])
  set_view_app(fn(root) {
    // (what shows: a box the window's size, cutting what it holds to itself)
    root.box(fn(c) {
      c.width(Is(Some(300.0))).height(Is(Some(300.0))).clips(Is(true)) |> ignore
      for at in [("seen.png", 0.0), ("under.png", 3000.0)] {
        let (src, y) = at
        c.box(fn(n) {
          n
          .over(Is(true))
          .offset(Is((0.0, y)))
          .width(Is(Some(60.0)))
          .height(Is(Some(40.0)))
          .image(Is(Some((src, "", 4096))))
          |> ignore
          n.reacts(fn() { n.image_ready(src, 60.0) }, fn(r) { told[src] = r })
        })
        |> ignore
      }
    })
    |> ignore
  })
  t.run_for(image_asked_test_ms)
  for src in ["seen.png", "under.png"] {
    assert_true(image_asked_count(t, src) > 0, msg=src)
    assert_eq(told.get(src), Some(true), msg=src)
  }
  // (the one outside what shows not drawn: its decode asked all the same)
  assert_eq(t.drawn_images().length(), 1)
}
