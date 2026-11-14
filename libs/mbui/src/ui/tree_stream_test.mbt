// A stream drawn in a node of the window's tree (@ui.stream), as one drawn by an old view (stream_test.mbt): the picture
// shown each frame the frame its host last said decoded, each frame said shown once painted; let go with its node.

///|
let tree_avcc : Bytes = b"\x01\x42\xc0\x1f\xff\xe1\x00\x06\x67\x42\xc0\x1f\xda\x01\x01\x00\x04\x68\xce\x3c\x80"

///|
test "a stream in a node of the tree: nothing drawn till a frame decodes; each frame decoded drawn there, said shown once painted, the next drawn in its place; let go with its node, closed" {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, h264=true)
  t.check_looks(false)
  let acks : Array[Double] = []
  let s = @ui.Stream::new(shown=fn(ts) { acks.push(ts) }, broken=fn() {  })
  let on = @signals.signal(true)
  @ui.set_view_app(fn(root) {
    root.show(fn() { on.get() }, fn(b) {
      @ui.stream(b, s).width(@view.Is(Some(200.0))).height(@view.Is(Some(100.0))) |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_false(t.drawlist().contains("stream"), msg=t.drawlist())
  s.h264(tree_avcc, 320, 640)
  s.frame(b"\x00\x00\x00\x01\x65", true, 101.0)
  t.draw()
  assert_eq(acks, [])
  t.stream_shows(s.id(), 101.0, 320, 640)
  t.draw()
  assert_eq(acks, [101.0])
  assert_true(t.drawlist().contains("\"stream 320x640 ts=101\""), msg=t.drawlist())
  // (the next, nothing else of the tree's changed: drawn in its place)
  s.frame(b"\x00\x00\x00\x01\x41", false, 102.0)
  t.draw()
  t.stream_shows(s.id(), 102.0, 320, 640)
  t.draw()
  assert_eq(acks, [101.0, 102.0])
  assert_true(t.drawlist().contains("\"stream 320x640 ts=102\""), msg=t.drawlist())
  // (its node let go, once its way out is over: the stream closed, nothing of it drawn)
  on.set(false)
  t.run_for(@ui.move_most_ms)
  assert_false(t.drawlist().contains("stream"), msg=t.drawlist())
  s.frame(b"\x00\x00\x00\x01\x41", false, 103.0)
  assert_eq(t.stream_fed(s.id()).filter(fn(l) { l.contains("ts=103") }), [])
}
