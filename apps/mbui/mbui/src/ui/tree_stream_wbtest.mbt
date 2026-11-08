///|
fn stream_node_picture(tree : Bool, fit : Fit, at : (Double, Double, Double, Double)?) -> Array[Array[Double]] raise {
  let slot : Ref[Stream?] = Ref(None)
  let t = Tester::new(fn(c) {
    if !tree {
      match slot.val {
        Some(s) => c.stream(s, w=Px(320.0), h=Px(200.0), fit~, at~, layer=false) |> ignore
        None => ()
      }
    }
  }, w=400.0, h=300.0, h264=true)
  let acknowledgements : Array[Double] = []
  let stream = Stream::new(shown=fn(ts) { acknowledgements.push(ts) }, broken=fn() {  })
  slot.val = Some(stream)
  let builds = Ref(0)
  if tree {
    set_view_app(fn(root) {
      builds.val += 1
      stream_node(root, stream, fit~, content=fn() { at }, layer=fn() { false })
      .width(Is(Some(320.0))).height(Is(Some(200.0))) |> ignore
    })
  }
  stream.h264(wb_avcc, 640, 360)
  stream.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  t.stream_shows(stream.id(), 1.0, 640, 360)
  t.draw()
  assert_eq(acknowledgements, [1.0])
  stream.frame(b"\x00\x00\x00\x01\x41", false, 2.0)
  t.stream_shows(stream.id(), 2.0, 640, 360)
  t.draw()
  assert_eq(acknowledgements, [1.0, 2.0])
  if tree { assert_eq(builds.val, 1) }
  let picture = t.drawn_instances().filter(fn(a) { a[5] == 4.0 })
  assert_eq(picture.length(), 1)
  stream.close()
  picture
}

///|
test "retained streams fit and crop the same decoded frame as the existing stream renderer" {
  for fit in [FitFill, FitContain, FitCover, FitCoverAt(0.25)] {
    for at in [None, Some((-20.0, 10.0, 400.0, 220.0))] {
      let original = stream_node_picture(false, fit, at)
      let retained = stream_node_picture(true, fit, at)
      assert_eq(retained, original)
    }
  }
}

///|
test "a retained stream releases its display binding but leaves ownership of the decoder with its caller" {
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0, h264=true)
  let present = @signals.signal(true)
  let content = @signals.signal(None)
  let stream = Stream::new(shown=fn(_) {  }, broken=fn() {  })
  set_view_app(fn(root) {
    root.show(fn() { present.get() }, fn(v) {
      stream_node(v, stream, content=fn() { content.get() })
      .width(Is(Some(320.0))).height(Is(Some(200.0))) |> ignore
    })
  })
  stream.h264(wb_avcc, 640, 360)
  stream.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  t.stream_shows(stream.id(), 1.0, 640, 360)
  t.draw()
  assert_eq(tree_streams.length(), 1)
  content.set(Some((10.0, 20.0, 100.0, 80.0)))
  t.draw()
  let image = t.drawn_instances().filter(fn(a) { a[5] == 4.0 })[0]
  assert_eq((image[0], image[1], image[2], image[3]), (10.0, 20.0, 100.0, 80.0))
  present.set(false)
  t.draw()
  assert_eq(tree_streams.length(), 0)
  assert_false(stream.closed)
  assert_eq(t.drawn_instances().filter(fn(a) { a[5] == 4.0 }).length(), 0)
  stream.close()
}

///|
test "a retained stream uses the system video layer and hides it when the node leaves" {
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0, h264=true)
  t.set_stream_layers(true)
  let present = @signals.signal(true)
  let stream = Stream::new(shown=fn(_) {  }, broken=fn() {  }, layer=true)
  set_view_app(fn(root) {
    root.show(fn() { present.get() }, fn(v) {
      stream_node(v, stream).width(Is(Some(320.0))).height(Is(Some(180.0))) |> ignore
    })
  })
  stream.h264(wb_avcc, 640, 360)
  stream.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  t.stream_shows(stream.id(), 1.0, 640, 360)
  t.draw()
  assert_true(t.fake.views.iter().any(fn(l) { l.has_prefix("place 1 0 0 320 180") && !l.contains("hidden") }), msg="\{t.fake.views}")
  // A frame on the host's layer remains quiet: no component rebuilt for it.
  stream.frame(b"\x00\x00\x00\x01\x41", false, 2.0)
  t.stream_shows(stream.id(), 2.0, 640, 360)
  let frames = t.frames
  on_outside(outside_streamed, stream.id(), 0)
  assert_eq(t.frames, frames)
  assert_true(t.stream_fed(stream.id()).contains("show ts=2"))
  present.set(false)
  t.draw()
  assert_true(t.fake.views.last().unwrap().contains("hidden"), msg="\{t.fake.views}")
  stream.close()
}

///|
test "a retained stream follows its node's transform and fades onto the canvas" {
  let t = Tester::new(fn(_) {  }, w=400.0, h=300.0, h264=true)
  t.set_stream_layers(true)
  let stream = Stream::new(shown=fn(_) {  }, broken=fn() {  }, layer=true)
  let alpha = @signals.signal(1.0)
  set_view_app(fn(root) {
    stream_node(root, stream)
    .width(Is(Some(320.0))).height(Is(Some(180.0)))
    .offset(Is((20.0, 30.0))).scale(Is(0.5), about=At(0.0, 0.0))
    .alpha(By(fn() { alpha.get() })) |> ignore
  })
  stream.h264(wb_avcc, 640, 360)
  stream.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  t.stream_shows(stream.id(), 1.0, 640, 360)
  t.draw()
  assert_true(t.fake.views.iter().any(fn(l) { l.has_prefix("place 1 20 30 160 90") && !l.contains("hidden") }), msg="\{t.fake.views}")
  alpha.set(0.5)
  t.draw()
  let image = t.drawn_instances().filter(fn(a) { a[5] == 4.0 })[0]
  assert_eq((image[0], image[1], image[2], image[3], image[11]), (20.0, 30.0, 160.0, 90.0, 0.5))
  assert_true(t.fake.views.last().unwrap().contains("hidden"), msg="\{t.fake.views}")
  stream.close()
}
