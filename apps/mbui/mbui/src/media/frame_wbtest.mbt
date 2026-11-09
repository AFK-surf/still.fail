///|
test "a frame's edge remains visible over content that fills it" {
  let style = FrameStyle::{
    fill: 0xFFFFFFFFL,
    edge: 0x000000FFL,
    edge_width: 3.0,
    radius: 20.0,
    inset: 0.0,
  }
  let t = @ui.Tester::new(fn(c) {
    frame(c, 200.0, 100.0, style, fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=0xFF0000FFL, fn() {  }) |> ignore
    })
    |> ignore
  })
  t.draw()
  let instances = t.drawn_instances()
  let mut content = -1
  let mut edge = -1
  for i, p in instances {
    if p[5] == 0.0 && p[8] == 1.0 && p[9] == 0.0 && p[10] == 0.0 && p[11] == 1.0 {
      content = i
    }
    if p[5] == 0.0 && p[6] == 3.0 {
      edge = i
    }
  }
  assert_true(content >= 0)
  assert_true(edge > content)
}
