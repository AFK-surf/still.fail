// tiny-skia's tests/integration/pattern.rs (tiny-skia 5d475477), against its reference images.


///|
fn crate_triangle() -> Pixmap {
    let paint = Paint::default()
    paint.set_color_rgba8(50, 127, 150, 200)
    paint.anti_alias = true
    let pb = PathBuilder::new()
    pb.move_to(0.0, 20.0)
    pb.line_to(20.0, 20.0)
    pb.line_to(10.0, 0.0)
    pb.close()
    let path = pb.finish().unwrap()
    let pixmap = Pixmap::new(20, 20).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    pixmap
}

///|
test "pattern pad_nearest" {
    let triangle = crate_triangle()
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = Pattern::new(
        triangle.as_ref(),
        SpreadMode::Pad,
        FilterQuality::Nearest,
        1.0,
        Transform::identity(),
    )
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("pattern/pad-nearest.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "pattern repeat_nearest" {
    let triangle = crate_triangle()
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = Pattern::new(
        triangle.as_ref(),
        SpreadMode::Repeat,
        FilterQuality::Nearest,
        1.0,
        Transform::identity(),
    )
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("pattern/repeat-nearest.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "pattern reflect_nearest" {
    let triangle = crate_triangle()
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = Pattern::new(
        triangle.as_ref(),
        SpreadMode::Reflect,
        FilterQuality::Nearest,
        1.0,
        Transform::identity(),
    )
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("pattern/reflect-nearest.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

// We have to test tile mode for bilinear/bicubic separately,
// because they're using a different algorithm from nearest.
///|
test "pattern pad_bicubic" {
    let triangle = crate_triangle()
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = Pattern::new(
        triangle.as_ref(),
        SpreadMode::Pad,
        FilterQuality::Bicubic,
        1.0,
        // Transform must be set, otherwise we will fallback to Nearest.
        Transform::from_row(1.1, 0.3, 0.0, 1.4, 0.0, 0.0),
    )
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("pattern/pad-bicubic.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "pattern repeat_bicubic" {
    let triangle = crate_triangle()
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = Pattern::new(
        triangle.as_ref(),
        SpreadMode::Repeat,
        FilterQuality::Bicubic,
        1.0,
        // Transform must be set, otherwise we will fallback to Nearest.
        Transform::from_row(1.1, 0.3, 0.0, 1.4, 0.0, 0.0),
    )
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("pattern/repeat-bicubic.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "pattern reflect_bicubic" {
    let triangle = crate_triangle()
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = Pattern::new(
        triangle.as_ref(),
        SpreadMode::Reflect,
        FilterQuality::Bicubic,
        1.0,
        // Transform must be set, otherwise we will fallback to Nearest.
        Transform::from_row(1.1, 0.3, 0.0, 1.4, 0.0, 0.0),
    )
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("pattern/reflect-bicubic.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "pattern filter_nearest_no_ts" {
    let triangle = crate_triangle()
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = Pattern::new(
        triangle.as_ref(),
        SpreadMode::Repeat,
        FilterQuality::Nearest,
        1.0,
        Transform::identity(),
    )
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("pattern/filter-nearest-no-ts.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "pattern filter_nearest" {
    let triangle = crate_triangle()
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = Pattern::new(
        triangle.as_ref(),
        SpreadMode::Repeat,
        FilterQuality::Nearest,
        1.0,
        Transform::from_row(1.5, 0.0, -0.4, -0.8, 5.0, 1.0),
    )
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("pattern/filter-nearest.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "pattern filter_bilinear" {
    let triangle = crate_triangle()
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = Pattern::new(
        triangle.as_ref(),
        SpreadMode::Repeat,
        FilterQuality::Bilinear,
        1.0,
        Transform::from_row(1.5, 0.0, -0.4, -0.8, 5.0, 1.0),
    )
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("pattern/filter-bilinear.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}

///|
test "pattern filter_bicubic" {
    let triangle = crate_triangle()
    let paint = Paint::default()
    paint.anti_alias = false
    paint.shader = Pattern::new(
        triangle.as_ref(),
        SpreadMode::Repeat,
        FilterQuality::Bicubic,
        1.0,
        Transform::from_row(1.5, 0.0, -0.4, -0.8, 5.0, 1.0),
    )
    let path = PathBuilder::from_rect(Rect::from_ltrb(10.0, 10.0, 190.0, 190.0).unwrap())
    let pixmap = Pixmap::new(200, 200).unwrap()
    pixmap.fill_path(path, paint, FillRule::Winding, Transform::identity(), None)
    let expected = load_pixmap(img("pattern/filter-bicubic.png")).unwrap()
    assert_eq(diff_count(pixmap, expected), 0)
}
