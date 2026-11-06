// What a field of the window's tree draws over everything (its caret's handle, Android's: Ctx::paint_top) is its
// layer's tops, put where the window's stack raises them (scene_layers.mbt): the frame put together with it in layers
// held in layers, a sibling of them drawn again each frame, comes to what drawing all of it anew comes to (the Tester's
// check of every frame), the handle over everything in it, after all the rest.

///|
test "a field's handle over everything, the field in layers held in layers, a sibling drawn again each frame: as drawn anew, the handle last" {
  let f = Field::new()
  f.set("hello world")
  let tint = @signals.signal(0x336699FFL)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=2)
  set_view_app(fn(root) {
    // (a layer of its own (moved off), holding another (faded), holding the field)
    root.box(fn(outer) {
      outer.offset(Is((10.0, 10.0))).width(Is(Some(220.0))).height(Is(Some(100.0))) |> ignore
      outer.box(fn(inner) {
        inner.alpha(Is(0.9)).width(Is(Some(200.0))).height(Is(Some(60.0))) |> ignore
        field(inner, f, font_size=12.0, max_lines=1) |> ignore
      })
      |> ignore
    })
    |> ignore
    // (a sibling of them over it, drawn again each frame)
    root.box(fn(s) {
      s.offset(Is((0.0, 150.0))).width(Is(Some(300.0))).height(Is(Some(40.0))).ground(By(fn() { tint.get() })) |> ignore
    })
    |> ignore
  })
  t.draw()
  t.tap(40.0, 18.0)
  t.clock_frame()
  for i in 0..<4 {
    tint.set(if i % 2 == 0 { 0x993366FFL } else { 0x336699FFL })
    t.clock_frame()
  }
  // (the handle drawn, and after everything else of the frame: the last instances are its)
  let c = g()
  let mut last_rect = -1
  for k in 0..<c.ninst {
    if c.inst[k * inst_size + 5] == 0.0 && c.inst[k * inst_size + 2] == 2.0 * handle_r {
      last_rect = k
    }
  }
  assert_true(last_rect >= 0, msg="no handle drawn")
  let mut after = 0
  for k in (last_rect + 1)..<c.ninst {
    if c.inst[k * inst_size + 5] != 12.0 {
      after = after + 1
    }
  }
  // (only the handle's own square corner after its circle; none of the rest)
  assert_true(after <= 1, msg="\{after} instances after the handle")
}
