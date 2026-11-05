// Where the host puts a control of its own (View::native_anchor): handed as each frame ends, where the node is drawn in
// it, following what holds it as that is drawn elsewhere, with nothing handed where it is not drawn.

///|
test "a node's native anchor handed where it is drawn each frame: moved with what holds it, kept where something else changes, none once it is gone" {
  let off = @signals.signal(0.0, same=fn(a, b) { a == b })
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let ink = @signals.signal(0x3366CCFFL, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let heard : Array[Int] = []
  on_native_anchors(fn(_c, a) { heard.push(a.length()) })
  set_view_app(fn(root) {
    root.box(fn(p) { p.height(Is(Some(30.0))).ground(By(fn() { ink.get() })) |> ignore }) |> ignore
    root.box(fn(holder) {
      holder.drawn_off(By(fn() { (off.get(), 0.0) })) |> ignore
      holder.show(fn() { shown.get() }, fn(k) {
        k.box(fn(a) {
          a.width(Is(Some(40.0))).height(Is(Some(20.0))).native_anchor(Is("glass")) |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
  t.draw()
  let first = native_anchor_drawn("glass")
  off.set(25.0)
  t.frame()
  let moved = native_anchor_drawn("glass")
  ink.set(0xCC3333FFL)
  t.frame()
  let kept = native_anchor_drawn("glass")
  shown.set(false)
  t.frame()
  let gone = native_anchors()
  assert_eq(
    (first, moved, kept, gone.length(), heard.length() > 0),
    (Some((0.0, 30.0, 40.0, 20.0)), Some((25.0, 30.0, 40.0, 20.0)), Some((25.0, 30.0, 40.0, 20.0)), 0, true),
  )
}
