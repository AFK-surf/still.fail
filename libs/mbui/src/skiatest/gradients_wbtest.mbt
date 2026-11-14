// tiny-skia's tests/integration/gradients.rs (tiny-skia 5d475477), against its reference images.


///|
test "gradients two_stops_linear_pad_lq" {
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = LinearGradient::new(
        Point::from_xy(10.0, 10.0),
        Point::from_xy(190.0, 190.0),
        [
            GradientStop::new(0.0, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.0, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/two-stops-linear-pad-lq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients two_stops_linear_repeat_lq" {
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = LinearGradient::new(
        Point::from_xy(10.0, 10.0),
        Point::from_xy(100.0, 100.0),
        [
            GradientStop::new(0.0, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.0, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Repeat,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/two-stops-linear-repeat-lq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients two_stops_linear_reflect_lq" {
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = LinearGradient::new(
        Point::from_xy(10.0, 10.0),
        Point::from_xy(100.0, 100.0),
        [
            GradientStop::new(0.0, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.0, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Reflect,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/two-stops-linear-reflect-lq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients three_stops_evenly_spaced_lq" {
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = LinearGradient::new(
        Point::from_xy(10.0, 10.0),
        Point::from_xy(190.0, 190.0),
        [
            GradientStop::new(0.25, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(0.50, Color::from_rgba8(220, 140, 75, 180)),
            GradientStop::new(0.75, Color::from_rgba8(40, 180, 55, 160)),
        ],
        // No need to check other modes. "Two stops" tests will cover them.
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/three-stops-evenly-spaced-lq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients two_stops_unevenly_spaced_lq" {
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = LinearGradient::new(
        Point::from_xy(10.0, 10.0),
        Point::from_xy(190.0, 190.0),
        [
            GradientStop::new(0.25, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(0.75, Color::from_rgba8(220, 140, 75, 180)),
        ],
        // No need to check other modes. "Two stops" tests will cover them.
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/two-stops-unevenly-spaced-lq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients two_stops_linear_pad_hq" {
    let paint = Paint::default()
    paint.force_hq_pipeline = true
    paint.anti_alias = false
    paint.shader = LinearGradient::new(
        Point::from_xy(10.0, 10.0),
        Point::from_xy(190.0, 190.0),
        [
            GradientStop::new(0.0, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.0, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/two-stops-linear-pad-hq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients two_stops_linear_repeat_hq" {
    let paint = Paint::default()
    paint.force_hq_pipeline = true
    paint.anti_alias = false
    paint.shader = LinearGradient::new(
        Point::from_xy(10.0, 10.0),
        Point::from_xy(100.0, 100.0),
        [
            GradientStop::new(0.0, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.0, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Repeat,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/two-stops-linear-repeat-hq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients two_stops_linear_reflect_hq" {
    let paint = Paint::default()
    paint.force_hq_pipeline = true
    paint.anti_alias = false
    paint.shader = LinearGradient::new(
        Point::from_xy(10.0, 10.0),
        Point::from_xy(100.0, 100.0),
        [
            GradientStop::new(0.0, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.0, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Reflect,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/two-stops-linear-reflect-hq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients three_stops_evenly_spaced_hq" {
    let paint = Paint::default()
    paint.force_hq_pipeline = true
    paint.anti_alias = false
    paint.shader = LinearGradient::new(
        Point::from_xy(10.0, 10.0),
        Point::from_xy(190.0, 190.0),
        [
            GradientStop::new(0.25, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(0.50, Color::from_rgba8(220, 140, 75, 180)),
            GradientStop::new(0.75, Color::from_rgba8(40, 180, 55, 160)),
        ],
        // No need to check other modes. "Two stops" tests will cover them.
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/three-stops-evenly-spaced-hq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients two_stops_unevenly_spaced_hq" {
    let paint = Paint::default()
    paint.force_hq_pipeline = true
    paint.anti_alias = false
    paint.shader = LinearGradient::new(
        Point::from_xy(10.0, 10.0),
        Point::from_xy(190.0, 190.0),
        [
            GradientStop::new(0.25, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(0.75, Color::from_rgba8(220, 140, 75, 180)),
        ],
        // No need to check other modes. "Two stops" tests will cover them.
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/two-stops-unevenly-spaced-hq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

// The radial gradient is only supported by the high quality pipeline.
// Therefore we do not have a lq/hq split.

///|
test "gradients well_behaved_radial" {
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = RadialGradient::new(
        Point::from_xy(100.0, 100.0),
        0.0,
        Point::from_xy(120.0, 80.0),
        100.0,
        [
            GradientStop::new(0.25, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(0.75, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/well-behaved-radial.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients focal_on_circle_radial" {
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = RadialGradient::new(
        Point::from_xy(100.0, 100.0),
        0.0,
        Point::from_xy(120.0, 80.0),
        28.29, // This radius forces the required pipeline stage.
        [
            GradientStop::new(0.25, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(0.75, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/focal-on-circle-radial.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients conical_greater_radial" {
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = RadialGradient::new(
        Point::from_xy(100.0, 100.0),
        0.0,
        Point::from_xy(120.0, 80.0),
        10.0, // This radius forces the required pipeline stage.
        [
            GradientStop::new(0.25, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(0.75, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/conical-greater-radial.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients simple_radial_lq" {
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = RadialGradient::new(
        Point::from_xy(100.0, 100.0),
        0.0,
        Point::from_xy(100.0, 100.0),
        100.0,
        [
            GradientStop::new(0.25, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.00, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/simple-radial-lq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients simple_radial_hq" {
    let paint = Paint::default()
    paint.force_hq_pipeline = true
    paint.anti_alias = false
    paint.shader = RadialGradient::new(
        Point::from_xy(100.0, 100.0),
        0.0,
        Point::from_xy(100.0, 100.0),
        100.0,
        [
            GradientStop::new(0.25, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.00, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/simple-radial-hq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients simple_radial_with_ts_hq" {
    let paint = Paint::default()
    paint.force_hq_pipeline = true
    paint.anti_alias = false
    paint.shader = RadialGradient::new(
        Point::from_xy(100.0, 100.0),
        0.0,
        Point::from_xy(100.0, 100.0),
        100.0,
        [
            GradientStop::new(0.25, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.00, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::from_row(2.0, 0.3, -0.7, 1.2, 10.5, -12.3),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/simple-radial-with-ts-hq.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

// Gradient doesn't add the Premultiply stage when all stops are opaque.
// But it checks colors only on creation, so we have to recheck them after calling `apply_opacity`.
///|
test "gradients global_opacity" {
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = RadialGradient::new(
        Point::from_xy(100.0, 100.0),
        0.0,
        Point::from_xy(100.0, 100.0),
        100.0,
        [
            GradientStop::new(0.25, Color::from_rgba8(50, 127, 150, 255)), // no opacity here
            GradientStop::new(1.00, Color::from_rgba8(220, 140, 75, 255)), // no opacity here
        ],
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    paint.shader = paint.shader.with_opacity(0.5)
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/global-opacity.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients strip_gradient" {
    // Equal radii, different centers creates a Strip gradient
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = RadialGradient::new(
        Point::from_xy(50.0, 100.0),
        50.0,
        Point::from_xy(150.0, 100.0),
        50.0,
        [
            GradientStop::new(0.0, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.0, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/strip-gradient.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients concentric_radial" {
    // Same center, non-zero start radius (concentric gradient)
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = RadialGradient::new(
        Point::from_xy(100.0, 100.0),
        30.0,
        Point::from_xy(100.0, 100.0),
        90.0,
        [
            GradientStop::new(0.0, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.0, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/concentric-radial.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients conical_smaller_radial" {
    // Configuration that triggers XYTo2PtConicalSmaller stage
    // r0=60, r1=30, distance=50
    // r0_norm=1.2, r1_norm=0.6, focal_x = 1.2/0.6 = 2.0 > 1.0
    // self.r1 = 0.6 / |1.0 - 2.0| = 0.6, so is_well_behaved() = false
    // (1.0 - focal_x) < 0.0 is true, triggering XYTo2PtConicalSmaller
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = RadialGradient::new(
        Point::from_xy(100.0, 100.0),
        60.0,
        Point::from_xy(150.0, 100.0),
        30.0,
        [
            GradientStop::new(0.0, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.0, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    ).unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("gradients/conical-smaller-radial.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients sweep_gradient" {
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = SweepGradient::new(
        Point::from_xy(100.0, 100.0),
        135.0,
        225.0,
        [
            GradientStop::new(0.0, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.0, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    )
        .unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(
        path,
        paint,
        FillRule::Winding,
        Transform::identity(),
        None,
    )
    let expected = load_pixmap(img("gradients/sweep-gradient.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "gradients sweep_gradient_full" {
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = SweepGradient::new(
        Point::from_xy(100.0, 100.0),
        0.0,
        360.0,
        [
            GradientStop::new(0.0, Color::from_rgba8(50, 127, 150, 200)),
            GradientStop::new(1.0, Color::from_rgba8(220, 140, 75, 180)),
        ],
        SpreadMode::Pad,
        Transform::identity(),
    )
    .unwrap()
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(
        path,
        paint,
        FillRule::Winding,
        Transform::identity(),
        None,
    )
    let expected = load_pixmap(img("gradients/sweep-gradient-full.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}
