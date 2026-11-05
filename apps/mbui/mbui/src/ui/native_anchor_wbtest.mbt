// Where the host puts a control of its own (View::native_anchor): handed as each frame ends, where the node is drawn in
// it, following what holds it as that is drawn elsewhere, with nothing handed where it is not drawn or not seen, and
// nothing of the window drawn again for where it is.

///|
test "a node's native anchor handed where it is drawn each frame: moved with what holds it, kept where something else changes, none once it is gone" {
  let off = @signals.signal(0.0, same=fn(a, b) { a == b })
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let ink = @signals.signal(0x3366CCFFL, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let heard : Array[Int] = []
  on_native_anchors("test", fn(_c, a) { heard.push(a.length()) })
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

///|
test "a native anchor that alone moves draws nothing of the window again" {
  let off = @signals.signal(0.0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(p) { p.height(Is(Some(30.0))).ground(Is(0x3366CCFFL)) |> ignore }) |> ignore
    root.box(fn(a) {
      a
      .width(Is(Some(40.0)))
      .height(Is(Some(20.0)))
      .native_anchor(Is("glass"))
      .drawn_off(By(fn() { (off.get(), 0.0) }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.frame()
  t.record_host()
  off.set(60.0)
  t.frame()
  let frames = t.host_frames()
  assert_eq(
    (native_anchor_drawn("glass"), frames.length() > 0, frames.map(fn(f) { f.damage }).filter(fn(d) { !d.is_empty() })),
    (Some((60.0, 30.0, 40.0, 20.0)), true, []),
    msg="\{frames}",
  )
}

///|
test "a native anchor cut out of sight by what holds it is handed none, and again where it comes back into it" {
  let off = @signals.signal(0.0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(holder) {
      holder.width(Is(Some(100.0))).height(Is(Some(50.0))).clips(Is(true)) |> ignore
      holder.box(fn(a) {
        a
        .width(Is(Some(40.0)))
        .height(Is(Some(20.0)))
        .native_anchor(Is("glass"))
        .drawn_off(By(fn() { (off.get(), 0.0) }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let seen = native_anchor_drawn("glass")
  off.set(80.0)
  t.frame()
  let cut = native_anchor_drawn("glass")
  off.set(200.0)
  t.frame()
  let out = native_anchors()
  off.set(0.0)
  t.frame()
  assert_eq(
    (seen, cut, out.length(), native_anchor_drawn("glass")),
    (Some((0.0, 0.0, 40.0, 20.0)), Some((80.0, 0.0, 20.0, 20.0)), 0, Some((0.0, 0.0, 40.0, 20.0))),
  )
}
