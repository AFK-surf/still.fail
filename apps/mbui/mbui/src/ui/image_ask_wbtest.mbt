// View::image_ask (view/env.mbt): a picture asked to be decoded before any node of it is drawn.

///|
test "View::image_ask asks for it: a node whose picture is made only once it is decoded is told it is, and draws it" {
  let told : Ref[Double] = Ref(-1.0)
  let t = Tester::new(fn(_c) {  }, images=[("p.png", 600, 400)])
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.width(Is(Some(60.0))).height(Is(Some(40.0))) |> ignore
      let ready = fn() {
        n.image_ask("p.png", 60.0)
        n.image_ready("p.png", 60.0)
      }
      n.show(ready, fn(p) {
        p.width(Is(Some(60.0))).height(Is(Some(40.0))).image(Is(Some(("p.png", "", 4096)))) |> ignore
      })
      n.reacts(ready, fn(r) {
        if r && told.val < 0.0 {
          told.val = n.cause_at()
        }
      })
    })
    |> ignore
  })
  t.run_for(image_asked_test_ms)
  assert_true(told.val >= 0.0, msg="never told it is decoded")
  assert_true(image_asked_count(t, "p.png") > 0)
  assert_eq(t.drawn_images().length(), 1)
}
