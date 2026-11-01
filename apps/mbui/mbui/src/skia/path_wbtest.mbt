// tiny-skia's own tests of its stroker and dasher (path/src/stroker.rs, dash.rs).

///|
fn bits(u : UInt) -> Float {
  Float::reinterpret_from_uint(u)
}

///|
test "stroke auto close" {
  let pb = PathBuilder::new()
  pb.move_to(10.0, 10.0)
  pb.line_to(20.0, 50.0)
  pb.line_to(30.0, 10.0)
  pb.close()
  let path = pb.finish().unwrap()
  let stroke_path = PathStroker::new().stroke(path, Stroke::default(), 1.0).unwrap()
  let iter = stroke_path.segments()
  iter.set_auto_close(true)
  let m = fn(x : Float, y : Float) { PathSegment::MoveTo(Point::from_xy(x, y)) }
  let l = fn(x : Float, y : Float) { PathSegment::LineTo(Point::from_xy(x, y)) }
  let want = [
    m(10.485071, 9.878732),
    l(20.485071, 49.878731),
    l(20.0, 50.0),
    l(19.514929, 49.878731),
    l(29.514929, 9.878732),
    l(30.0, 10.0),
    l(30.0, 10.5),
    l(10.0, 10.5),
    l(10.0, 10.0),
    l(10.485071, 9.878732),
    Close,
    m(9.3596115, 9.5),
    l(30.640388, 9.5),
    l(20.485071, 50.121269),
    l(19.514929, 50.121269),
    l(9.514929, 10.121268),
    l(9.3596115, 9.5),
    Close,
  ]
  for w in want {
    assert_eq(iter.next(), Some(w))
  }
}

///|
test "stroke cubic 1" {
  let pb = PathBuilder::new()
  pb.move_to(51.0161362, 1511.52478)
  pb.cubic_to(51.0161362, 1511.52478, 51.0161362, 1511.52478, 51.0161362, 1511.52478)
  let path = pb.finish().unwrap()
  let stroke = { ..Stroke::default(), width: 0.394537568 }
  assert_true(PathStroker::new().stroke(path, stroke, 1.0) is None)
}

///|
test "stroke cubic 2" {
  let pb = PathBuilder::new()
  pb.move_to(bits(0x424c1086), bits(0x44bcf0cb))
  pb.cubic_to(bits(0x424c107c), bits(0x44bcf0cb), bits(0x424c10c2), bits(0x44bcf0cb), bits(0x424c1119), bits(0x44bcf0ca))
  let path = pb.finish().unwrap()
  let stroke = { ..Stroke::default(), width: 0.394537568 }
  assert_true(PathStroker::new().stroke(path, stroke, 1.0) is Some(_))
}

///|
test "stroke big" {
  let pb = PathBuilder::new()
  pb.move_to(bits(0x46380000), bits(0xc6380000))
  pb.line_to(bits(0x46a00000), bits(0xc6a00000))
  pb.line_to(bits(0x468c0000), bits(0xc68c0000))
  pb.line_to(bits(0x46100000), bits(0xc6100000))
  pb.line_to(bits(0x46380000), bits(0xc6380000))
  pb.close()
  let path = pb.finish().unwrap()
  let stroke = { ..Stroke::default(), width: 1.49679073e+10 }
  assert_true(PathStroker::new().stroke(path, stroke, 1.0) is Some(_))
}

///|
test "quad stroker one off" {
  let pb = PathBuilder::new()
  pb.move_to(bits(0x43c99223), bits(0x42b7417e))
  pb.quad_to(bits(0x4285d839), bits(0x43ed6645), bits(0x43c941c8), bits(0x42b3ace3))
  let path = pb.finish().unwrap()
  let stroke = { ..Stroke::default(), width: 164.683548 }
  assert_true(PathStroker::new().stroke(path, stroke, 1.0) is Some(_))
}

///|
test "cubic stroker one off" {
  let pb = PathBuilder::new()
  pb.move_to(bits(0x433f5370), bits(0x43d1f4b3))
  pb.cubic_to(bits(0x4331cb76), bits(0x43ea3340), bits(0x4388f498), bits(0x42f7f08d), bits(0x43f1cd32), bits(0x42802ec1))
  let path = pb.finish().unwrap()
  let stroke = { ..Stroke::default(), width: 42.835968 }
  assert_true(PathStroker::new().stroke(path, stroke, 1.0) is Some(_))
}

///|
test "dash validity" {
  let inf = (1.0 : Float) / 0.0
  assert_true(StrokeDash::new([], 0.0) is None)
  assert_true(StrokeDash::new([1.0], 0.0) is None)
  assert_true(StrokeDash::new([1.0, 2.0, 3.0], 0.0) is None)
  assert_true(StrokeDash::new([1.0, -2.0], 0.0) is None)
  assert_true(StrokeDash::new([0.0, 0.0], 0.0) is None)
  assert_true(StrokeDash::new([1.0, -1.0], 0.0) is None)
  assert_true(StrokeDash::new([1.0, 1.0], inf) is None)
  assert_true(StrokeDash::new([1.0, inf], 0.0) is None)
}

///|
test "dash bug 26" {
  let pb = PathBuilder::new()
  pb.move_to(665.54, 287.3)
  pb.line_to(675.67, 273.04)
  pb.line_to(675.52, 271.32)
  pb.line_to(674.79, 269.61)
  pb.line_to(674.05, 268.04)
  pb.line_to(672.88, 266.47)
  pb.line_to(671.27, 264.9)
  let path = pb.finish().unwrap()
  let stroke_dash = StrokeDash::new([6.0, 4.5], 0.0).unwrap()
  assert_true(path.dash(stroke_dash, 1.0) is Some(_))
}
