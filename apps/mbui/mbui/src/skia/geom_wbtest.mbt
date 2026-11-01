// tiny-skia's own tests of its scalars, rects and transforms (path/src/scalar.rs, rect.rs, transform.rs).

///|
test "bound" {
  let nan = (0.0 : Float) / 0.0
  let inf = (1.0 : Float) / 0.0
  assert_eq(bound(nan, 0.0, 1.0), 1.0)
  assert_eq(bound(inf, 0.0, 1.0), 1.0)
  assert_eq(bound(-inf, 0.0, 1.0), 0.0)
  assert_eq(bound(f32_epsilon, 0.0, 1.0), f32_epsilon)
  assert_eq(bound(0.5, 0.0, 1.0), 0.5)
  assert_eq(bound(-1.0, 0.0, 1.0), 0.0)
  assert_eq(bound(2.0, 0.0, 1.0), 1.0)
}

///|
test "int rects" {
  assert_eq(IntRect::from_xywh(0, 0, 0, 0), None)
  assert_eq(IntRect::from_xywh(0, 0, 1, 0), None)
  assert_eq(IntRect::from_xywh(0, 0, 0, 1), None)
  assert_eq(IntRect::from_xywh64(0, 0, 4294967295L, 4294967295L), None)
  assert_eq(IntRect::from_xywh64(0, 0, 1L, 4294967295L), None)
  assert_eq(IntRect::from_xywh64(0, 0, 4294967295L, 1L), None)
  assert_eq(IntRect::from_xywh(2147483647, 0, 1, 1), None)
  assert_eq(IntRect::from_xywh(0, 2147483647, 1, 1), None)
  let r1 = IntRect::from_xywh(1, 2, 3, 4).unwrap()
  let r2 = IntRect::from_xywh(11, 12, 13, 14).unwrap()
  assert_eq(r1.intersect(r2), None)
  let r1 = IntRect::from_xywh(1, 2, 30, 40).unwrap()
  let r2 = IntRect::from_xywh(11, 12, 13, 14).unwrap()
  assert_eq(r1.intersect(r2), IntRect::from_xywh(11, 12, 13, 14))
  let r1 = IntRect::from_xywh(1, 2, 30, 40).unwrap()
  let r2 = IntRect::from_xywh(11, 12, 50, 60).unwrap()
  assert_eq(r1.intersect(r2), IntRect::from_xywh(11, 12, 20, 30))
}

///|
test "rects" {
  let nan = (0.0 : Float) / 0.0
  let inf = (1.0 : Float) / 0.0
  assert_eq(Rect::from_ltrb(10.0, 10.0, 5.0, 10.0), None)
  assert_eq(Rect::from_ltrb(10.0, 10.0, 10.0, 5.0), None)
  assert_eq(Rect::from_ltrb(nan, 10.0, 10.0, 10.0), None)
  assert_eq(Rect::from_ltrb(10.0, nan, 10.0, 10.0), None)
  assert_eq(Rect::from_ltrb(10.0, 10.0, nan, 10.0), None)
  assert_eq(Rect::from_ltrb(10.0, 10.0, 10.0, nan), None)
  assert_eq(Rect::from_ltrb(10.0, 10.0, 10.0, inf), None)
  let rect = Rect::from_ltrb(10.0, 20.0, 30.0, 40.0).unwrap()
  assert_eq(rect.left, 10.0)
  assert_eq(rect.top, 20.0)
  assert_eq(rect.right, 30.0)
  assert_eq(rect.bottom, 40.0)
  assert_eq(rect.width(), 20.0)
  assert_eq(rect.height(), 20.0)
  let rect = Rect::from_ltrb(-30.0, 20.0, -10.0, 40.0).unwrap()
  assert_eq(rect.width(), 20.0)
  assert_eq(rect.height(), 20.0)
}

///|
test "rect transform" {
  let rect = Rect::from_ltrb(1.0, 2.0, 3.0, 4.0).unwrap()
  assert_eq(rect.transform(Transform::identity()).unwrap(), rect)
  assert_eq(rect.transform(Transform::from_scale(1.0, 2.0)).unwrap(), Rect::from_ltrb(1.0, 4.0, 3.0, 8.0).unwrap())
  assert_eq(rect.transform(Transform::from_skew(1.0, 0.0)).unwrap(), Rect::from_ltrb(3.0, 2.0, 7.0, 4.0).unwrap())
  assert_eq(rect.transform(Transform::from_skew(0.0, 2.0)).unwrap(), Rect::from_ltrb(1.0, 4.0, 3.0, 10.0).unwrap())
}

///|
test "transform kinds" {
  assert_eq(Transform::identity(), Transform::from_row(1.0, 0.0, 0.0, 1.0, 0.0, 0.0))
  assert_eq(Transform::from_scale(1.0, 2.0), Transform::from_row(1.0, 0.0, 0.0, 2.0, 0.0, 0.0))
  assert_eq(Transform::from_skew(2.0, 3.0), Transform::from_row(1.0, 3.0, 2.0, 1.0, 0.0, 0.0))
  assert_eq(Transform::from_translate(5.0, 6.0), Transform::from_row(1.0, 0.0, 0.0, 1.0, 5.0, 6.0))
  let kinds = fn(ts : Transform) {
    [
      ts.is_identity(),
      ts.is_scale(),
      ts.is_skew(),
      ts.is_translate(),
      ts.is_scale_translate(),
      ts.has_scale(),
      ts.has_skew(),
      ts.has_translate(),
    ]
  }
  assert_eq(kinds(Transform::identity()), [true, false, false, false, false, false, false, false])
  assert_eq(kinds(Transform::from_scale(2.0, 3.0)), [false, true, false, false, true, true, false, false])
  assert_eq(kinds(Transform::from_skew(2.0, 3.0)), [false, false, true, false, false, false, true, false])
  assert_eq(kinds(Transform::from_translate(2.0, 3.0)), [false, false, false, true, true, false, false, true])
  assert_eq(kinds(Transform::from_row(1.0, 2.0, 3.0, 4.0, 5.0, 6.0)), [
    false, false, false, false, false, true, true, true,
  ])
  assert_false(Transform::from_scale(1.0, 1.0).has_scale())
  assert_false(Transform::from_skew(0.0, 0.0).has_skew())
  assert_false(Transform::from_translate(0.0, 0.0).has_translate())
}

///|
test "transform concat" {
  let ts = Transform::from_row(1.2, 3.4, -5.6, -7.8, 1.2, 3.4).pre_scale(2.0, -4.0)
  assert_eq(ts, Transform::from_row(2.4, 6.8, 22.4, 31.2, 1.2, 3.4))
  let ts = Transform::from_row(1.2, 3.4, -5.6, -7.8, 1.2, 3.4).post_scale(2.0, -4.0)
  assert_eq(ts, Transform::from_row(2.4, -13.6, -11.2, 31.2, 2.4, -13.6))
}

///|
test "rust's float rules" {
  let nan = (0.0 : Float) / 0.0
  assert_eq(f2i(nan), 0)
  assert_eq(f2i(3.0e10), 2147483647)
  assert_eq(f2i(-3.0e10), -2147483648)
  assert_eq(f2i(-1.9), -1)
  assert_eq(fround(2.5), 3.0)
  assert_eq(fround(-2.5), -3.0)
  assert_eq(fround(0.49999997), 0.0)
  assert_eq(fmin(nan, 1.0), 1.0)
  assert_eq(fmax(1.0, nan), 1.0)
}

///|
test "eval cubic at 1" {
  let src = [
    Point::from_xy(30.0, 40.0),
    Point::from_xy(30.0, 40.0),
    Point::from_xy(171.0, 45.0),
    Point::from_xy(180.0, 155.0),
  ]
  assert_eq(eval_cubic_pos_at(src, 0.0), Point::from_xy(30.0, 40.0))
  assert_eq(eval_cubic_tangent_at(src, 0.0), Point::from_xy(141.0, 5.0))
}

///|
test "find cubic max curvature 1" {
  let src = [
    Point::from_xy(20.0, 160.0),
    Point::from_xy(20.0001, 160.0),
    Point::from_xy(160.0, 20.0),
    Point::from_xy(160.0001, 20.0),
  ]
  let t_values : Array[Float] = [0.0, 0.0, 0.0]
  let n = find_cubic_max_curvature(src, t_values)
  assert_eq(t_values[:n].to_array(), [0.0, 0.5, 1.0])
}
