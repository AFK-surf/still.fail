// A capture checks the failed pictures the current frame needs, not every failure still held in the cache.

///|
fn failed_drawn_sources(t : Tester) -> Array[String] {
  t.failed_images_drawn().map(fn(id) { t.image_src(id) })
}

///|
test "an old view's failed picture is reported while shown, not after it leaves, and again when it returns" {
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let t = Tester::new(fn(c) {
    if shown.get() {
      c.image("missing.png", w=Px(50.0), h=Px(50.0), fade=false) |> ignore
    }
  }, w=100.0, h=100.0)
  assert_eq(failed_drawn_sources(t), ["missing.png"])
  shown.set(false)
  t.draw()
  assert_true(!t.failed_images().is_empty(), msg="the decode is still cached")
  assert_eq(failed_drawn_sources(t), [])
  shown.set(true)
  t.draw()
  assert_eq(failed_drawn_sources(t), ["missing.png"])
  t.frame()
  assert_eq(failed_drawn_sources(t), ["missing.png"])
}

///|
test "a window tree's failed picture is reported only while the tree draws it" {
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=100.0, h=100.0)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.width(Is(Some(50.0)))
      .height(Is(Some(50.0)))
      .image(By(fn() { if shown.get() { Some(("missing.png", "", 4096)) } else { None } }))
      |> ignore
    }) |> ignore
  })
  t.draw()
  assert_eq(failed_drawn_sources(t), ["missing.png"])
  shown.set(false)
  t.draw()
  assert_true(!t.failed_images().is_empty(), msg="the decode is still cached")
  assert_eq(failed_drawn_sources(t), [])
  shown.set(true)
  t.draw()
  assert_eq(failed_drawn_sources(t), ["missing.png"])
}
